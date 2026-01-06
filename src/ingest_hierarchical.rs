// Copyright (c) 2025 Michael A. Wright
// Licensed under the MIT License

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

/// Based on research: ~400 tokens for children, ~1000 tokens for parents
/// Reduced to stay under embedding model's ~2000 char limit
const CHILD_TARGET_SIZE: usize = 1200;
const PARENT_TARGET_SIZE: usize = 1800;
const MIN_PARENT_SIZE: usize = 800;

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

/// Safely truncate a string at a character boundary
fn safe_truncate(s: &str, max_chars: usize) -> &str {
    if s.chars().count() <= max_chars {
        s
    } else {
        // Find the byte position of the nth character
        let byte_pos = s
            .char_indices()
            .nth(max_chars)
            .map(|(pos, _)| pos)
            .unwrap_or(s.len());
        &s[..byte_pos]
    }
}

fn create_summary(content: &str, headers: &[String]) -> String {
    // Simple summary: headers + first paragraph
    let mut summary = headers.join(" > ");

    // Find first substantial paragraph
    for line in content.lines() {
        if !line.starts_with('#') && !line.trim().is_empty() && line.chars().count() > 50 {
            summary.push_str(" | ");
            let truncated = safe_truncate(line, 200);
            summary.push_str(truncated);
            if line.chars().count() > 200 {
                summary.push_str("...");
            }
            break;
        }
    }

    summary
}

/// Maximum characters to send to embedding model (nomic-embed-text crashes around 2500)
const MAX_EMBEDDING_CHARS: usize = 2000;

/// Sanitize text for embedding by replacing problematic Unicode with ASCII equivalents
fn sanitize_for_embedding(text: &str) -> String {
    let mut result = String::with_capacity(text.len());

    for c in text.chars() {
        let replacement = match c {
            // Box drawing characters → ASCII
            '═' | '─' | '━' | '╌' | '╍' | '┄' | '┅' | '┈' | '┉' => '-',
            '│' | '┃' | '╎' | '╏' | '┆' | '┇' | '┊' | '┋' => '|',
            '┌' | '┍' | '┎' | '┏' | '╒' | '╓' | '╔' => '+',
            '┐' | '┑' | '┒' | '┓' | '╕' | '╖' | '╗' => '+',
            '└' | '┕' | '┖' | '┗' | '╘' | '╙' | '╚' => '+',
            '┘' | '┙' | '┚' | '┛' | '╛' | '╜' | '╝' => '+',
            '├' | '┝' | '┞' | '┟' | '┠' | '┡' | '┢' | '┣' | '╞' | '╟' | '╠' => {
                '+'
            }
            '┤' | '┥' | '┦' | '┧' | '┨' | '┩' | '┪' | '┫' | '╡' | '╢' | '╣' => {
                '+'
            }
            '┬' | '┭' | '┮' | '┯' | '┰' | '┱' | '┲' | '┳' | '╤' | '╥' | '╦' => {
                '+'
            }
            '┴' | '┵' | '┶' | '┷' | '┸' | '┹' | '┺' | '┻' | '╧' | '╨' | '╩' => {
                '+'
            }
            '┼' | '┽' | '┾' | '┿' | '╀' | '╁' | '╂' | '╃' | '╄' | '╅' | '╆' | '╇' | '╈' | '╉'
            | '╊' | '╋' | '╪' | '╫' | '╬' => '+',
            // Block elements → asterisk or space
            '█' | '▓' | '▒' | '░' | '▀' | '▄' | '▌' | '▐' => '*',
            // Arrows → ASCII arrows
            '→' | '⇒' | '➔' | '➜' | '➝' | '➞' => '>',
            '←' | '⇐' => '<',
            '↑' | '⇑' => '^',
            '↓' | '⇓' => 'v',
            // Common emoji → descriptive or skip (keep as single char to preserve meaning)
            '✓' | '✔' | '☑' => 'Y',
            '✗' | '✘' | '☒' => 'X',
            '★' | '☆' | '⭐' => '*',
            '•' | '◦' | '‣' | '⁃' => '-',
            // Smart quotes → regular quotes
            '\u{2018}' | '\u{2019}' | '\u{201A}' | '\u{201B}' => '\'', // ' ' ‚ ‛
            '\u{201C}' | '\u{201D}' | '\u{201E}' | '\u{201F}' => '"',  // " " „ ‟
            // Dashes → regular dash
            '–' | '—' | '―' => '-',
            // Ellipsis
            '…' => '.',
            // Common status/UI emoji → skip entirely (return space to preserve word boundaries)
            '🔍' | '📦' | '🎯' | '✅' | '❌' | '⚠' | '💭' | '📄' | '📊' | '📚' | '🚀' | '💡'
            | '⏳' | '✨' | '🖥' | '🔨' | '🔧' | '🏷' | '🔄' | '▶' | '🔐' | '🗑' | '📜' | '⚙'
            | '🏥' | '🧮' | '📤' | '🛑' => ' ',
            // Everything else passes through
            _ => c,
        };
        result.push(replacement);
    }

    // Collapse multiple spaces
    let mut prev_space = false;
    result
        .chars()
        .filter(|&c| {
            let is_space = c == ' ';
            let keep = !is_space || !prev_space;
            prev_space = is_space;
            keep
        })
        .collect()
}

