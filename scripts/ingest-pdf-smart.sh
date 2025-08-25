#!/bin/bash

# Smart PDF Ingestion via Markdown
# Preserves code blocks and document structure

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PDF_FILE="$1"
EXTRACTED_DIR="./extracted"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <pdf-file>"
    echo "Example: $0 document.pdf"
    exit 1
fi

if [ ! -f "$PDF_FILE" ]; then
    echo -e "${RED}❌ Error: PDF file not found: $PDF_FILE${NC}"
    exit 1
fi

echo -e "${CYAN}🚀 Smart PDF Ingestion Pipeline${NC}"
echo "════════════════════════════════════════"
echo ""

# Check prerequisites
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo -e "${RED}❌ Ollama is not running. Please start it with: ollama serve${NC}"
    exit 1
fi

if ! curl -s http://localhost:6333/collections > /dev/null 2>&1; then
    echo -e "${RED}❌ Qdrant is not running. Please run: ./scripts/setup-qdrant.sh${NC}"
    exit 1
fi

# Ensure embedding model is available
if ! ollama list | grep -q "nomic-embed-text"; then
    echo "📦 Pulling embedding model..."
    ollama pull nomic-embed-text
fi

# Step 1: Convert PDF to Markdown
echo -e "${YELLOW}Step 1: PDF → Markdown${NC}"
echo "────────────────────────────────────────"

chmod +x scripts/pdf-to-markdown.sh 2>/dev/null || true
./scripts/pdf-to-markdown.sh "$PDF_FILE" "$EXTRACTED_DIR"

# Get the markdown file path
BASENAME=$(basename "$PDF_FILE" .pdf)
MD_FILE="$EXTRACTED_DIR/${BASENAME}.md"

if [ ! -f "$MD_FILE" ]; then
    echo -e "${RED}❌ Markdown conversion failed${NC}"
    exit 1
fi

echo ""

# Step 2: Build the ingestion tool if needed
if [ ! -f "target/release/ingest-markdown" ]; then
    echo -e "${YELLOW}Step 2: Building ingestion tool...${NC}"
    cargo build --release --bin ingest-markdown
    echo ""
fi

# Step 3: Ingest Markdown with smart chunking
echo -e "${YELLOW}Step 3: Markdown → Qdrant (with smart chunking)${NC}"
echo "────────────────────────────────────────"

./target/release/ingest-markdown "$MD_FILE"

echo ""
echo -e "${GREEN}✨ Smart ingestion complete!${NC}"
echo ""

# Show statistics
echo -e "${CYAN}📊 Ingestion Statistics:${NC}"
echo "────────────────────────────────────────"

# Get collection stats
VECTORS=$(curl -s http://localhost:6333/collections/documents | jq -r '.result.points_count // 0')
echo "  Total vectors in database: $VECTORS"

# Test search for code
echo ""
echo -e "${CYAN}🔍 Quick Test - Searching for code examples:${NC}"

if [ -f "target/release/search-qdrant" ]; then
    # Search for common Rust patterns
    for pattern in "fn main" "macro_rules" "impl" "struct"; do
        COUNT=$(./target/release/search-qdrant "$pattern" --limit 1 --json 2>/dev/null | \
                jq '.results | length' 2>/dev/null || echo "0")
        if [ "$COUNT" -gt 0 ]; then
            SCORE=$(./target/release/search-qdrant "$pattern" --limit 1 --json 2>/dev/null | \
                    jq -r '.results[0].score' 2>/dev/null)
            echo "  ✓ Found '$pattern' (score: $SCORE)"
        fi
    done
fi

echo ""
echo -e "${GREEN}Ready for queries!${NC}"
echo "  Use: ./scripts/interactive-rag.sh"
echo "  Or:  ./scripts/query-rag.sh 'your question'"