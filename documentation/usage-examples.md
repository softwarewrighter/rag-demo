# Usage Examples & Real-World Scenarios

This guide provides concrete examples of how to use the RAG Demo scripts to accomplish specific goals. Each example shows the exact sequence of commands and expected outcomes.

## Table of Contents

1. [Research Student: Building a Paper Library](#1-research-student-building-a-paper-library)
2. [Developer: Creating a Programming Knowledge Base](#2-developer-creating-a-programming-knowledge-base)
3. [Team: Shared Documentation Repository](#3-team-shared-documentation-repository)
4. [Quick Demo for Presentation](#4-quick-demo-for-presentation)
5. [Performance Testing & Optimization](#5-performance-testing--optimization)
6. [Migrating from Another System](#6-migrating-from-another-system)
7. [Recovery: Starting Fresh After Issues](#7-recovery-starting-fresh-after-issues)
8. [Adding New Documents Weekly](#8-adding-new-documents-weekly)
9. [Web Dashboard for Non-Technical Users](#9-web-dashboard-for-non-technical-users)
10. [Comparing Different Chunking Strategies](#10-comparing-different-chunking-strategies)

---

## 1. Research Student: Building a Paper Library

**Scenario:** You're a grad student in machine learning. You have 50+ research papers across different topics (deep learning, reinforcement learning, NLP, computer vision). You want to organize them and quickly find relevant information.

### Step-by-Step

```bash
# 1. Initial setup (one-time)
./scripts/setup-qdrant.sh
# In another terminal: ollama serve
./scripts/build-all.sh
./scripts/health-check.sh

# 2. Organize your PDFs by topic
mkdir -p ingest/{deep-learning,reinforcement-learning,nlp,computer-vision}

# Move your papers into appropriate folders
mv ~/Downloads/attention-is-all-you-need.pdf ingest/nlp/
mv ~/Downloads/resnet.pdf ingest/computer-vision/
mv ~/Downloads/dqn.pdf ingest/reinforcement-learning/
mv ~/Downloads/transformer-xl.pdf ingest/nlp/
# ... etc for all papers

# 3. Verify organization
ls ingest/*/

# 4. Ingest all papers into separate collections
./scripts/ingest-by-directory.sh ./ingest

# 5. Monitor progress (in another terminal)
./scripts/ingestion-status.sh

# 6. Verify collections created
./scripts/verify-collections.sh

# Expected output:
# Collection: nlp-books (24 papers, 2,156 vectors)
# Collection: computer-vision-books (18 papers, 1,843 vectors)
# Collection: reinforcement-learning-books (12 papers, 987 vectors)
# Collection: deep-learning-books (15 papers, 1,432 vectors)

# 7. Add descriptive aliases
./scripts/update-collection-alias.sh nlp-books "Natural Language Processing Papers"
./scripts/update-collection-alias.sh computer-vision-books "Computer Vision Papers"
./scripts/update-collection-alias.sh reinforcement-learning-books "Reinforcement Learning Papers"
./scripts/update-collection-alias.sh deep-learning-books "Deep Learning Papers"

# 8. Check overall statistics
./scripts/qdrant-stats.sh

# 9. Try queries on specific topics
RAG_COLLECTION=nlp-books ./scripts/query-rag.sh "How does attention mechanism work?"
RAG_COLLECTION=reinforcement-learning-books ./scripts/query-rag.sh "What is Q-learning?"

# 10. Use interactive mode for literature review
RAG_COLLECTION=nlp-books ./scripts/interactive-rag.sh
```

### Usage Pattern

**Daily workflow:**
```bash
# Start interactive session for your current research topic
RAG_COLLECTION=nlp-books ./scripts/interactive-rag.sh

# Example questions:
# > What are the key innovations in transformer models?
# > Compare BERT and GPT architectures
# > What are attention mechanism variants?
# > stats (see session statistics)
```

**Adding new papers:**
```bash
# Download new paper
mv ~/Downloads/llama2-paper.pdf ingest/nlp/

# Re-run ingestion (only processes new file)
./scripts/ingest-by-directory.sh ./ingest

# Verify
RAG_COLLECTION=nlp-books ./scripts/qdrant-stats.sh
```

---

## 2. Developer: Creating a Programming Knowledge Base

**Scenario:** You're a Rust developer learning multiple languages. You want a searchable knowledge base of programming books: Rust, Python, JavaScript, Go, and Lisp.

### Step-by-Step

```bash
# 1. Setup
./scripts/setup-qdrant.sh
./scripts/build-all.sh

# 2. Organize programming books
mkdir -p ingest/{rust,python,javascript,go,lisp}

cp ~/Books/Programming/rust-book.pdf ingest/rust/
cp ~/Books/Programming/async-rust.pdf ingest/rust/
cp ~/Books/Programming/rust-atomics.pdf ingest/rust/

cp ~/Books/Programming/fluent-python.pdf ingest/python/
cp ~/Books/Programming/effective-python.pdf ingest/python/

cp ~/Books/Programming/javascript-definitive-guide.pdf ingest/javascript/
cp ~/Books/Programming/eloquent-javascript.pdf ingest/javascript/

cp ~/Books/Programming/go-programming-language.pdf ingest/go/

cp ~/Books/Programming/practical-common-lisp.pdf ingest/lisp/
cp ~/Books/Programming/land-of-lisp.pdf ingest/lisp/

# 3. Ingest all at once
./scripts/ingest-by-directory.sh ./ingest

# 4. Build dashboard for visual exploration
./scripts/build-dashboard.sh

# 5. Serve dashboard
./scripts/serve-dashboard.sh
# Opens: http://localhost:8080

# 6. Try language-specific queries from command line
RAG_COLLECTION=rust-books ./scripts/query-rag.sh "How does Rust handle memory safety?"
RAG_COLLECTION=python-books ./scripts/query-rag.sh "What are Python decorators?"
RAG_COLLECTION=javascript-books ./scripts/query-rag.sh "Explain closures and scope"
RAG_COLLECTION=go-books ./scripts/query-rag.sh "How do goroutines work?"
RAG_COLLECTION=lisp-books ./scripts/query-rag.sh "What are macros?"

# 7. Compare concepts across languages
RAG_COLLECTION=rust-books ./scripts/query-rag.sh "error handling patterns" > rust-errors.txt
RAG_COLLECTION=go-books ./scripts/query-rag.sh "error handling patterns" > go-errors.txt
diff rust-errors.txt go-errors.txt
```

### Usage Pattern

**When learning a new concept:**
```bash
# Start with overview
RAG_COLLECTION=rust-books ./scripts/interactive-rag.sh

# Interactive session:
# > What is ownership?
# > Explain borrowing rules
# > Show examples of lifetimes
# > What are smart pointers?
# > stats
```

**When debugging:**
```bash
# Quick reference lookup
RAG_COLLECTION=rust-books ./scripts/query-rag.sh "common lifetime errors"
RAG_COLLECTION=python-books ./scripts/query-rag.sh "gil and threading issues"
```

**Cross-language comparison:**
```bash
# Compare same concept in different languages
echo "=== Rust ===" && \
RAG_COLLECTION=rust-books ./scripts/query-rag.sh "async programming patterns" && \
echo "\n=== JavaScript ===" && \
RAG_COLLECTION=javascript-books ./scripts/query-rag.sh "async programming patterns"
```

---

## 3. Team: Shared Documentation Repository

**Scenario:** Your team has internal documentation, API specs, architecture docs, and runbooks as PDFs. You want a searchable team knowledge base.

### Step-by-Step

```bash
# 1. Setup on team server
./scripts/setup-qdrant.sh
./scripts/build-all.sh

# 2. Organize team documents
mkdir -p ingest/{api-docs,architecture,runbooks,onboarding,rfcs}

# Copy team documents
cp /shared/docs/api/*.pdf ingest/api-docs/
cp /shared/docs/architecture/*.pdf ingest/architecture/
cp /shared/docs/runbooks/*.pdf ingest/runbooks/
cp /shared/docs/onboarding/*.pdf ingest/onboarding/
cp /shared/docs/rfcs/*.pdf ingest/rfcs/

# 3. Ingest all
./scripts/ingest-by-directory.sh ./ingest

# 4. Add descriptive names
./scripts/update-collection-alias.sh api-docs-books "API Documentation"
./scripts/update-collection-alias.sh architecture-books "Architecture & Design Docs"
./scripts/update-collection-alias.sh runbooks-books "Operations Runbooks"
./scripts/update-collection-alias.sh onboarding-books "Team Onboarding"
./scripts/update-collection-alias.sh rfcs-books "RFCs & Design Proposals"

# 5. Verify everything
./scripts/verify-collections.sh
./scripts/qdrant-stats.sh

# 6. Build and serve dashboard for team access
./scripts/serve-dashboard.sh
# Share URL with team: http://team-server:8080

# 7. Test common queries
RAG_COLLECTION=api-docs-books ./scripts/query-rag.sh "authentication endpoints"
RAG_COLLECTION=runbooks-books ./scripts/query-rag.sh "how to deploy to production"
RAG_COLLECTION=architecture-books ./scripts/query-rag.sh "microservices communication"
```

### Usage Pattern

**New employee onboarding:**
```bash
# Interactive session for new hires
RAG_COLLECTION=onboarding-books ./scripts/interactive-rag.sh

# Typical questions:
# > How do I set up my development environment?
# > What is our code review process?
# > Where is the staging environment?
# > How do I access the VPN?
```

**On-call engineer:**
```bash
# Quick incident response
RAG_COLLECTION=runbooks-books ./scripts/query-rag.sh "database connection pool exhausted"
RAG_COLLECTION=runbooks-books ./scripts/query-rag.sh "high memory usage investigation"
```

**Developer working on feature:**
```bash
# API reference
RAG_COLLECTION=api-docs-books ./scripts/interactive-rag.sh
# > What are the user authentication endpoints?
# > How do I paginate results?
# > What are rate limiting rules?

# Architecture context
RAG_COLLECTION=architecture-books ./scripts/query-rag.sh "payment processing flow"
```

**Weekly documentation updates:**
```bash
# Add new docs
cp /shared/docs/new-week/*.pdf ingest/appropriate-category/

# Re-ingest (deduplication prevents re-processing)
./scripts/ingest-by-directory.sh ./ingest

# Verify
./scripts/qdrant-stats.sh
```

---

## 4. Quick Demo for Presentation

**Scenario:** You're giving a presentation tomorrow and need to demo RAG capabilities. You have 30 minutes to set up.

### Step-by-Step

```bash
# 1. Speed setup
./scripts/setup-qdrant.sh
./scripts/build-all.sh

# 2. Get sample documents (use a few interesting PDFs)
mkdir -p ingest
cp ~/Demo-Materials/*.pdf ingest/
# Or download from internet
# wget https://example.com/sample-doc.pdf -O ingest/sample.pdf

# 3. Quick ingest
./scripts/ingest-all-pdfs.sh

# 4. Verify it worked
./scripts/qdrant-stats.sh

# 5. Prepare demo queries (test them first!)
./scripts/query-rag.sh "key concept from your document"

# 6. Build dashboard for visual demo
./scripts/build-dashboard.sh

# 7. Create aliases for better demo visuals
./scripts/serve-dashboard.sh

# 8. Prepare benchmark results to show performance
./scripts/benchmark-queries.sh > benchmark-results.txt
```

### Demo Script

**Part 1: Command Line Demo**
```bash
# Show single query
./scripts/query-rag.sh "impressive question about your documents"

# Show interactive mode with follow-up questions
./scripts/interactive-rag.sh
# > First question
# > Follow-up question using context
# > stats (show performance)
```

**Part 2: Dashboard Demo**
```bash
# Already running from serve-dashboard.sh
# Open http://localhost:8080 in browser
# Show:
# - Collection selection
# - Search interface
# - Real-time results
# - System status
```

**Part 3: Performance Numbers**
```bash
# Show stats
./scripts/qdrant-stats.sh

# Show benchmark results
cat benchmark-results.txt
```

---

## 5. Performance Testing & Optimization

**Scenario:** You've ingested documents but want to optimize performance and understand system capabilities.

### Step-by-Step

```bash
# 1. Ensure documents are ingested
./scripts/qdrant-stats.sh

# 2. Run comprehensive benchmarks
./scripts/benchmark-queries.sh

# Sample output:
# Query 1: "sample question" - 67ms
# Query 2: "another question" - 72ms
# Query 3: "complex question" - 89ms
# Average: 76ms

# 3. Check indexing status (impacts performance)
./scripts/verify-collections.sh

# Expected output shows indexed_vectors_count
# If vectors_count > indexed_vectors_count, indexing in progress

# 4. Monitor during queries
# Terminal 1:
./scripts/query-rag.sh "test query"

# Terminal 2:
watch -n 1 './scripts/qdrant-stats.sh'

# 5. Test with different query complexities
# Simple factual:
time ./scripts/query-rag.sh "What is X?"

# Complex reasoning:
time ./scripts/query-rag.sh "Compare X and Y, considering their advantages"

# 6. Test collection-specific performance
for collection in rust-books python-books javascript-books; do
  echo "Testing $collection"
  time RAG_COLLECTION=$collection ./scripts/query-rag.sh "example question"
done

# 7. Check memory usage
docker stats qdrant
```

### Optimization Steps

**If queries are slow (>200ms):**
```bash
# Check if indexing is complete
./scripts/verify-collections.sh

# Check vector counts
./scripts/qdrant-stats.sh

# If needed, force rebuild index
curl -X POST http://localhost:6333/collections/documents/index

# Verify improvement
./scripts/benchmark-queries.sh
```

**If ingestion is slow:**
```bash
# Ingest smaller batches
# Split PDFs into smaller groups
ls ingest/*.pdf | head -10 | xargs -I {} ./scripts/ingest-pdf-smart.sh {}

# Monitor progress
./scripts/ingestion-status.sh
```

---

## 6. Migrating from Another System

**Scenario:** You have documents in another RAG system or format. You want to migrate to this system.

### Step-by-Step

```bash
# 1. Setup new system
./scripts/setup-qdrant.sh
./scripts/build-all.sh

# 2. Export PDFs from old system (system-specific)
# Example: Copy from old system's storage
cp /old-system/storage/*.pdf ./ingest/

# 3. Verify PDFs are valid
for pdf in ingest/*.pdf; do
  echo "Checking: $pdf"
  pdfinfo "$pdf" || echo "ERROR: $pdf is invalid"
done

# 4. Organize by topic if needed
mkdir -p ingest/{topic1,topic2,topic3}
# Move files as appropriate

# 5. Test with single document first
./scripts/ingest-pdf-smart.sh ingest/test-doc.pdf
./scripts/query-rag.sh "question about test doc"

# 6. If successful, bulk ingest
./scripts/ingest-by-directory.sh ./ingest

# 7. Verify migration completeness
OLD_DOC_COUNT=150  # From old system
NEW_VECTOR_COUNT=$(curl -s http://localhost:6333/collections | jq '[.result.collections[].vectors_count] | add')
echo "Old system docs: $OLD_DOC_COUNT"
echo "New system vectors: $NEW_VECTOR_COUNT"

# 8. Spot check with known queries
./scripts/query-rag.sh "query that worked in old system"

# 9. Compare results (manual verification)
./scripts/interactive-rag.sh
```

### Migration Checklist

```bash
# ✓ All documents copied
ls ingest/ | wc -l

# ✓ Ingestion successful
./scripts/qdrant-stats.sh

# ✓ Collections organized correctly
./scripts/verify-collections.sh

# ✓ Sample queries work
./scripts/query-rag.sh "test query 1"
./scripts/query-rag.sh "test query 2"
./scripts/query-rag.sh "test query 3"

# ✓ Performance acceptable
./scripts/benchmark-queries.sh

# ✓ Dashboard accessible
./scripts/serve-dashboard.sh
```

---

## 7. Recovery: Starting Fresh After Issues

**Scenario:** Something went wrong. Collections are corrupted, or you want to start over with different settings.

### Step-by-Step

```bash
# 1. Backup checksums (if you want to preserve deduplication history)
cp .ingested_checksums .ingested_checksums.backup
cp .ingestion_stats.json .ingestion_stats.json.backup

# 2. Reset Qdrant (DESTRUCTIVE - deletes all data)
./scripts/reset-qdrant.sh
# Confirm when prompted

# 3. Verify clean state
./scripts/qdrant-stats.sh
# Should show no collections

# 4. If you want fresh deduplication tracking, remove checksums
rm .ingested_checksums

# 5. Re-ingest everything
./scripts/ingest-all-pdfs.sh
# Or
./scripts/ingest-by-directory.sh ./ingest

# 6. Verify restoration
./scripts/verify-collections.sh
./scripts/qdrant-stats.sh

# 7. Test queries
./scripts/query-rag.sh "test query"

# 8. Rebuild dashboard
./scripts/build-dashboard.sh
```

### Partial Recovery

**Reset single collection:**
```bash
# Delete specific collection
curl -X DELETE http://localhost:6333/collections/problem-collection

# Recreate it
./scripts/setup-collection.sh problem-collection "Fixed Collection"

# Re-ingest just that topic
RAG_COLLECTION=problem-collection ./scripts/ingest-pdf-smart.sh ingest/*.pdf
```

---

## 8. Adding New Documents Weekly

**Scenario:** You have a weekly workflow where new papers/docs arrive and need to be added to your existing knowledge base.

### Step-by-Step

**Week 1 - Initial Setup:**
```bash
./scripts/setup-qdrant.sh
./scripts/build-all.sh
./scripts/ingest-by-directory.sh ./ingest
```

**Week 2 - Add New Documents:**
```bash
# 1. Download/receive new documents
# Say you get 5 new ML papers

# 2. Add to appropriate directory
mv ~/Downloads/new-paper-1.pdf ingest/deep-learning/
mv ~/Downloads/new-paper-2.pdf ingest/nlp/
mv ~/Downloads/new-paper-3.pdf ingest/nlp/
mv ~/Downloads/new-paper-4.pdf ingest/computer-vision/
mv ~/Downloads/new-paper-5.pdf ingest/reinforcement-learning/

# 3. Re-run ingestion (automatically skips existing files via checksums)
./scripts/ingest-by-directory.sh ./ingest

# Expected output:
# - Skipping: attention-is-all-you-need.pdf (already processed)
# - Processing: new-paper-1.pdf ✓
# - Processing: new-paper-2.pdf ✓
# - Skipping: resnet.pdf (already processed)
# ...

# 4. Verify new documents added
./scripts/qdrant-stats.sh
# Vector count should have increased

# 5. Test with query about new content
./scripts/query-rag.sh "topic from new paper"
```

**Week 3 - Same Process:**
```bash
# Add new docs to ingest directories
mv ~/Downloads/weekly-papers/*.pdf ingest/appropriate-topic/

# Re-run (deduplication is automatic)
./scripts/ingest-by-directory.sh ./ingest

# Verify
./scripts/qdrant-stats.sh
```

### Automation Script

Create `weekly-update.sh`:
```bash
#!/bin/bash
# Place in project root

set -e

echo "=== Weekly RAG Update ==="
echo "Date: $(date)"

# Check for new files
NEW_FILES=$(find ingest/ -name "*.pdf" -mtime -7 | wc -l)
echo "New PDFs in last 7 days: $NEW_FILES"

if [ "$NEW_FILES" -eq 0 ]; then
  echo "No new documents to process"
  exit 0
fi

# Show new files
echo "New documents:"
find ingest/ -name "*.pdf" -mtime -7 -exec basename {} \;

# Ingest
echo ""
echo "Starting ingestion..."
./scripts/ingest-by-directory.sh ./ingest

# Stats
echo ""
echo "Updated statistics:"
./scripts/qdrant-stats.sh

# Test query
echo ""
echo "Testing query..."
./scripts/query-rag.sh "test query" > /dev/null && echo "✓ System operational"

echo ""
echo "=== Update Complete ==="
```

Usage:
```bash
chmod +x weekly-update.sh
./weekly-update.sh
```

---

## 9. Web Dashboard for Non-Technical Users

**Scenario:** You want to provide access to the RAG system for team members who aren't comfortable with command line.

### Step-by-Step

```bash
# 1. Ensure everything is ingested
./scripts/verify-collections.sh

# 2. Add friendly collection names
./scripts/update-collection-alias.sh rust-books "Rust Programming Guides"
./scripts/update-collection-alias.sh python-books "Python Documentation"
./scripts/update-collection-alias.sh javascript-books "JavaScript References"

# 3. Build and start dashboard
./scripts/serve-dashboard.sh

# Dashboard runs at: http://localhost:8080

# 4. For remote access (same network):
# Find server IP
ifconfig | grep inet

# Share URL with team: http://your-ip:8080
```

### Dashboard User Guide

Share this with your users:

```
Using the RAG Demo Dashboard
============================

1. Open: http://your-server:8080

2. Select Collection:
   - "Rust Programming Guides" for Rust questions
   - "Python Documentation" for Python questions
   - etc.

3. Enter Your Question:
   - Be specific: "How does Rust handle memory safety?"
   - Not: "memory"

4. View Results:
   - Ranked by relevance (score)
   - Click source to see which document

5. System Status (bottom):
   - Green = working
   - Red = service down (contact admin)
```

### Remote Access Setup

**Option 1: SSH Tunnel (Secure)**
```bash
# On remote machine:
ssh -L 8080:localhost:8080 user@server

# Then open: http://localhost:8080
```

**Option 2: Reverse Proxy (Production)**
```bash
# Install nginx
sudo apt install nginx

# Configure (in /etc/nginx/sites-available/rag-demo):
server {
    listen 80;
    server_name rag.yourcompany.com;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}

# Enable and restart
sudo ln -s /etc/nginx/sites-available/rag-demo /etc/nginx/sites-enabled/
sudo systemctl restart nginx
```

---

## 10. Comparing Different Chunking Strategies

**Scenario:** You want to experiment with different ingestion strategies to see which gives better results.

### Step-by-Step

```bash
# 1. Start fresh for clean comparison
./scripts/reset-qdrant.sh

# 2. Create test collections
./scripts/setup-collection.sh test-hierarchical "Hierarchical Chunking"
./scripts/setup-collection.sh test-simple "Simple Chunking"
./scripts/setup-collection.sh test-markdown "Markdown-Aware Chunking"

# 3. Ingest same document with different strategies

# Test document
TEST_DOC="ingest/sample-book.pdf"

# Strategy 1: Hierarchical (recommended)
RAG_COLLECTION=test-hierarchical ./scripts/ingest-pdf-smart.sh "$TEST_DOC"

# Strategy 2: Simple (legacy)
./target/release/pdf-to-embeddings \
  --collection test-simple \
  --chunk-size 1000 \
  --overlap 200 \
  "$TEST_DOC"

# Strategy 3: Markdown-aware
./scripts/pdf-to-markdown.sh "$TEST_DOC" ./extracted/
RAG_COLLECTION=test-markdown ./target/release/ingest-markdown \
  ./extracted/sample-book.md

# 4. Compare vector counts
echo "=== Hierarchical ===" && \
curl -s http://localhost:6333/collections/test-hierarchical | jq '.result.vectors_count'

echo "=== Simple ===" && \
curl -s http://localhost:6333/collections/test-simple | jq '.result.vectors_count'

echo "=== Markdown ===" && \
curl -s http://localhost:6333/collections/test-markdown | jq '.result.vectors_count'

# 5. Test same query across all strategies
TEST_QUERY="What are the key concepts?"

echo "=== Hierarchical Results ==="
RAG_COLLECTION=test-hierarchical ./scripts/query-rag.sh "$TEST_QUERY"

echo -e "\n=== Simple Results ==="
RAG_COLLECTION=test-simple ./scripts/query-rag.sh "$TEST_QUERY"

echo -e "\n=== Markdown Results ==="
RAG_COLLECTION=test-markdown ./scripts/query-rag.sh "$TEST_QUERY"

# 6. Performance comparison
echo "=== Performance Comparison ==="
for collection in test-hierarchical test-simple test-markdown; do
  echo "Testing: $collection"
  time RAG_COLLECTION=$collection ./scripts/query-rag.sh "$TEST_QUERY" > /dev/null
done

# 7. Analyze chunk sizes
for collection in test-hierarchical test-simple test-markdown; do
  echo "=== $collection chunk sizes ==="
  curl -s "http://localhost:6333/collections/$collection/points/scroll" \
    -H "Content-Type: application/json" \
    -d '{"limit": 10, "with_payload": true}' \
    | jq '.result.points[].payload.text | length'
done
```

### Results Analysis

Create comparison report:
```bash
# Save results
{
  echo "# Chunking Strategy Comparison"
  echo "Date: $(date)"
  echo ""

  echo "## Vector Counts"
  for c in test-hierarchical test-simple test-markdown; do
    count=$(curl -s http://localhost:6333/collections/$c | jq '.result.vectors_count')
    echo "- $c: $count vectors"
  done

  echo ""
  echo "## Sample Query Results"
  echo "Query: '$TEST_QUERY'"
  echo ""

  for c in test-hierarchical test-simple test-markdown; do
    echo "### $c"
    RAG_COLLECTION=$c ./scripts/query-rag.sh "$TEST_QUERY" | head -20
    echo ""
  done
} > chunking-comparison.md

cat chunking-comparison.md
```

---

## Summary: Quick Reference

### First Time Ever
```bash
./scripts/setup-qdrant.sh
./scripts/build-all.sh
./scripts/health-check.sh
./scripts/ingest-all-pdfs.sh
./scripts/query-rag.sh "test"
```

### Daily Use
```bash
./scripts/interactive-rag.sh
```

### Adding Documents
```bash
cp new.pdf ingest/
./scripts/ingest-all-pdfs.sh
```

### Web Interface
```bash
./scripts/serve-dashboard.sh
```

### Check Status
```bash
./scripts/qdrant-stats.sh
```

### Start Over
```bash
./scripts/reset-qdrant.sh
./scripts/ingest-all-pdfs.sh
```

---

## Next Steps

- [Quick Start Guide](./quick-start.md) - Complete script reference
- [Multi-Collection Guide](./multi-collection-guide.md) - Advanced organization
- [CLAUDE.md](../CLAUDE.md) - Development and architecture
- [Main README](../README.md) - Project overview
