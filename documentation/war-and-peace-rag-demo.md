# War and Peace RAG Demo

This document demonstrates the RAG system using Leo Tolstoy's *War and Peace* as a test corpus. We ingest the complete novel and ask verifiable questions to evaluate retrieval quality and LLM response accuracy.

## Source Text

- **Title**: War and Peace
- **Author**: Leo Tolstoy (translated by Louise and Aylmer Maude)
- **Source**: [Project Gutenberg #2600](https://www.gutenberg.org/ebooks/2600)
- **Preprocessing**: Gutenberg boilerplate stripped using `./scripts/strip-gutenberg.sh`
- **Final size**: 65,660 lines (~3.2 MB)

## Ingestion Stats

```
Collection: classic-literature
Parent chunks: 1900 (avg 1722 chars)
Child chunks: 3177 (avg 1030 chars)
Total vectors: 5077
```

## Test Questions

We designed questions that:
1. **Are verifiable** - answers can be confirmed by searching the source text
2. **Are specific** - won't flood context with too many RAG results
3. **Test different retrieval patterns** - character names, events, relationships, locations

### Question Set

| # | Question | Expected Answer | Verification Method |
|---|----------|-----------------|---------------------|
| 1 | Who is Prince Andrei's father? | Prince Nikolai Bolkonsky (the old prince) | `grep -i "andrei.*father\|bolkonsky"` |
| 2 | What is the name of Prince Andrei's estate? | Bald Hills | `grep -i "bald hills"` |
| 3 | Who does Pierre Bezukhov marry first? | Helene Kuragina | `grep -i "pierre.*wife\|helene"` |
| 4 | What happens to Prince Andrei at the Battle of Borodino? | He is mortally wounded by a shell | `grep -i "andrei.*wound\|borodino"` |
| 5 | Who does Natasha Rostova almost elope with? | Anatole Kuragin | `grep -i "anatole.*natasha\|elope"` |
| 6 | Who is Pierre's illegitimate father? | Count Kirill Bezukhov | `grep -i "kirill\|pierre.*father"` |
| 7 | What secret society does Pierre join? | The Freemasons | `grep -i "freemason\|mason\|lodge"` |

## Running the Demo

### Prerequisites

```bash
# Ensure services are running
./scripts/health-check.sh

# Verify the collection exists
curl -s http://localhost:6333/collections/classic-literature | jq '.result.points_count'
```

### Querying with RAG

```bash
# Set the collection
export RAG_COLLECTION=classic-literature

# Query with mistral:7b
./scripts/query-rag.sh "Who is Prince Andrei's father?"
```

## Results

### Question 1: Who is Prince Andrei's father?

**Query:**
```bash
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "Who is Prince Andrei's father?"
```

**LLM Response:**
```
Based on the provided context, it can be inferred that Prince Andrew's father is
referred to as "the old man" or "the prince." However, the text does not provide
his name explicitly, so further information is needed to determine who exactly
Prince Andrew's father is within this narrative.
```

**Expected Answer:** Prince Nikolai Bolkonsky (Prince Nicholas Andreevich Bolkonski)

**Result:** Partially Correct - identified "the old prince" but did not retrieve the name

---

### Question 2: What is the name of Prince Andrei's estate?

**Query:**
```bash
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "What is the name of Prince Andrei's estate?"
```

**LLM Response:**
```
The name of Prince Andrei's estate is Bogucharovo Cloister.
```

**Expected Answer:** Bald Hills

**Verification:**
```
At Bald Hills, Prince Nicholas Andreevich Bolkonski's estate, the...
```

**Result:** Incorrect - answered "Bogucharovo Cloister" but the correct answer is "Bald Hills"

---

### Question 3: Who does Pierre Bezukhov marry first?

**Query:**
```bash
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "Who does Pierre Bezukhov marry first?"
```

**LLM Response:**
```
Based on the provided context, it is not clearly stated who Pierre Bezukhov
marries first. The text mentions that there are rumors of marriage plans for him,
specifically with Prince Vasili's son Anatole, but no marriage has been confirmed
to have taken place yet.
```

**Expected Answer:** Helene Kuragina (Prince Vasili's daughter)

**Result:** Incorrect - the RAG context did not include Pierre's marriage to Helene

---

### Question 4: What happens to Prince Andrei at the Battle of Borodino?

**Query:**
```bash
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "What happens to Prince Andrei at the Battle of Borodino?"
```

**LLM Response:**
```
During the Battle of Borodino, Prince Andrew takes action in response to Kutuzov's
distress. He leaps from his horse, grabs the standard (a military flag), and runs
towards the enemy with full confidence that his battalion will follow him. Initially,
he runs alone but soon is joined by other soldiers. They run towards an artillery
battery where they see French infantry seizing the artillery horses and turning guns
around. Despite the constant whistle of bullets and falling comrades, Prince Andrew
continues to lead his battalion forward, focused on the battery. The context does
not provide information about the outcome of this charge or whether Prince Andrew
is injured or killed in the battle.
```

**Expected Answer:** He is mortally wounded by a shell

**Result:** Partially Correct - retrieved battle context but missed the critical wounding scene

---

### Question 5: Who does Natasha Rostova almost elope with?

**Query:**
```bash
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "Who does Natasha Rostova almost elope with?"
```

**LLM Response:**
```
Based on the provided context, it is not indicated that Natasha Rostova almost
elopes with anyone specifically. The excerpt shows her considering a career as a
dancer and expressing an unwillingness to marry Boris, but there's no mention of
an elopement or another romantic interest.
```

**Expected Answer:** Anatole Kuragin

**Result:** Incorrect - RAG did not retrieve the elopement subplot

---

### Question 6: Who is Pierre's illegitimate father?

**Query:**
```bash
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "Who is Pierre's illegitimate father?"
```

**LLM Response:**
```
Based on the given context, it is not explicitly stated who Pierre's illegitimate
father is. The text mentions that Pierre believes his father loved Natasha and
left her to his friend, but it does not specify the identity of this friend or
his relationship to Pierre.
```

**Expected Answer:** Count Kirill Bezukhov

**Result:** Incorrect - Did not retrieve inheritance/legitimization context

---

### Question 7: What secret society does Pierre join?

**Query:**
```bash
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "What secret society does Pierre join?"
```

**LLM Response:**
```
The text does not specify the exact name of the secret society that Pierre joins.
However, it is clear that he becomes involved with Freemasonry and rises to a
higher grade within it.
```

**Expected Answer:** The Freemasons

**Result:** Correct - accurately identified Freemasonry

---

## Summary

| Question | Result | Notes |
|----------|--------|-------|
| 1. Prince Andrei's father | Partially Correct | Identified "the old prince" but not the name |
| 2. Prince Andrei's estate | Incorrect | Said "Bogucharovo" instead of "Bald Hills" |
| 3. Pierre's first wife | Incorrect | Failed to retrieve marriage context |
| 4. Andrei at Borodino | Partially Correct | Got battle context but missed wounding |
| 5. Natasha's elopement | Incorrect | Did not retrieve Anatole subplot |
| 6. Pierre's father | Incorrect | Did not retrieve inheritance context |
| 7. Pierre's secret society | Correct | Correctly identified Freemasonry |

**Overall Accuracy:** 1 correct, 2 partially correct, 4 incorrect out of 7 (14% fully correct, 43% partially or better)

## Observations

### What Worked Well
- Ingestion completed successfully with 5077 vectors (1900 parent, 3177 child chunks)
- The Freemasonry question was answered correctly - this is a distinctive topic that likely had good semantic similarity
- The system retrieved relevant battle scenes for Borodino, showing vector search works

### Issues Encountered
- **Semantic retrieval limitations**: Questions about relationships and specific plot points often retrieved tangentially related content rather than the exact passages needed
- **Character name variations**: The text uses "Prince Andrew" / "Andrei" / "Andrey" interchangeably, which may affect retrieval
- **Context fragmentation**: Key information like "Bald Hills estate" exists in the text but wasn't in the top retrieved chunks
- **Dense narrative**: Unlike technical documentation with clear section headers, novel prose has information distributed throughout

### Recommendations
1. **Hybrid search**: Combine vector search with keyword matching to catch exact names and places
2. **Entity extraction**: Pre-process to identify character names, places, and relationships
3. **Chunk overlap tuning**: Increase overlap to capture context spanning chunk boundaries
4. **Re-ranking**: Add a re-ranking step that boosts chunks containing query keywords
5. **Question reformulation**: Transform questions to include character name variations

## Appendix: Commands Used

```bash
# Download source
curl -L -o ~/Downloads/war-and-peace-tolstoy.txt \
  "https://www.gutenberg.org/cache/epub/2600/pg2600.txt"

# Strip Gutenberg boilerplate
./scripts/strip-gutenberg.sh ~/Downloads/war-and-peace-tolstoy.txt

# Create collection
./scripts/setup-collection.sh classic-literature "Classic Literature"

# Ingest
RAG_COLLECTION=classic-literature \
  ./target/release/ingest-hierarchical ~/Downloads/war-and-peace-tolstoy-clean.txt

# Query
RAG_COLLECTION=classic-literature ./scripts/query-rag.sh "your question"
```

## Technical Notes

### Bugs Fixed During This Demo

1. **RAG_COLLECTION environment variable ignored**: The `ingest-hierarchical` binary was not reading the `RAG_COLLECTION` environment variable, causing all ingestion to go to the default "documents" collection instead of "classic-literature". Fixed by adding `env = "RAG_COLLECTION"` to the clap argument definition.

2. **Silent Qdrant errors**: Qdrant returns HTTP 200 even when there are errors in the request body. The code was only checking HTTP status, not the response body for errors. Fixed by parsing the response JSON and checking for `status.error`.

These fixes are documented in `documentation/learnings.md`.
