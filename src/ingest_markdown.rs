// Copyright (c) 2025 Michael A. Wright
// Licensed under the MIT License

use anyhow::{Context, Result};
use clap::Parser;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::fs;
use uuid::Uuid;

#[derive(Parser, Debug)]
#[command(author, version, about = "Ingest Markdown with smart chunking", long_about = None)]
struct Args {
    #[arg(help = "Path to Markdown file")]
    md_path: String,

    #[arg(short, long, default_value = "1500", help = "Max characters per chunk")]
    chunk_size: usize,

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

#[derive(Debug, Clone)]
struct MarkdownChunk {
    content: String,
    chunk_type: ChunkType,
    header_context: String,
    #[allow(dead_code)]
    index: usize,
}

#[derive(Debug, Clone, Serialize)]
enum ChunkType {
    #[allow(dead_code)]
    Header,
    CodeBlock,
    Text,
    #[allow(dead_code)]
    List,
    #[allow(dead_code)]
    Table,
}

fn smart_chunk_markdown(content: &str, max_chunk_size: usize) -> Vec<MarkdownChunk> {
    let mut chunks = Vec::new();
    let lines: Vec<&str> = content.lines().collect();
    let mut current_chunk = String::new();
    let mut current_header = String::new();
    let mut in_code_block = false;
    let mut code_block = String::new();
    let mut chunk_index = 0;

    for line in lines {
        // Detect headers
        if line.starts_with('#') && !in_code_block {
            // Save previous chunk if exists
            if !current_chunk.is_empty() {
                chunks.push(MarkdownChunk {
                    content: current_chunk.clone(),
                    chunk_type: ChunkType::Text,
                    header_context: current_header.clone(),
                    index: chunk_index,
                });
                chunk_index += 1;
                current_chunk.clear();
            }

            // Update header context
            let level = line.chars().take_while(|c| *c == '#').count();
            if level <= 2 {
                // Only track h1 and h2
                current_header = line.to_string();
            }

            current_chunk.push_str(line);
            current_chunk.push('\n');
        }
        // Detect code blocks
        else if line.trim().starts_with("```") {
            if in_code_block {
                // End of code block
                code_block.push_str(line);
                code_block.push('\n');

                // Save code block as single chunk (don't split code)
                chunks.push(MarkdownChunk {
                    content: code_block.clone(),
                    chunk_type: ChunkType::CodeBlock,
                    header_context: current_header.clone(),
                    index: chunk_index,
                });
                chunk_index += 1;

                code_block.clear();
                in_code_block = false;
            } else {
                // Start of code block
                // Save current chunk if exists
                if !current_chunk.is_empty() {
                    chunks.push(MarkdownChunk {
                        content: current_chunk.clone(),
                        chunk_type: ChunkType::Text,
                        header_context: current_header.clone(),
                        index: chunk_index,
                    });
                    chunk_index += 1;
                    current_chunk.clear();
                }

                in_code_block = true;
                code_block.push_str(line);
                code_block.push('\n');
            }
        } else if in_code_block {
            // Inside code block
            code_block.push_str(line);
            code_block.push('\n');
        } else {
            // Regular text
            current_chunk.push_str(line);
            current_chunk.push('\n');

            // Check if chunk is getting too large
            if current_chunk.len() > max_chunk_size {
                // Try to break at paragraph boundary
                if line.trim().is_empty() {
                    chunks.push(MarkdownChunk {
                        content: current_chunk.clone(),
                        chunk_type: ChunkType::Text,
                        header_context: current_header.clone(),
                        index: chunk_index,
                    });
                    chunk_index += 1;
                    current_chunk.clear();
                }
            }
        }
    }

    // Save any remaining content
    if !current_chunk.is_empty() {
        chunks.push(MarkdownChunk {
            content: current_chunk,
            chunk_type: ChunkType::Text,
            header_context: current_header.clone(),
            index: chunk_index,
        });
    }

    if !code_block.is_empty() {
        chunks.push(MarkdownChunk {
            content: code_block,
            chunk_type: ChunkType::CodeBlock,
            header_context: current_header,
            index: chunk_index,
        });
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

    // Read markdown file
    println!("📄 Reading Markdown: {}", args.md_path);
    let content = fs::read_to_string(&args.md_path).context("Failed to read Markdown file")?;

    // Smart chunking
    println!("✂️  Smart chunking (preserving code blocks and structure)...");
    let chunks = smart_chunk_markdown(&content, args.chunk_size);

    println!("📦 Created {} chunks:", chunks.len());
    let code_chunks = chunks
        .iter()
        .filter(|c| matches!(c.chunk_type, ChunkType::CodeBlock))
        .count();
    let text_chunks = chunks
        .iter()
        .filter(|c| matches!(c.chunk_type, ChunkType::Text))
        .count();
    println!("   Code blocks: {}", code_chunks);
    println!("   Text sections: {}", text_chunks);

    // Generate embeddings and prepare points
    println!("🧮 Generating embeddings with model: {}", args.model);
    let mut points = Vec::new();

    for (i, chunk) in chunks.iter().enumerate() {
        print!("  Processing chunk {}/{}...\r", i + 1, chunks.len());

        // For code blocks, include the header context in the embedding
        let embedding_text = if matches!(chunk.chunk_type, ChunkType::CodeBlock)
            && !chunk.header_context.is_empty()
        {
            format!("{}\n\n{}", chunk.header_context, chunk.content)
        } else {
            chunk.content.clone()
        };

        let embedding = get_embedding(&client, &args.ollama_url, &args.model, &embedding_text)?;

        let point = QdrantPoint {
            id: Uuid::new_v4().to_string(),
            vector: embedding,
            payload: json!({
                "text": chunk.content,
                "source": args.md_path,
                "chunk_index": i,
                "total_chunks": chunks.len(),
                "chunk_type": chunk.chunk_type,
                "header_context": chunk.header_context,
                "is_code": matches!(chunk.chunk_type, ChunkType::CodeBlock),
            }),
        };

        points.push(point);
    }
    println!("\n✅ Generated embeddings for all chunks");

    // Upload to Qdrant in batches
    println!("📤 Uploading to Qdrant collection: {}", args.collection);
    let batch_size = 100;
    let total_batches = points.len().div_ceil(batch_size);

    for (i, batch) in points.chunks(batch_size).enumerate() {
        print!("  Uploading batch {}/{}...\r", i + 1, total_batches);

        let response = client
            .put(format!(
                "{}/collections/{}/points",
                args.qdrant_url, args.collection
            ))
            .json(&json!({
                "points": batch
            }))
            .send()
            .context("Failed to upload to Qdrant")?;

        if !response.status().is_success() {
            let error_text = response
                .text()
                .unwrap_or_else(|_| "Unknown error".to_string());
            anyhow::bail!("Qdrant returned error in batch {}: {}", i + 1, error_text);
        }
    }
    println!();

    println!("✅ Successfully ingested Markdown into Qdrant!");
    println!("📊 Summary:");
    println!("   Total chunks: {}", chunks.len());
    println!("   Code blocks preserved: {}", code_chunks);
    println!("   Source: {}", args.md_path);

    Ok(())
}
