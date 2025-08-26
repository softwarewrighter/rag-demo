#!/bin/bash

# Simple wrapper for the Rust directory ingestion tool

set -e

# Build if needed
if [ ! -f "target/release/ingest-by-directory" ]; then
    echo "🔨 Building ingestion tool..."
    cargo build --release --bin ingest-by-directory
fi

# Run the Rust tool
./target/release/ingest-by-directory "$@"