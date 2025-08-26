#!/bin/bash

# Real-time ingestion status monitor

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

QDRANT_URL="http://localhost:6333"

# Expected collections and PDF counts
# Using simple variables for macOS compatibility
RUST_PDFS=11
JAVASCRIPT_PDFS=8
PYTHON_PDFS=4
LISP_PDFS=6

# Function to format large numbers with commas
format_number() {
    printf "%'d" $1
}

# Function to draw a progress bar
draw_progress_bar() {
    local current=$1
    local total=$2
    local width=30
    
    if [ "$total" -eq 0 ]; then
        echo -n "[${RED}No data${NC}]"
        return
    fi
    
    local percent=$((current * 100 / total))
    local filled=$((width * current / total))
    
    echo -n "["
    for ((i=0; i<filled; i++)); do
        echo -n "${GREEN}█${NC}"
    done
    for ((i=filled; i<width; i++)); do
        echo -n "░"
    done
    echo -n "] ${percent}%"
}

# Main monitoring loop
while true; do
    clear
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}           📚 RAG Ingestion Status Monitor${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "Time: ${YELLOW}$(date +"%H:%M:%S")${NC}"
    echo ""
    
    TOTAL_VECTORS=0
    TOTAL_INDEXED=0
    COLLECTIONS_READY=0
    
    for collection in "rust-books" "javascript-books" "python-books" "lisp-books"; do
        case "$collection" in
            "rust-books") EXPECTED=$RUST_PDFS ;;
            "javascript-books") EXPECTED=$JAVASCRIPT_PDFS ;;
            "python-books") EXPECTED=$PYTHON_PDFS ;;
            "lisp-books") EXPECTED=$LISP_PDFS ;;
        esac
        
        # Get collection stats
        RESPONSE=$(curl -s "$QDRANT_URL/collections/$collection" 2>/dev/null)
        
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}📁 $collection${NC} (${EXPECTED} PDFs expected)"
        
        if echo "$RESPONSE" | grep -q '"status":"ok"'; then
            VECTORS=$(echo "$RESPONSE" | jq -r '.result.points_count // 0')
            INDEXED=$(echo "$RESPONSE" | jq -r '.result.indexed_vectors_count // 0')
            STATUS=$(echo "$RESPONSE" | jq -r '.result.status // "unknown"')
            
            TOTAL_VECTORS=$((TOTAL_VECTORS + VECTORS))
            TOTAL_INDEXED=$((TOTAL_INDEXED + INDEXED))
            
            # Status indicator
            if [ "$STATUS" = "green" ]; then
                STATUS_ICON="🟢"
                COLLECTIONS_READY=$((COLLECTIONS_READY + 1))
            elif [ "$STATUS" = "yellow" ]; then
                STATUS_ICON="🟡"
            else
                STATUS_ICON="🔴"
            fi
            
            echo -e "   Status: $STATUS_ICON ${STATUS}"
            echo -e "   Vectors: ${CYAN}$(format_number $VECTORS)${NC}"
            
            # Indexing progress
            echo -n "   Indexing: "
            if [ "$VECTORS" -gt 0 ]; then
                draw_progress_bar $INDEXED $VECTORS
                echo ""
            else
                echo "No vectors yet"
            fi
            
            # Estimate completion based on average vectors per PDF
            if [ "$VECTORS" -gt 100 ]; then
                # Rough estimate: assume similar distribution across PDFs
                AVG_PER_PDF=$((VECTORS / 2))  # Assume we've processed ~2 PDFs if we have vectors
                if [ "$AVG_PER_PDF" -gt 0 ]; then
                    ESTIMATED_TOTAL=$((AVG_PER_PDF * EXPECTED))
                    echo -n "   Progress: "
                    draw_progress_bar $VECTORS $ESTIMATED_TOTAL
                    echo " (estimate)"
                fi
            fi
        else
            echo -e "   Status: 🔴 ${RED}Not created yet${NC}"
            echo -e "   ${YELLOW}Waiting to be processed...${NC}"
        fi
        echo ""
    done
    
    # Overall summary
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}📊 Overall Statistics${NC}"
    echo -e "   Collections ready: ${GREEN}$COLLECTIONS_READY${NC}/4"
    echo -e "   Total vectors: ${CYAN}$(format_number $TOTAL_VECTORS)${NC}"
    echo -e "   Total indexed: ${CYAN}$(format_number $TOTAL_INDEXED)${NC}"
    
    if [ "$TOTAL_VECTORS" -gt 0 ]; then
        OVERALL_INDEX_PERCENT=$((TOTAL_INDEXED * 100 / TOTAL_VECTORS))
        echo -e "   Index coverage: ${CYAN}${OVERALL_INDEX_PERCENT}%${NC}"
    fi
    
    # Check if ingestion is running
    echo ""
    if pgrep -f "ingest-by-directory" > /dev/null || pgrep -f "ingest-pdf" > /dev/null; then
        echo -e "   ${GREEN}⚡ Ingestion is running${NC}"
        
        # Show recent extracted markdown files as activity indicator
        RECENT_MD=$(find ./extracted -name "*.md" -mmin -5 2>/dev/null | wc -l | tr -d ' ')
        if [ "$RECENT_MD" -gt 0 ]; then
            echo -e "   ${YELLOW}📝 $RECENT_MD files processed in last 5 minutes${NC}"
        fi
    else
        echo -e "   ${YELLOW}⏸  Ingestion not running${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Press Ctrl+C to exit${NC}"
    echo -e "${CYAN}Updates every 5 seconds...${NC}"
    
    sleep 5
done