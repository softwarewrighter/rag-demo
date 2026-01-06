#!/bin/bash
# strip-gutenberg.sh - Remove Project Gutenberg header/footer boilerplate from text files
#
# Project Gutenberg files contain license text and transcriber notes at the
# beginning and end. This script extracts only the actual book content.
#
# Usage:
#   ./scripts/strip-gutenberg.sh input.txt [output.txt]
#   ./scripts/strip-gutenberg.sh input.txt              # outputs to input-clean.txt
#   ./scripts/strip-gutenberg.sh input.txt -            # outputs to stdout
#
# Markers recognized:
#   Start: "*** START OF THE PROJECT GUTENBERG EBOOK" (or THIS PROJECT GUTENBERG EBOOK)
#   End:   "*** END OF THE PROJECT GUTENBERG EBOOK" (or THIS PROJECT GUTENBERG EBOOK)

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <input.txt> [output.txt | -]" >&2
    echo "  If output is '-', writes to stdout" >&2
    echo "  If output is omitted, writes to <input>-clean.txt" >&2
    exit 1
fi

INPUT_FILE="$1"

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file not found: $INPUT_FILE" >&2
    exit 1
fi

# Determine output destination
if [[ $# -ge 2 ]]; then
    if [[ "$2" == "-" ]]; then
        OUTPUT_FILE="/dev/stdout"
    else
        OUTPUT_FILE="$2"
    fi
else
    # Default: input-clean.txt
    BASENAME="${INPUT_FILE%.txt}"
    OUTPUT_FILE="${BASENAME}-clean.txt"
fi

# Create temp file for processing
TEMP_FILE=$(mktemp)
trap "rm -f '$TEMP_FILE'" EXIT

# Find line numbers for start and end markers
# Gutenberg uses variations like:
#   *** START OF THE PROJECT GUTENBERG EBOOK ...
#   *** START OF THIS PROJECT GUTENBERG EBOOK ...
START_LINE=$(grep -n -i -m 1 '\*\*\* START OF \(THE\|THIS\) PROJECT GUTENBERG' "$INPUT_FILE" | cut -d: -f1 || echo "")
END_LINE=$(grep -n -i '\*\*\* END OF \(THE\|THIS\) PROJECT GUTENBERG' "$INPUT_FILE" | tail -1 | cut -d: -f1 || echo "")

if [[ -z "$START_LINE" ]]; then
    echo "Warning: No Gutenberg start marker found, copying entire file" >&2
    cp "$INPUT_FILE" "$TEMP_FILE"
else
    if [[ -z "$END_LINE" ]]; then
        echo "Warning: No Gutenberg end marker found, stripping only header" >&2
        # Skip from start marker line + 1 to end of file
        tail -n +"$((START_LINE + 1))" "$INPUT_FILE" > "$TEMP_FILE"
    else
        # Extract content between markers (exclusive of marker lines)
        TOTAL_LINES=$(wc -l < "$INPUT_FILE")
        CONTENT_START=$((START_LINE + 1))
        CONTENT_END=$((END_LINE - 1))

        if [[ $CONTENT_END -lt $CONTENT_START ]]; then
            echo "Error: End marker appears before start marker" >&2
            exit 1
        fi

        sed -n "${CONTENT_START},${CONTENT_END}p" "$INPUT_FILE" > "$TEMP_FILE"
    fi
fi

# Remove leading/trailing blank lines from extracted content
# Use awk for cross-platform compatibility (works on both Linux and macOS)
awk '
    NF {p=1}           # Set flag when we hit non-blank line
    p {lines[++n]=$0}  # Store lines once flag is set
    END {
        # Find last non-blank line
        for (i=n; i>=1; i--) {
            if (lines[i] ~ /[^ \t]/) {
                last=i
                break
            }
        }
        # Print from first to last non-blank
        for (i=1; i<=last; i++) print lines[i]
    }
' "$TEMP_FILE" > "$TEMP_FILE.trimmed" && mv "$TEMP_FILE.trimmed" "$TEMP_FILE"

# Report stats
ORIGINAL_LINES=$(wc -l < "$INPUT_FILE")
CLEAN_LINES=$(wc -l < "$TEMP_FILE")
REMOVED=$((ORIGINAL_LINES - CLEAN_LINES))

if [[ "$OUTPUT_FILE" != "/dev/stdout" ]]; then
    cp "$TEMP_FILE" "$OUTPUT_FILE"
    echo "Stripped $REMOVED lines of boilerplate from $INPUT_FILE"
    echo "Output: $OUTPUT_FILE ($CLEAN_LINES lines)"
else
    cat "$TEMP_FILE"
fi
