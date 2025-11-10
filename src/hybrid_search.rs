// Copyright (c) 2025 Michael A. Wright
// Licensed under the MIT License

//! Hybrid search combining vector similarity with keyword matching.
//!
//! This binary performs both semantic (vector) search and keyword-based search,
//! then combines the results for better precision and recall.

use anyhow::{Context, Result};
use clap::Parser;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

#[derive(Parser, Debug)]
#[command(author, version, about = "Hybrid search: vector + keyword matching", long_about = None)]
struct Args {
    #[arg(help = "Search query")]
    query: String,

    #[arg(short, long, default_value = "10", help = "Number of results")]
    limit: usize,

    #[arg(long, default_value = "documents", help = "Collection name")]
    collection: String,

    #[arg(long, default_value = "http://localhost:6333", help = "Qdrant URL")]
    qdrant_url: String,

    #[arg(long, default_value = "http://localhost:11434", help = "Ollama URL")]
    ollama_url: String,

    #[arg(
        short,
        long,
        default_value = "nomic-embed-text",
        help = "Model for embeddings"
    )]
    model: String,

    #[arg(long, default_value = "0.7", help = "Vector search weight (0.0-1.0)")]
    vector_weight: f32,

    #[arg(long, default_value = "0.3", help = "Keyword search weight (0.0-1.0)")]
    keyword_weight: f32,

    #[arg(long, help = "Output as JSON")]
    json: bool,

    #[arg(long, help = "Filter by metadata field (format: key=value)")]
    filter: Option<Vec<String>>,
}

#[derive(Debug, Serialize, Deserialize)]
struct EmbeddingRequest {
    model: String,
    prompt: String,
}

#[derive(Debug, Deserialize)]
struct EmbeddingResponse {
    embedding: Vec<f32>,
}

