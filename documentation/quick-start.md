# Quick Start Guide

This guide explains all available scripts and the typical workflow for using the RAG Demo system.

**Looking for specific examples?** See [Usage Examples](./usage-examples.md) for 10 real-world scenarios with complete command sequences.

## 📋 Prerequisites

Before running any scripts, ensure you have:
- Docker installed and running
- Ollama installed and serving (`ollama serve`)
- Rust toolchain installed (`cargo --version`)
- jq installed for JSON processing

## 🚀 First-Time Setup (Required)

### 1. Start Qdrant Vector Database
```bash
./scripts/setup-qdrant.sh
```
**What it does:** Downloads and starts Qdrant in a Docker container with persistent storage mounted at `./qdrant_storage/`.

**When to use:** Run once initially, or after removing the Qdrant container.

### 2. Build All Rust Tools
```bash
./scripts/build-all.sh
```
**What it does:** Compiles all Rust binaries in release mode (ingest and search tools).

**When to use:** After cloning the repository, or after making changes to Rust source code.

### 3. Verify System Health
```bash
./scripts/health-check.sh
```
**What it does:** Checks that Qdrant (port 6333) and Ollama (port 11434) are running and accessible.

**When to use:** Before ingesting or querying to ensure all services are ready.

## 📊 Dashboard & Demo

### Build Interactive Dashboard
```bash
./scripts/build-dashboard.sh
```
**What it does:** Creates a production build of the web dashboard in `./dashboard-dist/` with build info injected.

**Requires:** Qdrant and Ollama running to function properly.

### Serve Dashboard Locally
```bash
./scripts/serve-dashboard.sh
```
**What it does:** Builds and serves the dashboard on http://localhost:8080.

**When to use:** To interact with the RAG system through a web UI instead of command line.

### Build Static Demo
```bash
./scripts/build-demo.sh
```
**What it does:** Creates a limited static demo with mocked data for GitHub Pages deployment in `./docs/`.

**When to use:** When preparing to deploy to GitHub Pages (not for local use).

## 📥 Document Ingestion

### Single PDF Ingestion
```bash
./scripts/ingest-pdf-smart.sh /path/to/document.pdf
```
**What it does:** Converts PDF to markdown, performs hierarchical chunking, generates embeddings, and stores in Qdrant.

**When to use:** For ingesting individual PDFs with high-quality processing.

### Bulk PDF Ingestion (Deduplication)
```bash
# Place PDFs in ./ingest/ directory first
./scripts/ingest-all-pdfs.sh
```
**What it does:** Ingests all PDFs in `./ingest/` directory with SHA-256 deduplication to prevent re-processing the same files.

**When to use:** For batch processing multiple PDFs at once. Safe to run repeatedly.

### Directory-Based Multi-Collection Ingestion
```bash
# Organize PDFs into subdirectories:
# ./ingest/rust/*.pdf → rust-books collection
# ./ingest/javascript/*.pdf → javascript-books collection

./scripts/ingest-by-directory.sh ./ingest
```
**What it does:** Processes each subdirectory as a separate collection, enabling topic-based organization.

**When to use:** When you want to organize different types of documents into separate searchable collections.

### Topic-Specific Ingestion
```bash
./scripts/ingest-python-books.sh python*.pdf
./scripts/ingest-javascript-books.sh javascript*.pdf
```
**What it does:** Ingests PDFs into topic-specific collections (python-books, javascript-books).

**When to use:** For manual control over which collection documents go into.

### PDF to Markdown Conversion
```bash
./scripts/pdf-to-markdown.sh input.pdf ./extracted/
```
**What it does:** Converts PDF to markdown format preserving code blocks and structure.

**When to use:** When you want to review or edit the markdown before ingestion, or use the markdown for other purposes.

## 🔍 Querying & Search

### Single Query
```bash
./scripts/query-rag.sh "What is Rust ownership?"
```
**What it does:** Searches default collection, retrieves relevant chunks, and generates LLM answer.

**Query Specific Collection:**
```bash
RAG_COLLECTION=python-books ./scripts/query-rag.sh "What are decorators?"
```

