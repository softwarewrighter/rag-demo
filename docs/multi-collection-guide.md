# Multi-Collection RAG Guide

## Overview

This guide explains how to organize different types of documents into separate Qdrant collections, preventing mixing of unrelated content and improving search relevance.

## Why Use Multiple Collections?

1. **Better Search Relevance**: Queries search only within relevant domains
2. **Organized Knowledge**: Keep different topics cleanly separated
3. **Scalability**: Each collection can be optimized independently
4. **Access Control**: Future ability to restrict access per collection
5. **Clear Naming**: Descriptive names instead of generic "documents"

## Collection Naming Best Practices

### ✅ Good Collection Names
- `rust-books` - Programming language documentation
- `javascript-docs` - Specific technology docs
- `python-tutorials` - Language-specific tutorials
- `company-policies` - Internal documentation
- `research-papers` - Academic content
- `api-documentation` - Technical API docs
- `customer-support` - Support knowledge base
- `legal-contracts` - Legal documents

### ❌ Avoid Generic Names
- `documents` - Too vague
- `pdfs` - Describes format, not content
- `data` - Meaningless
- `collection1` - No semantic meaning
- `test` - Unclear purpose

## Setting Up Collections

### Method 1: Create Collection First

```bash
# Create a new collection with descriptive alias
./scripts/setup-collection.sh javascript-books "JavaScript Documentation"

# The script will:
# 1. Validate the name (alphanumeric, hyphens, underscores)
# 2. Warn if using generic names like "documents"
# 3. Create the collection with proper vector configuration
# 4. Add a human-readable alias
```

### Method 2: Auto-Create During Ingestion

```bash
# Set the target collection
export RAG_COLLECTION=python-books

# Ingest will create collection if it doesn't exist
./scripts/ingest-pdf-smart.sh python-guide.pdf
```

### Method 3: Use Topic-Specific Scripts

```bash
# JavaScript books
./scripts/ingest-javascript-books.sh eloquent-javascript.pdf

# Python books  
./scripts/ingest-python-books.sh fluent-python.pdf
```

## Ingesting into Specific Collections

### Single PDF Ingestion

```bash
# Set target collection
export RAG_COLLECTION=rust-books

# Ingest single PDF
./scripts/ingest-pdf-smart.sh rust-programming.pdf
```

### Bulk Ingestion by Topic

```bash
# JavaScript books
export RAG_COLLECTION=javascript-books
for pdf in ingest/*javascript*.pdf ingest/*js*.pdf; do
    ./scripts/ingest-pdf-smart.sh "$pdf"
done

# Python books
export RAG_COLLECTION=python-books
for pdf in ingest/*python*.pdf ingest/*py*.pdf; do
    ./scripts/ingest-pdf-smart.sh "$pdf"
done
```

### Using Wrapper Scripts

```bash
# These scripts handle collection setup automatically
./scripts/ingest-javascript-books.sh ingest/*.js.pdf
./scripts/ingest-python-books.sh ingest/*.py.pdf
```

## Querying Specific Collections

### Command Line Queries

```bash
# Query Rust books
export RAG_COLLECTION=rust-books
./scripts/query-rag.sh "How do I implement traits?"

# Query JavaScript docs
export RAG_COLLECTION=javascript-books
./scripts/query-rag.sh "Explain promises and async/await"

# Query Python tutorials
export RAG_COLLECTION=python-books
./scripts/query-rag.sh "What are decorators?"
```

### Interactive Mode

```bash
# Interactive chat with JavaScript docs
RAG_COLLECTION=javascript-books ./scripts/interactive-rag.sh

# Interactive chat with Python docs
RAG_COLLECTION=python-books ./scripts/interactive-rag.sh
```

### Programmatic Access

```rust
// In Rust code, specify collection
let args = Args {
    collection: "javascript-books".to_string(),
    query: "closures in JavaScript".to_string(),
    // ...
};
```

## Managing Collections

### List All Collections

```bash
# View all collections and their stats
curl -s http://localhost:6333/collections | jq '.result.collections'
```

### Check Collection Statistics

```bash
# Check specific collection
COLLECTION=javascript-books
curl -s "http://localhost:6333/collections/$COLLECTION" | \
    jq '.result | {points: .points_count, status: .status}'
```

### View Collection Details

```bash
# Detailed stats for a collection
./scripts/qdrant-stats.sh javascript-books
```

### Delete a Collection

```bash
# WARNING: This permanently deletes all data
curl -X DELETE "http://localhost:6333/collections/old-collection"
```

