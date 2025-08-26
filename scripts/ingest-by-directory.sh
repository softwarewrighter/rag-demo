#!/bin/bash

# Ingest PDFs organized by subdirectory into appropriate collections
# Each subdirectory becomes its own collection

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

INGEST_DIR="${1:-./ingest}"

echo -e "${CYAN}📚 Directory-Based Ingestion System${NC}"
echo "═══════════════════════════════════════════════════"
echo ""

# Check if ingest directory exists
if [ ! -d "$INGEST_DIR" ]; then
    echo -e "${RED}❌ Ingest directory not found: $INGEST_DIR${NC}"
    exit 1
fi

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

# Build tools if needed
if [ ! -f "target/release/ingest-hierarchical" ]; then
    echo "🔨 Building ingestion tools..."
    cargo build --release --bin ingest-hierarchical
fi

# Track statistics
TOTAL_PDFS=0
TOTAL_COLLECTIONS=0
# Use a simpler approach for stats tracking
COLLECTION_LIST=""

# Process each subdirectory
for dir in "$INGEST_DIR"/*; do
    if [ ! -d "$dir" ]; then
        continue
    fi
    
    # Get directory name for collection
    DIRNAME=$(basename "$dir")
    COLLECTION="${DIRNAME}-books"
    
    # Count PDFs in this directory
    PDF_COUNT=$(find "$dir" -maxdepth 1 -name "*.pdf" 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$PDF_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No PDFs found in $DIRNAME/, skipping${NC}"
        continue
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📂 Processing: $DIRNAME${NC}"
    echo -e "${CYAN}   Collection: $COLLECTION${NC}"
    echo -e "${CYAN}   PDF files: $PDF_COUNT${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # Create collection if needed (no alias)
    echo -e "${YELLOW}Setting up collection: $COLLECTION${NC}"
    ./scripts/setup-collection.sh "$COLLECTION"
    
    # Track collection
    TOTAL_COLLECTIONS=$((TOTAL_COLLECTIONS + 1))
    COLLECTION_STATS["$COLLECTION"]=0
    
    # Process each PDF in the directory
    for pdf in "$dir"/*.pdf; do
        if [ ! -f "$pdf" ]; then
            continue
        fi
        
        PDF_NAME=$(basename "$pdf")
        echo ""
        echo -e "${CYAN}📄 Ingesting: $PDF_NAME${NC}"
        
        # Set collection and ingest
        export RAG_COLLECTION="$COLLECTION"
        
        # Use smart ingestion for better results
        if ./scripts/ingest-pdf-smart.sh "$pdf"; then
            TOTAL_PDFS=$((TOTAL_PDFS + 1))
            COLLECTION_STATS["$COLLECTION"]=$((COLLECTION_STATS["$COLLECTION"] + 1))
            echo -e "${GREEN}   ✓ Successfully ingested${NC}"
        else
            echo -e "${RED}   ✗ Failed to ingest $PDF_NAME${NC}"
        fi
    done
    
    # Show collection statistics
    VECTORS=$(curl -s "http://localhost:6333/collections/$COLLECTION" | jq -r '.result.points_count // 0')
    echo ""
    echo -e "${CYAN}📊 Collection '$COLLECTION' Statistics:${NC}"
    echo "   • PDFs ingested: ${COLLECTION_STATS[$COLLECTION]}"
    echo "   • Total vectors: $VECTORS"
done

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✨ Directory-Based Ingestion Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}📊 Overall Statistics:${NC}"
echo "   • Total collections created: $TOTAL_COLLECTIONS"
echo "   • Total PDFs ingested: $TOTAL_PDFS"
echo ""

# Show all collections with their stats
echo -e "${CYAN}📚 Collections Summary:${NC}"
for collection in "${!COLLECTION_STATS[@]}"; do
    VECTORS=$(curl -s "http://localhost:6333/collections/$collection" 2>/dev/null | jq -r '.result.points_count // 0')
    INDEXED=$(curl -s "http://localhost:6333/collections/$collection" 2>/dev/null | jq -r '.result.indexed_vectors_count // 0')
    STATUS=$(curl -s "http://localhost:6333/collections/$collection" 2>/dev/null | jq -r '.result.status // "unknown"')
    
    echo ""
    echo "   ${collection}:"
    echo "      • PDFs: ${COLLECTION_STATS[$collection]}"
    echo "      • Vectors: $VECTORS"
    echo "      • Indexed: $INDEXED"
    echo "      • Status: $STATUS"
done

echo ""
echo -e "${CYAN}🎯 Next Steps:${NC}"
echo "   1. Query Rust books:       RAG_COLLECTION=rust-books ./scripts/query-rag.sh \"What is ownership?\""
echo "   2. Query JavaScript books: RAG_COLLECTION=javascript-books ./scripts/query-rag.sh \"Explain promises\""
echo "   3. Query Python books:     RAG_COLLECTION=python-books ./scripts/query-rag.sh \"What are decorators?\""
echo "   4. Query Lisp books:       RAG_COLLECTION=lisp-books ./scripts/query-rag.sh \"What are macros?\""
echo ""
echo "   View dashboard: http://localhost:6333/dashboard"