### Interactive Chat Mode
```bash
./scripts/interactive-rag.sh
```
**What it does:** Starts an interactive session with performance metrics, session statistics, and conversation history.

**When to use:** For exploring your knowledge base with multiple related queries.

**With Specific Collection:**
```bash
RAG_COLLECTION=rust-books ./scripts/interactive-rag.sh
```

### Performance Benchmarking
```bash
./scripts/benchmark-queries.sh
```
**What it does:** Runs a suite of test queries and reports performance metrics (latency, accuracy).

**When to use:** After ingesting documents to verify system performance.

## 🗄️ Database Management

### View Database Statistics
```bash
./scripts/qdrant-stats.sh
```
**What it does:** Displays collection count, vector count, memory usage, and sample data.

**When to use:** To monitor database size and verify ingestion success.

### Create New Collection
```bash
./scripts/setup-collection.sh ml-papers "Machine Learning Papers"
```
**What it does:** Creates a new Qdrant collection with proper configuration and optional human-readable alias.

**When to use:** Before ingesting documents into a new topic area.

### Update Collection Alias
```bash
./scripts/update-collection-alias.sh rust-books "Rust Programming Documentation"
```
**What it does:** Adds or updates a descriptive alias for an existing collection.

**When to use:** To make collection names more readable in dashboards.

### Verify Collections Status
```bash
./scripts/verify-collections.sh
```
**What it does:** Lists all collections with their vector counts and indexing status.

**When to use:** To check which collections exist and their health.

### Monitor Ingestion Progress
```bash
./scripts/ingestion-status.sh
```
**What it does:** Shows real-time status of ongoing ingestion operations.

**When to use:** During bulk ingestion to monitor progress.

### Reset Database (⚠️ Destructive)
```bash
./scripts/reset-qdrant.sh
```
**What it does:** Stops Qdrant, deletes all data, and restarts with fresh storage.

**When to use:** To start completely fresh. Requires confirmation. **All ingested data will be lost.**

## 📝 Typical Workflows

### Workflow 1: First Time Setup
```bash
# 1. Start services
./scripts/setup-qdrant.sh
# In another terminal: ollama serve

# 2. Build tools
./scripts/build-all.sh

# 3. Verify everything works
./scripts/health-check.sh

# 4. Ingest some documents
mkdir -p ingest
cp ~/Documents/my-books/*.pdf ingest/
./scripts/ingest-all-pdfs.sh

# 5. Try a query
./scripts/query-rag.sh "What is the main topic?"

# 6. Use interactive mode
./scripts/interactive-rag.sh
```

### Workflow 2: Multi-Topic Organization
```bash
# 1. Organize PDFs by topic
mkdir -p ingest/{rust,python,javascript,ml}
cp ~/rust-books/*.pdf ingest/rust/
cp ~/python-books/*.pdf ingest/python/
cp ~/js-docs/*.pdf ingest/javascript/
cp ~/ml-papers/*.pdf ingest/ml/

# 2. Ingest all at once
./scripts/ingest-by-directory.sh ./ingest

# 3. Verify collections created
./scripts/verify-collections.sh

# 4. Query specific topics
RAG_COLLECTION=rust-books ./scripts/query-rag.sh "Explain ownership"
RAG_COLLECTION=python-books ./scripts/query-rag.sh "What are decorators?"
```

### Workflow 3: Adding New Documents
```bash
# 1. Add new PDFs to ingest directory
cp new-book.pdf ingest/

# 2. Re-run ingestion (deduplication prevents re-processing old files)
./scripts/ingest-all-pdfs.sh

# 3. Verify
./scripts/qdrant-stats.sh

# 4. Test with query
./scripts/query-rag.sh "topic from new book"
```

### Workflow 4: Dashboard Development
```bash
# 1. Ensure services running
./scripts/health-check.sh

# 2. Build and serve dashboard
./scripts/serve-dashboard.sh

# 3. Open browser to http://localhost:8080

# 4. Make changes to dashboard files in ./dashboard/

# 5. Rebuild
./scripts/build-dashboard.sh

# 6. Refresh browser
```

