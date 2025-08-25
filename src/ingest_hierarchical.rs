use anyhow::{Context, Result};
use clap::Parser;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use std::fs;
use uuid::Uuid;

#[derive(Parser, Debug)]
#[command(author, version, about = "Hierarchical parent-child ingestion based on research", long_about = None)]
struct Args {
    #[arg(help = "Path to Markdown file")]
    md_path: String,

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
struct ParentChunk {
    id: String,
    content: String,
    start_line: usize,
    end_line: usize,
    headers: Vec<String>,
    child_ids: Vec<String>,
    summary: String,
}

#[derive(Debug, Clone)]
struct ChildChunk {
    id: String,
    parent_id: String,
    content: String,
    start_line: usize,
    end_line: usize,
    chunk_type: ChunkType,
    index_in_parent: usize,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
enum ChunkType {
    Code,
    Text,
    Header,
    List,
    Mixed,
}

/// Based on research: ~400 tokens (1600 chars) for children, 2000-4000 chars for parents
const CHILD_TARGET_SIZE: usize = 1600;
const PARENT_TARGET_SIZE: usize = 4000;
const MIN_PARENT_SIZE: usize = 2000;

fn create_hierarchical_chunks(content: &str) -> (Vec<ParentChunk>, Vec<ChildChunk>) {
    let mut parent_chunks = Vec::new();
    let mut child_chunks = Vec::new();
    let lines: Vec<&str> = content.lines().collect();

    let mut current_parent = String::new();
    let mut current_parent_start = 0;
    let mut current_headers: Vec<String> = Vec::new();
    let mut current_child_ids = Vec::new();

    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];

        // Detect section boundaries (H1 and H2)
        if line.starts_with("##") && !line.starts_with("###") {
            // Save current parent if substantial
            if current_parent.len() > MIN_PARENT_SIZE {
                let parent_id = Uuid::new_v4().to_string();
                let summary = create_summary(&current_parent, &current_headers);

                parent_chunks.push(ParentChunk {
                    id: parent_id.clone(),
                    content: current_parent.clone(),
                    start_line: current_parent_start,
                    end_line: i - 1,
                    headers: current_headers.clone(),
                    child_ids: current_child_ids.clone(),
                    summary,
                });

                current_parent.clear();
                current_child_ids.clear();
                current_parent_start = i;
            }

            // Update headers
            current_headers = vec![line.to_string()];
        } else if line.starts_with("#") && !line.starts_with("##") {
            // H1 - major section
            if !current_parent.is_empty() {
                let parent_id = Uuid::new_v4().to_string();
                let summary = create_summary(&current_parent, &current_headers);

                parent_chunks.push(ParentChunk {
                    id: parent_id.clone(),
                    content: current_parent.clone(),
                    start_line: current_parent_start,
                    end_line: i - 1,
                    headers: current_headers.clone(),
                    child_ids: current_child_ids.clone(),
                    summary,
                });

                current_parent.clear();
                current_child_ids.clear();
                current_parent_start = i;
            }
            current_headers = vec![line.to_string()];
        } else if line.starts_with("###") {
            // H3 - subsection, add to headers
            if current_headers.len() < 3 {
                current_headers.push(line.to_string());
            }
        }

        // Add line to parent
        current_parent.push_str(line);
        current_parent.push('\n');

        // Check if we should create a parent chunk
        if current_parent.len() >= PARENT_TARGET_SIZE {
            // Look for natural break point
            let mut break_point = i;
            for j in (i.saturating_sub(5)..=i).rev() {
                if j < lines.len() && lines[j].trim().is_empty() {
                    break_point = j;
                    break;
                }
            }

            // Create parent and its children
            let parent_id = Uuid::new_v4().to_string();
            let parent_content = lines[current_parent_start..=break_point].join("\n");
            let children = create_child_chunks(&parent_content, &parent_id, current_parent_start);

            for child in &children {
                current_child_ids.push(child.id.clone());
            }
            child_chunks.extend(children);

            let summary = create_summary(&parent_content, &current_headers);
            parent_chunks.push(ParentChunk {
                id: parent_id.clone(),
                content: parent_content,
                start_line: current_parent_start,
                end_line: break_point,
                headers: current_headers.clone(),
                child_ids: current_child_ids.clone(),
                summary,
            });

            // Reset for next parent
            current_parent.clear();
            current_child_ids.clear();
            current_parent_start = break_point + 1;
            i = break_point;
        }

        i += 1;
    }

    // Handle remaining content
    if !current_parent.trim().is_empty() {
        let parent_id = Uuid::new_v4().to_string();
        let children = create_child_chunks(&current_parent, &parent_id, current_parent_start);

        for child in &children {
            current_child_ids.push(child.id.clone());
        }
        child_chunks.extend(children);

        let summary = create_summary(&current_parent, &current_headers);
        parent_chunks.push(ParentChunk {
            id: parent_id,
            content: current_parent,
            start_line: current_parent_start,
            end_line: lines.len() - 1,
            headers: current_headers,
            child_ids: current_child_ids,
            summary,
        });
    }

