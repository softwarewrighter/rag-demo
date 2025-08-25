#!/bin/bash

# Convert PDF to Markdown for better text extraction
# Preserves code blocks and document structure

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PDF_FILE="$1"
OUTPUT_DIR="${2:-./extracted}"

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <pdf-file> [output-dir]"
    echo "Example: $0 document.pdf ./extracted"
    exit 1
fi

if [ ! -f "$PDF_FILE" ]; then
    echo -e "${RED}❌ File not found: $PDF_FILE${NC}"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get base filename
BASENAME=$(basename "$PDF_FILE" .pdf)
MD_FILE="$OUTPUT_DIR/${BASENAME}.md"

echo -e "${CYAN}📄 PDF to Markdown Converter${NC}"
echo "════════════════════════════════════════"
echo "Input: $PDF_FILE"
echo "Output: $MD_FILE"
echo ""

# Method 1: Try marker (AI-powered PDF to MD converter)
if command -v marker &> /dev/null; then
    echo -e "${GREEN}Using marker (AI-powered)...${NC}"
    marker "$PDF_FILE" "$OUTPUT_DIR" --parallel_factor 2
    
elif command -v pandoc &> /dev/null; then
    # Method 2: Try pandoc
    echo -e "${YELLOW}Using pandoc...${NC}"
    pandoc -f pdf -t markdown -o "$MD_FILE" "$PDF_FILE" 2>/dev/null || {
        echo -e "${YELLOW}Pandoc failed, trying alternative...${NC}"
    }
    
elif command -v pdftotext &> /dev/null; then
    # Method 3: pdftotext then format
    echo -e "${YELLOW}Using pdftotext with formatting...${NC}"
    TEMP_TXT="$OUTPUT_DIR/${BASENAME}_temp.txt"
    pdftotext -layout "$PDF_FILE" "$TEMP_TXT"
    
    # Basic formatting: detect code blocks and headers
    python3 - "$TEMP_TXT" "$MD_FILE" << 'EOF'
import sys
import re

def text_to_markdown(input_file, output_file):
    with open(input_file, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    
    output = []
    in_code = False
    code_buffer = []
    blank_lines = 0
    
    for line in lines:
        stripped = line.strip()
        
        # Detect potential headers
        if stripped and len(stripped) < 80 and stripped.isupper():
            # Close any open code block first
            if in_code and code_buffer:
                code_buffer.append("```\n\n")
                output.extend(code_buffer)
                code_buffer = []
                in_code = False
            output.append(f"\n## {stripped.title()}\n")
            continue
            
        # Detect code blocks - must have consistent indentation of 4+ spaces
        # or contain clear Rust syntax markers
        is_code_line = (
            re.match(r'^    \s*\S', line) or  # 4+ space indent with content
            re.search(r'^\s*(fn |impl |struct |enum |trait |macro_rules!|use |pub |let |const |static |mod |match |if |for |while |loop )', line)
        )
        
        if is_code_line:
            if not in_code:
                in_code = True
                code_buffer = ["```rust\n"]
                blank_lines = 0
            code_buffer.append(line.rstrip() + '\n')
        elif in_code:
            # Handle blank lines within code blocks
            if not stripped:
                blank_lines += 1
                # Allow up to 2 blank lines within code blocks
                if blank_lines <= 2:
                    code_buffer.append('\n')
                else:
                    # Too many blank lines, end the code block
                    code_buffer.append("```\n\n")
                    output.extend(code_buffer)
                    code_buffer = []
                    in_code = False
                    blank_lines = 0
            else:
                # Non-code line encountered, close the code block
                code_buffer.append("```\n\n")
                output.extend(code_buffer)
                code_buffer = []
                in_code = False
                blank_lines = 0
                # Process this line as regular text
                output.append(line.rstrip() + '\n')
        else:
            # Regular text
            if stripped or not output or not output[-1].endswith('\n\n'):
                output.append(line.rstrip() + '\n')
    
    # Close any open code block
    if in_code and code_buffer:
        code_buffer.append("```\n")
        output.extend(code_buffer)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        f.writelines(output)
    
    print(f"Converted to: {output_file}")

text_to_markdown(sys.argv[1], sys.argv[2])
EOF
    
    rm -f "$TEMP_TXT"
    
else
    # Method 4: Use our Rust tool but format as markdown
    echo -e "${YELLOW}Using pdf-extract with markdown formatting...${NC}"
    
    if [ ! -f "target/release/pdf-to-embeddings" ]; then
        cargo build --release --bin pdf-to-embeddings 2>/dev/null
    fi
    
    # Extract text using our tool
    pdf-extract "$PDF_FILE" 2>/dev/null > "$MD_FILE" || {
        echo -e "${RED}❌ All extraction methods failed${NC}"
        echo "Consider installing one of:"
        echo "  • marker (pip install marker-pdf)"
        echo "  • pandoc (brew install pandoc)"
        echo "  • pdftotext (brew install poppler)"
        exit 1
    }
fi

# Post-process to ensure proper markdown formatting
if [ -f "$MD_FILE" ]; then
    # Count code blocks and headers
    CODE_BLOCKS=$(grep -c '```' "$MD_FILE" 2>/dev/null || echo "0")
    HEADERS=$(grep -c '^#' "$MD_FILE" 2>/dev/null || echo "0")
    FILE_SIZE=$(ls -lh "$MD_FILE" | awk '{print $5}')
    
    echo ""
    echo -e "${GREEN}✅ Conversion complete!${NC}"
    echo "  Output: $MD_FILE"
    echo "  Size: $FILE_SIZE"
    echo "  Headers: $HEADERS"
    echo "  Code blocks: $((CODE_BLOCKS / 2))"
    
    # Preview
    echo ""
    echo -e "${CYAN}Preview (first 20 lines):${NC}"
    echo "────────────────────────────────────────"
    head -20 "$MD_FILE"
    echo "────────────────────────────────────────"
else
    echo -e "${RED}❌ Conversion failed${NC}"
    exit 1
fi