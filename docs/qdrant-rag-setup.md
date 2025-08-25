# Qdrant RAG System Setup Guide for M3 MacBook Pro

## Overview
This guide will help you set up a complete RAG (Retrieval-Augmented Generation) system using:
- **Qdrant** for vector storage and similarity search
- **Rust** for all application logic
- **Ollama** for local embeddings generation
- **Claude CLI** for the chat interface

## Prerequisites

### 1. Install Required Tools

```bash
# Install Rust if not already installed
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Docker for Qdrant
brew install --cask docker

# Install jq for JSON processing
brew install jq

# Install Ollama for local embeddings
brew install ollama

# Install Claude CLI
brew install claude
```

## Step 1: Set Up Qdrant

### Option A: Using Docker (Recommended)
```bash
# Pull and run Qdrant with both REST and gRPC interfaces
docker run -d \
  --name qdrant \
  -p 6333:6333 \
  -p 6334:6334 \
  -v $(pwd)/qdrant_storage:/qdrant/storage \
  -e QDRANT__SERVICE__GRPC_PORT="6334" \
  qdrant/qdrant
```

### Option B: Using Binary (Alternative)
```bash
# Download Qdrant binary for Apple Silicon
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-aarch64-apple-darwin.tar.gz | tar xz
./qdrant --config-path config/config.yaml
```

### Verify Qdrant is Running
```bash
curl http://localhost:6333/collections
# Should return: {"result":{"collections":[]},"status":"ok","time":0.0}
```

## Step 2: Set Up Ollama for Embeddings

```bash
# Start Ollama service
ollama serve &

# Pull an embedding model (nomic-embed-text is good for RAG)
ollama pull nomic-embed-text

# Test the embedding model
curl http://localhost:11434/api/embeddings -d '{
  "model": "nomic-embed-text",
  "prompt": "Test embedding"
}' | jq '.embedding[0:5]'
```

## Step 3: Create the Rust RAG Application

### Create Project Structure
```bash
mkdir qdrant-rag-rust
cd qdrant-rag-rust
cargo init
```

### Update Cargo.toml
```toml
[package]
name = "qdrant-rag-rust"
version = "0.1.0"
edition = "2021"

[dependencies]
qdrant-client = "1.12"
tokio = { version = "1", features = ["full"] }
anyhow = "1.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
reqwest = { version = "0.12", features = ["json"] }
pdf-extract = "0.7"
uuid = { version = "1.4", features = ["v4", "serde"] }
clap = { version = "4.4", features = ["derive"] }
indicatif = "0.17"
textwrap = "0.16"

[[bin]]
name = "rag-ingest"
path = "src/ingest.rs"

[[bin]]
name = "rag-query"
path = "src/query.rs"
```

### Create Core Library (src/lib.rs)
```rust
use anyhow::Result;
use qdrant_client::qdrant::{
    CreateCollectionBuilder, Distance, PointStruct, SearchPointsBuilder,
    UpsertPointsBuilder, VectorParamsBuilder,
};
use qdrant_client::{Payload, Qdrant};
use reqwest;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

pub const COLLECTION_NAME: &str = "pdf_documents";
pub const EMBEDDING_DIM: u64 = 768; // nomic-embed-text dimension
pub const CHUNK_SIZE: usize = 1000; // characters per chunk
pub const CHUNK_OVERLAP: usize = 200;

#[derive(Debug, Serialize, Deserialize)]
pub struct EmbeddingRequest {
    pub model: String,
    pub prompt: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EmbeddingResponse {
    pub embedding: Vec<f32>,
}

pub struct RagSystem {
    qdrant: Qdrant,
    embedding_model: String,
}

impl RagSystem {
    pub async fn new() -> Result<Self> {
        let qdrant = Qdrant::from_url("http://localhost:6334").build()?;
        
        // Try to create collection, ignore if exists
        let _ = qdrant
            .create_collection(
                CreateCollectionBuilder::new(COLLECTION_NAME)
                    .vectors_config(VectorParamsBuilder::new(EMBEDDING_DIM, Distance::Cosine)),
            )
            .await;
        
        Ok(Self {
            qdrant,
            embedding_model: "nomic-embed-text".to_string(),
        })
    }
    
    pub async fn get_embedding(&self, text: &str) -> Result<Vec<f32>> {
        let client = reqwest::Client::new();
        let request = EmbeddingRequest {
            model: self.embedding_model.clone(),
            prompt: text.to_string(),
        };
        
        let response = client
            .post("http://localhost:11434/api/embeddings")
            .json(&request)
            .send()
            .await?;
        
        let embedding_response: EmbeddingResponse = response.json().await?;
        Ok(embedding_response.embedding)
    }
    
    pub fn chunk_text(text: &str) -> Vec<String> {
        let mut chunks = Vec::new();
        let chars: Vec<char> = text.chars().collect();
        let mut start = 0;
        
        while start < chars.len() {
            let end = std::cmp::min(start + CHUNK_SIZE, chars.len());
            let chunk: String = chars[start..end].iter().collect();
            chunks.push(chunk);
            
            start += CHUNK_SIZE - CHUNK_OVERLAP;
        }
        
        chunks
    }
    
    pub async fn ingest_document(&self, filename: &str, content: &str) -> Result<()> {
        let chunks = Self::chunk_text(content);
        let mut points = Vec::new();
        
        for (i, chunk) in chunks.iter().enumerate() {
            let embedding = self.get_embedding(chunk).await?;
            let id = Uuid::new_v4();
            
            let mut payload = HashMap::new();
            payload.insert("filename", filename.into());
            payload.insert("chunk_index", i.into());
            payload.insert("text", chunk.clone().into());
            
            points.push(PointStruct::new(
                id.to_string(),
                embedding,
                Payload::from(payload),
            ));
        }
        
        self.qdrant
            .upsert_points(UpsertPointsBuilder::new(COLLECTION_NAME, points))
            .await?;
        
        Ok(())
    }
    
    pub async fn search(&self, query: &str, limit: u64) -> Result<Vec<(String, f32)>> {
        let query_embedding = self.get_embedding(query).await?;
        
        let search_result = self.qdrant
            .search_points(
                SearchPointsBuilder::new(COLLECTION_NAME, query_embedding, limit)
                    .with_payload(true),
            )
            .await?;
        
        let mut results = Vec::new();
        for point in search_result.result {
            if let Some(text_value) = point.payload.get("text") {
                let text = text_value.to_string().trim_matches('"').to_string();
                results.push((text, point.score));
            }
        }
        
        Ok(results)
    }
}
```