    (parent_chunks, child_chunks)
}

fn create_child_chunks(
    parent_content: &str,
    parent_id: &str,
    parent_start_line: usize,
) -> Vec<ChildChunk> {
    let mut children = Vec::new();
    let lines: Vec<&str> = parent_content.lines().collect();

    let mut current_chunk = String::new();
    let mut chunk_start = 0;
    let mut in_code_block = false;
    let mut chunk_type = ChunkType::Text;
    let mut has_code = false;

    for (i, line) in lines.iter().enumerate() {
        // Track code blocks
        if line.trim().starts_with("```") {
            if !in_code_block {
                // Starting code block - save current chunk if exists
                if current_chunk.len() > 300 {
                    children.push(ChildChunk {
                        id: Uuid::new_v4().to_string(),
                        parent_id: parent_id.to_string(),
                        content: current_chunk.clone(),
                        start_line: parent_start_line + chunk_start,
                        end_line: parent_start_line + i - 1,
                        chunk_type: if has_code {
                            ChunkType::Mixed
                        } else {
                            chunk_type.clone()
                        },
                        index_in_parent: children.len(),
                    });
                    current_chunk.clear();
                    chunk_start = i;
                    has_code = false;
                }
                in_code_block = true;
                chunk_type = ChunkType::Code;
            } else {
                // Ending code block
                in_code_block = false;
                has_code = true;
            }
        }

        // Detect chunk types
        if !in_code_block {
            if line.starts_with('#') {
                chunk_type = ChunkType::Header;
            } else if line.trim().starts_with('-')
                || line.trim().starts_with('*')
                || line.trim().starts_with('1')
            {
                chunk_type = ChunkType::List;
            } else if chunk_type == ChunkType::Code {
                chunk_type = ChunkType::Text;
            }
        }

        current_chunk.push_str(line);
        current_chunk.push('\n');

        // Create child chunk at target size (but not in middle of code)
        if !in_code_block && current_chunk.len() >= CHILD_TARGET_SIZE {
            // Find natural break
            if line.trim().is_empty() || (i + 1 < lines.len() && lines[i + 1].starts_with('#')) {
                children.push(ChildChunk {
                    id: Uuid::new_v4().to_string(),
                    parent_id: parent_id.to_string(),
                    content: current_chunk.clone(),
                    start_line: parent_start_line + chunk_start,
                    end_line: parent_start_line + i,
                    chunk_type: if has_code {
                        ChunkType::Mixed
                    } else {
                        chunk_type.clone()
                    },
                    index_in_parent: children.len(),
                });
                current_chunk.clear();
                chunk_start = i + 1;
                chunk_type = ChunkType::Text;
                has_code = false;
            }
        }
    }

    // Add remaining content
    if !current_chunk.trim().is_empty() {
        children.push(ChildChunk {
            id: Uuid::new_v4().to_string(),
            parent_id: parent_id.to_string(),
            content: current_chunk,
            start_line: parent_start_line + chunk_start,
            end_line: parent_start_line + lines.len() - 1,
            chunk_type: if has_code {
                ChunkType::Mixed
            } else {
                chunk_type
            },
            index_in_parent: children.len(),
        });
    }

    children
}

