#!/bin/bash
# Build script for RAG Demo Dashboard
# Injects build information (host, SHA, timestamp) into the dashboard

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building RAG Demo Dashboard...${NC}"

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Create output directory
OUTPUT_DIR="dashboard-dist"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy dashboard files
echo -e "${YELLOW}Copying dashboard files...${NC}"
cp dashboard/index.html "$OUTPUT_DIR/"
cp dashboard/style.css "$OUTPUT_DIR/"
cp dashboard/app.js "$OUTPUT_DIR/"

# Copy favicon if it exists
if [ -f dashboard/favicon.ico ]; then
    cp dashboard/favicon.ico "$OUTPUT_DIR/"
    echo "  ✓ Copied favicon.ico"
fi

# Generate build information
BUILD_HOST=$(hostname)
BUILD_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo -e "${YELLOW}Injecting build information...${NC}"
echo "  Host: $BUILD_HOST"
echo "  SHA:  $BUILD_SHA"
echo "  Time: $BUILD_TIME"

# Inject build info into HTML
sed -i.bak "s/__BUILD_HOST__/$BUILD_HOST/g" "$OUTPUT_DIR/index.html"
sed -i.bak "s/__BUILD_SHA__/$BUILD_SHA/g" "$OUTPUT_DIR/index.html"
sed -i.bak "s/__BUILD_TIME__/$BUILD_TIME/g" "$OUTPUT_DIR/index.html"
rm "$OUTPUT_DIR/index.html.bak"

echo -e "${GREEN}Dashboard built successfully!${NC}"
echo -e "${GREEN}Output directory: ./$OUTPUT_DIR${NC}"
echo ""
echo -e "${BLUE}To serve the dashboard locally:${NC}"
echo "  cd $OUTPUT_DIR && python3 -m http.server 8080"
echo "  Then open: http://localhost:8080"
echo ""
echo -e "${YELLOW}Note: The dashboard requires Qdrant and Ollama to be running:${NC}"
echo "  - Qdrant: http://localhost:6333"
echo "  - Ollama: http://localhost:11434"
