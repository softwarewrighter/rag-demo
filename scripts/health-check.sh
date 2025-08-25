#!/bin/bash

# Health check for RAG system components

echo "🏥 RAG System Health Check"
echo "=========================="
echo ""

ERRORS=0

# Check Docker
echo -n "Docker:        "
if command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        echo "✅ Running"
    else
        echo "❌ Not running (start Docker Desktop)"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "❌ Not installed (brew install --cask docker)"
    ERRORS=$((ERRORS + 1))
fi

# Check Qdrant
echo -n "Qdrant:        "
if curl -s http://localhost:6333/collections > /dev/null 2>&1; then
    echo "✅ Running on port 6333"
    
    # Check collections
    COLLECTIONS=$(curl -s http://localhost:6333/collections | jq -r '.result.collections[].name' 2>/dev/null)
    if [ ! -z "$COLLECTIONS" ]; then
        echo "  Collections: $COLLECTIONS"
        
        # Check document count in 'documents' collection
        if echo "$COLLECTIONS" | grep -q "documents"; then
            COUNT=$(curl -s http://localhost:6333/collections/documents | jq -r '.result.points_count' 2>/dev/null || echo "0")
            echo "  Documents:   $COUNT vectors stored"
        fi
    else
        echo "  Collections: None"
    fi
else
    echo "❌ Not running (run ./scripts/setup-qdrant.sh)"
    ERRORS=$((ERRORS + 1))
fi

# Check Ollama
echo -n "Ollama:        "
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "✅ Running on port 11434"
    
    # Check models
    MODELS=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')
    if [ ! -z "$MODELS" ]; then
        echo "  Models:      $MODELS"
    else
        echo "  Models:      None installed"
    fi
    
    # Check for required embedding model
    if ! echo "$MODELS" | grep -q "nomic-embed-text"; then
        echo "  ⚠️  Missing embedding model (run: ollama pull nomic-embed-text)"
    fi
else
    echo "❌ Not running (run: ollama serve)"
    ERRORS=$((ERRORS + 1))
fi

# Check Rust tools
echo -n "Rust Tools:    "
if [ -f "target/release/pdf-to-embeddings" ] && [ -f "target/release/search-qdrant" ]; then
    echo "✅ Built"
else
    echo "⚠️  Not built (will build on first use)"
fi

# Check jq (required for scripts)
echo -n "jq:            "
if command -v jq &> /dev/null; then
    echo "✅ Installed"
else
    echo "❌ Not installed (brew install jq)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "=========================="

if [ $ERRORS -eq 0 ]; then
    echo "✨ All systems operational!"
    echo ""
    echo "Quick Start:"
    echo "  1. Ingest a PDF:  ./scripts/ingest-pdf.sh document.pdf"
    echo "  2. Query the RAG: ./scripts/query-rag.sh 'your question'"
else
    echo "⚠️  Found $ERRORS issue(s). Please resolve before using the system."
fi