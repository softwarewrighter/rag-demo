# Data Flow Diagrams

> **Copyright © 2025 Michael A. Wright** | Licensed under the [MIT License](../LICENSE)

## Table of Contents
- [PDF Ingestion Flow](#pdf-ingestion-flow)
- [Hierarchical Chunking Flow](#hierarchical-chunking-flow)
- [Query Processing Flow](#query-processing-flow)
- [Hybrid Search Flow](#hybrid-search-flow)
- [Collection Export Flow](#collection-export-flow)
- [Collection Import Flow](#collection-import-flow)
- [Deduplication Flow](#deduplication-flow)

## PDF Ingestion Flow

### Single PDF Ingestion (Hierarchical)

```mermaid
sequenceDiagram
    participant User
    participant Script as ingest-pdf-smart.sh
    participant PDF as pdftotext
    participant IH as ingest-hierarchical
    participant Ollama
    participant Qdrant
    participant FS as Filesystem

    User->>Script: ./ingest-pdf-smart.sh doc.pdf
    Script->>FS: Check .ingested_checksums
    alt Already ingested
        FS-->>Script: Checksum exists
        Script-->>User: Skipping (already ingested)
    else New document
        Script->>PDF: pdftotext -layout doc.pdf
        PDF->>FS: Write markdown to ./extracted/
        Script->>IH: Launch with markdown file

        IH->>IH: Read markdown content
        IH->>IH: Hierarchical chunking (parent ~3500, child ~750)

        loop For each child chunk
            IH->>Ollama: POST /api/embeddings {model: nomic-embed-text, prompt: chunk}
            Ollama-->>IH: {embedding: [768 floats]}
        end

        IH->>Qdrant: Check collection exists
        alt Collection missing
            IH->>Qdrant: Create collection (768 dims, Cosine, HNSW)
        end

        IH->>Qdrant: Upsert points batch (vectors + metadata)
        Qdrant-->>IH: Success

        IH->>FS: Update .ingested_checksums SHA256|path|count|timestamp
        IH-->>Script: Ingestion complete
        Script-->>User: ✅ Success (N chunks ingested)
    end
```

### Bulk Ingestion with Deduplication

```mermaid
sequenceDiagram
    participant User
    participant Script as ingest-all-pdfs.sh
    participant FS as Filesystem
    participant Ingest as ingest-hierarchical

    User->>Script: ./ingest-all-pdfs.sh
    Script->>FS: Read .ingested_checksums
    Script->>FS: List ./ingest/*.pdf

    loop For each PDF
        Script->>Script: Compute SHA-256
        alt Already in checksums
            Script->>User: Skipping (already ingested)
        else New or modified
            Script->>Ingest: Process PDF
            Ingest-->>Script: Success
            Script->>FS: Append to checksums
            Script->>User: ✅ Ingested
        end
    end

    Script->>FS: Write .ingestion_stats.json
    Script-->>User: Bulk ingestion complete X new, Y skipped
```

## Hierarchical Chunking Flow

### Parent-Child Chunk Creation

```mermaid
flowchart TD
    Start[Markdown Document] --> Read[Read Full Content]
    Read --> Parent[Create Parent Chunks ~3500 chars]

    Parent --> P1[Parent Chunk 1]
    Parent --> P2[Parent Chunk 2]
    Parent --> PN[Parent Chunk N]

    P1 --> C1[Child Chunk 1.1 ~750 chars]
    P1 --> C2[Child Chunk 1.2 ~750 chars]
    P1 --> C3[Child Chunk 1.3 ~750 chars]

    P2 --> C4[Child Chunk 2.1]
    P2 --> C5[Child Chunk 2.2]

    C1 --> E1[Generate Embedding]
    C2 --> E2[Generate Embedding]
    C3 --> E3[Generate Embedding]
    C4 --> E4[Generate Embedding]
    C5 --> E5[Generate Embedding]

    E1 --> Q1[Store in Qdrant Payload: text, parent_id, source]
    E2 --> Q2[Store in Qdrant Payload: text, parent_id, source]
    E3 --> Q3[Store in Qdrant Payload: text, parent_id, source]
    E4 --> Q4[Store in Qdrant Payload: text, parent_id, source]
    E5 --> Q5[Store in Qdrant Payload: text, parent_id, source]

    style P1 fill:#3498db
    style P2 fill:#3498db
    style C1 fill:#2ecc71
    style C2 fill:#2ecc71
    style C3 fill:#2ecc71
    style C4 fill:#2ecc71
    style C5 fill:#2ecc71
```

## Query Processing Flow

### Basic RAG Query

```mermaid
sequenceDiagram
    participant User
    participant Script as query-rag.sh
    participant Search as search-hierarchical
    participant Ollama
    participant Qdrant

    User->>Script: ./query-rag.sh "What is Rust?"
    Script->>Search: Execute with query

    Search->>Ollama: POST /api/embeddings {model: nomic-embed-text, prompt: query}
    Ollama-->>Search: {embedding: [768 floats]}

    Search->>Qdrant: POST /collections/{name}/points/search {vector: [...], limit: 5}
    Qdrant-->>Search: Top 5 similar chunks (with scores & metadata)

    Search->>Search: Extract text from results
    Search-->>Script: JSON results with context

    Script->>Script: Build RAG prompt: "Context: [...]\nQuestion: [...]"

    Script->>Ollama: POST /api/generate {model: llama3.2, prompt: rag_prompt}
    Ollama-->>Script: Streaming response

    Script-->>User: 📝 Answer with sources ⏱️ Search: 67ms 🤖 Generation: 3.2s
```

### Interactive RAG Session

```mermaid
sequenceDiagram
    participant User
    participant Script as interactive-rag.sh
    participant Search as search-hierarchical
    participant Ollama
    participant Qdrant

    User->>Script: ./interactive-rag.sh
    Script->>Script: Initialize session stats
    Script->>User: 🤖 RAG Chat (type 'quit' to exit)

    loop Chat Session
        User->>Script: Enter query

        alt Special command
            User->>Script: stats
            Script-->>User: 📊 Session statistics Queries: N, Avg time: Xms
        else Regular query
            Script->>Search: Execute search
            Search->>Ollama: Get query embedding
            Ollama-->>Search: Embedding
            Search->>Qdrant: Vector search
            Qdrant-->>Search: Results
            Search-->>Script: Context chunks

            Script->>Ollama: Generate answer
            Ollama-->>Script: Response

            Script->>Script: Update session stats
            Script-->>User: Answer + metrics
        end
    end

    User->>Script: quit
    Script-->>User: 👋 Goodbye! (session summary)
```

## Hybrid Search Flow

### Vector + Keyword Search

```mermaid
sequenceDiagram
    participant User
    participant Script as hybrid-search.sh
    participant HS as hybrid-search
    participant Ollama
    participant Qdrant

    User->>Script: ./hybrid-search.sh "rust macros" -v 0.7 -k 0.3 --filter is_code=true
    Script->>HS: Execute with params

    par Vector Search
        HS->>Ollama: Generate embedding
        Ollama-->>HS: Vector [768]
        HS->>Qdrant: Vector search (with metadata filter)
        Qdrant-->>HS: Vector results + scores
    and Keyword Search
        HS->>HS: Tokenize query: ["rust", "macros"]
        HS->>Qdrant: Fetch all matching filter
        HS->>HS: Compute BM25 scores
    end

    HS->>HS: Normalize scores (0-1)
    HS->>HS: Blend: score = 0.7*vec + 0.3*kw
    HS->>HS: Sort by blended score
    HS->>HS: Top K results

    HS-->>Script: Hybrid results
    Script-->>User: 📊 Results with scores Vector: X%, Keyword: Y%
```

### Keyword Scoring Algorithm

```mermaid
flowchart TD
    Start[Query: rust macros] --> Tokenize[Tokenize query]
    Tokenize --> Terms[Terms: rust, macros]

    Terms --> Fetch[Fetch documents matching filter]
    Fetch --> Docs[Document Set]

    Docs --> BM25[Compute BM25 Scores]

    BM25 --> TF[Term Frequency tf = count / total_terms]
    BM25 --> IDF[Inverse Doc Frequency idf = log(N / df)]

    TF --> Calc[BM25 Formula: sum over terms]
    IDF --> Calc

    Calc --> Norm[Normalize to 0-1]
    Norm --> Blend[Blend with vector scores]
    Blend --> Result[Final ranked results]

    style BM25 fill:#9b59b6
    style Blend fill:#e74c3c
```

## Collection Export Flow

```mermaid
sequenceDiagram
    participant User
    participant Script as export-collection.sh
    participant Export as export-collection
    participant Qdrant
    participant FS as Filesystem

    User->>Script: ./export-collection.sh python-books --include-vectors --pretty
    Script->>Export: Execute with params

    Export->>Qdrant: GET /collections/python-books
    Qdrant-->>Export: Collection info (count, config)

    Export->>Export: Calculate batch size (limit: 100 per batch)

    loop For each batch (offset += 100)
        Export->>Qdrant: POST /collections/python-books/points/scroll {limit: 100, offset: X, with_vector: true}
        Qdrant-->>Export: Batch of points
        Export->>Export: Append to JSON structure
    end

    Export->>Export: Build metadata: - Collection config - Export timestamp - Point count

    Export->>FS: Write exports/python-books.json (pretty formatted)
    FS-->>Export: Success

    Export-->>Script: Export complete
    Script-->>User: ✅ Exported N points 📁 exports/python-books.json
```

## Collection Import Flow

```mermaid
sequenceDiagram
    participant User
    participant Script as import-collection.sh
    participant Import as import-collection
    participant FS as Filesystem
    participant Qdrant

    User->>Script: ./import-collection.sh exports/python-books.json
    Script->>Import: Execute with file path

    Import->>FS: Read JSON file
    FS-->>Import: Collection data + metadata

    Import->>Import: Validate JSON structure
    Import->>Import: Check vectors present

    alt Vectors missing
        Import-->>User: ❌ Error: No vectors in export
    else Vectors present
        Import->>Qdrant: Check collection exists

        alt Collection exists & no --force
            Import-->>User: ❌ Error: Collection exists
        else Create or force merge
            alt Collection missing
                Import->>Qdrant: Create collection (match exported config)
            end

            Import->>Import: Batch points (100 per batch)

            loop For each batch
                Import->>Qdrant: PUT /collections/{name}/points {points: [...]}
                Qdrant-->>Import: Success
            end

            Import->>Qdrant: Verify point count
            Qdrant-->>Import: Collection stats

            Import-->>Script: Import complete
            Script-->>User: ✅ Imported N points Collection: {name}
        end
    end
```

## Deduplication Flow

### SHA-256 Checksum System

```mermaid
flowchart TD
    Start[New PDF: doc.pdf] --> Compute[Compute SHA-256 hash]
    Compute --> Read[Read .ingested_checksums]

    Read --> Check{Hash exists?}

    Check -->|Yes| GetInfo[Extract: filename, count, timestamp]
    GetInfo --> Compare{Same file?}

    Compare -->|Yes| Skip[Skip ingestion]
    Compare -->|No| Warn[⚠️ Collision detected Different files, same hash]

    Check -->|No| Ingest[Proceed with ingestion]
    Ingest --> Process[Process PDF → Chunks → Embeddings]
    Process --> Store[Store in Qdrant]
    Store --> Record[Append to .ingested_checksums]

    Record --> Format["Format: hash|filepath|chunk_count|timestamp"]
    Format --> Write[Write to file]
    Write --> Done[✅ Complete]

    Skip --> Done
    Warn --> Done

    style Skip fill:#f39c12
    style Ingest fill:#2ecc71
    style Warn fill:#e74c3c
```

### Checksum File Format

```
# .ingested_checksums format
# SHA256|filepath|chunk_count|timestamp

e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855|ingest/rust-book.pdf|342|2025-11-17T10:23:45
a1b2c3d4e5f6789012345678901234567890123456789012345678901234567890|ingest/javascript-guide.pdf|187|2025-11-17T10:25:12
```

## Multi-Collection Ingestion Flow

### Directory-Based Organization

```mermaid
sequenceDiagram
    participant User
    participant Script as ingest-by-directory.sh
    participant IBD as ingest-by-directory
    participant Ollama
    participant Qdrant

    User->>Script: ./ingest-by-directory.sh ./ingest
    Script->>Script: Scan directory structure

    Note over Script: ./ingest/rust/*.pdf → rust-books ./ingest/python/*.pdf → python-books ./ingest/javascript/*.pdf → javascript-books

    loop For each subdirectory
        Script->>IBD: Process directory → collection

        IBD->>Qdrant: Create collection: rust-books

        loop For each PDF in subdir
            IBD->>IBD: Extract text
            IBD->>IBD: Hierarchical chunking

            loop For each chunk
                IBD->>Ollama: Generate embedding
                Ollama-->>IBD: Vector
            end

            IBD->>Qdrant: Upsert points batch
        end

        IBD-->>Script: Collection complete
        Script-->>User: ✅ rust-books: 342 chunks
    end

    Script-->>User: 🎉 All collections created 3 collections, 876 total chunks
```

## Performance Metrics Flow

### Query Latency Breakdown

```mermaid
gantt
    title RAG Query Latency Breakdown (Typical)
    dateFormat X
    axisFormat %L ms

    section Query Processing
    Query embedding generation: 0, 150
    Vector search in Qdrant: 150, 80
    Context assembly: 230, 20

    section LLM Generation
    LLM prompt processing: 250, 500
    Token generation: 750, 2500
    Response streaming: 3250, 250

    section Total
    End-to-end: 0, 3500
```

### Indexing Performance

```mermaid
flowchart LR
    subgraph "No Index"
        V1[Vectors: 50]
        S1[Search: Linear O n]
        T1[Time: ~150ms]
    end

    subgraph "HNSW Index"
        V2[Vectors: 5000]
        S2[Search: HNSW O log n]
        T2[Time: ~70ms]
    end

    V1 --> Threshold[Threshold: 100 vectors]
    Threshold --> V2

    style V2 fill:#2ecc71
    style T2 fill:#2ecc71
```

## Related Documentation

- [Architecture Overview](Architecture-Overview) - High-level system design
- [Rust Components](Rust-Components) - Component implementation details
- [Database Schema](Database-Schema) - Qdrant data structures
- [Query Processing](Query-Processing) - Search algorithms in detail
- [Ingestion Workflows](Ingestion-Workflows) - Complete ingestion processes

---

**Last Updated**: 2025-11-17
**Related**: [Home](Home) | [Architecture](Architecture-Overview) | [Components](Rust-Components)
