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
| 2 | What is the name of Prince Andrei's estate? | Boguchárovo (given by his father; Bald Hills is the father's estate) |
| 3 | Who does Pierre Bezukhov marry first? | Hélène Kuragina |
| 4 | What happens to Prince Andrei at Borodino? | Mortally wounded by shell |
| 5 | Who does Natasha almost elope with? | Anatole Kuragin |
| 6 | What secret society does Pierre join? | The Freemasons |

### Results by Context Size

| Question | 4K context | 16K context | Notes |
|----------|-----------|-------------|-------|
| Andrei's father | Partial ("old prince") | **Correct** (Nicholas) | Two-pass query reformulation helped |
| Andrei's estate | **Correct** (Boguchárovo) | **Correct** (Boguchárovo) | Initial expected answer was wrong |
| Pierre's first wife | Incorrect | **Correct** (Hélène) | Larger context found marriage passage |
| Borodino | Partial (battle only) | Partial (wounded) | Specific shell detail hard to retrieve |
| Natasha's elopement | Incorrect | Incorrect | Chunk boundary issue (see analysis) |
| Pierre's secret society | **Correct** | **Correct** | Topic matching works well |

**4K Context Accuracy**: 2/6 correct, 2/6 partial (33% fully correct)
**16K Context Accuracy**: 4/6 correct, 1/6 partial (67% fully correct)

## Analysis

### What Vector Search Handles Well

- **Semantic similarity**: "father" matches passages about parents, ancestry
- **Synonyms**: No need to search "dad", "parent" separately - embeddings handle this
- **Paraphrasing**: Different phrasings of same concept cluster together
- **Topic matching**: "Freemasons" finds passages about lodges, secret societies

### Where Vector Search Struggles

1. **Syntactic Inversion**: Question asks "father of Andrei" but text says "Andrei is son of Nicholas" - semantically similar but vector similarity is lower than generic "father" passages

2. **Ranking Competition**: Many passages match "father" concept; the specific answer competes with generic family discussions. Increasing context from 5 to 20 chunks (4K→16K chars) doubled accuracy.

3. **Chunk Boundaries**: The Natasha elopement question fails because Pierre's accusation ("were about to elope") and Anatole's response are in different chunks. Retrieving one doesn't get the other.

4. **Rare Keywords**: "elope" appears only 3 times in 3.2MB. Keyword boosting can't help when the term is this rare.

### Key Finding: Context Size Matters

| Context Size | Chunks | Accuracy |
|-------------|--------|----------|
| 4,000 chars | ~5 | 33% |
| 16,000 chars | ~20 | 67% |

Doubling context from 4K to 16K doubled accuracy. The correct answer often exists but ranks outside the default top-5 results.

## Recommendations

### Proven Improvements

1. **Increase Context to 16K+**: The single most effective change. Modern LLMs can handle 32K-128K tokens.

2. **Use Hybrid Search**: Combine vector similarity (70%) with keyword matching (30%) for proper nouns.

3. **Query Reformulation**: Ask LLM to suggest search terms. Helps when question contains entity names the corpus uses differently.

### What Doesn't Help

- **Synonym expansion**: Vector embeddings already capture semantic similarity
- **Soundex/phonetic matching**: The problem isn't spelling variants
- **More search queries**: Generates noise without improving precision when the answer isn't semantically close to the question

### Remaining Challenges

1. **Chunk boundary splits**: Important context can span multiple chunks
2. **Inverse relationships**: "X's father" vs "father of X" vs "son of Y"
3. **Rare terminology**: Keywords appearing <5 times can't benefit from keyword boosting

## Commands Reference

```bash
# Ingest text file
RAG_COLLECTION=classic-literature \
  ./target/release/ingest-hierarchical ~/Downloads/war-and-peace-tolstoy-clean.txt

# Single-pass query (4K context, 5 chunks)
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "your question"

# Two-pass query with LLM reformulation
RAG_COLLECTION=classic-literature ./scripts/query-rag-2pass.sh "your question"

# Multi-pass with expanded context (16K context, 20 chunks) - RECOMMENDED
RAG_COLLECTION=classic-literature ./scripts/query-rag-multipass.sh "your question" mistral:7b large

# Multi-pass strategies:
#   large    - 20 chunks, 16K chars (best accuracy)
#   multi    - Multiple query variations combined
#   paginate - Batch summarization for very large context
#   parent   - Include parent chunks for broader context

# Direct hybrid search (for debugging)
./target/release/hybrid-search "search terms" --collection classic-literature --limit 20

# Check collection stats
curl -s http://localhost:6333/collections/classic-literature | jq '.result.points_count'
```
