#!/bin/bash

# Ingest all PDFs with deduplication and progress tracking
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

INGEST_DIR="${1:-./ingest}"
EXTRACTED_DIR="./extracted"
CHECKSUM_FILE=".ingested_checksums"
STATS_FILE=".ingestion_stats.json"

# Initialize stats
TOTAL_PDFS=0
NEW_PDFS=0
SKIPPED_PDFS=0
TOTAL_CHUNKS=0
TOTAL_TIME=0
FAILED_PDFS=()

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Bulk PDF Ingestion with Dedup     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
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

# Ensure tools are built
if [ ! -f "target/release/ingest-hierarchical" ]; then
    echo -e "${YELLOW}Building ingestion tools...${NC}"
    cargo build --release --bin ingest-hierarchical
fi

# Create directories
mkdir -p "$EXTRACTED_DIR"
touch "$CHECKSUM_FILE"

# Function to calculate file checksum
calc_checksum() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        sha256sum "$1" | cut -d' ' -f1
    fi
}

# Function to check if file was already ingested
is_ingested() {
    local checksum="$1"
    grep -q "^$checksum" "$CHECKSUM_FILE" 2>/dev/null
}

# Function to record ingestion
record_ingestion() {
    local file="$1"
    local checksum="$2"
    local chunks="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$checksum|$file|$chunks|$timestamp" >> "$CHECKSUM_FILE"
}

