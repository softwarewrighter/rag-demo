#!/bin/bash

# Query the RAG system using Qdrant and Ollama

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <query> [llm-model]"
    echo "Example: $0 'What is machine learning?' llama3.2"
    echo ""
    echo "Optional: Specify LLM model (default: llama3.2)"
    echo ""
    echo "To query a specific collection:"
    echo "  export RAG_COLLECTION=python-books"
    echo "  $0 'What are decorators?'"
    exit 1
fi

QUERY="$1"
LLM_MODEL="${2:-llama3.2}"
COLLECTION="${RAG_COLLECTION:-documents}"

echo "🔍 Querying collection: $COLLECTION"

# Check if Ollama is running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "❌ Ollama is not running. Please start it with: ollama serve"
    exit 1
fi

# Check if LLM model is available
if ! ollama list | grep -q "$LLM_MODEL"; then
    echo "📦 Pulling $LLM_MODEL model..."
    ollama pull "$LLM_MODEL"
fi

# Check if embedding model is available
if ! ollama list | grep -q "nomic-embed-text"; then
    echo "📦 Pulling nomic-embed-text model..."
    ollama pull nomic-embed-text
fi

# Check if Qdrant is running
if ! curl -s http://localhost:6333/collections > /dev/null 2>&1; then
    echo "❌ Qdrant is not running. Please run: ./scripts/setup-qdrant.sh"
    exit 1
fi

# Build the Rust search tool if needed
if [ ! -f "target/release/search-qdrant" ]; then
    echo "🔨 Building search tool..."
    cargo build --release --bin search-qdrant
fi

# Search for relevant context
echo "🔍 Searching knowledge base..."
CONTEXT=$(./target/release/search-qdrant "$QUERY" --collection "$COLLECTION" --json 2>/dev/null | jq -r '.results[].text' 2>/dev/null | head -c 4000)

if [ -z "$CONTEXT" ]; then
    echo "⚠️  No relevant context found in knowledge base"
    echo "💭 Answering without RAG context..."
    
    # Answer without context
    PROMPT="Please answer this question: $QUERY"
else
    echo "📚 Found relevant context"
    echo "💭 Generating answer with $LLM_MODEL..."
    
    # Create RAG prompt
    PROMPT="Based on the following context from the knowledge base, please answer the question.

Context:
$CONTEXT

Question: $QUERY

Please provide a clear and concise answer based on the context provided. If the context doesn't contain enough information to fully answer the question, please indicate what information is missing."
fi

# Send to Ollama
echo ""
echo "🤖 Answer:"
echo "────────────────────────────────────────"
curl -s -X POST http://localhost:11434/api/generate \
    -d "{
        \"model\": \"$LLM_MODEL\",
        \"prompt\": \"$PROMPT\",
        \"stream\": false
    }" | jq -r '.response'
echo "────────────────────────────────────────"