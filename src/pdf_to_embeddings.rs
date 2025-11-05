// Copyright (c) 2025 Michael A. Wright
// Licensed under the MIT License

use anyhow::{Context, Result};
use clap::Parser;
use pdf_extract::extract_text;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::path::Path;
use uuid::Uuid;

#[derive(Parser, Debug)]
#[command(author, version, about = "Extract text from PDF and store in Qdrant", long_about = None)]
struct Args {
    #[arg(help = "Path to PDF file")]
    pdf_path: String,

    #[arg(short, long, default_value = "1000", help = "Characters per chunk")]
    chunk_size: usize,

    #[arg(short, long, default_value = "200", help = "Overlap between chunks")]
    overlap: usize,

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

#[derive(Debug, Serialize)]
struct QdrantPoint {
    id: String,
    vector: Vec<f32>,
    payload: serde_json::Value,
}

fn chunk_text(text: &str, chunk_size: usize, overlap: usize) -> Vec<String> {
    let mut chunks = Vec::new();
    let chars: Vec<char> = text.chars().collect();
    let mut start = 0;

    while start < chars.len() {
        let end = std::cmp::min(start + chunk_size, chars.len());
        let chunk: String = chars[start..end].iter().collect();
        chunks.push(chunk);

        if end >= chars.len() {
            break;
        }

        start += chunk_size - overlap;
    }

    chunks
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

    // Extract text from PDF
    println!("📄 Extracting text from PDF: {}", args.pdf_path);
    let path = Path::new(&args.pdf_path);
    let text = extract_text(path).context("Failed to extract text from PDF")?;

    // Create chunks
    println!(
        "✂️  Creating chunks (size: {}, overlap: {})",
        args.chunk_size, args.overlap
    );
    let chunks = chunk_text(&text, args.chunk_size, args.overlap);
    println!("📦 Created {} chunks", chunks.len());

    // Generate embeddings and prepare points
    println!("🧮 Generating embeddings with model: {}", args.model);
    let mut points = Vec::new();

    for (i, chunk) in chunks.iter().enumerate() {
        print!("  Processing chunk {}/{}...\r", i + 1, chunks.len());

        let embedding = get_embedding(&client, &args.ollama_url, &args.model, chunk)?;

        let point = QdrantPoint {
            id: Uuid::new_v4().to_string(),
            vector: embedding,
            payload: json!({
                "text": chunk,
                "source": args.pdf_path,
                "chunk_index": i,
                "total_chunks": chunks.len(),
            }),
        };

        points.push(point);
    }
    println!("\n✅ Generated embeddings for all chunks");

    // Upload to Qdrant
    println!("📤 Uploading to Qdrant collection: {}", args.collection);
    let response = client
        .put(format!(
            "{}/collections/{}/points",
            args.qdrant_url, args.collection
        ))
        .json(&json!({
            "points": points
        }))
        .send()
        .context("Failed to upload to Qdrant")?;

    if !response.status().is_success() {
        let error_text = response
            .text()
            .unwrap_or_else(|_| "Unknown error".to_string());
        anyhow::bail!("Qdrant returned error: {}", error_text);
    }

    println!("✅ Successfully ingested PDF into Qdrant!");
    println!("📊 Stored {} chunks from {}", chunks.len(), args.pdf_path);

    Ok(())
}
