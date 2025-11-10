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

show_usage() {
    echo "Usage: $0 <export-file.json> [options]"
    echo ""
    echo "Import a Qdrant collection from JSON export file."
    echo ""
    echo "Options:"
    echo "  -c, --collection NAME   Target collection name (default: use name from export)"
    echo "  -f, --force             Force import, merge with existing collection"
    echo "  -s, --skip-create       Skip collection creation (assume exists)"
    echo "  -b, --batch-size SIZE   Batch size for uploading (default: 100)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  QDRANT_URL              Qdrant server URL (default: http://localhost:6333)"
    echo ""
    echo "Examples:"
    echo "  $0 exports/python-books.json"
    echo "  $0 backup.json --collection my-collection"
    echo "  $0 data.json --force"
    exit 1
}

# Check if file provided
if [ $# -eq 0 ]; then
    show_usage
fi

EXPORT_FILE="$1"
shift

# Check if file exists
if [ ! -f "$EXPORT_FILE" ]; then
    echo -e "${RED}❌ Error: File not found: ${EXPORT_FILE}${NC}"
    exit 1
fi

# Build binary if needed
if [ ! -f "./target/release/import-collection" ]; then
    echo -e "${BLUE}Building import-collection binary...${NC}"
    cargo build --release --bin import-collection
fi

# Parse additional arguments
ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--collection)
            ARGS+=("--collection" "$2")
            shift 2
            ;;
        -f|--force)
            ARGS+=("--force")
            shift
            ;;
        -s|--skip-create)
            ARGS+=("--skip-create")
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

echo -e "${BLUE}🔄 Importing from: ${EXPORT_FILE}${NC}"
echo ""

# Run import
./target/release/import-collection \
    "$EXPORT_FILE" \
    --qdrant-url "$QDRANT_URL" \
    "${ARGS[@]}"

echo ""
echo -e "${GREEN}✅ Import complete!${NC}"
