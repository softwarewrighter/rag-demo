# RAG Demo - Architecture Documentation

> **Copyright © 2025 Michael A. Wright** | Licensed under the [MIT License](../LICENSE)

Welcome to the RAG Demo architecture documentation wiki! This wiki provides comprehensive technical documentation about the system architecture, components, data flows, and design decisions.

## 📚 Documentation Index

### Core Architecture
- **[Architecture Overview](Architecture-Overview.md)** - High-level system architecture, component diagram, and design principles
- **[Data Flow Diagrams](Data-Flow-Diagrams.md)** - Sequence diagrams for ingestion, query, and search operations
- **[Deployment Architecture](Deployment-Architecture.md)** - System deployment, Docker setup, and infrastructure components

### Component Documentation
- **[Rust Components](Rust-Components.md)** - Detailed documentation of all Rust binaries and their responsibilities
- **[Database Schema](Database-Schema.md)** - Qdrant collection structure, vector configuration, and data model
- **[Chunking Strategies](Chunking-Strategies.md)** - Hierarchical parent-child chunking implementation and research background

### Operations & Workflows
- **[Ingestion Workflows](Ingestion-Workflows.md)** - PDF processing, deduplication, and multi-collection management
- **[Query Processing](Query-Processing.md)** - Search algorithms, hybrid search, and LLM integration
- **[Collection Management](Collection-Management.md)** - Multi-collection architecture and backup/restore operations

## 🎯 Quick Navigation

### For Developers
- Start with [Architecture Overview](Architecture-Overview.md) to understand the system design
- Read [Rust Components](Rust-Components.md) for implementation details
- Check [Data Flow Diagrams](Data-Flow-Diagrams.md) to understand operations

### For DevOps/SRE
- Review [Deployment Architecture](Deployment-Architecture.md) for infrastructure setup
- See [Database Schema](Database-Schema.md) for data persistence
- Consult [Collection Management](Collection-Management.md) for backup strategies

### For Data Scientists
- Understand [Chunking Strategies](Chunking-Strategies.md) for RAG optimization
- Review [Query Processing](Query-Processing.md) for search algorithms
- Check [Ingestion Workflows](Ingestion-Workflows.md) for data preparation

## 🏗️ System Overview

The RAG Demo is a local-first Retrieval-Augmented Generation system built with:

```
┌─────────────────────────────────────────────────────────────┐
│                     RAG Demo System                         │
├─────────────────────────────────────────────────────────────┤
│  PDF Documents → Rust Processing → Qdrant → Ollama → LLM  │
│                                                              │
│  • Local-first (no cloud dependencies)                      │
│  • Hierarchical parent-child chunking                       │
│  • Multi-collection support                                 │
│  • Sub-100ms query latency                                  │
│  • Privacy-preserving (all data local)                      │
└─────────────────────────────────────────────────────────────┘
```

## 🔑 Key Technologies

| Technology | Purpose | Version/Config |
|------------|---------|----------------|
| **Rust** | Core processing binaries | Edition 2021 |
| **Qdrant** | Vector database | Latest (Docker) |
| **Ollama** | LLM inference & embeddings | nomic-embed-text, llama3.2 |
| **Docker** | Container runtime | Qdrant deployment |
| **Bash** | Orchestration scripts | System automation |

## 📐 Architecture Principles

The system is designed around these core principles:

1. **Local-First**: All processing happens on your machine, no cloud dependencies
2. **Privacy-Preserving**: Documents never leave your system
3. **Performance**: Sub-100ms query latency with HNSW indexing
4. **Flexibility**: Multi-collection support for different document types
5. **Reliability**: Deduplication, checksums, and data persistence
6. **Simplicity**: Unix-style tools that do one thing well

## 🚀 Getting Started with Documentation

If you're new to the system:

1. Read [Architecture Overview](Architecture-Overview.md) for the big picture
2. Follow [Deployment Architecture](Deployment-Architecture.md) to understand setup
3. Review [Data Flow Diagrams](Data-Flow-Diagrams.md) to see operations in action
4. Dive into [Rust Components](Rust-Components.md) for implementation details

## 📖 Additional Resources

- [Main README](../README.md) - User-facing documentation and quick start
- [CLAUDE.md](../CLAUDE.md) - Development guide for contributors
- [Quick Start Guide](../documentation/quick-start.md) - Step-by-step walkthrough
- [Usage Examples](../documentation/usage-examples.md) - Real-world scenarios
- [Learnings](../documentation/learnings.md) - Common issues and solutions

## 🤝 Contributing

When contributing to the system:

1. Consult [CLAUDE.md](../CLAUDE.md) for development guidelines
2. Review [Learnings](../documentation/learnings.md) to avoid known issues
3. Follow the checkpoint process for code quality
4. Update architecture documentation when making significant changes

---

**Note**: This wiki documents the system as implemented. For research background and design decisions, see [Research](../documentation/research.md).
