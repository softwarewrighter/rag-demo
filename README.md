# RAG Demo with Qdrant and Ollama

A local RAG (Retrieval-Augmented Generation) system using:
- **Qdrant** - Vector database for storing and searching embeddings
- **Ollama** - Local LLM for embeddings and text generation  
- **Rust** - PDF processing and embedding tools
- **Bash** - Orchestration scripts

## 🎯 Features

- **Local-first**: Everything runs on your machine, no cloud dependencies
- **Fast search**: Vector similarity search in ~50-75ms
- **Persistent storage**: Data survives Docker restarts
- **Web UI**: Qdrant dashboard at http://localhost:6333/dashboard
- **Interactive chat**: Real-time RAG queries with performance metrics
- **LLM-agnostic**: Works with any Ollama-supported model

## Prerequisites

1. **Docker** - For running Qdrant
   ```bash
   brew install --cask docker
   ```

2. **Ollama** - For local LLM inference
   ```bash
   brew install ollama
   ollama serve  # Run in a separate terminal
   ```

3. **Rust** - For building the tools
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

4. **jq** - For JSON processing in scripts
   ```bash
   brew install jq
   ```

## Quick Start

1. **Set up Qdrant:**
   ```bash
   ./scripts/setup-qdrant.sh
   ```

2. **Check system health:**
   ```bash
   ./scripts/health-check.sh
   ```

3. **Ingest a PDF:**
   ```bash
   ./scripts/ingest-pdf.sh path/to/document.pdf
   ```

4. **Query with RAG:**
   ```bash
   ./scripts/query-rag.sh "What is the main topic of the document?"
   ```

## Scripts

- `setup-qdrant.sh` - Installs and starts Qdrant in Docker with persistent storage
- `ingest-pdf.sh` - Extracts text from PDF and stores embeddings in Qdrant
- `query-rag.sh` - Searches for relevant context and generates answers
- `health-check.sh` - Verifies all components are running
- `interactive-rag.sh` - Interactive chat interface with performance metrics
- `qdrant-stats.sh` - Display detailed database statistics and performance

## Architecture

```
PDF → [pdf-to-embeddings] → Ollama (embeddings) → Qdrant (storage)
                                ↓
Query → [search-qdrant] → Ollama (embeddings) → Qdrant (search)
                                ↓
                        Context + Query → Ollama (LLM) → Answer
```

## Rust Tools

The project includes two Rust CLI tools:

- **pdf-to-embeddings** - Extracts text from PDFs, chunks it, generates embeddings via Ollama, and stores in Qdrant
- **search-qdrant** - Generates query embeddings and searches Qdrant for similar documents

Build with:
```bash
cargo build --release
```

## Using Different LLMs

The query script accepts an optional model parameter:
```bash
./scripts/query-rag.sh "your question" llama3.2
./scripts/query-rag.sh "your question" mistral
./scripts/query-rag.sh "your question" gemma2
```

## Data Persistence & Storage

### Where Qdrant Stores Data
- **Local directory**: `./qdrant_storage/` (in your project folder)
- **Inside container**: `/qdrant/storage`
- **Persistence**: ✅ Data survives Docker restarts and system reboots
- **Volume mount**: Already configured with bind mount in `setup-qdrant.sh`

The setup script creates this mount automatically:
```bash
docker run -v $(pwd)/qdrant_storage:/qdrant/storage qdrant/qdrant
```

## Performance & Indexing

### Current Performance
- **Search latency**: 50-75ms (without indexing)
- **828 vectors**: 2MB memory usage
- **Distance metric**: Cosine similarity
- **Indexing status**: Not yet indexed (automatic at 10,000 vectors)

### Why It's Fast Without Indexing
Qdrant uses HNSW (Hierarchical Navigable Small World) indexing, but with only 828 vectors, brute-force search is still very fast. Indexing automatically kicks in at the `indexing_threshold` (default: 10,000 vectors).

## Interactive Usage

### Web UI
Access the Qdrant dashboard at http://localhost:6333/dashboard to:
- View collections and vectors
- Run test queries
- Monitor performance
- Inspect stored payloads

### Interactive Chat
```bash
# Start interactive RAG chat
./scripts/interactive-rag.sh

# Use a different model
./scripts/interactive-rag.sh llama3.2
```

Features:
- Real-time search through ingested documents
- Performance metrics per query
- Session statistics (type 'stats')
- Color-coded output

### Check Database Statistics
```bash
./scripts/qdrant-stats.sh
```
Shows:
- Vector count and memory usage
- Collection configuration
- Sample stored data
- Performance test results

## Known Limitations

