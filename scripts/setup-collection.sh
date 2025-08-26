#!/bin/bash

# Setup script for creating named collections in Qdrant
# Usage: ./scripts/setup-collection.sh <collection-name> [alias]
# Example: ./scripts/setup-collection.sh javascript-books "JS Programming Books"

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check arguments
if [ $# -lt 1 ]; then
    echo -e "${RED}❌ Error: Collection name required${NC}"
    echo "Usage: $0 <collection-name> [alias]"
    echo "Examples:"
    echo "  $0 rust-books \"Rust Programming Books\""
    echo "  $0 javascript-books \"JavaScript Documentation\""
    echo "  $0 python-books \"Python References\""
    exit 1
fi

COLLECTION_NAME="$1"
COLLECTION_ALIAS="${2:-}"
QDRANT_URL="http://localhost:6333"

echo -e "${CYAN}📚 Setting up collection: $COLLECTION_NAME${NC}"
echo "═══════════════════════════════════════════"

# Validate collection name (alphanumeric, hyphens, underscores only)
if ! [[ "$COLLECTION_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo -e "${RED}❌ Invalid collection name. Use only letters, numbers, hyphens, and underscores${NC}"
    exit 1
fi

# Prevent using generic "documents" name
if [ "$COLLECTION_NAME" = "documents" ]; then
    echo -e "${YELLOW}⚠️  Warning: 'documents' is too generic!${NC}"
    echo "Please use a more descriptive name like:"
    echo "  • rust-books"
    echo "  • javascript-docs"
    echo "  • python-tutorials"
    echo "  • company-policies"
    echo "  • research-papers"
    read -p "Do you really want to use 'documents'? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if Qdrant is running
if ! curl -s "$QDRANT_URL/health" > /dev/null 2>&1; then
    echo -e "${RED}❌ Qdrant is not running${NC}"
    echo "Please start Qdrant first with: ./scripts/setup-qdrant.sh"
    exit 1
fi

# Check if collection already exists
echo -e "${YELLOW}Checking if collection exists...${NC}"
if curl -s "$QDRANT_URL/collections/$COLLECTION_NAME" | grep -q '"status":"ok"'; then
    echo -e "${GREEN}✅ Collection '$COLLECTION_NAME' already exists${NC}"
    
    # Still try to add alias if provided and not already set
    if [ -n "$COLLECTION_ALIAS" ]; then
        echo -e "${YELLOW}Adding/updating alias...${NC}"
        curl -s -X POST "$QDRANT_URL/collections/aliases" \
            -H "Content-Type: application/json" \
            -d "{
                \"actions\": [
                    {
                        \"create_alias\": {
                            \"collection_name\": \"$COLLECTION_NAME\",
                            \"alias_name\": \"$COLLECTION_ALIAS\"
                        }
                    }
                ]
            }" > /dev/null 2>&1 || true
    fi
else
    # Create new collection
    echo -e "${YELLOW}Creating new collection '$COLLECTION_NAME'...${NC}"
    
    RESPONSE=$(curl -s -X PUT "$QDRANT_URL/collections/$COLLECTION_NAME" \
        -H "Content-Type: application/json" \
        -d '{
            "vectors": {
                "size": 768,
                "distance": "Cosine"
            },
            "optimizers_config": {
                "default_segment_number": 2,
                "indexing_threshold": 1000
            }
        }')
    
    if echo "$RESPONSE" | grep -q '"status":"ok"'; then
        echo -e "${GREEN}✅ Collection created successfully${NC}"
    else
        echo -e "${RED}❌ Failed to create collection${NC}"
        echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
        exit 1
    fi
    
    # Add alias if provided
    if [ -n "$COLLECTION_ALIAS" ]; then
        echo -e "${YELLOW}Adding alias '$COLLECTION_ALIAS'...${NC}"
        curl -s -X POST "$QDRANT_URL/collections/aliases" \
            -H "Content-Type: application/json" \
            -d "{
                \"actions\": [
                    {
                        \"create_alias\": {
                            \"collection_name\": \"$COLLECTION_NAME\",
                            \"alias_name\": \"$COLLECTION_ALIAS\"
                        }
                    }
                ]
            }" > /dev/null 2>&1 || true
        echo -e "${GREEN}✅ Alias added${NC}"
    fi
fi

# Display collection info
echo ""
echo -e "${CYAN}Collection Information:${NC}"
echo "  • Name: $COLLECTION_NAME"
if [ -n "$COLLECTION_ALIAS" ]; then
    echo "  • Alias: $COLLECTION_ALIAS"
fi
echo "  • Vector size: 768 (nomic-embed-text)"
echo "  • Distance metric: Cosine"
echo "  • API endpoint: $QDRANT_URL/collections/$COLLECTION_NAME"
echo ""
echo -e "${GREEN}✨ Collection ready for ingestion!${NC}"
echo ""
echo "Next steps:"
echo "  1. Export collection name: export RAG_COLLECTION=\"$COLLECTION_NAME\""
echo "  2. Ingest PDFs: ./scripts/ingest-pdf.sh <pdf-file>"
echo "  3. Query: ./scripts/query-rag.sh \"your question\""