#!/bin/bash
# Build script for RAG Demo Static GitHub Pages Demo
# Creates a limited demo with mocked data for GitHub Pages deployment

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building RAG Demo Static Demo for GitHub Pages...${NC}"

# Ensure we're in the project root
cd "$(dirname "$0")/.."

# Clean and create output directory
OUTPUT_DIR="docs"
echo -e "${YELLOW}Cleaning output directory: ./$OUTPUT_DIR${NC}"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy dashboard files
echo -e "${YELLOW}Copying dashboard files...${NC}"
cp dashboard/index.html "$OUTPUT_DIR/"
cp dashboard/style.css "$OUTPUT_DIR/"

# Copy favicon if it exists
if [ -f dashboard/favicon.ico ]; then
    cp dashboard/favicon.ico "$OUTPUT_DIR/"
    echo "  ✓ Copied favicon.ico"
fi

# Use the demo version of the JavaScript (with mocked data)
echo -e "${YELLOW}Using demo version with mocked data...${NC}"
cp dashboard/app-demo.js "$OUTPUT_DIR/app.js"

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

# Create a README for the docs directory
cat > "$OUTPUT_DIR/README.md" << 'EOF'
# RAG Demo - Live Demo

This is a **limited static demo** of the RAG Demo Dashboard hosted on GitHub Pages.

⚠️ **Important:** This demo uses mocked data and does not have a real backend. It's intended to show the UI and basic interaction flow.

## To Use the Full Version

For the complete interactive experience with real document ingestion and search:

1. Clone the repository: `git clone https://github.com/softwarewrighter/rag-demo.git`
2. Follow the setup instructions in the main README
3. Run Qdrant and Ollama locally
4. Ingest your own documents
5. Build and serve the dashboard: `./scripts/build-dashboard.sh`

## What's Different in the Live Demo

- ✅ Shows the dashboard UI
- ✅ Demonstrates search interface
- ✅ Displays sample results
- ❌ Cannot connect to real Qdrant/Ollama backend
- ❌ Cannot ingest real documents
- ❌ Shows only pre-generated mocked data

Visit the [main repository](https://github.com/softwarewrighter/rag-demo) for the full version.
EOF

# Ensure .nojekyll exists
touch "$OUTPUT_DIR/.nojekyll"

echo -e "${GREEN}Static demo built successfully!${NC}"
echo -e "${GREEN}Output directory: ./$OUTPUT_DIR${NC}"
echo ""
echo -e "${BLUE}This demo is ready for GitHub Pages deployment.${NC}"
echo ""
echo -e "${YELLOW}To enable GitHub Pages:${NC}"
echo "  1. Push these changes to GitHub"
echo "  2. Go to repository Settings > Pages"
echo "  3. Set Source to 'Deploy from a branch'"
echo "  4. Select branch 'main' and folder '/docs'"
echo "  5. Save and wait for deployment"
echo ""
echo -e "${RED}Remember: This is a LIMITED DEMO with mocked data.${NC}"
echo -e "${RED}Users must clone and run locally for the full experience.${NC}"
