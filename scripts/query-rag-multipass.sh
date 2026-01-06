#!/bin/bash

# Multi-pass RAG with expanded context
# Strategies:
# 1. Large initial retrieval (20+ chunks)
# 2. Multiple query variations
# 3. Parent chunk expansion
# 4. Pagination for very large context

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <query> [llm-model] [strategy]"
    echo ""
    echo "Strategies:"
    echo "  large    - Single search with 20 chunks (default)"
    echo "  multi    - Multiple query variations combined"
    echo "  paginate - Search in batches, summarize each"
    echo "  parent   - Include parent chunks for context"
    echo ""
    echo "Example: $0 'What is Prince Andrei\\'s estate?' mistral:7b multi"
    exit 1
fi

QUERY="$1"
LLM_MODEL="${2:-mistral:7b}"
STRATEGY="${3:-large}"
COLLECTION="${RAG_COLLECTION:-documents}"

# Context size limits (characters)
MAX_CONTEXT=16000  # ~4K tokens, safe for most models
BATCH_SIZE=8000    # For pagination

echo "=============================================="
echo "Multi-Pass RAG Query"
echo "=============================================="
echo "Collection: $COLLECTION"
echo "Question:   $QUERY"
echo "Strategy:   $STRATEGY"
echo "Model:      $LLM_MODEL"
echo "Max context: $MAX_CONTEXT chars"
echo ""

# Function to search and extract text
search_chunks() {
    local query="$1"
    local limit="$2"

    ./target/release/hybrid-search "$query" \
        --collection "$COLLECTION" \
        --limit "$limit" \
        --json 2>/dev/null | jq -r '.[].payload.text // empty'
}

# Function to get unique chunks from multiple searches
combine_searches() {
    local -a queries=("$@")
    local seen_file=$(mktemp)
    local output=""

    for q in "${queries[@]}"; do
        while IFS= read -r chunk; do
            # Simple dedup by first 100 chars
            local sig=$(echo "$chunk" | head -c 100 | md5sum | cut -d' ' -f1)
            if ! grep -q "$sig" "$seen_file" 2>/dev/null; then
                echo "$sig" >> "$seen_file"
                output="${output}

---
${chunk}"
            fi
        done < <(search_chunks "$q" 10)
    done

    rm -f "$seen_file"
    echo "$output"
}

# Function to call LLM
call_llm() {
    local prompt="$1"
    local escaped=$(echo "$prompt" | jq -Rs .)

    curl -s -X POST http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$LLM_MODEL" --argjson prompt "$escaped" \
            '{model: $model, prompt: $prompt, stream: false}')" \
        | jq -r '.response'
}