fn create_summary(content: &str, headers: &[String]) -> String {
    // Simple summary: headers + first paragraph
    let mut summary = headers.join(" > ");

    // Find first substantial paragraph
    for line in content.lines() {
        if !line.starts_with('#') && !line.trim().is_empty() && line.len() > 50 {
            summary.push_str(" | ");
            summary.push_str(&line[..line.len().min(200)]);
            if line.len() > 200 {
                summary.push_str("...");
            }
            break;
        }
    }

    summary
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

    // Create hierarchical chunks
    println!("🎯 Creating hierarchical parent-child chunks...");
    println!("   Research-based sizes: ~400 tokens for children, 1000-2000 tokens for parents");
    let (parent_chunks, child_chunks) = create_hierarchical_chunks(&content);

    println!("📦 Created chunks:");
    println!(
        "   Parent chunks: {} (avg {} chars)",
        parent_chunks.len(),
        parent_chunks.iter().map(|p| p.content.len()).sum::<usize>() / parent_chunks.len().max(1)
    );
    println!(
        "   Child chunks: {} (avg {} chars)",
        child_chunks.len(),
        child_chunks.iter().map(|c| c.content.len()).sum::<usize>() / child_chunks.len().max(1)
    );

    // Count chunk types
    let code_chunks = child_chunks
        .iter()
        .filter(|c| matches!(c.chunk_type, ChunkType::Code))
        .count();
    let mixed_chunks = child_chunks
        .iter()
        .filter(|c| matches!(c.chunk_type, ChunkType::Mixed))
        .count();
    println!("   Code chunks: {}", code_chunks);
    println!("   Mixed (code+text) chunks: {}", mixed_chunks);

    // Ensure collection exists with proper configuration
    println!("🔧 Checking Qdrant collection...");

    // Check if collection exists
    let check_response = client
        .get(format!(
            "{}/collections/{}",
            args.qdrant_url, args.collection
        ))
        .send();

    if check_response.is_err() || !check_response.unwrap().status().is_success() {
        // Collection doesn't exist, create it
        println!("   Creating new collection...");
        let collection_config = json!({
            "vectors": {
                "size": 768,
                "distance": "Cosine"
            },
            "sparse_vectors": {
                "text": {}  // For keyword/BM25 search
            }
        });

        let response = client
            .put(format!(
                "{}/collections/{}",
                args.qdrant_url, args.collection
            ))
            .json(&collection_config)
            .send()
            .context("Failed to create collection")?;

        if !response.status().is_success() {
            println!(
                "Warning: Collection creation returned: {}",
                response.status()
            );
        }
    } else {
        println!("   Using existing collection");
    }

    // Generate embeddings for parents
    println!("🧮 Generating embeddings for parent chunks...");
    let mut parent_points = Vec::new();

    for (i, parent) in parent_chunks.iter().enumerate() {
        print!("  Processing parent {}/{}...\r", i + 1, parent_chunks.len());

        // Embed summary + headers for better retrieval
        let embedding_text = format!("{}\n\n{}", parent.summary, parent.content);
        let embedding = get_embedding(&client, &args.ollama_url, &args.model, &embedding_text)?;

        parent_points.push(QdrantPoint {
            id: parent.id.clone(),
            vector: embedding,
            payload: json!({
                "text": parent.content,
                "source": args.md_path,
                "chunk_type": "parent",
                "summary": parent.summary,
                "headers": parent.headers,
                "child_ids": parent.child_ids,
                "start_line": parent.start_line,
                "end_line": parent.end_line,
                "char_count": parent.content.len(),
            }),
        });
    }
    println!("\n✅ Generated parent embeddings");

    // Generate embeddings for children
    println!("🧮 Generating embeddings for child chunks...");
    let mut child_points = Vec::new();

    // Create parent lookup for context
    let parent_map: HashMap<String, &ParentChunk> =
        parent_chunks.iter().map(|p| (p.id.clone(), p)).collect();

    for (i, child) in child_chunks.iter().enumerate() {
        print!("  Processing child {}/{}...\r", i + 1, child_chunks.len());

        // Include parent context in child embedding for better retrieval
        let parent = parent_map.get(&child.parent_id);
        let embedding_text = if let Some(p) = parent {
            format!("{}\n\n{}", p.headers.join(" > "), child.content)
        } else {
            child.content.clone()
        };

        let embedding = get_embedding(&client, &args.ollama_url, &args.model, &embedding_text)?;

        child_points.push(QdrantPoint {
            id: child.id.clone(),
            vector: embedding,
            payload: json!({
                "text": child.content,
                "source": args.md_path,
                "chunk_type": format!("child_{:?}", child.chunk_type).to_lowercase(),
                "parent_id": child.parent_id,
                "parent_summary": parent.map(|p| &p.summary),
                "index_in_parent": child.index_in_parent,
                "start_line": child.start_line,
                "end_line": child.end_line,
                "char_count": child.content.len(),
            }),
        });
    }
    println!("\n✅ Generated child embeddings");

    // Upload all points
    println!("📤 Uploading to Qdrant...");
    let all_points: Vec<QdrantPoint> = parent_points
        .into_iter()
        .chain(child_points.into_iter())
        .collect();

    let batch_size = 100;
    for (i, batch) in all_points.chunks(batch_size).enumerate() {
        print!(
            "  Uploading batch {}/{}...\r",
            i + 1,
            (all_points.len() + batch_size - 1) / batch_size
        );

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
            anyhow::bail!("Qdrant upload failed: {}", error_text);
        }
    }
    println!();

    println!("✅ Successfully ingested with hierarchical chunking!");
    println!("\n📊 Summary:");
    println!("   Total vectors: {}", all_points.len());
    println!(
        "   Parent chunks: {} (provide context)",
        parent_chunks.len()
    );
    println!(
        "   Child chunks: {} (precise retrieval)",
        child_chunks.len()
    );
    println!("\n💡 Search strategy:");
    println!("   1. Search returns matching child chunks");
    println!("   2. System retrieves parent for full context");
    println!("   3. Both child (precise) and parent (context) provided to LLM");

    Ok(())
}
