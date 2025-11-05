# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Copyright © 2025 Michael A. Wright** | Licensed under the MIT License (see LICENSE file)

## ⚠️ CRITICAL: Review Before Making Changes

**ALWAYS consult `./documentation/learnings.md` BEFORE writing or modifying code** to avoid repeating past mistakes. This file contains specific issues encountered and their resolutions.

## Project Overview

This is a local RAG (Retrieval-Augmented Generation) system using Qdrant vector database and Ollama for LLM inference. The system ingests PDF documents, converts them to embeddings, and enables semantic search with LLM-powered answers. Supports multi-collection organization for different document types (e.g., python-books, javascript-docs).

## Key Commands

### Build & Development
```bash
# Build all Rust tools
cargo build --release

# Build specific tool
cargo build --release --bin ingest-hierarchical

# Run linting/checks
cargo clippy
cargo fmt
```

### Dashboard & Demo
```bash
# Build interactive dashboard (requires Qdrant + Ollama running)
./scripts/build-dashboard.sh
# Output: ./dashboard-dist/
# Serve with: cd dashboard-dist && python3 -m http.server 8080

# Build static demo for GitHub Pages (mocked data)
./scripts/build-demo.sh
# Output: ./docs/
# This is automatically served at: https://softwarewrighter.github.io/rag-demo/
```

### System Setup & Health
```bash
# Initial setup
./scripts/setup-qdrant.sh       # Start Qdrant in Docker
ollama serve                     # Start Ollama (separate terminal)

# Health check
./scripts/health-check.sh       # Verify all components running
./scripts/qdrant-stats.sh       # Database statistics
```

### Document Ingestion
```bash
# Single PDF ingestion (uses hierarchical chunking)
./scripts/ingest-pdf-smart.sh document.pdf

# Ingest into specific collection
RAG_COLLECTION=python-books ./scripts/ingest-pdf-smart.sh python-guide.pdf

# Bulk ingestion with deduplication
./scripts/ingest-all-pdfs.sh    # Processes ./ingest/*.pdf

# Directory-based ingestion (each subdirectory becomes a collection)
./scripts/ingest-by-directory.sh ./ingest

# Topic-specific ingestion scripts
./scripts/ingest-javascript-books.sh *.js.pdf
./scripts/ingest-python-books.sh *.py.pdf

# PDF to Markdown conversion
./scripts/pdf-to-markdown.sh input.pdf ./extracted/
```

### Querying & Search
```bash
# Query with RAG (default collection)
./scripts/query-rag.sh "your question"

# Query specific collection
RAG_COLLECTION=python-books ./scripts/query-rag.sh "What are decorators?"

# Interactive chat
./scripts/interactive-rag.sh

# Interactive with specific collection
RAG_COLLECTION=javascript-books ./scripts/interactive-rag.sh

# Direct search (returns raw results)
./target/release/search-hierarchical "search term" --limit 5

# Performance benchmark
./scripts/benchmark-queries.sh
```

### Database Management
```bash
# Reset database (requires confirmation)
./scripts/reset-qdrant.sh

# Create new collection with alias
./scripts/setup-collection.sh rust-books "Rust Documentation"

# Update collection alias
./scripts/update-collection-alias.sh collection-name "New Alias"

# Verify collections
./scripts/verify-collections.sh

# Check ingested documents
cat .ingested_checksums         # View SHA-256 checksums
cat .ingestion_stats.json       # View last ingestion stats
./scripts/ingestion-status.sh   # Current ingestion status
```

## Architecture & Key Components

### Core Architecture Pattern
The system uses **hierarchical parent-child chunking** based on research showing this approach provides optimal retrieval performance:
- **Parent chunks**: ~3500 chars providing full context
- **Child chunks**: ~750 chars for precise retrieval (~400 tokens)
- Search returns child chunks but can retrieve parent for context

### Rust Binaries

1. **ingest-hierarchical** (`src/ingest_hierarchical.rs`)
   - Primary ingestion tool using parent-child chunking
   - Creates embeddings via Ollama
   - **Important**: Does NOT delete existing collection (fixed from earlier versions)

2. **search-hierarchical** (`src/search_hierarchical.rs`)
   - Searches with parent-child awareness
   - Can return both child matches and parent context

3. **ingest-by-directory** (`src/ingest_by_directory.rs`)
   - Ingests PDFs organized by subdirectory into separate collections
   - Each subdirectory becomes its own collection

4. **ingest-markdown-multi** (`src/ingest_markdown_multi.rs`)
   - Ingests markdown files into specified collections
   - Supports multi-collection workflows

5. **pdf-to-embeddings** (`src/pdf_to_embeddings.rs`)
   - Legacy simple chunking (1000 chars with 200 overlap)
   - Still used by some scripts

6. **ingest-markdown** (`src/ingest_markdown.rs`)
   - Smart chunking that preserves code blocks
   - Used after PDF→Markdown conversion

### Data Flow
```
PDF → pdftotext → Markdown → Hierarchical Chunking → Embeddings → Qdrant
                                   ↓
                            Parent (context)
                            Child (precise match)
```

### Storage & Persistence
- **Qdrant data**: `./qdrant_storage/` (Docker volume mount, gitignored)
- **Extracted markdown**: `./extracted/` (gitignored)
- **Checksums**: `.ingested_checksums` (prevents re-ingestion)
- **Stats**: `.ingestion_stats.json`
- **Dashboard build**: `./dashboard-dist/` (gitignored)
- **GitHub Pages demo**: `./docs/` (committed, served on GitHub Pages)
- **Screenshots**: `./images/` (committed)
- **Documentation**: `./documentation/` (was `./docs/`, renamed to avoid conflict)