#[derive(Debug, Deserialize)]
struct QdrantSearchResponse {
    result: Vec<SearchResult>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
struct SearchResult {
    id: String,
    score: f32,
    payload: serde_json::Value,
}

#[derive(Debug, Serialize)]
struct HybridSearchResult {
    id: String,
    vector_score: f32,
    keyword_score: f32,
    combined_score: f32,
    payload: serde_json::Value,
}

fn get_embedding(client: &Client, ollama_url: &str, model: &str, text: &str) -> Result<Vec<f32>> {
    let request = EmbeddingRequest {
        model: model.to_string(),
        prompt: text.to_string(),
    };

    let response = client
        .post(format!("{}/api/embeddings", ollama_url))
        .json(&request)
        .send()
        .context("Failed to get embedding from Ollama")?;

    if !response.status().is_success() {
        anyhow::bail!("Ollama returned error: {}", response.status());
    }

    let embedding: EmbeddingResponse = response
        .json()
        .context("Failed to parse embedding response")?;

    Ok(embedding.embedding)
}

fn vector_search(
    client: &Client,
    qdrant_url: &str,
    collection: &str,
    embedding: Vec<f32>,
    limit: usize,
    filter: Option<&serde_json::Value>,
) -> Result<Vec<SearchResult>> {
    let mut request_body = serde_json::json!({
        "vector": embedding,
        "limit": limit * 2, // Fetch more for hybrid merging
        "with_payload": true,
    });

    if let Some(f) = filter {
        request_body["filter"] = f.clone();
    }

    let url = format!("{}/collections/{}/points/search", qdrant_url, collection);

    let response: QdrantSearchResponse = client
        .post(&url)
        .json(&request_body)
        .send()
        .context("Failed to search Qdrant")?
        .json()
        .context("Failed to parse search response")?;

    Ok(response.result)
}

fn keyword_score(query: &str, text: &str) -> f32 {
    let query_lower = query.to_lowercase();
    let text_lower = text.to_lowercase();

    // Extract query terms
    let query_terms: Vec<&str> = query_lower
        .split_whitespace()
        .filter(|t| t.len() > 2) // Ignore very short words
        .collect();

    if query_terms.is_empty() {
        return 0.0;
    }

    let mut score = 0.0;
    let text_words: Vec<&str> = text_lower.split_whitespace().collect();
    let text_len = text_words.len() as f32;

    // Calculate TF (term frequency) for each query term
    for term in &query_terms {
        let count = text_lower.matches(term).count() as f32;

        if count > 0.0 {
            // TF component: log-scaled frequency
            let tf = (1.0 + count.ln()) / (1.0 + text_len.ln());

            // Boost for exact phrase matches
            let phrase_boost = if text_lower.contains(&query_lower) {
                2.0
            } else {
                1.0
            };

            // Boost for term at start of text
            let position_boost = if text_lower.starts_with(term) {
                1.5
            } else {
                1.0
            };

            score += tf * phrase_boost * position_boost;
        }
    }

    // Normalize by query length
    score / query_terms.len() as f32
}

fn hybrid_search(
    query: &str,
    vector_results: Vec<SearchResult>,
    vector_weight: f32,
    keyword_weight: f32,
) -> Vec<HybridSearchResult> {
    let mut results_map: HashMap<String, HybridSearchResult> = HashMap::new();

    // Normalize vector scores (0-1 range)
    let max_vector_score = vector_results
        .iter()
        .map(|r| r.score)
        .max_by(|a, b| a.partial_cmp(b).unwrap())
        .unwrap_or(1.0);

    // Process vector results
    for result in vector_results {
        let text = result
            .payload
            .get("text")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let keyword_score_val = keyword_score(query, text);
        let normalized_vector_score = result.score / max_vector_score;

        let combined_score =
            (normalized_vector_score * vector_weight) + (keyword_score_val * keyword_weight);

        results_map.insert(
            result.id.clone(),
            HybridSearchResult {
                id: result.id,
                vector_score: result.score,
                keyword_score: keyword_score_val,
                combined_score,
                payload: result.payload,
            },
        );
    }

    // Convert to vec and sort by combined score
    let mut results: Vec<HybridSearchResult> = results_map.into_values().collect();
    results.sort_by(|a, b| b.combined_score.partial_cmp(&a.combined_score).unwrap());

    results
}

fn build_filter(filter_args: &[String]) -> Result<serde_json::Value> {
    let mut must_conditions = Vec::new();

    for filter_str in filter_args {
        let parts: Vec<&str> = filter_str.splitn(2, '=').collect();
        if parts.len() != 2 {
            anyhow::bail!("Invalid filter format: '{}'. Use key=value", filter_str);
        }

        let (key, value) = (parts[0], parts[1]);

        // Try to parse as bool
        let filter_value = if value == "true" || value == "false" {
            serde_json::json!({
                "key": key,
                "match": {"value": value == "true"}
            })
        } else {
            // Treat as string
            serde_json::json!({
                "key": key,
                "match": {"value": value}
            })
        };

        must_conditions.push(filter_value);
    }

    Ok(serde_json::json!({
        "must": must_conditions
    }))
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Validate weights
    let total_weight = args.vector_weight + args.keyword_weight;
    if (total_weight - 1.0).abs() > 0.01 {
        eprintln!(
            "⚠️  Warning: Weights don't sum to 1.0 ({}). Continuing anyway...",
            total_weight
        );
    }

    let client = Client::new();

    // Build filter if provided
    let filter = if let Some(ref filter_args) = args.filter {
        Some(build_filter(filter_args)?)
    } else {
        None
    };

    if !args.json {
        println!("🔍 Hybrid Search: {} + {}", "Vector".to_string(), "Keyword");
        println!("   Query: {}", args.query);
        println!(
            "   Weights: {:.0}% vector, {:.0}% keyword",
            args.vector_weight * 100.0,
            args.keyword_weight * 100.0
        );
        if let Some(ref f) = filter {
            println!("   Filter: {:?}", f);
        }
        println!();
    }

    // Step 1: Get query embedding
    let embedding = get_embedding(&client, &args.ollama_url, &args.model, &args.query)?;

    // Step 2: Perform vector search
    let vector_results = vector_search(
        &client,
        &args.qdrant_url,
        &args.collection,
        embedding,
        args.limit,
        filter.as_ref(),
    )?;

    if !args.json {
        println!("📊 Vector search found {} results", vector_results.len());
    }

    // Step 3: Combine with keyword scoring
    let hybrid_results = hybrid_search(
        &args.query,
        vector_results,
        args.vector_weight,
        args.keyword_weight,
    );

    // Step 4: Output results
    let results_to_show: Vec<_> = hybrid_results.into_iter().take(args.limit).collect();

    if args.json {
        println!("{}", serde_json::to_string_pretty(&results_to_show)?);
    } else {
        println!("🎯 Top {} Results:\n", results_to_show.len());

        for (i, result) in results_to_show.iter().enumerate() {
            println!("--- Result {} ---", i + 1);
            println!(
                "Score: {:.3} (vector: {:.3}, keyword: {:.3})",
                result.combined_score, result.vector_score, result.keyword_score
            );

            if let Some(text) = result.payload.get("text").and_then(|v| v.as_str()) {
                let preview = if text.len() > 200 {
                    format!("{}...", &text[..200])
                } else {
                    text.to_string()
                };
                println!("{}", preview);
            }

            println!();
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keyword_score_exact_match() {
        let query = "rust macros";
        let text = "rust macros are powerful";

        let score = keyword_score(query, text);
        assert!(score > 0.0, "Should have positive score for match");
    }

    #[test]
    fn test_keyword_score_partial_match() {
        let query = "rust macros";
        let text = "rust is a programming language";

        let score = keyword_score(query, text);
        assert!(score > 0.0, "Should match on 'rust'");
    }

    #[test]
    fn test_keyword_score_no_match() {
        let query = "rust macros";
        let text = "python programming guide";

        let score = keyword_score(query, text);
        assert_eq!(score, 0.0, "Should have zero score for no match");
    }

    #[test]
    fn test_keyword_score_phrase_boost() {
        let query = "rust macros";
        let exact_text = "this is about rust macros and their uses";
        let partial_text = "this is about rust and also macros";

        let exact_score = keyword_score(query, exact_text);
        let partial_score = keyword_score(query, partial_text);

        assert!(
            exact_score > partial_score,
            "Exact phrase should score higher"
        );
    }

    #[test]
    fn test_keyword_score_case_insensitive() {
        let query = "Rust Macros";
        let text = "RUST MACROS are powerful";

        let score = keyword_score(query, text);
        assert!(score > 0.0, "Should be case insensitive");
    }

    #[test]
    fn test_build_filter_single() {
        let filters = vec!["is_code=true".to_string()];
        let result = build_filter(&filters).unwrap();

        assert!(result["must"].is_array());
        assert_eq!(result["must"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn test_build_filter_multiple() {
        let filters = vec!["is_code=true".to_string(), "source=test.pdf".to_string()];
        let result = build_filter(&filters).unwrap();

        assert_eq!(result["must"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn test_build_filter_invalid() {
        let filters = vec!["invalid_format".to_string()];
        let result = build_filter(&filters);

        assert!(result.is_err());
    }

    #[test]
    fn test_hybrid_search_combines_scores() {
        let vector_results = vec![SearchResult {
            id: "test1".to_string(),
            score: 0.8,
            payload: serde_json::json!({"text": "rust macros are great"}),
        }];

        let results = hybrid_search("rust macros", vector_results, 0.7, 0.3);

        assert_eq!(results.len(), 1);
        assert!(results[0].combined_score > 0.0);
        assert!(results[0].vector_score > 0.0);
        assert!(results[0].keyword_score > 0.0);
    }

    #[test]
    fn test_hybrid_search_sorts_by_combined() {
        let vector_results = vec![
            SearchResult {
                id: "test1".to_string(),
                score: 0.9,
                payload: serde_json::json!({"text": "unrelated content"}),
            },
            SearchResult {
                id: "test2".to_string(),
                score: 0.7,
                payload: serde_json::json!({"text": "rust macros exact match"}),
            },
        ];

        let results = hybrid_search("rust macros", vector_results, 0.5, 0.5);

        // Second result should rank higher due to keyword match
        assert_eq!(results[0].id, "test2");
    }
}