### Create Ingestion Tool (src/ingest.rs)
```rust
use anyhow::Result;
use clap::Parser;
use indicatif::{ProgressBar, ProgressStyle};
use pdf_extract::extract_text;
use qdrant_rag_rust::RagSystem;
use std::fs;
use std::path::Path;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// PDF file to ingest
    #[arg(short, long)]
    file: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();
    
    println!("🚀 Initializing RAG system...");
    let rag = RagSystem::new().await?;
    
    println!("📄 Reading PDF: {}", args.file);
    let path = Path::new(&args.file);
    let text = extract_text(path)?;
    
    let chunks = RagSystem::chunk_text(&text);
    println!("📝 Created {} chunks", chunks.len());
    
    let pb = ProgressBar::new(chunks.len() as u64);
    pb.set_style(
        ProgressStyle::default_bar()
            .template("{spinner:.green} [{bar:40.cyan/blue}] {pos}/{len} {msg}")?
            .progress_chars("#>-"),
    );
    
    println!("💾 Ingesting document into Qdrant...");
    for (i, _) in chunks.iter().enumerate() {
        pb.set_message(format!("Processing chunk {}", i + 1));
        pb.inc(1);
    }
    
    rag.ingest_document(&args.file, &text).await?;
    pb.finish_with_message("✅ Ingestion complete!");
    
    Ok(())
}
```

### Create Query Tool (src/query.rs)
```rust
use anyhow::Result;
use clap::Parser;
use qdrant_rag_rust::RagSystem;
use std::io::{self, Write};
use textwrap::wrap;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Query to search for
    #[arg(short, long)]
    query: Option<String>,
    
    /// Number of results to return
    #[arg(short, long, default_value = "3")]
    limit: u64,
    
    /// Interactive mode
    #[arg(short, long)]
    interactive: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();
    let rag = RagSystem::new().await?;
    
    if args.interactive {
        println!("🤖 RAG Query System - Interactive Mode");
        println!("Type 'quit' to exit\n");
        
        loop {
            print!("Query> ");
            io::stdout().flush()?;
            
            let mut input = String::new();
            io::stdin().read_line(&mut input)?;
            let query = input.trim();
            
            if query == "quit" {
                break;
            }
            
            search_and_display(&rag, query, args.limit).await?;
        }
    } else if let Some(query) = args.query {
        search_and_display(&rag, &query, args.limit).await?;
    } else {
        eprintln!("Please provide a query with -q or use -i for interactive mode");
    }
    
    Ok(())
}

async fn search_and_display(rag: &RagSystem, query: &str, limit: u64) -> Result<()> {
    println!("\n🔍 Searching for: {}", query);
    let results = rag.search(query, limit).await?;
    
    if results.is_empty() {
        println!("No results found.");
    } else {
        println!("\n📚 Top {} results:\n", results.len());
        for (i, (text, score)) in results.iter().enumerate() {
            println!("--- Result {} (Score: {:.3}) ---", i + 1, score);
            let wrapped = wrap(text, 80);
            for line in wrapped {
                println!("{}", line);
            }
            println!();
        }
    }
    
    Ok(())
}
```

