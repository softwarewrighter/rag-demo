#!/bin/bash

# Setup script for Qdrant vector database

set -e

echo "🚀 Setting up Qdrant RAG Server"
echo "================================"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first:"
    echo "   brew install --cask docker"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Docker is not running. Please start Docker Desktop."
    exit 1
fi

echo "✅ Docker is installed and running"

# Check if Qdrant container already exists
if docker ps -a --format '{{.Names}}' | grep -q '^qdrant$'; then
    echo "🔄 Qdrant container already exists"
    
    # Check if it's running
    if docker ps --format '{{.Names}}' | grep -q '^qdrant$'; then
        echo "✅ Qdrant is already running"
    else
        echo "▶️  Starting existing Qdrant container..."
        docker start qdrant
        echo "✅ Qdrant started"
    fi
else
    echo "📦 Pulling Qdrant Docker image..."
    docker pull qdrant/qdrant
    
    echo "🚀 Starting Qdrant container..."
    docker run -d \
        --name qdrant \
        -p 6333:6333 \
        -p 6334:6334 \
        -v $(pwd)/qdrant_storage:/qdrant/storage \
        -e QDRANT__SERVICE__GRPC_PORT="6334" \
        qdrant/qdrant
    
    echo "✅ Qdrant container created and started"
fi

# Wait for Qdrant to be ready
echo "⏳ Waiting for Qdrant to be ready..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:6333/collections > /dev/null 2>&1; then
        echo "✅ Qdrant is ready!"
        break
    fi
    
    attempt=$((attempt + 1))
    if [ $attempt -eq $max_attempts ]; then
        echo "❌ Qdrant failed to start after 30 seconds"
        exit 1
    fi
    
    sleep 1
    echo -n "."
done
echo

# Create default collection for documents
echo "📚 Creating default collection 'documents'..."
curl -s -X PUT "http://localhost:6333/collections/documents" \
    -H "Content-Type: application/json" \
    -d '{
        "vectors": {
            "size": 768,
            "distance": "Cosine"
        }
    }' > /dev/null 2>&1 || echo "Collection might already exist (that's OK)"

# Verify setup
echo ""
echo "🔍 Verifying Qdrant setup..."
response=$(curl -s http://localhost:6333/collections)
if echo "$response" | grep -q '"status":"ok"'; then
    echo "✅ Qdrant REST API is responding at http://localhost:6333"
    echo "✅ Qdrant gRPC API is available at http://localhost:6334"
    echo ""
    echo "📊 Collections:"
    echo "$response" | grep -o '"name":"[^"]*"' | sed 's/"name":"/  - /g' | sed 's/"//g'
else
    echo "⚠️  Qdrant is running but API response was unexpected"
fi

echo ""
echo "✨ Qdrant setup complete!"
echo ""
echo "Next steps:"
echo "  1. Run ./scripts/ingest-pdf.sh <pdf-file> to ingest a PDF"
echo "  2. Run ./scripts/query-rag.sh <query> to search and get answers"
echo "  3. Run ./scripts/health-check.sh to check system status"