#!/bin/bash

# Interactive RAG Chat with Statistics
# Uses Qdrant for vector search and Ollama for LLM generation

set -e

# Configuration
LLM_MODEL="${1:-llama3.2}"
SEARCH_LIMIT=5
MAX_CONTEXT_LENGTH=4000

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Statistics
TOTAL_QUERIES=0
TOTAL_SEARCH_TIME=0
TOTAL_LLM_TIME=0

# Check prerequisites
check_requirements() {
    local missing=0
    
    if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo -e "${RED}❌ Ollama is not running${NC}"
        echo "   Please start it with: ollama serve"
        missing=1
    fi
    
    if ! curl -s http://localhost:6333/collections > /dev/null 2>&1; then
        echo -e "${RED}❌ Qdrant is not running${NC}"
        echo "   Please run: ./scripts/setup-qdrant.sh"
        missing=1
    fi
    
    if [ ! -f "target/release/search-qdrant" ]; then
        echo -e "${YELLOW}🔨 Building search tool...${NC}"
        cargo build --release --bin search-qdrant
    fi
    
    if ! ollama list | grep -q "$LLM_MODEL" 2>/dev/null; then
        echo -e "${YELLOW}📦 Model $LLM_MODEL not found. Available models:${NC}"
        ollama list | tail -n +2 | awk '{print "   - " $1}'
        echo -e "${YELLOW}Pulling $LLM_MODEL...${NC}"
        ollama pull "$LLM_MODEL"
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
}

# Function to show statistics
show_stats() {
    echo ""
    echo -e "${CYAN}📊 Session Statistics:${NC}"
    echo "────────────────────────────────"
    
    # Get Qdrant stats
    local collection_info=$(curl -s http://localhost:6333/collections/documents)
    local vectors_count=$(echo "$collection_info" | jq -r '.result.points_count // 0')
    local vectors_indexed=$(echo "$collection_info" | jq -r '.result.indexed_vectors_count // 0')
    
    echo -e "📚 Qdrant Database:"
    echo -e "   Vectors stored: ${GREEN}$vectors_count${NC}"
    echo -e "   Vectors indexed: ${GREEN}$vectors_indexed${NC}"
    
    if [ $TOTAL_QUERIES -gt 0 ]; then
        local avg_search_time=$(echo "scale=2; $TOTAL_SEARCH_TIME / $TOTAL_QUERIES" | bc 2>/dev/null || echo "0")
        local avg_llm_time=$(echo "scale=2; $TOTAL_LLM_TIME / $TOTAL_QUERIES" | bc 2>/dev/null || echo "0")
        
        echo ""
        echo -e "⚡ Performance:"
        echo -e "   Total queries: ${GREEN}$TOTAL_QUERIES${NC}"
        echo -e "   Avg search time: ${GREEN}${avg_search_time}s${NC}"
        echo -e "   Avg LLM time: ${GREEN}${avg_llm_time}s${NC}"
    fi
    
    echo "────────────────────────────────"
}

# Function to perform RAG query
rag_query() {
    local query="$1"
    local start_time=$(date +%s.%N)
    
    # Search for relevant context
    echo -e "${BLUE}🔍 Searching knowledge base...${NC}"
    local search_start=$(date +%s.%N)
    
    local search_results=$(./target/release/search-qdrant "$query" --limit $SEARCH_LIMIT --json 2>/dev/null)
    
    local search_end=$(date +%s.%N)
    local search_time=$(echo "$search_end - $search_start" | bc)
    TOTAL_SEARCH_TIME=$(echo "$TOTAL_SEARCH_TIME + $search_time" | bc)
    
    # Extract context from results
    local context=$(echo "$search_results" | jq -r '.results[].text' 2>/dev/null | head -c $MAX_CONTEXT_LENGTH)
    
    # Show search results summary
    local num_results=$(echo "$search_results" | jq '.results | length' 2>/dev/null || echo "0")
    if [ "$num_results" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $num_results relevant chunks${NC} (${search_time}s)"
        
        # Show top result score
        local top_score=$(echo "$search_results" | jq -r '.results[0].score' 2>/dev/null)
        echo -e "${CYAN}  Best match score: $top_score${NC}"
    else
        echo -e "${YELLOW}⚠️  No relevant context found${NC}"
    fi
    
    # Generate response
    echo -e "${BLUE}💭 Generating answer...${NC}"
    local llm_start=$(date +%s.%N)
    
    local prompt
    if [ -n "$context" ]; then
        prompt="Based on the following context from the knowledge base, please answer the question accurately and concisely.

Context:
$context

Question: $query

Answer based on the context provided. If the context doesn't contain enough information, say so."
    else
        prompt="Please answer this question: $query"
    fi
    
    # Call Ollama
    local response=$(curl -s -X POST http://localhost:11434/api/generate \
        -d "$(jq -n \
            --arg model "$LLM_MODEL" \
            --arg prompt "$prompt" \
            '{model: $model, prompt: $prompt, stream: false}')" \
        | jq -r '.response // "Error: Could not generate response"')
    
    local llm_end=$(date +%s.%N)
    local llm_time=$(echo "$llm_end - $llm_start" | bc)
    TOTAL_LLM_TIME=$(echo "$TOTAL_LLM_TIME + $llm_time" | bc)
    
    echo -e "${GREEN}✓ Answer generated${NC} (${llm_time}s)"
    echo ""
    echo -e "${GREEN}🤖 Answer:${NC}"
    echo "────────────────────────────────────────"
    echo "$response"
    echo "────────────────────────────────────────"
    
    TOTAL_QUERIES=$((TOTAL_QUERIES + 1))
}

# Main interactive loop
main() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     RAG Interactive Chat System        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo -e "${CYAN}Using model: $LLM_MODEL${NC}"
    echo ""
    
    check_requirements
    
    # Show initial stats
    local vectors=$(curl -s http://localhost:6333/collections/documents | jq -r '.result.points_count // 0')
    echo -e "${GREEN}✅ System ready! ($vectors vectors in database)${NC}"
    echo ""
    echo -e "${YELLOW}Commands:${NC}"
    echo "  • Type your question and press Enter"
    echo "  • 'stats' - Show performance statistics"
    echo "  • 'clear' - Clear the screen"
    echo "  • 'quit' or 'exit' - Exit the program"
    echo ""
    echo "────────────────────────────────────────"
    
    while true; do
        echo ""
        echo -ne "${CYAN}You:${NC} "
        read -r user_input
        
        # Handle commands
        case "$user_input" in
            quit|exit|q)
                show_stats
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            stats|s)
                show_stats
                continue
                ;;
            clear|c)
                clear
                echo -e "${GREEN}RAG Interactive Chat${NC} (Model: $LLM_MODEL)"
                echo "────────────────────────────────────────"
                continue
                ;;
            "")
                continue
                ;;
            *)
                echo ""
                rag_query "$user_input"
                ;;
        esac
    done
}

# Handle Ctrl+C gracefully
trap 'echo ""; show_stats; echo -e "${GREEN}Goodbye!${NC}"; exit 0' INT

# Run main function
main