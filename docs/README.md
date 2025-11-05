# RAG Demo - Live Demo

This is a **limited static demo** of the RAG Demo Dashboard hosted on GitHub Pages.

⚠️ **Important:** This demo uses **synthetic mocked data only**. No actual copyrighted document content is included in this repository.

## Data Privacy & Copyright Notice

**This repository does NOT contain:**
- Real PDF documents (excluded via `.gitignore`)
- Actual document content or extracts
- Vector database embeddings
- Any copyrighted material from ingested documents

**All demo data is synthetic** - created specifically for demonstration purposes using general programming knowledge.

**Real content locations** (all gitignored and private):
- `/ingest/` - Your PDF documents (never committed)
- `/extracted/` - Markdown extracts (never committed)
- `/qdrant_storage/` - Vector database (never committed)

These directories are **never pushed to GitHub** to ensure your copyrighted documents remain private and local-only.

## To Use the Full Version

For the complete interactive experience with real document ingestion and search:

1. Clone the repository: `git clone https://github.com/softwarewrighter/rag-demo.git`
2. Follow the setup instructions in the main README
3. Run Qdrant and Ollama locally
4. Ingest your own documents
5. Build and serve the dashboard: `./scripts/build-dashboard.sh`

## What's Different in the Live Demo

- ✅ Shows the dashboard UI
- ✅ Demonstrates search interface
- ✅ Displays sample results
- ❌ Cannot connect to real Qdrant/Ollama backend
- ❌ Cannot ingest real documents
- ❌ Shows only pre-generated mocked data

Visit the [main repository](https://github.com/softwarewrighter/rag-demo) for the full version.
