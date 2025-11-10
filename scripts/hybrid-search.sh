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
COLLECTION="${RAG_COLLECTION:-documents}"
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
MODEL="${EMBEDDING_MODEL:-nomic-embed-text}"
VECTOR_WEIGHT="0.7"
KEYWORD_WEIGHT="0.3"
LIMIT="5"

show_usage() {
    echo "Usage: $0 <query> [options]"
    echo ""
    echo "Hybrid search combining vector similarity with keyword matching."
    echo ""
    echo "Options:"
    echo "  -l, --limit N           Number of results (default: 5)"
    echo "  -v, --vector-weight W   Vector search weight 0-1 (default: 0.7)"
    echo "  -k, --keyword-weight W  Keyword search weight 0-1 (default: 0.3)"
    echo "  -f, --filter KEY=VALUE  Filter by metadata (can be repeated)"
    echo "  -j, --json              Output as JSON"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RAG_COLLECTION          Collection to search (default: documents)"
    echo "  QDRANT_URL              Qdrant server URL (default: http://localhost:6333)"
    echo "  OLLAMA_URL              Ollama server URL (default: http://localhost:11434)"
    echo "  EMBEDDING_MODEL         Embedding model (default: nomic-embed-text)"
    echo ""
    echo "Examples:"
    echo "  $0 \"rust macros\""
    echo "  $0 \"async programming\" --limit 10"
    echo "  $0 \"macro example\" --filter is_code=true"
    echo "  $0 \"error handling\" -v 0.5 -k 0.5"
    echo ""
    echo "Filter Examples:"
    echo "  --filter is_code=true           # Only code blocks"
    echo "  --filter source=myfile.pdf      # From specific file"
    echo "  --filter chunk_type=Code        # Specific chunk type"
    exit 1
}

# Check if query provided
if [ $# -eq 0 ]; then
    show_usage
fi

QUERY="$1"
shift

# Build binary if needed
if [ ! -f "./target/release/hybrid-search" ]; then
    echo -e "${BLUE}Building hybrid-search binary...${NC}"
    cargo build --release --bin hybrid-search
fi

# Parse additional arguments
ARGS=()
FILTERS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--limit)
            LIMIT="$2"
            shift 2
            ;;
        -v|--vector-weight)
            VECTOR_WEIGHT="$2"
            shift 2
            ;;
        -k|--keyword-weight)
            KEYWORD_WEIGHT="$2"
            shift 2
            ;;
        -f|--filter)
            FILTERS+=("$2")
            shift 2
            ;;
        -j|--json)
            ARGS+=("--json")
            shift
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

# Build filter arguments
for filter in "${FILTERS[@]}"; do
    ARGS+=("--filter" "$filter")
done

# Run hybrid search
./target/release/hybrid-search \
    "$QUERY" \
    --collection "$COLLECTION" \
    --qdrant-url "$QDRANT_URL" \
    --ollama-url "$OLLAMA_URL" \
    --model "$MODEL" \
    --limit "$LIMIT" \
    --vector-weight "$VECTOR_WEIGHT" \
    --keyword-weight "$KEYWORD_WEIGHT" \
    "${ARGS[@]}"
