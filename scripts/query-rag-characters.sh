#!/bin/bash

# RAG with character-aware query expansion
# Ask LLM to suggest character names that might be relevant, then search with those

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <query> [llm-model]"
    exit 1
fi

QUERY="$1"
LLM_MODEL="${2:-mistral:7b}"
COLLECTION="${RAG_COLLECTION:-documents}"

echo "=============================================="
echo "Character-Aware RAG Query"
echo "=============================================="
echo "Question: $QUERY"
echo ""

# Step 1: Ask LLM to identify relevant character names
echo "Step 1: Identifying relevant characters..."

CHAR_PROMPT="For this question about a novel, suggest 3-5 specific CHARACTER NAMES that might appear in passages containing the answer. Just list the names, one per line.

Question: $QUERY

Character names:"

ESCAPED=$(echo "$CHAR_PROMPT" | jq -Rs .)
CHARACTERS=$(curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$LLM_MODEL" --argjson prompt "$ESCAPED" \
        '{model: $model, prompt: $prompt, stream: false}')" \
    | jq -r '.response' | grep -E "^[0-9]*\.?\s*[A-Z]" | sed 's/^[0-9]*\.\s*//' | head -5)

echo "   Suggested characters:"
echo "$CHARACTERS" | sed 's/^/      /'
echo ""

# Step 2: Search with each character name + key terms from question
echo "Step 2: Searching with character names..."

# Extract key terms from question
KEY_TERMS=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]' | grep -oE '\b[a-z]{4,}\b' | grep -v "what\|which\|where\|when\|does\|with\|almost\|about" | head -3 | tr '\n' ' ')

COMBINED_CONTEXT=""
SEEN=""

while IFS= read -r char; do
    [ -z "$char" ] && continue

    # Clean character name
    char_clean=$(echo "$char" | sed 's/[^A-Za-z ]//g' | xargs)
    [ -z "$char_clean" ] && continue

    SEARCH_QUERY="$char_clean $KEY_TERMS"
    echo "   Searching: $SEARCH_QUERY"

    RESULTS=$(./target/release/hybrid-search "$SEARCH_QUERY" \
        --collection "$COLLECTION" \
        --limit 3 \
        --json 2>/dev/null || echo '[]')

    # Add unique chunks
    while IFS= read -r chunk_text; do
        [ -z "$chunk_text" ] && continue
        sig=$(echo "$chunk_text" | head -c 80 | md5sum | cut -d' ' -f1)
        if ! echo "$SEEN" | grep -q "$sig"; then
            SEEN="$SEEN $sig"
            COMBINED_CONTEXT="${COMBINED_CONTEXT}

---
${chunk_text}"
        fi
    done < <(echo "$RESULTS" | jq -r '.[].payload.text // empty' 2>/dev/null)

done <<< "$CHARACTERS"

# Limit context
CONTEXT=$(echo "$COMBINED_CONTEXT" | head -c 16000)
CONTEXT_SIZE=${#CONTEXT}

echo ""
echo "Total context: $CONTEXT_SIZE characters"
echo ""

# Step 3: Answer
echo "=============================================="
echo "Answer:"
echo "=============================================="

FINAL_PROMPT="Based on these passages from the novel, answer the question.

$CONTEXT

Question: $QUERY

Provide a specific answer based on the text:"

ESCAPED=$(echo "$FINAL_PROMPT" | jq -Rs .)
curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$LLM_MODEL" --argjson prompt "$ESCAPED" \
        '{model: $model, prompt: $prompt, stream: false}')" \
    | jq -r '.response'

echo ""
echo "=============================================="
