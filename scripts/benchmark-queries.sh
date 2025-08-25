#!/bin/bash

# Benchmark query performance
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      RAG Query Performance Test       ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# Test queries
QUERIES=(
    "What is a macro_rules example?"
    "How do I implement a derive macro?"
    "What are the different types of Rust macros?"
    "Show me async web server code"
    "How does ownership work in Rust?"
    "What is the difference between String and str?"
    "How to handle errors in Rust?"
    "Explain lifetimes with examples"
    "What are traits and how to use them?"
    "How to write tests in Rust?"
)

# Get collection stats
VECTOR_COUNT=$(curl -s http://localhost:6333/collections/documents | jq -r '.result.points_count // 0')
INDEXED_COUNT=$(curl -s http://localhost:6333/collections/documents | jq -r '.result.indexed_vectors_count // 0')
SEGMENTS=$(curl -s http://localhost:6333/collections/documents | jq -r '.result.segments_count // 0')

echo -e "${BLUE}📊 Database Status:${NC}"
echo "   Vectors: $VECTOR_COUNT"
echo "   Indexed: $INDEXED_COUNT"
echo "   Segments: $SEGMENTS"
echo ""

# Function to measure query time
measure_query() {
    local query="$1"
    local start=$(date +%s%N)
    
    # Run search
    ./target/release/search-hierarchical "$query" --limit 5 --json > /dev/null 2>&1
    
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 )) # Convert to milliseconds
    echo $duration
}

echo -e "${YELLOW}Running benchmark queries...${NC}"
echo ""

TOTAL_TIME=0
MIN_TIME=999999
MAX_TIME=0
TIMES=()

for i in "${!QUERIES[@]}"; do
    query="${QUERIES[$i]}"
    echo -n "Query $((i+1))/10: "
    
    # Run query 3 times and take average
    sum=0
    for run in 1 2 3; do
        time=$(measure_query "$query")
        sum=$((sum + time))
    done
    avg=$((sum / 3))
    
    TIMES+=($avg)
    TOTAL_TIME=$((TOTAL_TIME + avg))
    
    if [ $avg -lt $MIN_TIME ]; then
        MIN_TIME=$avg
    fi
    if [ $avg -gt $MAX_TIME ]; then
        MAX_TIME=$avg
    fi
    
    # Display with color coding
    if [ $avg -lt 100 ]; then
        echo -e "${GREEN}${avg}ms${NC} - \"${query:0:40}...\""
    elif [ $avg -lt 200 ]; then
        echo -e "${YELLOW}${avg}ms${NC} - \"${query:0:40}...\""
    else
        echo -e "${RED}${avg}ms${NC} - \"${query:0:40}...\""
    fi
done

AVG_TIME=$((TOTAL_TIME / ${#QUERIES[@]}))

echo ""
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}Performance Summary:${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""
echo "📈 Query Performance:"
echo "   • Average: ${AVG_TIME}ms"
echo "   • Minimum: ${MIN_TIME}ms"
echo "   • Maximum: ${MAX_TIME}ms"
echo ""

# Calculate percentiles
IFS=$'\n' SORTED=($(sort -n <<<"${TIMES[*]}"))
P50=${SORTED[4]}
P90=${SORTED[8]}
P99=${SORTED[9]}

echo "📊 Percentiles:"
echo "   • P50 (median): ${P50}ms"
echo "   • P90: ${P90}ms"
echo "   • P99: ${P99}ms"
echo ""

# Performance rating
if [ $AVG_TIME -lt 100 ]; then
    echo -e "${GREEN}⚡ Performance: EXCELLENT${NC}"
    echo "   Sub-100ms average response time!"
elif [ $AVG_TIME -lt 200 ]; then
    echo -e "${YELLOW}✓ Performance: GOOD${NC}"
    echo "   Acceptable response times for interactive use"
else
    echo -e "${RED}⚠ Performance: NEEDS OPTIMIZATION${NC}"
    echo "   Consider enabling indexing or optimizing chunk sizes"
fi

echo ""

# Check if indexing would help
if [ "$INDEXED_COUNT" -eq 0 ] && [ "$VECTOR_COUNT" -gt 1000 ]; then
    echo -e "${YELLOW}💡 Optimization Tip:${NC}"
    echo "   No vectors are indexed. With $VECTOR_COUNT vectors,"
    echo "   building an HNSW index could improve performance."
    echo "   The index will auto-build at 10,000 vectors."
fi