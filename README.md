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
- **Multi-collection support**: Organize different topics into separate collections

## System Capabilities

- **Efficient storage**: Vector database typically smaller than source PDFs
- **Fast queries**: Sub-100ms response times with HNSW indexing
- **Deduplication**: SHA-256 checksums prevent re-ingesting identical files
- **Scalable**: Handles thousands of vectors efficiently
- **Hierarchical chunking**: Preserves document structure and context

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

3. **Prepare your PDFs:**
   ```bash
   # Create ingest directory if needed
   mkdir -p ingest
   
   # Copy your PDFs to the ingest directory
   cp /path/to/your/*.pdf ingest/
   ```

4. **Ingest PDFs:**
   ```bash
   # Single PDF with smart chunking (default collection)
   ./scripts/ingest-pdf-smart.sh ingest/your-document.pdf
   
   # Ingest into specific collection
   export RAG_COLLECTION=python-books
   ./scripts/ingest-pdf-smart.sh python-guide.pdf
   
   # Or use topic-specific scripts
   ./scripts/ingest-javascript-books.sh ingest/*.js.pdf
   ./scripts/ingest-python-books.sh ingest/*.py.pdf
   
   # Bulk ingest all PDFs (with deduplication)
   ./scripts/ingest-all-pdfs.sh
   ```

5. **Query your documents:**
   ```bash
   # Query default collection
   ./scripts/query-rag.sh "What is the main topic?"
   
   # Query specific collection
   RAG_COLLECTION=python-books ./scripts/query-rag.sh "What are decorators?"
   
   # Interactive chat mode (recommended)
   ./scripts/interactive-rag.sh
   
   # Interactive with specific collection
   RAG_COLLECTION=javascript-books ./scripts/interactive-rag.sh
   ```

6. **Monitor performance:**
   ```bash
   # View database statistics
   ./scripts/qdrant-stats.sh
   
   # Run performance benchmarks
   ./scripts/benchmark-queries.sh
   ```

## Scripts

### Core Operations
- `setup-qdrant.sh` - Installs and starts Qdrant in Docker with persistent storage
- `setup-collection.sh` - Create named collections with validation and aliases
- `health-check.sh` - Verifies all components are running
- `qdrant-stats.sh` - Display detailed database statistics and performance
- `reset-qdrant.sh` - Clear and recreate the collection (requires confirmation)
- `update-collection-alias.sh` - Add descriptive aliases to existing collections

### Ingestion Scripts
- `ingest-pdf-smart.sh` - Smart PDF ingestion via Markdown conversion with hierarchical chunking
- `ingest-all-pdfs.sh` - Bulk ingest with SHA-256 deduplication
- `pdf-to-markdown.sh` - Convert PDF to Markdown preserving code blocks
- `ingest-javascript-books.sh` - Ingest JavaScript documentation into dedicated collection
- `ingest-python-books.sh` - Ingest Python documentation into dedicated collection

### Query Scripts  
- `query-rag.sh` - Single query with RAG context
- `interactive-rag.sh` - Interactive chat interface with performance metrics
- `benchmark-queries.sh` - Performance testing suite

## Architecture

```
PDF → [pdf-to-embeddings] → Ollama (embeddings) → Qdrant (storage)
                                ↓
Query → [search-qdrant] → Ollama (embeddings) → Qdrant (search)
                                ↓
                        Context + Query → Ollama (LLM) → Answer
```

## Rust Tools

The project includes several Rust CLI tools:

### Primary Tools (Hierarchical Strategy)
- **ingest-hierarchical** - Creates parent-child chunks for optimal retrieval (recommended)
- **search-hierarchical** - Searches with parent context awareness

### Alternative Strategies
- **ingest-markdown** - Smart chunking that preserves code blocks
- **ingest-markdown-multi** - Multi-scale chunking at different sizes
- **pdf-to-embeddings** - Original simple chunking (legacy)
- **search-qdrant** - Basic search without hierarchy

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

## Multi-Collection Support

Organize different document types into separate collections:

```bash
# Create topic-specific collections
./scripts/setup-collection.sh javascript-books "JavaScript Documentation"
./scripts/setup-collection.sh python-books "Python Documentation"
./scripts/setup-collection.sh rust-books "Rust Programming Books"

# Ingest into specific collections
export RAG_COLLECTION=javascript-books
./scripts/ingest-pdf-smart.sh javascript-guide.pdf

# Query specific collections
RAG_COLLECTION=python-books ./scripts/query-rag.sh "What are decorators?"
```

See [docs/multi-collection-guide.md](docs/multi-collection-guide.md) for detailed usage.

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

### Expected Performance
- **Search latency**: Typically 50-100ms with indexing
- **Distance metric**: Cosine similarity  
- **Indexing**: HNSW index builds automatically after threshold
- **Chunking strategy**: Hierarchical parent-child architecture

### How It Works
Qdrant's HNSW (Hierarchical Navigable Small World) index provides logarithmic search complexity. The system uses a two-level approach:
- **Parent chunks** (~3500 chars): Provide full context
- **Child chunks** (~750 chars): Enable precise retrieval

### Testing Example
In testing with 11 technical PDFs (~97MB), the system achieved:
- 9,193 vectors indexed
- 66ms average query time
- 94MB storage (smaller than source PDFs)
- Perfect deduplication via checksums

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

## Known Limitations & Solutions

1. **PDF extraction**: ~~Code formatting is lost~~ → **FIXED**: Using `pdftotext -layout` preserves formatting
2. **Chunking**: ~~Small chunks split code~~ → **FIXED**: Hierarchical parent-child chunking preserves context
3. **Collection deletion bug**: **FIXED**: Now checks if collection exists before creating
4. **Remaining limitations**:
   - Semantic search may not match exact code syntax (use keyword search for literals)
   - PDF extraction quality depends on PDF structure
   - Some PDFs may need manual markdown cleanup

## Improvements & Feature Requests

### ✅ Completed Improvements
- [x] **Hierarchical chunking**: Parent-child structure preserves context while enabling precise retrieval
- [x] **Smart ingestion**: PDF→Markdown pipeline preserves code blocks
- [x] **Deduplication**: SHA-256 checksums prevent re-ingesting identical files
- [x] **Automatic indexing**: HNSW index builds automatically with sufficient vectors
- [x] **Batch processing**: Handles large document sets efficiently

### 🚀 Future Improvements
- [ ] **Hybrid search**: Combine vector + keyword (BM25) search
- [ ] **Metadata filtering**: Add file/chapter filtering to searches
- [ ] **Query expansion**: Automatically expand queries with synonyms

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