# Count PDFs
PDF_FILES=($(find "$INGEST_DIR" -name "*.pdf" -type f 2>/dev/null | sort))
TOTAL_PDFS=${#PDF_FILES[@]}

if [ $TOTAL_PDFS -eq 0 ]; then
    echo -e "${YELLOW}No PDF files found in $INGEST_DIR${NC}"
    exit 0
fi

echo -e "${BLUE}Found $TOTAL_PDFS PDF files to process${NC}"
echo ""

# Check Qdrant current state
INITIAL_VECTORS=$(curl -s http://localhost:6333/collections/documents | jq -r '.result.points_count // 0')
echo -e "${CYAN}Current database: $INITIAL_VECTORS vectors${NC}"
echo ""

# Process each PDF
START_TIME=$(date +%s)

for i in "${!PDF_FILES[@]}"; do
    PDF="${PDF_FILES[$i]}"
    BASENAME=$(basename "$PDF" .pdf)
    PROGRESS=$((i + 1))
    
    echo -e "${YELLOW}[$PROGRESS/$TOTAL_PDFS] Processing: $BASENAME${NC}"
    echo "────────────────────────────────────────"
    
    # Calculate checksum
    CHECKSUM=$(calc_checksum "$PDF")
    echo "  Checksum: ${CHECKSUM:0:16}..."
    
    # Check if already ingested
    if is_ingested "$CHECKSUM"; then
        echo -e "  ${YELLOW}⏭️  Already ingested (skipping)${NC}"
        SKIPPED_PDFS=$((SKIPPED_PDFS + 1))
        
        # Show when it was ingested
        INGESTION_INFO=$(grep "^$CHECKSUM" "$CHECKSUM_FILE" | tail -1)
        INGESTED_DATE=$(echo "$INGESTION_INFO" | cut -d'|' -f4)
        INGESTED_CHUNKS=$(echo "$INGESTION_INFO" | cut -d'|' -f3)
        echo "  Previously ingested: $INGESTED_DATE ($INGESTED_CHUNKS chunks)"
        echo ""
        continue
    fi
    
    # Extract to Markdown
    echo "  📄 Converting to Markdown..."
    MD_FILE="$EXTRACTED_DIR/${BASENAME}.md"
    
    if ./scripts/pdf-to-markdown.sh "$PDF" "$EXTRACTED_DIR" 2>&1 | grep -q "Conversion complete"; then
        echo -e "  ${GREEN}✓ Converted successfully${NC}"
    else
        echo -e "  ${RED}✗ Conversion failed${NC}"
        FAILED_PDFS+=("$BASENAME")
        continue
    fi
    
    # Get file size info
    PDF_SIZE=$(ls -lh "$PDF" | awk '{print $5}')
    MD_SIZE=$(ls -lh "$MD_FILE" 2>/dev/null | awk '{print $5}' || echo "0")
    echo "  Sizes: PDF=$PDF_SIZE, MD=$MD_SIZE"
    
    # Ingest with hierarchical chunking
    echo "  🧮 Ingesting with hierarchical chunking..."
    INGEST_OUTPUT=$(./target/release/ingest-hierarchical "$MD_FILE" 2>&1)
    
    # Extract chunk counts
    PARENT_CHUNKS=$(echo "$INGEST_OUTPUT" | grep "Parent chunks:" | grep -oE '[0-9]+' | head -1 || echo "0")
    CHILD_CHUNKS=$(echo "$INGEST_OUTPUT" | grep "Child chunks:" | grep -oE '[0-9]+' | head -1 || echo "0") 
    CHUNK_COUNT=$((PARENT_CHUNKS + CHILD_CHUNKS))
    
    if [ "$CHUNK_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Ingested: $PARENT_CHUNKS parent + $CHILD_CHUNKS child chunks${NC}"
        record_ingestion "$PDF" "$CHECKSUM" "$CHUNK_COUNT"
        NEW_PDFS=$((NEW_PDFS + 1))
        TOTAL_CHUNKS=$((TOTAL_CHUNKS + CHUNK_COUNT))
    else
        echo -e "  ${RED}✗ Ingestion failed${NC}"
        FAILED_PDFS+=("$BASENAME")
    fi
    
    echo ""
done

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

# Get final stats
FINAL_VECTORS=$(curl -s http://localhost:6333/collections/documents | jq -r '.result.points_count // 0')
NEW_VECTORS=$((FINAL_VECTORS - INITIAL_VECTORS))

# Display summary
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Ingestion Summary            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Successfully processed:${NC}"
echo "   • Total PDFs found: $TOTAL_PDFS"
echo "   • New PDFs ingested: $NEW_PDFS"
echo "   • PDFs skipped (duplicate): $SKIPPED_PDFS"
echo "   • Failed: ${#FAILED_PDFS[@]}"
if [ ${#FAILED_PDFS[@]} -gt 0 ]; then
    echo -e "${RED}   Failed files:${NC}"
    for f in "${FAILED_PDFS[@]}"; do
        echo "     - $f"
    done
fi
echo ""
echo -e "${BLUE}📊 Database Statistics:${NC}"
echo "   • Vectors before: $INITIAL_VECTORS"
echo "   • Vectors after: $FINAL_VECTORS"
echo "   • New vectors added: $NEW_VECTORS"
echo "   • Total chunks created: $TOTAL_CHUNKS"
echo ""
echo -e "${YELLOW}⏱️  Performance:${NC}"
echo "   • Total time: ${TOTAL_TIME}s"
if [ $NEW_PDFS -gt 0 ]; then
    AVG_TIME=$((TOTAL_TIME / NEW_PDFS))
    echo "   • Average per PDF: ${AVG_TIME}s"
fi
echo ""

# Save stats to JSON
cat > "$STATS_FILE" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_pdfs": $TOTAL_PDFS,
  "new_pdfs": $NEW_PDFS,
  "skipped_pdfs": $SKIPPED_PDFS,
  "failed_pdfs": ${#FAILED_PDFS[@]},
  "total_chunks": $TOTAL_CHUNKS,
  "new_vectors": $NEW_VECTORS,
  "total_vectors": $FINAL_VECTORS,
  "processing_time_seconds": $TOTAL_TIME
}
EOF

echo -e "${GREEN}📁 Stats saved to: $STATS_FILE${NC}"
echo -e "${GREEN}📝 Checksums saved to: $CHECKSUM_FILE${NC}"