1. **PDF extraction**: Code formatting is lost during extraction
2. **Chunking**: 1000-character chunks may split code examples
3. **Semantic search**: May not match code syntax well
4. **Tips for better results**:
   - Search for specific terms: "macro_rules!", "fn main"
   - Ask about concepts rather than "show me an example"
   - Use more specific queries

## Improvements & Feature Requests

### 🚀 Immediate Improvements
- [ ] **Force indexing**: Configure HNSW index even for small datasets
- [ ] **Better chunking**: Implement code-aware chunking to preserve examples
- [ ] **Metadata filtering**: Add file/chapter filtering to searches
- [ ] **Hybrid search**: Combine vector + keyword search for better code finding

### 📈 Scalability Enhancements
- [ ] **Sharding**: Configure for multiple collections/tenants
- [ ] **Compression**: Enable vector quantization for larger datasets
- [ ] **Batch ingestion**: Process multiple PDFs in parallel
- [ ] **Incremental updates**: Add/remove individual documents

### 🎯 Precision Improvements
- [ ] **Re-ranking**: Add a cross-encoder for result re-ranking
- [ ] **Fine-tuned embeddings**: Use domain-specific embedding models
- [ ] **Query expansion**: Automatically expand queries with synonyms
- [ ] **Feedback loop**: Learn from user interactions

### 🔧 Better Qdrant Configuration
```rust
// Recommended optimizations for Cargo.toml
[dependencies]
qdrant-client = { version = "1.12", features = ["tokio-runtime"] }

// Force indexing for better performance
let collection_config = CollectionConfig {
    hnsw_config: HnswConfig {
        m: 16,                    // Connections per node
        ef_construct: 200,        // Build-time accuracy
        full_scan_threshold: 0,  // Force indexing immediately
    },
    optimizer_config: OptimizerConfig {
        indexing_threshold: 100,  // Index after 100 vectors
    },
    quantization_config: Some(QuantizationConfig::Scalar(
        ScalarQuantization {
            type_: ScalarType::Int8,
            quantile: Some(0.99),
            always_ram: Some(true),
        }
    )),
};
```

## MCP (Model Context Protocol) Integration

### Value Proposition
Implementing an MCP server would enable:

1. **Remote Access**: LLMs on powerful GPU servers can query your local knowledge base
2. **Tool-using LLMs**: Models like GPT-4, Claude, or local LLMs with tool-use can directly search documents
3. **Multi-modal**: Share both text and extracted images from PDFs
4. **Federated Knowledge**: Multiple RAG instances can be accessed by one LLM

### Proposed MCP Implementation
```rust
// Potential MCP server in Rust
use mcp_rust::{Server, Tool, Resource};

struct RagMcpServer {
    qdrant_client: QdrantClient,
    ollama_client: OllamaClient,
}

impl McpServer for RagMcpServer {
    async fn list_tools(&self) -> Vec<Tool> {
        vec![
            Tool {
                name: "search_documents",
                description: "Search ingested PDFs for relevant information",
                parameters: json!({
                    "query": "string",
                    "limit": "number",
                    "filter": {"source": "string"}
                }),
            },
            Tool {
                name: "ingest_document",
                description: "Add a new PDF to the knowledge base",
                parameters: json!({"url": "string"}),
            },
        ]
    }
    
    async fn call_tool(&self, name: &str, params: Value) -> Result<Value> {
        match name {
            "search_documents" => {
                let results = self.search_qdrant(params).await?;
                Ok(json!({
                    "results": results,
                    "tokens_used": calculate_tokens(results)
                }))
            },
            _ => Err("Unknown tool")
        }
    }
}
```

### MCP Benefits for LAN deployment
- **Centralized knowledge**: One RAG server, multiple AI clients
- **Resource efficiency**: Embeddings computed once, used everywhere
- **Privacy**: Keep documents local while allowing remote AI access
- **Scalability**: Add more documents without updating each client

### Example MCP Usage
```python
# From a remote LLM server with MCP client
async with mcp.connect("ws://192.168.1.100:8080/rag") as client:
    # LLM can now search your local PDFs
    results = await client.call_tool(
        "search_documents",
        {"query": "Rust macro examples", "limit": 5}
    )
    
    # Generate response with RAG context
    response = llm.generate(
        prompt=f"Based on: {results}, answer: {user_question}"
    )
```

## Future Enhancements

This system is designed to be LLM-agnostic and could be extended with:
- ✅ Model Context Protocol (MCP) server implementation
- Support for other embedding models (mxbai-embed-large, etc.)
- Web UI for document management
- Support for other document formats (DOCX, HTML, Markdown)
- Hybrid search (vector + keyword)
- Multi-lingual support
- Document versioning and updates