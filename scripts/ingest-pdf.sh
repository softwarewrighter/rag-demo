#!/bin/bash

# Ingest a PDF into Qdrant for RAG

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <pdf-file>"
    echo "Example: $0 document.pdf"
    echo ""
    echo "To use a specific collection:"
    echo "  export RAG_COLLECTION=javascript-books"
    echo "  $0 javascript-guide.pdf"
    exit 1
fi

PDF_FILE="$1"
COLLECTION="${RAG_COLLECTION:-documents}"

echo -e "${CYAN}Target collection: $COLLECTION${NC}"

# Check if PDF exists
if [ ! -f "$PDF_FILE" ]; then
    echo "❌ Error: PDF file not found: $PDF_FILE"
    exit 1
fi

# Check if Ollama is running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "❌ Ollama is not running. Please start it with: ollama serve"
    exit 1
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

# Build the Rust tool if needed
if [ ! -f "target/release/pdf-to-embeddings" ]; then
    echo "🔨 Building PDF ingestion tool..."
    cargo build --release --bin pdf-to-embeddings
fi

# Check if collection exists
if ! curl -s "http://localhost:6333/collections/$COLLECTION" | grep -q '"status":"ok"'; then
    echo -e "${YELLOW}⚠️  Collection '$COLLECTION' does not exist${NC}"
    echo "Creating it now..."
    ./scripts/setup-collection.sh "$COLLECTION"
fi

# Run the ingestion
echo "📄 Ingesting PDF: $PDF_FILE into collection: $COLLECTION"
./target/release/pdf-to-embeddings --collection "$COLLECTION" "$PDF_FILE"

echo -e "${GREEN}✅ PDF ingestion complete!${NC}"