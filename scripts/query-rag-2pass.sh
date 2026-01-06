#!/bin/bash

# Two-pass RAG: LLM-guided query reformulation
# 1. Ask LLM what to search for
# 2. Search vector DB with those terms
# 3. Answer original question with context

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <query> [llm-model]"
    echo "Example: $0 'Who is Prince Andrei\\'s father?' mistral:7b"
    exit 1
fi

QUERY="$1"
LLM_MODEL="${2:-mistral:7b}"
COLLECTION="${RAG_COLLECTION:-documents}"

echo "🔍 Two-Pass RAG Query"
echo "   Collection: $COLLECTION"
echo "   Question: $QUERY"
echo ""

# === PASS 1: Ask LLM what to search for ===
echo "📝 Pass 1: Query reformulation..."

REFORMULATION_PROMPT="You are helping search a vector database containing text from classic literature (novels like War and Peace).

The user wants to answer this question:
\"$QUERY\"

Vector databases work by semantic similarity - they find text chunks with similar meaning to the search query. They work best with:
- Specific names (characters, places)
- Key phrases that might appear in the text
- Multiple related terms

Provide 3-5 search queries that would help find relevant passages. Focus on:
1. Character names (including alternate spellings like Andrei/Andrew)
2. Key nouns and relationships
3. Phrases that might literally appear in the text

Output ONLY the search queries, one per line, no numbering or explanation."

# Call LLM for search terms
ESCAPED_PROMPT=$(echo "$REFORMULATION_PROMPT" | jq -Rs .)
SEARCH_TERMS=$(curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$LLM_MODEL" --argjson prompt "$ESCAPED_PROMPT" \
        '{model: $model, prompt: $prompt, stream: false}')" \
    | jq -r '.response')

echo "   LLM suggests searching for:"
echo "$SEARCH_TERMS" | sed 's/^/      /'
echo ""

# === PASS 2: Search with each term and combine results ===
echo "🔎 Pass 2: Searching vector database..."

# Collect unique chunks from all searches
COMBINED_CONTEXT=""
SEEN_IDS=""

# Search with each suggested term
while IFS= read -r term; do
    # Skip empty lines
    [ -z "$term" ] && continue

    # Clean the term (remove leading numbers, dashes, etc.)
    clean_term=$(echo "$term" | sed 's/^[0-9]*[.)-]* *//' | tr -d '"')
    [ -z "$clean_term" ] && continue

    echo "   Searching: \"$clean_term\""

    # Use hybrid search for better keyword matching
    # hybrid-search returns raw array, not {"results": [...]}
    RESULTS=$(./target/release/hybrid-search "$clean_term" \
        --collection "$COLLECTION" \
        --limit 3 \
        --json 2>/dev/null || echo '[]')

    # Extract text from results, deduplicate by chunk ID
    while IFS= read -r chunk; do
        [ -z "$chunk" ] && continue

        chunk_id=$(echo "$chunk" | jq -r '.id // empty')
        chunk_text=$(echo "$chunk" | jq -r '.payload.text // empty')

        # Skip if we've seen this chunk or no ID
        [ -z "$chunk_id" ] && continue
        if echo "$SEEN_IDS" | grep -q "$chunk_id"; then
            continue
        fi
        SEEN_IDS="$SEEN_IDS $chunk_id"

        # Add to context (with separator)
        if [ -n "$chunk_text" ]; then
            COMBINED_CONTEXT="${COMBINED_CONTEXT}

---
${chunk_text}"
        fi
    done < <(echo "$RESULTS" | jq -c '.[]?' 2>/dev/null)

done <<< "$SEARCH_TERMS"

# Trim context to reasonable size (8000 chars to allow more context)
TRIMMED_CONTEXT=$(echo "$COMBINED_CONTEXT" | head -c 8000)
CONTEXT_SIZE=${#TRIMMED_CONTEXT}

echo ""
echo "📚 Retrieved $CONTEXT_SIZE characters of context"
echo ""

# === PASS 3: Answer with context ===
echo "💭 Pass 3: Generating answer..."

if [ -z "$TRIMMED_CONTEXT" ]; then
    echo "⚠️  No relevant context found"
    FINAL_PROMPT="Please answer this question (no context available): $QUERY"
else
    FINAL_PROMPT="Based on the following passages from the text, please answer the question.

=== PASSAGES FROM TEXT ===
$TRIMMED_CONTEXT

=== QUESTION ===
$QUERY

Please provide a clear answer based on the passages above. Quote relevant text when helpful."
fi

echo ""
echo "🤖 Answer:"
echo "────────────────────────────────────────"

ESCAPED_FINAL=$(echo "$FINAL_PROMPT" | jq -Rs .)
curl -s -X POST http://localhost:11434/api/generate \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$LLM_MODEL" --argjson prompt "$ESCAPED_FINAL" \
        '{model: $model, prompt: $prompt, stream: false}')" \
    | jq -r '.response'

echo "────────────────────────────────────────"
