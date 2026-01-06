# Worked Example: Ingesting Source Code into RAG

This document demonstrates ingesting the rag-demo codebase into Qdrant for semantic search and RAG queries.

## Overview

**Goal**: Ingest all source files from this repository into Qdrant, enabling semantic search and LLM-powered question answering about the codebase itself.

**Date**: 2026-01-06

## Prerequisites

```bash
# Verify services are running
./scripts/health-check.sh
```

Required:
- Qdrant running on `localhost:6333`
- Ollama running on `localhost:11434` with `nomic-embed-text` model
- Rust tools built (`cargo build --release`)

## Step 1: Concatenate Source Files

Create a markdown document containing all source files:

```bash
./scripts/concat-source-files.sh project.md
```

**Output**:
```
Files processed: 54
Total lines: 12,376
Output size: 382,647 bytes
```

The script collects Rust source, shell scripts, configuration, documentation, and dashboard files, wrapping each in code fences with appropriate language tags.

## Step 2: Create Collection and Ingest

```bash
# Create collection
./scripts/setup-collection.sh project-source "RAG Demo Source Code"

# Ingest with hierarchical chunking
./target/release/ingest-hierarchical project.md --collection project-source
```

**Ingestion Results**:
```
Parent chunks: 878 (avg 435 chars)
Child chunks: 184 (avg 887 chars)
Total vectors: 1062
```

**Chunk Type Distribution**:
| Type | Count |
|------|-------|
| parent | 878 |
| child_text | 114 |
| child_header | 27 |
| child_mixed | 21 |
| child_list | 19 |
| child_code | 3 |

## Step 3: Query the RAG System

### Semantic Search

```bash
./target/release/search-hierarchical "hierarchical chunking" \
  --collection project-source --limit 3
```

**Results**:
```
Result 1 (Score: 0.682) - child_text
    create_child_chunks(parent_content, parent_id, 0);
    assert_eq!(children.len(), 1, "Should create at least one child chunk");
    ...

Result 2 (Score: 0.655) - child_list
    Option 2 (Parent-Child): This hierarchical approach aligns with research
    showing hierarchical chunking breaks down documents at multiple levels...
```

### Full RAG Query (Local)

```bash
export RAG_COLLECTION=project-source
./scripts/query-rag.sh "What is the hierarchical chunking approach used in this project?"
```

**Response** (mistral:7b):
> The hierarchical chunking approach used in this project is Parent-Child chunking. This approach breaks down documents at multiple levels and preserves document structure while maintaining context at multiple levels of granularity, which aligns with research showing its benefits for production-scale RAG systems.

## Step 4: Validation

### Test 1: Search Accuracy

**Ground Truth**:
```bash
$ grep "PARENT_TARGET_SIZE" src/ingest_hierarchical.rs
const PARENT_TARGET_SIZE: usize = 1800;
```

**Search Query**:
```bash
./target/release/search-hierarchical "PARENT_TARGET_SIZE chunking" \
  --collection project-source --limit 1
```

**Result**: Score 0.712 - Found chunk containing `if current_parent.len() >= PARENT_TARGET_SIZE`

**Status**: PASS

### Test 2: RAG Answer Accuracy

**Ground Truth**: Project uses parent-child hierarchical chunking (from code and research.md)

**RAG Response**: Correctly identified "Parent-Child chunking" strategy

**Status**: PASS

### Test 3: Vector Count Verification

**Qdrant API**:
```bash
$ curl -s "http://localhost:6333/collections/project-source" | jq '.result.points_count'
1062
```

**Ingestion Claimed**: 878 + 184 = 1062

**Status**: PASS

### Validation Summary

| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| Vector count | 1062 | 1062 | PASS |
| Strategy identified | Parent-Child | Parent-Child | PASS |
| Search finds code | PARENT_TARGET_SIZE | Score 0.712 | PASS |
| Collection status | green | green | PASS |

## Collection Statistics

```bash
curl -s "http://localhost:6333/collections/project-source" | jq '.result'
```

```json
{
  "status": "green",
  "indexed_vectors_count": 1062,
  "points_count": 1062,
  "segments_count": 2,
  "config": {
    "params": {
      "vectors": { "size": 768, "distance": "Cosine" }
    },
    "hnsw_config": { "m": 16, "ef_construct": 100 }
  }
}
```

## Reproducing This Example

```bash
# 1. Ensure services running
./scripts/health-check.sh

# 2. Build tools
cargo build --release

# 3. Create source file bundle
./scripts/concat-source-files.sh project.md

# 4. Create collection
./scripts/setup-collection.sh project-source "RAG Demo Source Code"

# 5. Ingest
./target/release/ingest-hierarchical project.md --collection project-source

# 6. Query
export RAG_COLLECTION=project-source
./scripts/query-rag.sh "How does the hybrid search work?"
```

## Key Takeaways

1. **Hierarchical chunking works well for code** - Parents capture file/section context, children capture specific snippets
2. **1062 vectors** indexed from 54 source files (12,376 lines)
3. **Search scores 0.65-0.71** for relevant queries
4. **RAG correctly answers** questions about the codebase architecture
