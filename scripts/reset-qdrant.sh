#!/bin/bash

# Reset Qdrant Database
# Options to clear collection or completely reset

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${YELLOW}⚠️  Qdrant Reset Tool${NC}"
echo "════════════════════════════════════════"
echo ""

# Check if Qdrant is running
if ! curl -s http://localhost:6333/collections > /dev/null 2>&1; then
    echo -e "${RED}❌ Qdrant is not running${NC}"
    echo "   Please run: ./scripts/setup-qdrant.sh"
    exit 1
fi

# Show current status
echo -e "${CYAN}Current Status:${NC}"
COLLECTIONS=$(curl -s http://localhost:6333/collections | jq -r '.result.collections[].name' 2>/dev/null)

if [ -z "$COLLECTIONS" ]; then
    echo "  No collections found"
else
    for collection in $COLLECTIONS; do
        COUNT=$(curl -s http://localhost:6333/collections/$collection | jq -r '.result.points_count' 2>/dev/null)
        echo "  Collection '$collection': $COUNT vectors"
    done
fi

QDRANT_SIZE=$(du -sh qdrant_storage/ 2>/dev/null | awk '{print $1}' || echo "Unknown")
echo "  Storage size: $QDRANT_SIZE"
echo ""

# Menu
echo "Choose reset option:"
echo "  1) Clear 'documents' collection (keep Qdrant running)"
echo "  2) Delete all collections (keep Qdrant running)"
echo "  3) Full reset - stop Qdrant and delete all data"
echo "  4) Cancel"
echo ""
echo -n "Enter choice [1-4]: "
read -r choice

case $choice in
    1)
        echo ""
        echo -e "${YELLOW}Clearing 'documents' collection...${NC}"
        
        # Delete and recreate the collection
        curl -s -X DELETE "http://localhost:6333/collections/documents" > /dev/null 2>&1 || true
        
        sleep 1
        
        # Recreate with proper configuration
        curl -s -X PUT "http://localhost:6333/collections/documents" \
            -H "Content-Type: application/json" \
            -d '{
                "vectors": {
                    "size": 768,
                    "distance": "Cosine"
                },
                "optimizers_config": {
                    "indexing_threshold": 1000
                },
                "hnsw_config": {
                    "m": 16,
                    "ef_construct": 200,
                    "full_scan_threshold": 100
                }
            }' > /dev/null 2>&1
        
        echo -e "${GREEN}✅ Collection 'documents' cleared and recreated${NC}"
        echo "   Ready for new ingestions"
        ;;
        
    2)
        echo ""
        echo -e "${YELLOW}Deleting all collections...${NC}"
        
        for collection in $COLLECTIONS; do
            echo "  Deleting '$collection'..."
            curl -s -X DELETE "http://localhost:6333/collections/$collection" > /dev/null 2>&1
        done
        
        # Recreate default collection
        sleep 1
        curl -s -X PUT "http://localhost:6333/collections/documents" \
            -H "Content-Type: application/json" \
            -d '{
                "vectors": {
                    "size": 768,
                    "distance": "Cosine"
                },
                "optimizers_config": {
                    "indexing_threshold": 1000
                },
                "hnsw_config": {
                    "m": 16,
                    "ef_construct": 200,
                    "full_scan_threshold": 100
                }
            }' > /dev/null 2>&1
        
        echo -e "${GREEN}✅ All collections deleted${NC}"
        echo "   Created fresh 'documents' collection"
        ;;
        
    3)
        echo ""
        echo -e "${RED}⚠️  This will DELETE ALL DATA and stop Qdrant!${NC}"
        echo -n "Are you sure? Type 'yes' to confirm: "
        read -r confirm
        
        if [ "$confirm" != "yes" ]; then
            echo "Cancelled"
            exit 0
        fi
        
        echo ""
        echo -e "${YELLOW}Performing full reset...${NC}"
        
        # Stop Qdrant container
        echo "  Stopping Qdrant container..."
        docker stop qdrant 2>/dev/null || true
        
        # Remove container
        echo "  Removing container..."
        docker rm qdrant 2>/dev/null || true
        
        # Delete storage
        echo "  Deleting storage directory..."
        rm -rf qdrant_storage/
        
        echo ""
        echo -e "${GREEN}✅ Full reset complete${NC}"
        echo ""
        echo "To start fresh, run:"
        echo "  ./scripts/setup-qdrant.sh"
        echo "  ./scripts/ingest-pdf.sh <your-pdf>"
        ;;
        
    4)
        echo "Cancelled"
        exit 0
        ;;
        
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo "════════════════════════════════════════"

# Show new status
if curl -s http://localhost:6333/collections > /dev/null 2>&1; then
    echo ""
    echo -e "${CYAN}New Status:${NC}"
    COLLECTIONS=$(curl -s http://localhost:6333/collections | jq -r '.result.collections[].name' 2>/dev/null)
    
    if [ -z "$COLLECTIONS" ]; then
        echo "  No collections"
    else
        for collection in $COLLECTIONS; do
            COUNT=$(curl -s http://localhost:6333/collections/$collection | jq -r '.result.points_count' 2>/dev/null)
            echo "  Collection '$collection': $COUNT vectors"
        done
    fi
    
    QDRANT_SIZE=$(du -sh qdrant_storage/ 2>/dev/null | awk '{print $1}' || echo "0K")
    echo "  Storage size: $QDRANT_SIZE"
fi