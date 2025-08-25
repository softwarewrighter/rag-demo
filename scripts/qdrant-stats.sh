#!/bin/bash

# Qdrant Database Statistics and Information

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Qdrant Database Statistics       ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if Qdrant is running
if ! curl -s http://localhost:6333/collections > /dev/null 2>&1; then
    echo -e "${RED}❌ Qdrant is not running${NC}"
    echo "   Please run: ./scripts/setup-qdrant.sh"
    exit 1
fi

# Web UI
echo -e "${GREEN}🌐 Web UI:${NC} http://localhost:6333/dashboard"
echo ""

# Get collection info
echo -e "${BLUE}📊 Collection Statistics:${NC}"
echo "────────────────────────────────────────"

collections=$(curl -s http://localhost:6333/collections | jq -r '.result.collections[].name')

if [ -z "$collections" ]; then
    echo "No collections found"
else
    for collection in $collections; do
        echo -e "${YELLOW}Collection: $collection${NC}"
        
        # Get detailed info
        info=$(curl -s http://localhost:6333/collections/$collection)
        
        # Extract stats
        points=$(echo "$info" | jq -r '.result.points_count')
        indexed=$(echo "$info" | jq -r '.result.indexed_vectors_count')
        segments=$(echo "$info" | jq -r '.result.segments_count')
        vector_size=$(echo "$info" | jq -r '.result.config.params.vectors.size')
        distance=$(echo "$info" | jq -r '.result.config.params.vectors.distance')
        status=$(echo "$info" | jq -r '.result.status')
        
        echo "  Status: $status"
        echo "  Vectors stored: $points"
        echo "  Vectors indexed: $indexed"
        echo "  Segments: $segments"
        echo "  Vector dimensions: $vector_size"
        echo "  Distance metric: $distance"
        
        # Calculate approximate memory usage
        # Each vector is vector_size * 4 bytes (float32) + metadata
        if [ "$points" -gt 0 ]; then
            vector_memory=$((points * vector_size * 4))
            vector_memory_mb=$((vector_memory / 1024 / 1024))
            echo "  Approx. vector memory: ${vector_memory_mb} MB"
        fi
        
        # Sample some data to show what's stored
        echo ""
        echo -e "${CYAN}  Sample stored data:${NC}"
        
        # Get a random point to show metadata
        sample=$(curl -s -X POST "http://localhost:6333/collections/$collection/points/scroll" \
            -H "Content-Type: application/json" \
            -d '{"limit": 1, "with_payload": true, "with_vector": false}' 2>/dev/null)
        
        if [ "$?" -eq 0 ]; then
            source=$(echo "$sample" | jq -r '.result.points[0].payload.source' 2>/dev/null)
            chunk_count=$(echo "$sample" | jq -r '.result.points[0].payload.total_chunks' 2>/dev/null)
            text_sample=$(echo "$sample" | jq -r '.result.points[0].payload.text' 2>/dev/null | head -c 100)
            
            if [ ! -z "$source" ] && [ "$source" != "null" ]; then
                echo "    Source file: $source"
                echo "    Total chunks: $chunk_count"
                echo "    Text sample: ${text_sample}..."
            fi
        fi
        
        echo ""
    done
fi

# Show search performance test
echo -e "${BLUE}⚡ Performance Test:${NC}"
echo "────────────────────────────────────────"

# Do a test search
if [ ! -z "$collections" ]; then
    test_query="example macro"
    echo "Testing search for: \"$test_query\""
    
    start_time=$(date +%s%N)
    
    # Use our search tool if available
    if [ -f "target/release/search-qdrant" ]; then
        results=$(./target/release/search-qdrant "$test_query" --limit 1 --json 2>/dev/null)
        end_time=$(date +%s%N)
        
        elapsed=$((($end_time - $start_time) / 1000000))
        
        if [ ! -z "$results" ]; then
            score=$(echo "$results" | jq -r '.results[0].score' 2>/dev/null)
            echo -e "${GREEN}✓ Search completed in ${elapsed}ms${NC}"
            echo "  Best match score: $score"
        fi
    else
        # Direct API call
        embedding=$(curl -s -X POST http://localhost:11434/api/embeddings \
            -d "{\"model\": \"nomic-embed-text\", \"prompt\": \"$test_query\"}" \
            | jq -r '.embedding' 2>/dev/null)
        
        if [ ! -z "$embedding" ]; then
            search_result=$(curl -s -X POST "http://localhost:6333/collections/documents/points/search" \
                -H "Content-Type: application/json" \
                -d "{\"vector\": $embedding, \"limit\": 1}" 2>/dev/null)
            
            end_time=$(date +%s%N)
            elapsed=$((($end_time - $start_time) / 1000000))
            
            score=$(echo "$search_result" | jq -r '.result[0].score' 2>/dev/null)
            echo -e "${GREEN}✓ Search completed in ${elapsed}ms${NC}"
            echo "  Best match score: $score"
        fi
    fi
fi

echo ""
echo -e "${CYAN}💡 Tips:${NC}"
echo "  • Visit http://localhost:6333/dashboard for the web UI"
echo "  • Use ./scripts/interactive-rag.sh for testing queries"
echo "  • Ingest more PDFs with ./scripts/ingest-pdf.sh <file>"