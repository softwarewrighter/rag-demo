// Copyright (c) 2025 Michael A. Wright
// Licensed under the MIT License

use anyhow::{Context, Result};
use clap::Parser;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Parser, Debug)]
#[command(author, version, about = "Hierarchical search with parent-child context", long_about = None)]
struct Args {
    #[arg(help = "Search query")]
    query: String,

    #[arg(short, long, default_value = "5", help = "Number of results")]
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

    #[arg(long, help = "Output as JSON")]
    json: bool,

    #[arg(long, help = "Include parent context for child chunks")]
    with_parent: bool,
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
struct HierarchicalResult {
    child: SearchResult,
    parent: Option<SearchResult>,
    combined_text: String,
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

fn search_qdrant(
    client: &Client,
    qdrant_url: &str,
    collection: &str,
    embedding: Vec<f32>,
    limit: usize,
    filter: Option<serde_json::Value>,
) -> Result<Vec<SearchResult>> {
    let search_request = json!({
        "vector": embedding,
        "limit": limit,
        "with_payload": true,
        "filter": filter,
    });

    let response = client
        .post(format!(
            "{}/collections/{}/points/search",
            qdrant_url, collection
        ))
        .json(&search_request)
        .send()
        .context("Failed to search Qdrant")?;

    if !response.status().is_success() {
        anyhow::bail!("Qdrant search failed: {}", response.status());
    }

    let search_response: QdrantSearchResponse =
        response.json().context("Failed to parse search response")?;

    Ok(search_response.result)
}

fn main() -> Result<()> {
    let args = Args::parse();
    let client = Client::new();

    // Get embedding for query
    let query_embedding = get_embedding(&client, &args.ollama_url, &args.model, &args.query)?;

    // Search for child chunks first (more precise)
    let child_filter = json!({
        "must": [{
            "key": "chunk_type",
            "match": {
                "any": ["child_code", "child_text", "child_mixed", "child_header", "child_list"]
            }
        }]
    });

    let child_results = search_qdrant(
        &client,
        &args.qdrant_url,
        &args.collection,
        query_embedding.clone(),
        args.limit,
        Some(child_filter),
    )?;

    if args.json {
        if args.with_parent {
            // Fetch parent chunks for context
            let mut hierarchical_results = Vec::new();

            for child in child_results {
                let parent_id = child
                    .payload
                    .get("parent_id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");

                // Fetch parent by ID
                let parent_filter = json!({
                    "must": [{
                        "key": "chunk_type",
                        "match": { "value": "parent" }
                    }]
                });

                // Search for parent chunk (using same embedding for now, could optimize)
                let parent_results = search_qdrant(
                    &client,
                    &args.qdrant_url,
                    &args.collection,
                    query_embedding.clone(),
                    20, // Search more to find the specific parent
                    Some(parent_filter),
                )?;

                // Find matching parent
                let parent = parent_results.iter().find(|p| p.id == parent_id).cloned();

                let combined_text = if let Some(ref p) = parent {
                    format!(
                        "=== CONTEXT (Parent Chunk) ===\n{}\n\n=== PRECISE MATCH (Child Chunk) ===\n{}",
                        p.payload.get("text").and_then(|v| v.as_str()).unwrap_or(""),
                        child
                            .payload
                            .get("text")
                            .and_then(|v| v.as_str())
                            .unwrap_or("")
                    )
                } else {
                    child
                        .payload
                        .get("text")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string()
                };

                hierarchical_results.push(HierarchicalResult {
                    child,
                    parent,
                    combined_text,
                });
            }

            println!("{}", serde_json::to_string_pretty(&hierarchical_results)?);
        } else {
            println!(
                "{}",
                serde_json::to_string_pretty(&json!({
                    "query": args.query,
                    "results": child_results,
                }))?
            );
        }
    } else {
        println!("🔍 Hierarchical Search Results for: {}\n", args.query);

        for (i, result) in child_results.iter().enumerate() {
            println!("--- Result {} (Score: {:.3}) ---", i + 1, result.score);

            let chunk_type = result
                .payload
                .get("chunk_type")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");

            let parent_id = result
                .payload
                .get("parent_id")
                .and_then(|v| v.as_str())
                .unwrap_or("none");

            let text = result
                .payload
                .get("text")
                .and_then(|v| v.as_str())
                .unwrap_or("");

            println!("Type: {}", chunk_type);

            if args.with_parent && parent_id != "none" {
                println!("Parent ID: {}", parent_id);

                // Show parent summary if available
                if let Some(summary) = result
                    .payload
                    .get("parent_summary")
                    .and_then(|v| v.as_str())
                {
                    println!("Context: {}", summary);
                }
            }

            // Show text preview
            let preview = if text.len() > 300 {
                format!("{}...", &text[..300])
            } else {
                text.to_string()
            };
            println!("{}", preview);

            println!();
        }

        if args.with_parent {
            println!(
                "💡 Tip: Child chunks provide precise matches, parent chunks provide full context"
            );
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_search_result_deserialization() {
        let json_data = json!({
            "id": "test-id-123",
            "score": 0.95,
            "payload": {
                "text": "Test content",
                "chunk_type": "Text"
            }
        });

        let result: SearchResult = serde_json::from_value(json_data).unwrap();

        assert_eq!(result.id, "test-id-123");
        assert_eq!(result.score, 0.95);
        assert_eq!(result.payload["text"], "Test content");
    }

    #[test]
    fn test_hierarchical_result_structure() {
        let child = SearchResult {
            id: "child-1".to_string(),
            score: 0.9,
            payload: json!({"text": "Child text", "chunk_type": "Text"}),
        };

        let parent = SearchResult {
            id: "parent-1".to_string(),
            score: 0.85,
            payload: json!({"text": "Parent text", "chunk_type": "Text"}),
        };

        let hierarchical = HierarchicalResult {
            child: child.clone(),
            parent: Some(parent.clone()),
            combined_text: "Combined text".to_string(),
        };

        assert_eq!(hierarchical.child.id, "child-1");
        assert!(hierarchical.parent.is_some());
        assert_eq!(hierarchical.combined_text, "Combined text");
    }

    #[test]
    fn test_hierarchical_result_without_parent() {
        let child = SearchResult {
            id: "child-1".to_string(),
            score: 0.9,
            payload: json!({"text": "Child text"}),
        };

        let hierarchical = HierarchicalResult {
            child: child.clone(),
            parent: None,
            combined_text: "Just child text".to_string(),
        };

        assert_eq!(hierarchical.child.id, "child-1");
        assert!(hierarchical.parent.is_none());
    }

    #[test]
    fn test_embedding_request_serialization() {
        let request = EmbeddingRequest {
            model: "nomic-embed-text".to_string(),
            prompt: "test query".to_string(),
        };

        let json = serde_json::to_value(&request).unwrap();

        assert_eq!(json["model"], "nomic-embed-text");
        assert_eq!(json["prompt"], "test query");
    }

    #[test]
    fn test_embedding_response_deserialization() {
        let json_data = json!({
            "embedding": [0.1, 0.2, 0.3, 0.4]
        });

        let response: EmbeddingResponse = serde_json::from_value(json_data).unwrap();

        assert_eq!(response.embedding.len(), 4);
        assert_eq!(response.embedding[0], 0.1);
        assert_eq!(response.embedding[3], 0.4);
    }

    #[test]
    fn test_search_result_clone() {
        let result = SearchResult {
            id: "test-id".to_string(),
            score: 0.88,
            payload: json!({"text": "Test"}),
        };

        let cloned = result.clone();

        assert_eq!(result.id, cloned.id);
        assert_eq!(result.score, cloned.score);
    }

    #[test]
    fn test_qdrant_search_response_deserialization() {
        let json_data = json!({
            "result": [
                {
                    "id": "id-1",
                    "score": 0.95,
                    "payload": {"text": "Result 1"}
                },
                {
                    "id": "id-2",
                    "score": 0.90,
                    "payload": {"text": "Result 2"}
                }
            ]
        });

        let response: QdrantSearchResponse = serde_json::from_value(json_data).unwrap();

        assert_eq!(response.result.len(), 2);
        assert_eq!(response.result[0].id, "id-1");
        assert_eq!(response.result[1].score, 0.90);
    }

    #[test]
    fn test_hierarchical_result_serialization() {
        let child = SearchResult {
            id: "child-1".to_string(),
            score: 0.92,
            payload: json!({"text": "Child"}),
        };

        let result = HierarchicalResult {
            child,
            parent: None,
            combined_text: "Text".to_string(),
        };

        let json = serde_json::to_value(&result).unwrap();

        assert!(json["child"].is_object());
        assert!(json["parent"].is_null());
        assert_eq!(json["combined_text"], "Text");
    }
}