/// Maximum retries for embedding requests
const MAX_RETRIES: u32 = 5;
/// Delay between retries in milliseconds (increases with each retry)
const BASE_RETRY_DELAY_MS: u64 = 500;

fn get_embedding(client: &Client, ollama_url: &str, model: &str, text: &str) -> Result<Vec<f32>> {
    // Sanitize and truncate text for embedding model
    let sanitized = sanitize_for_embedding(text);
    let prompt = safe_truncate(&sanitized, MAX_EMBEDDING_CHARS).to_string();

    let request = EmbeddingRequest {
        model: model.to_string(),
        prompt,
    };

    // Retry logic with exponential backoff for transient failures
    let mut last_error = None;
    for attempt in 0..MAX_RETRIES {
        if attempt > 0 {
            // Exponential backoff: 500ms, 1000ms, 2000ms, 4000ms
            let delay = BASE_RETRY_DELAY_MS * (1 << (attempt - 1));
            std::thread::sleep(std::time::Duration::from_millis(delay));

            // On retry, try to "wake up" the model by sending a tiny test request
            let _ = client
                .post(format!("{}/api/embeddings", ollama_url))
                .json(&EmbeddingRequest {
                    model: model.to_string(),
                    prompt: "test".to_string(),
                })
                .send();
            std::thread::sleep(std::time::Duration::from_millis(100));
        }

        let response = client
            .post(format!("{}/api/embeddings", ollama_url))
            .json(&request)
            .send();

        match response {
            Ok(resp) => {
                if resp.status().is_success() {
                    match resp.json::<EmbeddingResponse>() {
                        Ok(embedding) => return Ok(embedding.embedding),
                        Err(e) => {
                            last_error = Some(format!("Failed to parse response: {e}"));
                        }
                    }
                } else {
                    last_error = Some(format!("Ollama returned error: {}", resp.status()));
                }
            }
            Err(e) => {
                last_error = Some(format!("Request failed: {e}"));
            }
        }
    }

    anyhow::bail!(
        "Failed after {MAX_RETRIES} attempts: {}",
        last_error.unwrap_or_else(|| "Unknown error".to_string())
    );
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
    let all_points: Vec<QdrantPoint> = parent_points.into_iter().chain(child_points).collect();

    let batch_size = 100;
    for (i, batch) in all_points.chunks(batch_size).enumerate() {
        print!(
            "  Uploading batch {}/{}...\r",
            i + 1,
            all_points.len().div_ceil(batch_size)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_safe_truncate_ascii() {
        assert_eq!(safe_truncate("hello", 10), "hello");
        assert_eq!(safe_truncate("hello world", 5), "hello");
        assert_eq!(safe_truncate("", 5), "");
    }

    #[test]
    fn test_safe_truncate_unicode() {
        // Test with multi-byte UTF-8 characters
        let s = "═══════════"; // Each ═ is 3 bytes
        assert_eq!(safe_truncate(s, 3).chars().count(), 3);

        // Mix of ASCII and multi-byte
        let mixed = "Hello ═══ World";
        let truncated = safe_truncate(mixed, 8);
        assert_eq!(truncated, "Hello ══");
        assert!(truncated.is_char_boundary(truncated.len()));

        // Emoji (4 bytes each)
        let emoji = "🔍📦🎯";
        assert_eq!(safe_truncate(emoji, 2), "🔍📦");
    }

    #[test]
    fn test_sanitize_for_embedding_box_drawing() {
        // Box drawing chars should become ASCII
        assert_eq!(sanitize_for_embedding("═══"), "---");
        assert_eq!(sanitize_for_embedding("│text│"), "|text|");
        assert_eq!(sanitize_for_embedding("┌──┐"), "+--+");
    }

    #[test]
    fn test_sanitize_for_embedding_emoji() {
        // Status emoji should become spaces
        assert_eq!(sanitize_for_embedding("✅ Done"), " Done");
        assert_eq!(sanitize_for_embedding("🔍 Search"), " Search");
        // Check marks should become Y/X
        assert_eq!(sanitize_for_embedding("✓ Yes ✗ No"), "Y Yes X No");
    }

    #[test]
    fn test_sanitize_for_embedding_quotes_and_dashes() {
        // Smart quotes → regular quotes (use raw strings to include curly quotes)
        let smart_double = "\u{201C}quoted\u{201D}"; // "quoted"
        assert_eq!(sanitize_for_embedding(smart_double), "\"quoted\"");
        let smart_single = "\u{2018}single\u{2019}"; // 'single'
        assert_eq!(sanitize_for_embedding(smart_single), "'single'");
        // Em/en dashes → regular dash
        let dashes = "a\u{2014}b\u{2013}c"; // a—b–c
        assert_eq!(sanitize_for_embedding(dashes), "a-b-c");
    }

    #[test]
    fn test_sanitize_for_embedding_collapses_spaces() {
        // Multiple emoji → single space
        assert_eq!(sanitize_for_embedding("🔍🔍🔍text"), " text");
        assert_eq!(sanitize_for_embedding("a  b"), "a b");
    }

    #[test]
    fn test_create_summary_with_headers() {
        let content = "# Main Title\n\nThis is a substantial first paragraph that should be included in the summary.\n\nMore content here.";
        let headers = vec!["# Main Title".to_string()];

        let summary = create_summary(content, &headers);

        assert!(summary.contains("# Main Title"));
        assert!(summary.contains("This is a substantial first paragraph"));
    }

    #[test]
    fn test_create_summary_truncates_long_lines() {
        let content = "# Header\n\n".to_string() + &"a".repeat(300);
        let headers = vec!["# Header".to_string()];

        let summary = create_summary(&content, &headers);

        assert!(summary.contains("..."));
        assert!(summary.len() < content.len());
    }

    #[test]
    fn test_create_summary_empty_content() {
        let content = "";
        let headers = vec![];

        let summary = create_summary(content, &headers);

        assert_eq!(summary, "");
    }

    #[test]
    fn test_hierarchical_chunks_simple_text() {
        let content = "# Title\n\n".to_string() + &"Some content. ".repeat(200);

        let (parent_chunks, child_chunks) = create_hierarchical_chunks(&content);

        assert!(
            !parent_chunks.is_empty(),
            "Should create at least one parent chunk"
        );
        assert!(
            !child_chunks.is_empty(),
            "Should create at least one child chunk"
        );

        // Verify parent-child relationship
        for child in &child_chunks {
            assert!(
                parent_chunks
                    .iter()
                    .any(|p| p.child_ids.contains(&child.id)),
                "Each child should be referenced by a parent"
            );
        }
    }

    #[test]
    fn test_hierarchical_chunks_with_code_blocks() {
        let content = r#"# Code Example

Here is some code:

```rust
fn main() {
    println!("Hello, world!");
}
```

More text after code.
"#
        .to_string()
            + &"Additional content. ".repeat(100);

        let (parent_chunks, child_chunks) = create_hierarchical_chunks(&content);

        assert!(!parent_chunks.is_empty());
        assert!(!child_chunks.is_empty());

        // Check that code blocks are preserved in chunks
        let has_code = child_chunks.iter().any(|c| c.content.contains("```"));
        assert!(has_code, "Code blocks should be preserved in child chunks");
    }

    #[test]
    fn test_hierarchical_chunks_multiple_sections() {
        let content = format!(
            "# Section 1\n\n{}\n\n## Section 2\n\n{}\n\n### Subsection\n\n{}",
            "Content for section 1. ".repeat(150),
            "Content for section 2. ".repeat(150),
            "Content for subsection. ".repeat(150)
        );

        let (parent_chunks, _child_chunks) = create_hierarchical_chunks(&content);

        // Multiple sections should create multiple parents
        assert!(
            parent_chunks.len() >= 2,
            "Multiple sections should create multiple parent chunks"
        );

        // Headers should be captured
        assert!(
            parent_chunks.iter().any(|p| !p.headers.is_empty()),
            "Parent chunks should capture headers"
        );
    }

    #[test]
    fn test_child_chunks_respects_code_boundaries() {
        let parent_content = r#"Some intro text.

```rust
fn example() {
    let x = 1;
    let y = 2;
    println!("{}, {}", x, y);
}
```

More text after the code block.
"#;
        let parent_id = "test-parent-id";

        let children = create_child_chunks(parent_content, parent_id, 0);

        assert!(!children.is_empty());

        // Verify all children reference the same parent
        for child in &children {
            assert_eq!(child.parent_id, parent_id);
        }

        // Verify chunk types are detected
        let has_code_or_mixed = children
            .iter()
            .any(|c| c.chunk_type == ChunkType::Code || c.chunk_type == ChunkType::Mixed);
        assert!(has_code_or_mixed, "Should detect code chunk types");
    }

    #[test]
    fn test_child_chunks_handles_lists() {
        let parent_content = r#"# List Example

- Item 1
- Item 2
- Item 3

1. Numbered item 1
2. Numbered item 2

More text.
"#;
        let parent_id = "test-parent-id";

        let children = create_child_chunks(parent_content, parent_id, 0);

        assert!(!children.is_empty());

        // Should detect list types
        let has_list = children.iter().any(|c| c.chunk_type == ChunkType::List);
        assert!(has_list, "Should detect list chunk types");
    }

    #[test]
    fn test_child_chunks_minimum_content() {
        let parent_content = "Short content.";
        let parent_id = "test-parent-id";

        let children = create_child_chunks(parent_content, parent_id, 0);

        // Even short content should create at least one child
        assert_eq!(children.len(), 1, "Should create at least one child chunk");
        assert_eq!(children[0].content.trim(), "Short content.");
    }

    #[test]
    fn test_hierarchical_chunks_preserves_line_numbers() {
        let content = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5";

        let (parent_chunks, _child_chunks) = create_hierarchical_chunks(content);

        for parent in &parent_chunks {
            assert!(
                parent.end_line >= parent.start_line,
                "End line should be >= start line"
            );
        }
    }

    #[test]
    fn test_chunk_type_enum() {
        // Verify enum variants are serializable
        let code_type = ChunkType::Code;
        let text_type = ChunkType::Text;
        let header_type = ChunkType::Header;
        let list_type = ChunkType::List;
        let mixed_type = ChunkType::Mixed;

        assert_eq!(code_type, ChunkType::Code);
        assert_eq!(text_type, ChunkType::Text);
        assert_eq!(header_type, ChunkType::Header);
        assert_eq!(list_type, ChunkType::List);
        assert_eq!(mixed_type, ChunkType::Mixed);
    }

    #[test]
    fn test_hierarchical_chunks_min_parent_size() {
        // Content smaller than MIN_PARENT_SIZE
        let small_content = "# Small\n\nJust a bit of text.";

        let (parent_chunks, _child_chunks) = create_hierarchical_chunks(small_content);

        // Should still create a parent even if small (handled in final block)
        assert!(
            !parent_chunks.is_empty(),
            "Should create parent for small content"
        );
    }

    #[test]
    fn test_child_chunk_indexing() {
        let parent_content = "Content. ".repeat(300);
        let parent_id = "test-parent-id";

        let children = create_child_chunks(&parent_content, parent_id, 0);

        // Verify index_in_parent is sequential
        for (i, child) in children.iter().enumerate() {
            assert_eq!(
                child.index_in_parent, i,
                "Child index should match position"
            );
        }
    }
}
