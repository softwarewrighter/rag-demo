#!/bin/bash

# Concatenate all source files in the repository into a single markdown file
# Each file is prefixed with its path as a header
# Output: project.md (markdown format for hierarchical ingestion)

set -e

OUTPUT_FILE="${1:-project.md}"
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "🔍 Concatenating source files from: $PROJECT_ROOT"
echo "📄 Output: $OUTPUT_FILE"
echo ""

# Create header for the project file
cat > "$OUTPUT_FILE" << 'EOF'
# RAG Demo Project Source Code

This document contains all source files from the rag-demo repository,
a local RAG (Retrieval-Augmented Generation) system using Qdrant and Ollama.

EOF

# Track statistics
total_files=0
total_lines=0

# Function to add a file with its path header
add_file() {
    local filepath="$1"
    local relative_path="${filepath#$PROJECT_ROOT/}"
    local extension="${filepath##*.}"

    # Skip binary/generated files
    case "$relative_path" in
        target/*|node_modules/*|.git/*|*.lock|*.png|*.jpg|*.pdf|*.woff*|*.ttf)
            return
            ;;
    esac

    # Skip large generated files
    if [ -f "$filepath" ]; then
        local size=$(wc -c < "$filepath")
        if [ "$size" -gt 100000 ]; then
            echo "  ⏭️  Skipping large file: $relative_path ($size bytes)"
            return
        fi
    fi

    # Determine code fence language
    local lang=""
    case "$extension" in
        rs) lang="rust" ;;
        sh) lang="bash" ;;
        py) lang="python" ;;
        js) lang="javascript" ;;
        ts) lang="typescript" ;;
        json) lang="json" ;;
        toml) lang="toml" ;;
        yaml|yml) lang="yaml" ;;
        md) lang="markdown" ;;
        html) lang="html" ;;
        css) lang="css" ;;
        *) lang="" ;;
    esac

    echo "  ✓ $relative_path"

    # Add file header and content
    echo "" >> "$OUTPUT_FILE"
    echo "## $relative_path" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    if [ -n "$lang" ]; then
        echo "\`\`\`$lang" >> "$OUTPUT_FILE"
    else
        echo "\`\`\`" >> "$OUTPUT_FILE"
    fi

    cat "$filepath" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "\`\`\`" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    total_files=$((total_files + 1))
    local lines=$(wc -l < "$filepath")
    total_lines=$((total_lines + lines))
}

# Add Rust source files
echo "📦 Rust source files:"
for f in "$PROJECT_ROOT"/src/*.rs; do
    [ -f "$f" ] && add_file "$f"
done

# Add shell scripts
echo ""
echo "📜 Shell scripts:"
for f in "$PROJECT_ROOT"/scripts/*.sh; do
    [ -f "$f" ] && add_file "$f"
done

# Add configuration files
echo ""
echo "⚙️  Configuration files:"
for f in "$PROJECT_ROOT"/Cargo.toml "$PROJECT_ROOT"/CLAUDE.md "$PROJECT_ROOT"/README.md; do
    [ -f "$f" ] && add_file "$f"
done

# Add documentation
echo ""
echo "📚 Documentation:"
for f in "$PROJECT_ROOT"/documentation/*.md; do
    [ -f "$f" ] && add_file "$f"
done

# Add dashboard source
echo ""
echo "🖥️  Dashboard files:"
for f in "$PROJECT_ROOT"/dashboard/*.html "$PROJECT_ROOT"/dashboard/*.js "$PROJECT_ROOT"/dashboard/*.css; do
    [ -f "$f" ] && add_file "$f"
done

# Summary
echo ""
echo "════════════════════════════════════════"
echo "📊 Summary:"
echo "   Files: $total_files"
echo "   Lines: $total_lines"
output_size=$(wc -c < "$OUTPUT_FILE")
echo "   Output size: $output_size bytes"
echo "   Output file: $OUTPUT_FILE"
echo ""
echo "✅ Done! Ready for ingestion with:"
echo "   ./target/release/ingest-hierarchical $OUTPUT_FILE --collection project-source"
