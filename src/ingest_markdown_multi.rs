use anyhow::{Context, Result};
use clap::Parser;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::fs;
use uuid::Uuid;

#[derive(Parser, Debug)]
#[command(author, version, about = "Multi-scale Markdown ingestion", long_about = None)]
struct Args {
    #[arg(help = "Path to Markdown file")]
    md_path: String,

    #[arg(long, default_value = "documents", help = "Base collection name")]
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

    #[arg(long, help = "Enable multi-scale ingestion")]
    multi_scale: bool,
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
struct Chunk {
    content: String,
    start_line: usize,
    end_line: usize,
    chunk_size: ChunkSize,
    has_code: bool,
    headers: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
enum ChunkSize {
    Small,  // ~500-1000 chars
    Medium, // ~2000-3000 chars
    Large,  // ~4000-6000 chars
}

fn create_multi_scale_chunks(content: &str) -> Vec<Chunk> {
    let mut chunks = Vec::new();
    let lines: Vec<&str> = content.lines().collect();

    // Chunk sizes with overlap
    let configs = vec![
        (ChunkSize::Small, 1000, 200),  // 1000 chars, 200 overlap
        (ChunkSize::Medium, 3000, 500), // 3000 chars, 500 overlap
        (ChunkSize::Large, 6000, 1000), // 6000 chars, 1000 overlap
    ];

    for (size_type, target_size, overlap) in configs {
        let mut current_chunk = String::new();
        let mut start_line = 0;
        let mut current_headers = Vec::new();
        let mut has_code = false;
        let mut in_code_block = false;

        for (i, line) in lines.iter().enumerate() {
            // Track headers for context
            if line.starts_with('#') && !in_code_block {
                let level = line.chars().take_while(|c| *c == '#').count();
                if level <= 2 {
                    current_headers.clear();
                    current_headers.push(line.to_string());
                } else if level == 3 {
                    current_headers.truncate(1);
                    current_headers.push(line.to_string());
                }
            }

            // Track code blocks
            if line.trim().starts_with("```") {
                in_code_block = !in_code_block;
                if in_code_block {
                    has_code = true;
                }
            }

            current_chunk.push_str(line);
            current_chunk.push('\n');

            // Check if we should create a chunk
            let should_chunk = current_chunk.len() >= target_size && {
                // Try to break at natural boundaries
                !in_code_block
                    && (
                        line.trim().is_empty() ||          // Paragraph break
                    lines.get(i + 1).map_or(true, |next| next.starts_with('#'))
                        // Before header
                    )
            };

            if should_chunk {
                chunks.push(Chunk {
                    content: current_chunk.clone(),
                    start_line,
                    end_line: i,
                    chunk_size: size_type.clone(),
                    has_code,
                    headers: current_headers.clone(),
                });

                // Overlap: go back some characters
                let overlap_start = current_chunk.len().saturating_sub(overlap);
                current_chunk = current_chunk[overlap_start..].to_string();
                start_line = i.saturating_sub(10); // Rough line overlap
                has_code = in_code_block;
            }
        }

        // Add remaining content
        if !current_chunk.trim().is_empty() {
            chunks.push(Chunk {
                content: current_chunk,
                start_line,
                end_line: lines.len() - 1,
                chunk_size: size_type,
                has_code,
                headers: current_headers,
            });
        }
    }

    chunks
}

fn semantic_chunk_markdown(content: &str, target_size: usize) -> Vec<Chunk> {
    let mut chunks = Vec::new();
    let lines: Vec<&str> = content.lines().collect();
    let mut current_chunk = String::new();
    let mut start_line = 0;
    let mut current_headers = Vec::new();
    let mut in_code_block = false;
    let mut has_code = false;
    let mut code_block_buffer = String::new();

    for (i, line) in lines.iter().enumerate() {
        // Track headers
        if line.starts_with('#') && !in_code_block {
            let level = line.chars().take_while(|c| *c == '#').count();

            // Major section boundary - save current chunk if substantial
            if level <= 2 && current_chunk.len() > 500 {
                chunks.push(Chunk {
                    content: current_chunk.clone(),
                    start_line,
                    end_line: i - 1,
                    chunk_size: ChunkSize::Medium,
                    has_code,
                    headers: current_headers.clone(),
                });
                current_chunk.clear();
                start_line = i;
                has_code = false;
            }

            // Update header context
            if level <= 2 {
                current_headers.clear();
                current_headers.push(line.to_string());
            } else if level == 3 {
                current_headers.truncate(1);
                current_headers.push(line.to_string());
            }
        }

        // Handle code blocks
        if line.trim().starts_with("```") {
            if !in_code_block {
                // Starting code block - save any pending content first
                if !current_chunk.is_empty() && current_chunk.len() > 300 {
                    chunks.push(Chunk {
                        content: current_chunk.clone(),
                        start_line,
                        end_line: i - 1,
                        chunk_size: ChunkSize::Medium,
                        has_code: false,
                        headers: current_headers.clone(),
                    });
                    current_chunk.clear();
                    start_line = i;
                }
                in_code_block = true;
                has_code = true;
                code_block_buffer.clear();
            } else {
                // Ending code block
                in_code_block = false;
                code_block_buffer.push_str(line);
                code_block_buffer.push('\n');

                // Add code block to current chunk
                current_chunk.push_str(&code_block_buffer);
                code_block_buffer.clear();
                continue;
            }
        }

        if in_code_block {
            code_block_buffer.push_str(line);
            code_block_buffer.push('\n');
        } else {
            current_chunk.push_str(line);
            current_chunk.push('\n');
        }

        // Check if we should create a chunk (but not in middle of code)
        if !in_code_block && current_chunk.len() >= target_size {
            // Look for good break point
            if line.trim().is_empty() || lines.get(i + 1).map_or(true, |next| next.starts_with('#'))
            {
                chunks.push(Chunk {
                    content: current_chunk.clone(),
                    start_line,
                    end_line: i,
                    chunk_size: ChunkSize::Medium,
                    has_code,
                    headers: current_headers.clone(),
                });
                current_chunk.clear();
                start_line = i + 1;
                has_code = false;
            }
        }
    }

    // Add remaining content
    if !current_chunk.trim().is_empty() || !code_block_buffer.is_empty() {
        current_chunk.push_str(&code_block_buffer);
        chunks.push(Chunk {
            content: current_chunk,
            start_line,
            end_line: lines.len() - 1,
            chunk_size: ChunkSize::Medium,
            has_code,
            headers: current_headers,
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

    // Create chunks
    let chunks = if args.multi_scale {
        println!("🎯 Multi-scale chunking...");
        create_multi_scale_chunks(&content)
    } else {
        println!("📝 Semantic chunking (target ~3000 chars)...");
        semantic_chunk_markdown(&content, 3000)
    };

    // Show statistics
    let small = chunks
        .iter()
        .filter(|c| matches!(c.chunk_size, ChunkSize::Small))
        .count();
    let medium = chunks
        .iter()
        .filter(|c| matches!(c.chunk_size, ChunkSize::Medium))
        .count();
    let large = chunks
        .iter()
        .filter(|c| matches!(c.chunk_size, ChunkSize::Large))
        .count();
    let with_code = chunks.iter().filter(|c| c.has_code).count();

    println!("📦 Created {} chunks:", chunks.len());
    if args.multi_scale {
        println!("   Small chunks: {}", small);
        println!("   Medium chunks: {}", medium);
        println!("   Large chunks: {}", large);
    }
    println!("   Chunks with code: {}", with_code);
    println!(
        "   Average size: {} chars",
        chunks.iter().map(|c| c.content.len()).sum::<usize>() / chunks.len()
    );

    // Generate embeddings and prepare points
    println!("🧮 Generating embeddings with model: {}", args.model);
    let mut points = Vec::new();

    for (i, chunk) in chunks.iter().enumerate() {
        print!("  Processing chunk {}/{}...\r", i + 1, chunks.len());

        // For chunks with code, include headers in embedding for better search
        let embedding_text = if chunk.has_code && !chunk.headers.is_empty() {
            format!("{}\n\n{}", chunk.headers.join("\n"), chunk.content)
        } else {
            chunk.content.clone()
        };

        let embedding = get_embedding(&client, &args.ollama_url, &args.model, &embedding_text)?;

        // Determine collection based on chunk size
        let collection_name = if args.multi_scale {
            match chunk.chunk_size {
                ChunkSize::Small => format!("{}_small", args.collection),
                ChunkSize::Medium => format!("{}_medium", args.collection),
                ChunkSize::Large => format!("{}_large", args.collection),
            }
        } else {
            args.collection.clone()
        };

        let point = QdrantPoint {
            id: Uuid::new_v4().to_string(),
            vector: embedding,
            payload: json!({
                "text": chunk.content,
                "source": args.md_path,
                "chunk_index": i,
                "total_chunks": chunks.len(),
                "chunk_size": chunk.chunk_size,
                "has_code": chunk.has_code,
                "headers": chunk.headers,
                "start_line": chunk.start_line,
                "end_line": chunk.end_line,
                "char_count": chunk.content.len(),
            }),
        };

        points.push((collection_name, point));
    }
    println!("\n✅ Generated embeddings for all chunks");

    // Group points by collection
    let mut collections: std::collections::HashMap<String, Vec<QdrantPoint>> =
        std::collections::HashMap::new();
    for (collection, point) in points {
        collections
            .entry(collection)
            .or_insert_with(Vec::new)
            .push(point);
    }

    // Upload to Qdrant
    for (collection_name, points) in collections {
        println!(
            "📤 Uploading {} chunks to collection: {}",
            points.len(),
            collection_name
        );

        // Ensure collection exists
        let _ = client
            .put(format!(
                "{}/collections/{}",
                args.qdrant_url, collection_name
            ))
            .json(&json!({
                "vectors": {
                    "size": 768,
                    "distance": "Cosine"
                }
            }))
            .send();

        // Upload in batches
        let batch_size = 100;
        for (i, batch) in points.chunks(batch_size).enumerate() {
            print!(
                "  Uploading batch {}/{}...\r",
                i + 1,
                (points.len() + batch_size - 1) / batch_size
            );

            let response = client
                .put(format!(
                    "{}/collections/{}/points",
                    args.qdrant_url, collection_name
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
                anyhow::bail!("Qdrant returned error: {}", error_text);
            }
        }
        println!();
    }

    println!("✅ Successfully ingested Markdown into Qdrant!");
    if args.multi_scale {
        println!("📊 Created 3 collections with different chunk sizes");
        println!("   Use hybrid search across all three for best results");
    }

    Ok(())
}
