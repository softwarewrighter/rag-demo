#!/bin/bash

# Add descriptive alias to the collection
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

QDRANT_URL="http://localhost:6333"
COLLECTION="documents"
ALIAS="rust-books"

echo -e "${CYAN}📚 Updating Collection Alias${NC}"
echo "════════════════════════════════════════"

# Check if Qdrant is running
if ! curl -s "$QDRANT_URL/health" > /dev/null 2>&1; then
    echo -e "${RED}❌ Qdrant is not running${NC}"
    echo "Please start Qdrant with: ./scripts/setup-qdrant.sh"
    exit 1
fi

# Check if collection exists
if ! curl -s "$QDRANT_URL/collections/$COLLECTION" | jq -e '.result' > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Collection '$COLLECTION' does not exist${NC}"
    echo "The collection will be created with the proper name when you ingest documents."
    exit 0
fi

# Create alias
echo -e "${YELLOW}Adding alias '$ALIAS' to collection '$COLLECTION'...${NC}"

RESPONSE=$(curl -s -X POST "$QDRANT_URL/collections/aliases" \
    -H "Content-Type: application/json" \
    -d "{
        \"actions\": [
            {
                \"create_alias\": {
                    \"collection_name\": \"$COLLECTION\",
                    \"alias_name\": \"$ALIAS\"
                }
            }
        ]
    }")

if echo "$RESPONSE" | jq -e '.result' > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Alias created successfully!${NC}"
    echo ""
    echo "You can now access the collection using either:"
    echo "  • Original name: $COLLECTION"
    echo "  • Alias: $ALIAS"
    echo ""
    echo "The Qdrant dashboard will show both names."
else
    ERROR=$(echo "$RESPONSE" | jq -r '.status.error // "Unknown error"')
    if [[ "$ERROR" == *"already exists"* ]]; then
        echo -e "${YELLOW}ℹ️  Alias '$ALIAS' already exists${NC}"
    else
        echo -e "${RED}❌ Failed to create alias: $ERROR${NC}"
        exit 1
    fi
fi

# Show current aliases
echo -e "${CYAN}Current collection aliases:${NC}"
curl -s "$QDRANT_URL/collections/aliases" | jq -r '.result.aliases[] | "  • \(.alias_name) → \(.collection_name)"'