## Collection Aliases

Aliases provide human-readable names for collections:

```bash
# Add alias to existing collection
curl -X POST "http://localhost:6333/collections/aliases" \
    -H "Content-Type: application/json" \
    -d '{
        "actions": [{
            "create_alias": {
                "collection_name": "js-docs-v2",
                "alias_name": "javascript-latest"
            }
        }]
    }'
```

## Environment Variables

### RAG_COLLECTION
Controls which collection is used for ingestion and queries:

```bash
# Set for current session
export RAG_COLLECTION=python-books

# Set for single command
RAG_COLLECTION=rust-books ./scripts/query-rag.sh "What is ownership?"
```

### RAG_ALIAS
Optionally set an alias during collection creation:

```bash
export RAG_COLLECTION=ml-papers
export RAG_ALIAS="Machine Learning Research"
./scripts/setup-qdrant.sh
```

## Migration from Generic "documents"

If you started with the generic "documents" collection:

```bash
# 1. Create specific collections
./scripts/setup-collection.sh rust-books "Rust Documentation"
./scripts/setup-collection.sh python-books "Python Documentation"

# 2. Re-ingest PDFs into proper collections
export RAG_COLLECTION=rust-books
./scripts/ingest-pdf-smart.sh ingest/*rust*.pdf

export RAG_COLLECTION=python-books
./scripts/ingest-pdf-smart.sh ingest/*python*.pdf

# 3. Optionally delete the old generic collection
curl -X DELETE "http://localhost:6333/collections/documents"
```

## Best Practices

1. **Plan Collections Before Ingestion**
   - Think about how you'll query the data
   - Group related content together
   - Keep unrelated topics separate

2. **Use Descriptive Names**
   - Include the content type (books, docs, papers)
   - Include the subject (rust, javascript, legal)
   - Avoid version numbers unless necessary

3. **Document Your Collections**
   - Maintain a list of collections and their purposes
   - Note ingestion dates and source materials
   - Track which models work best for each type

4. **Test Search Quality**
   - Verify queries return relevant results
   - Check that topics don't cross-contaminate
   - Monitor performance per collection

## Common Patterns

### Multi-Language Documentation

```bash
# Separate collections per programming language
./scripts/setup-collection.sh rust-docs "Rust Documentation"
./scripts/setup-collection.sh go-docs "Go Documentation"
./scripts/setup-collection.sh python-docs "Python Documentation"
```

### Versioned Documentation

```bash
# Version-specific collections
./scripts/setup-collection.sh react-v18 "React 18 Documentation"
./scripts/setup-collection.sh react-v17 "React 17 Documentation"
```

### Domain-Specific Knowledge

```bash
# Different domains in same system
./scripts/setup-collection.sh medical-research "Medical Papers"
./scripts/setup-collection.sh legal-documents "Legal Contracts"
./scripts/setup-collection.sh technical-specs "Product Specifications"
```

## Troubleshooting

### Collection Not Found

```bash
# Check if collection exists
curl -s "http://localhost:6333/collections/my-collection" | jq '.status'

# Create if missing
./scripts/setup-collection.sh my-collection "My Collection"
```

### Wrong Collection Used

```bash
# Always verify which collection is active
echo "Current collection: ${RAG_COLLECTION:-documents}"

# Explicitly set for critical operations
RAG_COLLECTION=production-docs ./scripts/ingest-pdf-smart.sh important.pdf
```

### Mixing Content Types

If you accidentally ingested wrong content:

1. Note the ingestion timestamp
2. Consider recreating the collection
3. Re-ingest correct content only

## Advanced Usage

### Cross-Collection Search

Future enhancement to search multiple collections:

```bash
# Concept: Search across multiple collections
./scripts/search-multi.sh "async programming" \
    --collections rust-books,javascript-books,python-books
```

### Collection Templates

For consistent collection settings:

```bash
# Create template for technical documentation
VECTOR_SIZE=768
DISTANCE_METRIC="Cosine"
INDEXING_THRESHOLD=1000

for lang in rust go python javascript; do
    ./scripts/setup-collection.sh "${lang}-api-docs" \
        "${lang^} API Documentation"
done
```

## Summary

Using multiple collections provides:
- **Better organization** of different knowledge domains
- **Improved search relevance** by searching only related content  
- **Clearer system architecture** with meaningful names
- **Flexibility** to optimize each collection independently
- **Scalability** as your knowledge base grows

Always use descriptive collection names that indicate the content type and domain, making your RAG system more maintainable and effective.