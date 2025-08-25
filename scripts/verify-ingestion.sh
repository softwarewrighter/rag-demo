#!/bin/bash

# Verify PDF Ingestion Completeness
# Compares extracted text size with stored chunks

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PDF_FILE="${1:-ingest/Write_Powerful_Rust_Macros.pdf}"

if [ ! -f "$PDF_FILE" ]; then
    echo -e "${RED}❌ File not found: $PDF_FILE${NC}"
    exit 1
fi

echo -e "${CYAN}📋 Ingestion Verification Report${NC}"
echo "════════════════════════════════════════"

# Get PDF info
PDF_SIZE=$(ls -lh "$PDF_FILE" | awk '{print $5}')
PDF_PAGES="Unknown"  # pdfinfo not required

echo -e "${YELLOW}📄 PDF Information:${NC}"
echo "  File: $PDF_FILE"
echo "  Size: $PDF_SIZE"
echo "  Pages: $PDF_PAGES"
echo ""

# Extract text and analyze
echo -e "${YELLOW}📝 Text Extraction:${NC}"
EXTRACTED_TEXT=$(pdf-extract "$PDF_FILE" 2>/dev/null)
TEXT_LENGTH=${#EXTRACTED_TEXT}
TEXT_KB=$((TEXT_LENGTH / 1024))

if [ $TEXT_LENGTH -eq 0 ]; then
    echo -e "${RED}  ⚠️  Warning: No text extracted from PDF${NC}"
    echo "  Trying alternative extraction..."
    
    # Try pdftotext if available
    if command -v pdftotext &> /dev/null; then
        pdftotext "$PDF_FILE" - 2>/dev/null > /tmp/pdf_text.txt
        TEXT_LENGTH=$(wc -c < /tmp/pdf_text.txt)
        TEXT_KB=$((TEXT_LENGTH / 1024))
        echo "  Alternative extraction: ${TEXT_KB}KB of text"
        rm -f /tmp/pdf_text.txt
    fi
else
    echo "  Extracted text: ${TEXT_KB}KB (${TEXT_LENGTH} characters)"
fi

# Check Qdrant storage
echo ""
echo -e "${YELLOW}🗄️  Qdrant Storage:${NC}"

if ! curl -s http://localhost:6333/collections > /dev/null 2>&1; then
    echo -e "${RED}  ❌ Qdrant is not running${NC}"
    exit 1
fi

# Get collection stats
COLLECTION_INFO=$(curl -s http://localhost:6333/collections/documents)
VECTORS_COUNT=$(echo "$COLLECTION_INFO" | jq -r '.result.points_count // 0')
INDEXED_COUNT=$(echo "$COLLECTION_INFO" | jq -r '.result.indexed_vectors_count // 0')

echo "  Vectors stored: $VECTORS_COUNT"
echo "  Vectors indexed: $INDEXED_COUNT"

# Calculate expected chunks
CHUNK_SIZE=1000
CHUNK_OVERLAP=200
EXPECTED_CHUNKS=0

if [ $TEXT_LENGTH -gt 0 ]; then
    EXPECTED_CHUNKS=$(( (TEXT_LENGTH - CHUNK_OVERLAP) / (CHUNK_SIZE - CHUNK_OVERLAP) + 1 ))
    echo "  Expected chunks: ~$EXPECTED_CHUNKS (based on ${CHUNK_SIZE} char chunks)"
fi

# Get actual stored text size
echo ""
echo -e "${YELLOW}📊 Coverage Analysis:${NC}"

# Sample 10 random chunks to estimate total stored text
SAMPLE_SIZE=10
TOTAL_STORED_TEXT=0

for i in $(seq 1 $SAMPLE_SIZE); do
    OFFSET=$((RANDOM % VECTORS_COUNT))
    CHUNK_TEXT=$(curl -s -X POST "http://localhost:6333/collections/documents/points/scroll" \
        -H "Content-Type: application/json" \
        -d "{\"offset\": $OFFSET, \"limit\": 1, \"with_payload\": true, \"with_vector\": false}" \
        2>/dev/null | jq -r '.result.points[0].payload.text' 2>/dev/null)
    
    if [ ! -z "$CHUNK_TEXT" ]; then
        CHUNK_LENGTH=${#CHUNK_TEXT}
        TOTAL_STORED_TEXT=$((TOTAL_STORED_TEXT + CHUNK_LENGTH))
    fi
done

AVG_CHUNK_SIZE=$((TOTAL_STORED_TEXT / SAMPLE_SIZE))
EST_TOTAL_STORED=$((AVG_CHUNK_SIZE * VECTORS_COUNT))
EST_TOTAL_KB=$((EST_TOTAL_STORED / 1024))

echo "  Average chunk size: $AVG_CHUNK_SIZE characters"
echo "  Estimated total stored: ${EST_TOTAL_KB}KB"

# Coverage calculation
if [ $TEXT_LENGTH -gt 0 ] && [ $EST_TOTAL_STORED -gt 0 ]; then
    COVERAGE=$((EST_TOTAL_STORED * 100 / TEXT_LENGTH))
    
    if [ $COVERAGE -gt 100 ]; then
        echo -e "  Coverage: ${GREEN}${COVERAGE}%${NC} (overlap due to chunking)"
    elif [ $COVERAGE -gt 80 ]; then
        echo -e "  Coverage: ${GREEN}${COVERAGE}%${NC} ✅"
    elif [ $COVERAGE -gt 60 ]; then
        echo -e "  Coverage: ${YELLOW}${COVERAGE}%${NC} ⚠️"
    else
        echo -e "  Coverage: ${RED}${COVERAGE}%${NC} ❌"
    fi
fi

# Check for code examples
echo ""
echo -e "${YELLOW}🔍 Content Quality Check:${NC}"

# Search for code indicators
CODE_INDICATORS=("fn " "impl " "macro_rules!" "struct " "let " "#[")
FOUND_CODE=false

for indicator in "${CODE_INDICATORS[@]}"; do
    COUNT=$(curl -s -X POST "http://localhost:6333/collections/documents/points/scroll" \
        -H "Content-Type: application/json" \
        -d '{"limit": 100, "with_payload": true, "with_vector": false}' 2>/dev/null | \
        jq -r '.result.points[].payload.text' 2>/dev/null | \
        grep -c "$indicator" || echo 0)
    
    if [ $COUNT -gt 0 ]; then
        echo "  ✓ Found '$indicator' in $COUNT chunks"
        FOUND_CODE=true
    fi
done

if [ "$FOUND_CODE" = false ]; then
    echo -e "  ${YELLOW}⚠️  No code patterns found - extraction may need improvement${NC}"
fi

# Storage efficiency
echo ""
echo -e "${YELLOW}💾 Storage Efficiency:${NC}"

QDRANT_SIZE=$(du -sh qdrant_storage/ 2>/dev/null | awk '{print $1}')
echo "  PDF size: $PDF_SIZE"
echo "  Qdrant storage: $QDRANT_SIZE"
echo "  Vectors memory: ~${VECTORS_COUNT} × 768 × 4 bytes = $(( VECTORS_COUNT * 768 * 4 / 1024 / 1024 ))MB"

# Recommendations
echo ""
echo -e "${CYAN}📋 Recommendations:${NC}"

if [ $INDEXED_COUNT -eq 0 ] && [ $VECTORS_COUNT -gt 100 ]; then
    echo "  • Consider forcing indexing for better search performance"
fi

if [ $TEXT_LENGTH -eq 0 ]; then
    echo "  • PDF extraction failed - consider using different extraction library"
elif [ $COVERAGE -lt 80 ] 2>/dev/null; then
    echo "  • Low coverage - check PDF extraction and chunking logic"
fi

if [ "$FOUND_CODE" = false ]; then
    echo "  • Code extraction poor - implement code-aware chunking"
fi

echo ""
echo "════════════════════════════════════════"