## 🔧 Script Reference Table

| Script | Purpose | Frequency | Destructive? |
|--------|---------|-----------|--------------|
| `setup-qdrant.sh` | Start Qdrant container | Once | No |
| `build-all.sh` | Compile Rust tools | After code changes | No |
| `health-check.sh` | Verify services running | As needed | No |
| `build-dashboard.sh` | Build web UI | After UI changes | No |
| `serve-dashboard.sh` | Build + serve web UI | Development | No |
| `build-demo.sh` | Build static GitHub Pages demo | Before deployment | No |
| `ingest-pdf-smart.sh` | Ingest single PDF | Per document | No |
| `ingest-all-pdfs.sh` | Bulk ingest with dedup | Batch processing | No |
| `ingest-by-directory.sh` | Multi-collection ingest | Topic organization | No |
| `ingest-python-books.sh` | Python docs to collection | Topic-specific | No |
| `ingest-javascript-books.sh` | JS docs to collection | Topic-specific | No |
| `pdf-to-markdown.sh` | Convert PDF to MD | As needed | No |
| `query-rag.sh` | Single query | Per query | No |
| `interactive-rag.sh` | Interactive chat | Exploration | No |
| `benchmark-queries.sh` | Performance testing | After ingestion | No |
| `qdrant-stats.sh` | View database stats | Monitoring | No |
| `setup-collection.sh` | Create new collection | Per topic | No |
| `update-collection-alias.sh` | Update collection name | As needed | No |
| `verify-collections.sh` | List all collections | Monitoring | No |
| `ingestion-status.sh` | Monitor ingestion | During bulk ops | No |
| `reset-qdrant.sh` | Delete all data | Start fresh | **YES** |

## 🆘 Troubleshooting

### "Connection refused" errors
- Run `./scripts/health-check.sh` to verify services
- Ensure Docker is running: `docker ps`
- Ensure Ollama is serving: `curl http://localhost:11434`

### Ingestion fails
- Check PDF file is readable: `ls -lh your-file.pdf`
- Try converting to markdown first: `./scripts/pdf-to-markdown.sh your-file.pdf ./extracted/`
- Check Qdrant has space: `./scripts/qdrant-stats.sh`

### Queries return no results
- Verify documents ingested: `./scripts/qdrant-stats.sh`
- Check correct collection: `RAG_COLLECTION=your-collection ./scripts/query-rag.sh "test"`
- Verify indexing complete: `./scripts/verify-collections.sh`

### Dashboard won't load
- Ensure services running: `./scripts/health-check.sh`
- Check build succeeded: `ls -la dashboard-dist/`
- Try rebuilding: `./scripts/build-dashboard.sh`
- Check browser console for errors (F12)

## 📚 Additional Resources

- [Usage Examples](./usage-examples.md) - 10 real-world scenarios (research, dev teams, demos, etc.)
- [Main README](../README.md) - Project overview and features
- [CLAUDE.md](../CLAUDE.md) - Development guide and architecture
- [Multi-Collection Guide](./multi-collection-guide.md) - Detailed collection management
- [Learnings](./learnings.md) - Common issues and solutions

## 💡 Tips

- **Always run `health-check.sh` first** - saves time debugging
- **Use deduplication** - `ingest-all-pdfs.sh` is safe to run repeatedly
- **Organize by topic** - multi-collection support makes queries more precise
- **Start small** - ingest 2-3 PDFs first to verify workflow
- **Check stats regularly** - `qdrant-stats.sh` shows what's actually indexed
- **Interactive mode** - best for exploration and learning
- **Dashboard** - great for demos and visual exploration

## 🎓 Learning Path

1. **Day 1:** Setup, health check, ingest 1-2 test PDFs
2. **Day 2:** Try queries, explore interactive mode
3. **Day 3:** Organize into collections, bulk ingest
4. **Day 4:** Build dashboard, explore web UI
5. **Day 5:** Benchmark performance, optimize
