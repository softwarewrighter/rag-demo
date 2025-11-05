// Copyright (c) 2025 Michael A. Wright
// Licensed under the MIT License

use anyhow::{Context, Result};
use clap::Parser;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Parser, Debug)]
#[command(author, version, about = "Search Qdrant for similar documents", long_about = None)]
struct Args {
    #[arg(help = "Search query")]
    query: String,

    #[arg(short, long, default_value = "5", help = "Number of results")]
    limit: usize,

    #[arg(long, default_value = "documents", help = "Qdrant collection name")]
    collection: String,

    #[arg(long, default_value = "http://localhost:6333", help = "Qdrant URL")]
    qdrant_url: String,

    #[arg(long, default_value = "http://localhost:11434", help = "Ollama URL")]
    ollama_url: String,

    #[arg(
        short,
        long,
        default_value = "nomic-embed-text",
        help = "Embedding model"
    )]
    model: String,

    #[arg(short, long, help = "Output as JSON")]
    json: bool,
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
struct SearchResult {
    #[allow(dead_code)]
    id: String,
    score: f32,
    payload: serde_json::Value,
}

#[derive(Debug, Deserialize)]
struct QdrantSearchResponse {
    result: Vec<SearchResult>,
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

fn main() -> Result<()> {
    let args = Args::parse();
    let client = Client::new();

    // Get embedding for query
    let query_embedding = get_embedding(&client, &args.ollama_url, &args.model, &args.query)
        .context("Failed to get query embedding")?;

    // Search Qdrant
    let search_request = json!({
        "vector": query_embedding,
        "limit": args.limit,
        "with_payload": true,
    });

    let response = client
        .post(format!(
            "{}/collections/{}/points/search",
            args.qdrant_url, args.collection
        ))
        .json(&search_request)
        .send()
        .context("Failed to search Qdrant")?;

    if !response.status().is_success() {
        let error_text = response
            .text()
            .unwrap_or_else(|_| "Unknown error".to_string());
        anyhow::bail!("Qdrant search failed: {}", error_text);
    }

    let search_response: QdrantSearchResponse =
        response.json().context("Failed to parse search response")?;

    // Output results
    if args.json {
        // JSON output for scripting
        let output = json!({
            "query": args.query,
            "results": search_response.result.iter().map(|r| {
                json!({
                    "score": r.score,
                    "text": r.payload.get("text").and_then(|v| v.as_str()).unwrap_or(""),
                    "source": r.payload.get("source").and_then(|v| v.as_str()).unwrap_or(""),
                    "chunk_index": r.payload.get("chunk_index").and_then(|v| v.as_i64()).unwrap_or(0),
                })
            }).collect::<Vec<_>>()
        });
        println!("{}", serde_json::to_string(&output)?);
    } else {
        // Human-readable output
        if search_response.result.is_empty() {
            println!("No results found for query: {}", args.query);
        } else {
            println!("🔍 Search Results for: {}\n", args.query);
            for (i, result) in search_response.result.iter().enumerate() {
                println!("--- Result {} (Score: {:.3}) ---", i + 1, result.score);

                if let Some(text) = result.payload.get("text").and_then(|v| v.as_str()) {
                    // Truncate long text for display
                    let display_text = if text.len() > 300 {
                        format!("{}...", &text[..300])
                    } else {
                        text.to_string()
                    };
                    println!("{}", display_text);
                }

                if let Some(source) = result.payload.get("source").and_then(|v| v.as_str()) {
                    println!("Source: {}", source);
                }

                if let Some(chunk) = result.payload.get("chunk_index").and_then(|v| v.as_i64()) {
                    println!("Chunk: {}", chunk + 1);
                }

                println!();
            }
        }
    }

    Ok(())
}
