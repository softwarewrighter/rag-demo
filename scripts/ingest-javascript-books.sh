#!/bin/bash

# Ingest JavaScript books into their own collection
# This ensures JavaScript documentation is separate from other topics

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}📚 JavaScript Books Ingestion${NC}"
echo "═══════════════════════════════════════"

# Set the collection name
export RAG_COLLECTION="javascript-books"

# Ensure the collection exists with proper alias
./scripts/setup-collection.sh "$RAG_COLLECTION" "JavaScript Documentation"

# Check for PDFs to ingest
if [ "$#" -eq 0 ]; then
    echo ""
    echo "Usage: $0 <pdf-files...>"
    echo "Example: $0 javascript-guide.pdf eloquent-javascript.pdf"
    echo ""
    echo "Or to ingest all JavaScript PDFs from ingest directory:"
    echo "  $0 ingest/*javascript*.pdf ingest/*js*.pdf"
    exit 1
fi

echo ""
echo -e "${YELLOW}Processing ${#} PDF file(s) into collection: $RAG_COLLECTION${NC}"

# Process each PDF
for pdf in "$@"; do
    if [ -f "$pdf" ]; then
        echo ""
        echo "───────────────────────────────────────"
        echo -e "${CYAN}Ingesting: $(basename "$pdf")${NC}"
        ./scripts/ingest-pdf-smart.sh "$pdf"
    else
        echo -e "${YELLOW}⚠️  Skipping non-existent file: $pdf${NC}"
    fi
done

echo ""
echo -e "${GREEN}✨ JavaScript books ingestion complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Query JavaScript docs: RAG_COLLECTION=javascript-books ./scripts/query-rag.sh \"How do promises work?\""
echo "  2. Interactive mode: RAG_COLLECTION=javascript-books ./scripts/interactive-rag.sh"
echo "  3. View stats: curl -s http://localhost:6333/collections/javascript-books | jq '.result.points_count'"