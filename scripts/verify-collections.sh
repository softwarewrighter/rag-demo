#!/bin/bash

# Verify collection status and indexing

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${CYAN}📊 Collection Verification Report${NC}"
echo "═══════════════════════════════════════════════════"
echo ""

QDRANT_URL="http://localhost:6333"
TOTAL_VECTORS=0
TOTAL_INDEXED=0
COLLECTIONS_FOUND=0

# Expected collections based on directory structure
EXPECTED_COLLECTIONS=("rust-books" "javascript-books" "python-books" "lisp-books")

for collection in "${EXPECTED_COLLECTIONS[@]}"; do
    echo -e "${BLUE}Checking $collection...${NC}"
    
    RESPONSE=$(curl -s "$QDRANT_URL/collections/$collection" 2>/dev/null)
    
    if echo "$RESPONSE" | grep -q '"status":"ok"'; then
        COLLECTIONS_FOUND=$((COLLECTIONS_FOUND + 1))
        
        # Extract stats
        VECTORS=$(echo "$RESPONSE" | jq -r '.result.points_count // 0')
        INDEXED=$(echo "$RESPONSE" | jq -r '.result.indexed_vectors_count // 0')
        STATUS=$(echo "$RESPONSE" | jq -r '.result.status // "unknown"')
        CONFIG=$(echo "$RESPONSE" | jq -r '.result.config')
        
        TOTAL_VECTORS=$((TOTAL_VECTORS + VECTORS))
        TOTAL_INDEXED=$((TOTAL_INDEXED + INDEXED))
        
        # Status color
        if [ "$STATUS" = "green" ]; then
            STATUS_COLOR="${GREEN}✓ $STATUS${NC}"
        elif [ "$STATUS" = "yellow" ]; then
            STATUS_COLOR="${YELLOW}⚠ $STATUS${NC}"
        else
            STATUS_COLOR="${RED}✗ $STATUS${NC}"
        fi
        
        echo -e "  Status: $STATUS_COLOR"
        echo -e "  Vectors: ${CYAN}$VECTORS${NC}"
        echo -e "  Indexed: ${CYAN}$INDEXED${NC}"
        
        # Check if indexing is enabled
        if [ "$INDEXED" -gt 0 ]; then
            echo -e "  Indexing: ${GREEN}✓ Active${NC}"
            PERCENTAGE=$((INDEXED * 100 / VECTORS))
            echo -e "  Coverage: ${CYAN}${PERCENTAGE}%${NC}"
        elif [ "$VECTORS" -gt 1000 ]; then
            echo -e "  Indexing: ${GREEN}✓ Should be active (>1000 vectors)${NC}"
        else
            echo -e "  Indexing: ${YELLOW}⚠ Pending (needs more vectors)${NC}"
        fi
        
        # Test search performance if vectors exist
        if [ "$VECTORS" -gt 0 ]; then
            echo -e "  ${YELLOW}Testing search performance...${NC}"
            
            # Get embedding for test query
            TEST_QUERY="test query for performance"
            EMBEDDING=$(curl -s -X POST "$QDRANT_URL/../11434/api/embeddings" \
                -d "{\"model\":\"nomic-embed-text\",\"prompt\":\"$TEST_QUERY\"}" 2>/dev/null \
                | jq -r '.embedding[:5]' 2>/dev/null || echo "[]")
            
            if [ "$EMBEDDING" != "[]" ] && [ "$EMBEDDING" != "null" ]; then
                # Time a search
                START=$(date +%s%N)
                curl -s -X POST "$QDRANT_URL/collections/$collection/points/search" \
                    -H "Content-Type: application/json" \
                    -d "{\"vector\": $EMBEDDING, \"limit\": 5}" > /dev/null 2>&1
                END=$(date +%s%N)
                
                ELAPSED=$(( (END - START) / 1000000 ))
                
                if [ "$ELAPSED" -lt 100 ]; then
                    echo -e "  Search latency: ${GREEN}${ELAPSED}ms ✓${NC}"
                elif [ "$ELAPSED" -lt 500 ]; then
                    echo -e "  Search latency: ${YELLOW}${ELAPSED}ms${NC}"
                else
                    echo -e "  Search latency: ${RED}${ELAPSED}ms${NC}"
                fi
            fi
        fi
    else
        echo -e "  Status: ${RED}✗ Not found${NC}"
    fi
    
    echo ""
done

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}📈 Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "Collections found: ${GREEN}$COLLECTIONS_FOUND${NC} / ${#EXPECTED_COLLECTIONS[@]}"
echo -e "Total vectors: ${CYAN}$TOTAL_VECTORS${NC}"
echo -e "Total indexed: ${CYAN}$TOTAL_INDEXED${NC}"

if [ "$TOTAL_INDEXED" -gt 0 ] && [ "$TOTAL_VECTORS" -gt 0 ]; then
    OVERALL_PERCENTAGE=$((TOTAL_INDEXED * 100 / TOTAL_VECTORS))
    echo -e "Overall indexing: ${CYAN}${OVERALL_PERCENTAGE}%${NC}"
fi

echo ""

# Recommendations
if [ "$COLLECTIONS_FOUND" -lt "${#EXPECTED_COLLECTIONS[@]}" ]; then
    echo -e "${YELLOW}⚠️  Some collections are missing. Run:${NC}"
    echo "   ./scripts/ingest-by-directory.sh"
fi

if [ "$TOTAL_INDEXED" -eq 0 ] && [ "$TOTAL_VECTORS" -gt 1000 ]; then
    echo -e "${YELLOW}⚠️  Indexing may need to be triggered. Collections will auto-index after threshold.${NC}"
fi

echo ""
echo -e "${CYAN}View dashboard: ${BLUE}http://localhost:6333/dashboard${NC}"