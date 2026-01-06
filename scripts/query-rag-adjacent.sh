#!/bin/bash

# RAG with adjacent chunk expansion
# When we find chunk C, also retrieve chunks B and D (by line number proximity)

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <query> [llm-model]"
    exit 1
fi

QUERY="$1"
LLM_MODEL="${2:-mistral:7b}"
COLLECTION="${RAG_COLLECTION:-documents}"
QDRANT_URL="http://localhost:6333"

echo "=============================================="
echo "RAG with Adjacent Chunk Expansion"
echo "=============================================="
echo "Collection: $COLLECTION"
echo "Question:   $QUERY"
echo ""

# Step 1: Find initial matching chunks
echo "Step 1: Finding matching chunks..."
INITIAL_RESULTS=$(./target/release/hybrid-search "$QUERY" \
    --collection "$COLLECTION" \
    --limit 5 \
    --json 2>/dev/null)

# Extract line ranges from initial results
LINE_RANGES=$(echo "$INITIAL_RESULTS" | jq -r '.[] | "\(.payload.start_line)-\(.payload.end_line)"' 2>/dev/null)

echo "   Found chunks at lines:"
echo "$LINE_RANGES" | sed 's/^/      /'

# Step 2: For each match, find adjacent chunks by line number
echo ""
echo "Step 2: Expanding to adjacent chunks..."

EXPANDED_CONTEXT=""
SEEN_RANGES=""

for range in $LINE_RANGES; do
    start=$(echo "$range" | cut -d'-' -f1)
    end=$(echo "$range" | cut -d'-' -f2)

    # Skip if we've seen overlapping range
    if echo "$SEEN_RANGES" | grep -q "$start"; then
        continue
    fi
    SEEN_RANGES="$SEEN_RANGES $start"

    # Calculate adjacent range (±50 lines for context)
    adj_start=$((start - 50))
    adj_end=$((end + 50))
    [ "$adj_start" -lt 0 ] && adj_start=0

    echo "   Chunk $start-$end → expanding to $adj_start-$adj_end"

    # Search for chunks that overlap with our expanded range
    # Using Qdrant filter for line number range
    ADJACENT=$(curl -s -X POST "$QDRANT_URL/collections/$COLLECTION/points/scroll" \
        -H "Content-Type: application/json" \
        -d "{
            \"limit\": 10,
            \"with_payload\": true,
            \"filter\": {
                \"must\": [
                    {\"key\": \"start_line\", \"range\": {\"gte\": $adj_start, \"lte\": $adj_end}}
                ]
            }
        }" 2>/dev/null | jq -r '.result.points[].payload.text // empty')

    if [ -n "$ADJACENT" ]; then
        EXPANDED_CONTEXT="${EXPANDED_CONTEXT}

=== CONTEXT BLOCK (lines $adj_start-$adj_end) ===
${ADJACENT}"
    fi
done

# Also include original matches
ORIGINAL_TEXT=$(echo "$INITIAL_RESULTS" | jq -r '.[].payload.text // empty' 2>/dev/null)
EXPANDED_CONTEXT="${EXPANDED_CONTEXT}

=== ORIGINAL MATCHES ===
${ORIGINAL_TEXT}"

# Limit context size
CONTEXT=$(echo "$EXPANDED_CONTEXT" | head -c 20000)
CONTEXT_SIZE=${#CONTEXT}

echo ""
echo "Total context: $CONTEXT_SIZE characters"
echo ""

# Step 3: Answer with expanded context
echo "=============================================="
echo "Answer:"
echo "=============================================="

PROMPT="Based on the following passages from the text, answer the question.

$CONTEXT

Question: $QUERY

Provide a clear answer based on the passages."

ESCAPED=$(echo "$PROMPT" | jq -Rs .)
curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$LLM_MODEL" --argjson prompt "$ESCAPED" \
        '{model: $model, prompt: $prompt, stream: false}')" \
    | jq -r '.response'

echo ""
echo "=============================================="
