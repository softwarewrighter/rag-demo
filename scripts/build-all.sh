#!/bin/bash
# Build all Rust binaries for the RAG Demo system

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building all RAG Demo tools...${NC}"
echo ""

# Ensure we're in the project root
cd "$(dirname "$0")/.."

echo -e "${YELLOW}Running cargo build --release...${NC}"
echo "This may take a few minutes on first run..."
echo ""

# Build all binaries
cargo build --release

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✅ All tools built successfully!${NC}"
    echo ""
    echo "Built binaries:"
    echo "  • target/release/pdf-to-embeddings"
    echo "  • target/release/search-qdrant"
    echo "  • target/release/ingest-markdown"
    echo "  • target/release/ingest-markdown-multi"
    echo "  • target/release/ingest-hierarchical"
    echo "  • target/release/search-hierarchical"
    echo "  • target/release/ingest-by-directory"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Verify services: ./scripts/health-check.sh"
    echo "  2. Ingest documents: ./scripts/ingest-all-pdfs.sh"
    echo "  3. Try a query: ./scripts/query-rag.sh \"your question\""
else
    echo ""
    echo -e "${RED}❌ Build failed. Please check the error messages above.${NC}"
    exit 1
fi
