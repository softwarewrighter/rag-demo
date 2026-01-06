# War and Peace RAG Demo

This document demonstrates the RAG system using Leo Tolstoy's *War and Peace* as a test corpus. We evaluate retrieval quality and LLM response accuracy on verifiable questions.

## Source Text

- **Title**: War and Peace
- **Author**: Leo Tolstoy (translated by Louise and Aylmer Maude)
- **Source**: [Project Gutenberg #2600](https://www.gutenberg.org/ebooks/2600)
- **Preprocessing**: Gutenberg boilerplate stripped using `./scripts/strip-gutenberg.sh`
- **Size**: 65,660 lines (~3.2 MB)

## Ingestion Process

### 1. Text Preparation

```bash
# Download from Project Gutenberg
curl -L -o ~/Downloads/war-and-peace-tolstoy.txt \
  "https://www.gutenberg.org/cache/epub/2600/pg2600.txt"

# Strip Gutenberg header/footer boilerplate
./scripts/strip-gutenberg.sh ~/Downloads/war-and-peace-tolstoy.txt
# Output: ~/Downloads/war-and-peace-tolstoy-clean.txt
```

### 2. Hierarchical Chunking

The system uses parent-child chunking to balance precision and context:

```bash
RAG_COLLECTION=classic-literature \
  ./target/release/ingest-hierarchical ~/Downloads/war-and-peace-tolstoy-clean.txt
```

**Chunking Strategy:**
- **Parent chunks**: ~3500 characters, provide full context
- **Child chunks**: ~750 characters, enable precise retrieval
- Each child references its parent via `parent_id`

**Ingestion Stats:**
```
Collection: classic-literature
Parent chunks: 1900 (avg 1722 chars)
Child chunks: 3177 (avg 1030 chars)
Total vectors: 5077
```

### 3. Embedding Generation

Each chunk is embedded using Ollama's `nomic-embed-text` model:
- Vector dimension: 768
- Character limit: 2000 (model stability)
- Retry logic with exponential backoff for large batches

### 4. Qdrant Storage

Vectors are stored in Qdrant with metadata:

```json
{
  "id": "uuid",
  "vector": [768 floats],
  "payload": {
    "text": "chunk content",
    "chunk_type": "child_text|parent",
    "parent_id": "parent-uuid",
    "source": "file path",
    "start_line": 1234,
    "end_line": 1256
  }
}
```

## Query Process

### Single-Pass RAG (Default)

```bash
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "Who is Prince Andrei's father?"
```

**Pipeline:**
1. Embed the question using `nomic-embed-text`
2. Search Qdrant for top 5 similar child chunks (cosine similarity)
3. Concatenate chunk text (limit 4000 chars)
4. Send to LLM with prompt: "Based on this context, answer the question..."

### Two-Pass RAG (Query Reformulation)

```bash
RAG_COLLECTION=classic-literature ./scripts/query-rag-2pass.sh "Who is Prince Andrei's father?"
```

**Pipeline:**
1. **Pass 1**: Ask LLM to suggest search terms for the question
2. **Pass 2**: Run hybrid search (vector + keyword) for each suggested term
3. **Pass 3**: Deduplicate chunks, send combined context to LLM

### How Qdrant is Used

**Vector Search:**
```
POST /collections/{collection}/points/search
{
  "vector": [768 floats from query embedding],
  "limit": 5,
  "with_payload": true,
  "filter": {
    "must": [{"key": "chunk_type", "match": {"any": ["child_text", "child_code"]}}]
  }
}
```

**Hybrid Search** (via `hybrid-search` binary):
- Vector similarity score (70% weight)
- Keyword matching score (30% weight)
- Combined ranking for final results

## Effectiveness Evaluation

### Test Questions

| # | Question | Expected Answer |
|---|----------|-----------------|
| 1 | Who is Prince Andrei's father? | Prince Nicholas Bolkonsky |
| 2 | What is the name of Prince Andrei's estate? | Bald Hills |
| 3 | Who does Pierre Bezukhov marry first? | Helene Kuragina |
| 4 | What happens to Prince Andrei at Borodino? | Mortally wounded by shell |
| 5 | Who does Natasha almost elope with? | Anatole Kuragin |
| 6 | What secret society does Pierre join? | The Freemasons |

### Results: Single-Pass vs Two-Pass

| Question | Single-Pass | Two-Pass |
|----------|-------------|----------|
| Andrei's father | Partial ("the old prince") | **Correct** (Nicholas Bolkónski) |
| Andrei's estate | Incorrect (Boguchárovo) | Incorrect (Boguchárovo) |
| Pierre's first wife | Incorrect | Incorrect (said Natasha) |
| Borodino | Partial (battle context, not wounding) | Not tested |
| Natasha's elopement | Incorrect | Not tested |
| Pierre's secret society | **Correct** (Freemasonry) | **Correct** (Freemasonry) |

**Single-Pass Accuracy**: 1/6 correct, 2/6 partial (17% fully correct)
**Two-Pass Accuracy**: 2/4 tested correct (50% on tested questions)

## Analysis

### What Vector Search Handles Well

- **Semantic similarity**: "father" matches passages about parents, ancestry
- **Synonyms**: No need to search "dad", "parent" separately
- **Paraphrasing**: Different phrasings of same concept cluster together
- **Topic matching**: "Freemasons" finds passages about lodges, secret societies

### Where Vector Search Struggles

1. **Syntactic Inversion**: Question asks "father of Andrei" but text says "Andrei is son of Nicholas" - semantically similar but vector similarity is lower than generic "father" passages

2. **Proper Noun Specificity**: "Bald Hills" is a specific name that needs exact matching. Vector search finds semantically similar "estate" passages but not the specific name

3. **Ranking Competition**: Many passages match "father" concept; the specific answer competes with generic family discussions

4. **Unknown Answers**: Two-pass reformulation can't suggest "Bald Hills" as a search term because the LLM doesn't know that's the answer

### Context Window Limitations

- Current limit: 4000 characters (~5 chunks)
- The correct answer often exists in the corpus but ranks outside top 5
- Example: "Nicholas Bolkónski" appeared in result #5 for the father question

## Recommendations

### For This System

1. **Use Hybrid Search**: Combine vector similarity with keyword matching for proper nouns
2. **Increase Context**: Allow more chunks (8000+ chars) to improve answer coverage
3. **Two-Pass for Complex Questions**: Query reformulation helps when the question contains entity names

### For RAG on Fiction Generally

1. **Entity-Aware Chunking**: Ensure character names, places stay with their descriptions
2. **Character Index**: Pre-extract character names and relationships as structured metadata
3. **Re-ranking**: After initial retrieval, boost chunks containing query keywords
4. **Iterative Retrieval**: Search, find candidate entities, search again with those terms

### What Doesn't Help

- **Synonym expansion**: Vector embeddings already capture semantic similarity
- **More search terms**: Generates noise without improving precision
- **Larger chunks**: Reduces precision without guaranteeing answer inclusion

## Commands Reference

```bash
# Ingest text file
RAG_COLLECTION=classic-literature \
  ./target/release/ingest-hierarchical ~/Downloads/war-and-peace-tolstoy-clean.txt

# Single-pass query
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "your question"

# Two-pass query with reformulation
RAG_COLLECTION=classic-literature ./scripts/query-rag-2pass.sh "your question"

# Direct hybrid search (for debugging)
./target/release/hybrid-search "search terms" --collection classic-literature --limit 5

# Check collection stats
curl -s http://localhost:6333/collections/classic-literature | jq '.result.points_count'
```