## Step 4: Build and Test the System

```bash
# Build the project
cargo build --release

# Test PDF ingestion
./target/release/rag-ingest -f path/to/your/document.pdf

# Test querying
./target/release/rag-query -q "your search query"

# Interactive mode
./target/release/rag-query -i
```

## Step 5: Create Claude CLI Integration Script

### Create claude-rag.sh
```bash
#!/bin/bash

# Function to query Qdrant and format for Claude
query_rag() {
    local query="$1"
    local context=$(./target/release/rag-query -q "$query" -l 5 2>/dev/null | \
        sed -n '/^---/,/^$/p' | \
        sed '/^---/d' | \
        tr '\n' ' ')
    echo "$context"
}

# Main chat loop
echo "🤖 Claude RAG Chat System"
echo "Type your questions. The system will search the knowledge base and use Claude to answer."
echo "Type 'quit' to exit."
echo

while true; do
    echo -n "You: "
    read user_query
    
    if [ "$user_query" = "quit" ]; then
        break
    fi
    
    # Get context from RAG
    context=$(query_rag "$user_query")
    
    # Create prompt for Claude
    prompt="Based on the following context from the knowledge base:

Context: $context

Please answer this question: $user_query

If the context doesn't contain relevant information, please say so."
    
    # Send to Claude CLI
    echo "Claude: "
    echo "$prompt" | claude --no-markdown
    echo
done
```

Make it executable:
```bash
chmod +x claude-rag.sh
```

## Step 6: Complete Workflow Example

```bash
# 1. Start Qdrant (if not running)
docker start qdrant

# 2. Start Ollama (if not running)
ollama serve &

# 3. Ingest your PDFs
./target/release/rag-ingest -f ~/Documents/paper1.pdf
./target/release/rag-ingest -f ~/Documents/paper2.pdf

# 4. Query the system
./target/release/rag-query -q "machine learning applications"

# 5. Chat with Claude using RAG context
./claude-rag.sh
```

## Advanced Features

### Batch PDF Ingestion Script
```bash
#!/bin/bash
# ingest-all.sh
for pdf in *.pdf; do
    echo "Ingesting $pdf..."
    ./target/release/rag-ingest -f "$pdf"
done
```

### System Health Check Script
```bash
#!/bin/bash
# health-check.sh

echo "Checking system components..."

# Check Qdrant
if curl -s http://localhost:6333/collections > /dev/null; then
    echo "✅ Qdrant is running"
else
    echo "❌ Qdrant is not running"
fi

# Check Ollama
if curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "✅ Ollama is running"
else
    echo "❌ Ollama is not running"
fi

# Check collection
collections=$(curl -s http://localhost:6333/collections | jq -r '.result.collections[].name')
if [[ $collections == *"pdf_documents"* ]]; then
    count=$(curl -s http://localhost:6333/collections/pdf_documents | jq '.result.points_count')
    echo "✅ Collection exists with $count points"
else
    echo "❌ Collection not found"
fi
```

## Performance Optimization Tips

1. **Embedding Caching**: Add a cache layer for embeddings to avoid recomputing
2. **Batch Processing**: Modify the ingest tool to process multiple chunks in parallel
3. **Index Optimization**: Configure Qdrant indexes for better search performance
4. **Model Selection**: Try different embedding models (e.g., `mxbai-embed-large` for better quality)

## Troubleshooting

### Common Issues and Solutions

1. **Qdrant Connection Failed**
   ```bash
   # Check if Qdrant is running
   docker ps | grep qdrant
   # Restart if needed
   docker restart qdrant
   ```

2. **Ollama Not Responding**
   ```bash
   # Kill existing Ollama process
   pkill ollama
   # Restart
   ollama serve &
   ```

3. **PDF Extraction Issues**
   - Some PDFs may have encoding issues
   - Try alternative crates like `lopdf` or `poppler-rs`

4. **Memory Issues on Large PDFs**
   - Increase chunk overlap for better context
   - Process PDFs in smaller batches

## Next Steps

1. **Add metadata filtering**: Enhance search with document metadata
2. **Implement hybrid search**: Combine vector and keyword search
3. **Add re-ranking**: Use a cross-encoder to re-rank results
4. **Build a web UI**: Create a Rust web server with Axum
5. **Add document management**: Track versions and updates

This setup provides a solid foundation for a production-ready RAG system using Rust and Qdrant!