### Performance Characteristics
- **Query latency**: 50-80ms with HNSW index
- **HNSW indexing**: Automatic at >100 vectors (configured)
- **Embedding model**: nomic-embed-text (768 dimensions)
- **LLM**: llama3.2 by default (configurable)

## Critical Implementation Details

### Deduplication System
The system uses SHA-256 checksums stored in `.ingested_checksums` to prevent re-ingesting identical PDFs. Format:
```
checksum|filepath|chunk_count|timestamp
```

### Qdrant Configuration
- Default collection: `documents`
- Topic collections: `python-books`, `javascript-books`, `rust-books`, etc.
- Distance metric: Cosine
- Vector size: 768
- HNSW parameters: m=16, ef_construct=200
- Automatic indexing threshold: 100 vectors
- Collections support human-readable aliases

### Chunking Strategy Evolution
1. **v1**: Simple 1000-char chunks (poor context)
2. **v2**: Smart markdown chunking (preserved code blocks but over-chunked)
3. **v3**: Hierarchical parent-child (current best approach)

### Known Issues & Workarounds
- **PDF code extraction**: `pdftotext -layout` preserves formatting better than pdf-extract crate
- **Small chunks problem**: Early versions created chunks too small (<100 chars)
- **Collection deletion bug**: Fixed - earlier versions deleted collection on each ingest

## Testing & Validation

### Test ingestion with deduplication
```bash
# First run ingests
./scripts/ingest-all-pdfs.sh

# Second run should skip all (deduplication working)
./scripts/ingest-all-pdfs.sh
```

### Verify search quality
```bash
# Should return code examples with context
./target/release/search-hierarchical "macro_rules example" --with-parent
```

### Check indexing status
```bash
curl -s http://localhost:6333/collections/documents | jq '.result.indexed_vectors_count'
```

## 🛑 CHECKPOINT PROCESS - MANDATORY

**Every checkpoint MUST follow this exact sequence:**

### 1. Check Git Status BEFORE Changes
```bash
git status  # Document initial state
```

### 2. Run Tests and Fix Issues
```bash
cargo test --all
# Fix any failing tests BEFORE proceeding
```

### 3. Run and Fix Linting
```bash
cargo clippy --all-targets --all-features -- -D warnings
# Fix ALL clippy warnings - they are errors
```

### 4. Format Code
```bash
cargo fmt
```

### 5. Update Documentation
- Update README.md if functionality changed
- Update this CLAUDE.md file if development process changed  
- **CRITICAL: Update documentation/learnings.md with ANY new errors encountered and their fixes**
- Ensure all public Rust items have doc comments
- If you fixed a bug that could have been avoided by checking learnings.md, add it!

### 6. Check Git Status DURING Process
```bash
git status  # Review what changed
git diff    # Examine specific changes
```

### 7. Stage and Commit
```bash
git add -A  # Or selectively add files
git commit -m "checkpoint: <description of changes>"
```

### 8. Push Changes IMMEDIATELY
```bash
git push  # CRITICAL: Always push so code can be tested on other systems
```

### ⚠️ Common Checkpoint Mistakes to Avoid:
- **Skipping tests** - Always run tests first
- **Ignoring clippy warnings** - These often indicate bugs
- **Forgetting to push** - Changes aren't backed up until pushed
- **Not updating docs** - Documentation drift causes confusion
- **Committing without testing** - Breaks CI/CD

## Common Development Tasks

### Adding a new ingestion strategy
1. Create new binary in `src/` 
2. Add to `Cargo.toml` under `[[bin]]`
3. Update ingestion scripts to use new binary

### Working with Collections
```bash
# Set target collection for operations
export RAG_COLLECTION=python-books

# Create collection with alias
./scripts/setup-collection.sh ml-papers "Machine Learning Papers"

# List all collections
curl -s http://localhost:6333/collections | jq '.result[].name'
```

### Modifying chunk sizes
Edit constants in `src/ingest_hierarchical.rs`:
- `CHILD_TARGET_SIZE`: 1600 (chars)
- `PARENT_TARGET_SIZE`: 4000 (chars)

### Forcing index rebuild
```bash
# For specific collection
curl -X POST http://localhost:6333/collections/python-books/index \
  -H "Content-Type: application/json" \
  -d '{"wait": true}'
```

## Environment Requirements
- Docker running for Qdrant
- Ollama serving on port 11434
- At least 4GB RAM for processing large PDFs
- Port 6333 available for Qdrant

## Known Issues from documentation/learnings.md

### Critical Bugs Fixed
1. **Collection deletion on each ingest** - ingest_hierarchical.rs was deleting and recreating the collection each time. Now checks if exists first.
2. **Wrong output directory** - Tools were writing to CWD instead of target directory. Always join paths with target.

### Common Rust/Clippy Issues
1. **Doc comments**: Use `//!` for module docs, `///` for item docs
2. **Format strings**: Always use inline format args: `"{var}"` not `"{}", var`
3. **Unused imports**: Remove immediately after refactoring
4. **Needless borrows**: Arrays often don't need `&` in generic contexts
5. **Edition**: Use "2021" or "2024", never development editions

### Before Writing ANY Code
1. Check if similar functionality exists
2. Review learnings.md for patterns to avoid
3. Run `cargo check` frequently during development
4. Address issues immediately, not at checkpoint

## Process Quality Gates

**Definition of "Done" for any task:**
- ✅ All tests pass (`cargo test`)
- ✅ No clippy warnings (`cargo clippy -- -D warnings`)
- ✅ Code formatted (`cargo fmt`)
- ✅ Documentation updated (README, CLAUDE.md, learnings.md)
- ✅ Changes committed with descriptive message
- ✅ Changes pushed to remote repository
- ✅ Can be checked out and run on a different machine