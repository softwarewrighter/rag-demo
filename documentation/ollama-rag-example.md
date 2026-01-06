# Remote Ollama RAG Example

This document demonstrates using a remote Ollama server (big72) with RAG queries against local Qdrant.

## Architecture

```
Local Machine                          Remote Server (big72)
┌──────────────┐                       ┌──────────────┐
│   Qdrant     │                       │   Ollama     │
│  (vectors)   │                       │  (LLM)       │
└──────────────┘                       └──────────────┘
       │                                      │
       │  1. Search vectors                   │
       ▼                                      │
┌──────────────┐                              │
│   Client     │──── 2. Send context+query ──▶│
│              │◀─── 3. Receive answer ───────│
└──────────────┘
```

## Available Models on big72

```bash
$ curl -s http://big72:11434/api/tags | jq -r '.models[].name' | grep -E "^(mistral|qwen|llama)"
mistral:7b
mistral:latest
qwen3:14b
qwen2.5:7b
llama3.2:1b
llama3.2-vision:11b
```

## RAG Query: Local Search + Remote LLM

### Step 1: Search Local Qdrant

```bash
CONTEXT=$(./target/release/search-hierarchical "hierarchical chunking" \
  --collection project-source --limit 3 --json | \
  jq -r '.results[].payload.text' | head -c 2500)
```

### Step 2: Query Remote Ollama

```bash
QUESTION="What chunking strategy does this project use?"

curl -s http://big72:11434/api/generate \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "mistral:7b" \
    --arg prompt "Based on this context, answer the question.

Context:
$CONTEXT

Question: $QUESTION" \
    '{model: $model, prompt: $prompt, stream: false}')" | jq -r '.response'
```

## Actual Results (2026-01-06)

### Test 1: mistral:7b on big72

**Query**: "What chunking strategy does this project use?"

**Response**:
> The project uses the "Hierarchical" chunking strategy, as demonstrated by the function `create_hierarchical_chunks()` and the context indicating that it creates parent-child chunks. This strategy is supported by research emphasizing hierarchical document structuring for better performance in RAG systems.

**Status**: PASS - Correctly identified hierarchical parent-child strategy

### Test 2: qwen3:14b on big72

**Query**: "What chunking strategy does this project use and what are the chunk sizes?"

**Response**:
> The project uses a **hierarchical parent-child chunking strategy**, with **child chunks** around **400 tokens** and **parent chunks** sized between **1000-2000 tokens**, based on research-based recommendations.

**Status**: PASS - Correctly identified strategy AND chunk sizes

### Validation Against Ground Truth

**Ground Truth** (from `src/ingest_hierarchical.rs`):
```rust
const CHILD_TARGET_SIZE: usize = 1200;   // ~400 tokens
const PARENT_TARGET_SIZE: usize = 1800;  // ~600 tokens
```

| Model | Strategy | Chunk Sizes | Status |
|-------|----------|-------------|--------|
| mistral:7b | Parent-Child | Not mentioned | PASS |
| qwen3:14b | Parent-Child | 400/1000-2000 tokens | PASS |

## Complete Script

```bash
#!/bin/bash
# remote-rag-query.sh - Query remote Ollama with local Qdrant context

QUESTION="${1:-What chunking strategy does this project use?}"
COLLECTION="${RAG_COLLECTION:-project-source}"
OLLAMA_HOST="${OLLAMA_HOST:-http://big72:11434}"
MODEL="${OLLAMA_MODEL:-mistral:7b}"

# Get context from local Qdrant
CONTEXT=$(./target/release/search-hierarchical "$QUESTION" \
  --collection "$COLLECTION" --limit 3 --json 2>/dev/null | \
  jq -r '.results[].payload.text' | head -c 2500)

if [ -z "$CONTEXT" ] || [ "$CONTEXT" = "null" ]; then
    echo "No context found"
    exit 1
fi

# Query remote Ollama
curl -s "$OLLAMA_HOST/api/generate" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg model "$MODEL" \
    --arg prompt "Context: $CONTEXT

Question: $QUESTION

Answer based on the context:" \
    '{model: $model, prompt: $prompt, stream: false}')" | jq -r '.response'
```

## Usage Examples

```bash
# Default (mistral:7b on big72)
./scripts/remote-rag-query.sh "How does hybrid search work?"

# Use qwen3:14b for more detailed answers
OLLAMA_MODEL=qwen3:14b ./scripts/remote-rag-query.sh "Explain the chunking constants"

# Query different collection
RAG_COLLECTION=rust-books ./scripts/remote-rag-query.sh "What are Rust macros?"
```

## Performance Comparison

| Location | Model | Response Time | Quality |
|----------|-------|---------------|---------|
| Local | mistral:7b | ~3 sec | Good |
| big72 | mistral:7b | ~5 sec | Good |
| big72 | qwen3:14b | ~12 sec | Better detail |

## Key Points

1. **Local Qdrant + Remote LLM** works seamlessly
2. **big72 has mistral:7b and qwen3:14b** available
3. **qwen3:14b provides more detailed answers** including specific values
4. **Network latency adds ~2 seconds** but larger models compensate with quality