case "$STRATEGY" in
    large)
        echo "Strategy: Large retrieval (20 chunks)"
        echo "----------------------------------------------"

        # Get 20 chunks instead of 5
        CONTEXT=$(search_chunks "$QUERY" 20 | head -c "$MAX_CONTEXT")
        CONTEXT_SIZE=${#CONTEXT}

        echo "Retrieved $CONTEXT_SIZE characters of context"
        echo ""
        ;;

    multi)
        echo "Strategy: Multiple query variations"
        echo "----------------------------------------------"

        # Generate query variations by extracting key terms
        # Extract potential search phrases
        QUERIES=(
            "$QUERY"
            "$(echo "$QUERY" | sed 's/What is //;s/Who is //;s/\?//')"
            "$(echo "$QUERY" | grep -oE "[A-Z][a-z]+" | head -3 | tr '\n' ' ')"
        )

        echo "Searching with variations:"
        for q in "${QUERIES[@]}"; do
            [ -n "$q" ] && echo "  - $q"
        done
        echo ""

        CONTEXT=$(combine_searches "${QUERIES[@]}" | head -c "$MAX_CONTEXT")
        CONTEXT_SIZE=${#CONTEXT}

        echo "Retrieved $CONTEXT_SIZE characters of context"
        echo ""
        ;;

    paginate)
        echo "Strategy: Pagination with batch summarization"
        echo "----------------------------------------------"

        # Get chunks in batches, summarize each
        BATCH1=$(search_chunks "$QUERY" 10 | head -c "$BATCH_SIZE")
        BATCH2=$(./target/release/hybrid-search "$QUERY" \
            --collection "$COLLECTION" \
            --limit 20 \
            --json 2>/dev/null | jq -r '.[10:20][].payload.text // empty' | head -c "$BATCH_SIZE")

        echo "Batch 1: ${#BATCH1} chars"
        echo "Batch 2: ${#BATCH2} chars"

        # Summarize each batch for relevant info
        if [ -n "$BATCH1" ]; then
            echo ""
            echo "Analyzing batch 1..."
            SUMMARY1=$(call_llm "Extract any facts relevant to this question from the text below. Be concise.

Question: $QUERY

Text:
$BATCH1

Relevant facts (if any):")
        fi

        if [ -n "$BATCH2" ]; then
            echo "Analyzing batch 2..."
            SUMMARY2=$(call_llm "Extract any facts relevant to this question from the text below. Be concise.

Question: $QUERY

Text:
$BATCH2

Relevant facts (if any):")
        fi

        # Combine summaries as context
        CONTEXT="Extracted information from search results:

Batch 1 findings:
$SUMMARY1

Batch 2 findings:
$SUMMARY2"
        CONTEXT_SIZE=${#CONTEXT}

        echo ""
        echo "Combined summary: $CONTEXT_SIZE characters"
        echo ""
        ;;

    parent)
        echo "Strategy: Parent chunk expansion"
        echo "----------------------------------------------"

        # Get child chunks, then fetch their parents for full context
        RESULTS=$(./target/release/hybrid-search "$QUERY" \
            --collection "$COLLECTION" \
            --limit 10 \
            --json 2>/dev/null)

        # Extract unique parent IDs
        PARENT_IDS=$(echo "$RESULTS" | jq -r '.[].payload.parent_id // empty' | sort -u | head -5)

        # Get child text
        CHILD_TEXT=$(echo "$RESULTS" | jq -r '.[].payload.text // empty' | head -c 8000)

        # Search for parent chunks
        PARENT_TEXT=""
        for pid in $PARENT_IDS; do
            [ -z "$pid" ] && continue
            # Search with parent ID as filter would be ideal, but we can search by content
            PARENT_CHUNK=$(curl -s -X POST "http://localhost:6333/collections/$COLLECTION/points/$pid" \
                2>/dev/null | jq -r '.result.payload.text // empty')
            if [ -n "$PARENT_CHUNK" ]; then
                PARENT_TEXT="${PARENT_TEXT}

=== BROADER CONTEXT ===
${PARENT_CHUNK}"
            fi
        done

        CONTEXT="=== PRECISE MATCHES ===
${CHILD_TEXT}
${PARENT_TEXT}"
        CONTEXT=$(echo "$CONTEXT" | head -c "$MAX_CONTEXT")
        CONTEXT_SIZE=${#CONTEXT}

        echo "Child chunks: ${#CHILD_TEXT} chars"
        echo "Parent chunks: ${#PARENT_TEXT} chars"
        echo "Total context: $CONTEXT_SIZE chars"
        echo ""
        ;;

    *)
        echo "Unknown strategy: $STRATEGY"
        exit 1
        ;;
esac

# Final answer
if [ -z "$CONTEXT" ] || [ "$CONTEXT_SIZE" -lt 100 ]; then
    echo "Warning: Very little context retrieved"
    FINAL_PROMPT="Please answer this question: $QUERY"
else
    FINAL_PROMPT="Based on the following passages, please answer the question.

=== PASSAGES ===
$CONTEXT

=== QUESTION ===
$QUERY

Provide a clear, specific answer based on the passages. Quote relevant text if helpful."
fi

echo "=============================================="
echo "Answer:"
echo "=============================================="
call_llm "$FINAL_PROMPT"
echo ""
echo "=============================================="
