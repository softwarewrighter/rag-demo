#!/bin/bash
# Copyright (c) 2025 Michael A. Wright
# Licensed under the MIT License

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
OUTPUT_DIR="${EXPORT_DIR:-./exports}"

show_usage() {
    echo "Usage: $0 <collection-name> [options]"
    echo ""
    echo "Export a Qdrant collection to JSON format for backup or sharing."
    echo ""
    echo "Options:"
    echo "  -o, --output FILE       Output file path (default: exports/<collection>.json)"
    echo "  -v, --include-vectors   Include vectors in export (increases file size)"
    echo "  -p, --pretty            Pretty-print JSON output"
    echo "  -b, --batch-size SIZE   Batch size for fetching (default: 100)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  QDRANT_URL              Qdrant server URL (default: http://localhost:6333)"
    echo "  EXPORT_DIR              Directory for exports (default: ./exports)"
    echo ""
    echo "Examples:"
    echo "  $0 python-books"
    echo "  $0 python-books --include-vectors --pretty"
    echo "  $0 rust-books -o my-backup.json"
    exit 1
}

# Check if collection name provided
if [ $# -eq 0 ]; then
    show_usage
fi

COLLECTION="$1"
shift

# Build binary if needed
if [ ! -f "./target/release/export-collection" ]; then
    echo -e "${BLUE}Building export-collection binary...${NC}"
    cargo build --release --bin export-collection
fi

# Create export directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Default output file
OUTPUT_FILE="${OUTPUT_DIR}/${COLLECTION}.json"

# Parse additional arguments
ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -v|--include-vectors)
            ARGS+=("--include-vectors")
            shift
            ;;
        -p|--pretty)
            ARGS+=("--pretty")
            shift
            ;;
        -b|--batch-size)
            ARGS+=("--batch-size" "$2")
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            ;;
    esac
done

echo -e "${BLUE}🔄 Exporting collection: ${COLLECTION}${NC}"
echo ""

# Run export
./target/release/export-collection \
    "$COLLECTION" \
    --output "$OUTPUT_FILE" \
    --qdrant-url "$QDRANT_URL" \
    "${ARGS[@]}"

echo ""
echo -e "${GREEN}✅ Export saved to: ${OUTPUT_FILE}${NC}"
