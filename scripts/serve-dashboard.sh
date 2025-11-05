#!/bin/bash
# Build and serve the RAG Demo dashboard locally

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Ensure we're in the project root
cd "$(dirname "$0")/.."

echo -e "${BLUE}RAG Demo Dashboard Server${NC}"
echo ""

# Check if services are running
echo -e "${YELLOW}Checking required services...${NC}"

QDRANT_OK=false
OLLAMA_OK=false

if curl -s http://localhost:6333/collections > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Qdrant is running on port 6333"
    QDRANT_OK=true
else
    echo -e "  ${RED}✗${NC} Qdrant is not running on port 6333"
fi

if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Ollama is running on port 11434"
    OLLAMA_OK=true
else
    echo -e "  ${RED}✗${NC} Ollama is not running on port 11434"
fi

if [ "$QDRANT_OK" = false ] || [ "$OLLAMA_OK" = false ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Some services are not running.${NC}"
    echo "The dashboard will load but may not function properly."
    echo ""
    echo "To start missing services:"
    if [ "$QDRANT_OK" = false ]; then
        echo "  - Qdrant: ./scripts/setup-qdrant.sh"
    fi
    if [ "$OLLAMA_OK" = false ]; then
        echo "  - Ollama: ollama serve (in separate terminal)"
    fi
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Build dashboard
echo ""
echo -e "${YELLOW}Building dashboard...${NC}"
./scripts/build-dashboard.sh

# Serve dashboard
PORT=8080
echo ""
echo -e "${GREEN}Starting web server...${NC}"
echo -e "${GREEN}Dashboard URL: http://localhost:${PORT}${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
echo ""

cd dashboard-dist
python3 -m http.server $PORT
