// Copyright (c) 2025 Michael A. Wright
// Licensed under the MIT License

use anyhow::{Context, Result};
use clap::Parser;
use colored::*;
use reqwest::blocking::Client;
use serde_json::json;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Parser, Debug)]
#[command(
    author,
    version,
    about = "Ingest PDFs organized by directory into separate collections"
)]
struct Args {
    #[arg(
        default_value = "./ingest",
        help = "Root directory containing subdirectories of PDFs"
    )]
    ingest_dir: PathBuf,

    #[arg(long, default_value = "http://localhost:6333", help = "Qdrant URL")]
    qdrant_url: String,

    #[arg(long, default_value = "http://localhost:11434", help = "Ollama URL")]
    ollama_url: String,

    #[arg(long, help = "Skip health checks")]
    skip_checks: bool,

    #[arg(long, help = "Dry run - show what would be ingested without doing it")]
    dry_run: bool,
}

#[derive(Debug)]
struct CollectionStats {
    pdfs_processed: usize,
    pdfs_failed: usize,
    total_vectors: usize,
    indexed_vectors: usize,
    status: String,
}

fn check_services(qdrant_url: &str, ollama_url: &str) -> Result<()> {
    let client = Client::new();

    // Check Qdrant
    client
        .get(format!("{}/health", qdrant_url))
        .send()
        .context("Qdrant is not running. Please run: ./scripts/setup-qdrant.sh")?;

    // Check Ollama
    client
        .get(format!("{}/api/tags", ollama_url))
        .send()
        .context("Ollama is not running. Please start it with: ollama serve")?;

    // Check embedding model
    let output = Command::new("ollama")
        .args(["list"])
        .output()
        .context("Failed to run ollama list")?;

    if !String::from_utf8_lossy(&output.stdout).contains("nomic-embed-text") {
        println!("{}", "📦 Pulling embedding model...".yellow());
        Command::new("ollama")
            .args(["pull", "nomic-embed-text"])
            .status()
            .context("Failed to pull embedding model")?;
    }

    Ok(())
}

fn ensure_collection_exists(
    client: &Client,
    qdrant_url: &str,
    collection_name: &str,
) -> Result<()> {
    // Check if collection exists
    let check_response = client
        .get(format!("{}/collections/{}", qdrant_url, collection_name))
        .send();

    if check_response.is_err() || !check_response.unwrap().status().is_success() {
        println!(
            "   {} Creating collection: {}",
            "📦".yellow(),
            collection_name.cyan()
        );

        // Create collection
        let response = client
            .put(format!("{}/collections/{}", qdrant_url, collection_name))
            .json(&json!({
                "vectors": {
                    "size": 768,
                    "distance": "Cosine"
                },
                "optimizers_config": {
                    "default_segment_number": 2,
                    "indexing_threshold": 1000
                }
            }))
            .send()
            .context("Failed to create collection")?;

        if !response.status().is_success() {
            anyhow::bail!("Failed to create collection: {}", response.status());
        }
    }

    Ok(())
}

fn ingest_pdf(pdf_path: &Path, collection: &str) -> Result<()> {
    let pdf_str = pdf_path.to_str().context("Invalid path")?;

    // Use the smart ingestion script with hierarchical chunking
    let status = Command::new("bash")
        .env("RAG_COLLECTION", collection)
        .args(["./scripts/ingest-pdf-smart.sh", pdf_str])
        .status()
        .context("Failed to run ingestion script")?;

    if !status.success() {
        anyhow::bail!("Ingestion failed for {}", pdf_str);
    }

    Ok(())
}

fn get_collection_stats(
    client: &Client,
    qdrant_url: &str,
    collection: &str,
) -> Result<CollectionStats> {
    let response = client
        .get(format!("{}/collections/{}", qdrant_url, collection))
        .send()
        .context("Failed to get collection stats")?;

    let json: serde_json::Value = response.json().context("Failed to parse response")?;
    let result = &json["result"];

    Ok(CollectionStats {
        pdfs_processed: 0, // Will be tracked during processing
        pdfs_failed: 0,
        total_vectors: result["points_count"].as_u64().unwrap_or(0) as usize,
        indexed_vectors: result["indexed_vectors_count"].as_u64().unwrap_or(0) as usize,
        status: result["status"].as_str().unwrap_or("unknown").to_string(),
    })
}

fn main() -> Result<()> {
    let args = Args::parse();
    let client = Client::new();

    println!("{}", "📚 Directory-Based Ingestion System".cyan().bold());
    println!("{}", "═".repeat(50).blue());
    println!();

    // Check if ingest directory exists
    if !args.ingest_dir.exists() {
        anyhow::bail!("Ingest directory not found: {:?}", args.ingest_dir);
    }

    // Check services
    if !args.skip_checks {
        println!("{} Checking services...", "🔍".yellow());
        check_services(&args.qdrant_url, &args.ollama_url)?;
        println!("{} All services are running", "✅".green());
        println!();
    }

    // Track overall statistics
    let mut total_pdfs = 0;
    let mut total_failed = 0;
    let mut collections_processed: HashMap<String, CollectionStats> = HashMap::new();

    // Process each subdirectory
    let entries = fs::read_dir(&args.ingest_dir).context("Failed to read ingest directory")?;

    for entry in entries {
        let entry = entry?;
        let path = entry.path();

        if !path.is_dir() {
            continue;
        }

        let dir_name = path
            .file_name()
            .and_then(|n| n.to_str())
            .context("Invalid directory name")?;

        // Skip hidden directories
        if dir_name.starts_with('.') {
            continue;
        }

        let collection_name = format!("{}-books", dir_name);

        // Find PDFs in this directory
        let pdfs: Vec<PathBuf> = fs::read_dir(&path)?
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|p| {
                p.extension()
                    .and_then(|ext| ext.to_str())
                    .map(|ext| ext.eq_ignore_ascii_case("pdf"))
                    .unwrap_or(false)
            })
            .collect();

        if pdfs.is_empty() {
            println!("{} No PDFs found in {}/", "⚠️ ".yellow(), dir_name);
            continue;
        }

        println!("{}", "━".repeat(50).blue());
        println!("{} Processing: {}", "📂".cyan(), dir_name.bold());
        println!("   Collection: {}", collection_name.cyan());
        println!("   PDF files: {}", pdfs.len().to_string().green());
        println!("{}", "━".repeat(50).blue());

        if args.dry_run {
            println!("{} Dry run - would process:", "🔍".yellow());
            for pdf in &pdfs {
                if let Some(name) = pdf.file_name() {
                    println!("   • {}", name.to_string_lossy());
                }
            }
            continue;
        }

        // Ensure collection exists
        ensure_collection_exists(&client, &args.qdrant_url, &collection_name)?;

        // Process each PDF
        let mut processed = 0;
        let mut failed = 0;

        for pdf in &pdfs {
            if let Some(pdf_name) = pdf.file_name() {
                println!();
                println!("{} Ingesting: {}", "📄".cyan(), pdf_name.to_string_lossy());

                match ingest_pdf(pdf, &collection_name) {
                    Ok(_) => {
                        processed += 1;
                        total_pdfs += 1;
                        println!("   {} Successfully ingested", "✓".green());
                    }
                    Err(e) => {
                        failed += 1;
                        total_failed += 1;
                        println!("   {} Failed: {}", "✗".red(), e);
                    }
                }
            }
        }

        // Get collection statistics
        if let Ok(mut stats) = get_collection_stats(&client, &args.qdrant_url, &collection_name) {
            stats.pdfs_processed = processed;
            stats.pdfs_failed = failed;

            println!();
            println!(
                "{} Collection '{}' Statistics:",
                "📊".cyan(),
                collection_name
            );
            println!(
                "   • PDFs processed: {}",
                stats.pdfs_processed.to_string().green()
            );
            if stats.pdfs_failed > 0 {
                println!("   • PDFs failed: {}", stats.pdfs_failed.to_string().red());
            }
            println!(
                "   • Total vectors: {}",
                stats.total_vectors.to_string().cyan()
            );
            println!(
                "   • Indexed vectors: {}",
                stats.indexed_vectors.to_string().cyan()
            );
            println!(
                "   • Status: {}",
                if stats.status == "green" {
                    stats.status.green()
                } else {
                    stats.status.yellow()
                }
            );

            collections_processed.insert(collection_name.clone(), stats);
        }
    }

    // Final summary
    println!();
    println!("{}", "═".repeat(50).blue());
    println!(
        "{} Directory-Based Ingestion Complete!",
        "✨".green().bold()
    );
    println!("{}", "═".repeat(50).blue());
    println!();

    println!("{} Overall Statistics:", "📊".cyan().bold());
    println!(
        "   • Collections processed: {}",
        collections_processed.len().to_string().green()
    );
    println!(
        "   • Total PDFs ingested: {}",
        total_pdfs.to_string().green()
    );
    if total_failed > 0 {
        println!("   • Total PDFs failed: {}", total_failed.to_string().red());
    }
    println!();

    if !collections_processed.is_empty() {
        println!("{} Collections Summary:", "📚".cyan().bold());
        for (name, stats) in &collections_processed {
            println!();
            println!("   {}:", name.bold());
            println!("      • PDFs: {}", stats.pdfs_processed.to_string().green());
            println!(
                "      • Vectors: {}",
                stats.total_vectors.to_string().cyan()
            );
            println!(
                "      • Indexed: {}",
                stats.indexed_vectors.to_string().cyan()
            );
            println!(
                "      • Status: {}",
                if stats.status == "green" {
                    stats.status.green()
                } else {
                    stats.status.yellow()
                }
            );
        }
    }

    println!();
    println!("{} Next Steps:", "🎯".cyan().bold());
    println!(
        "   1. Query Rust books:       RAG_COLLECTION=rust-books ./scripts/query-rag.sh \"What is ownership?\""
    );
    println!(
        "   2. Query JavaScript books: RAG_COLLECTION=javascript-books ./scripts/query-rag.sh \"Explain promises\""
    );
    println!(
        "   3. Query Python books:     RAG_COLLECTION=python-books ./scripts/query-rag.sh \"What are decorators?\""
    );
    println!(
        "   4. Query Lisp books:       RAG_COLLECTION=lisp-books ./scripts/query-rag.sh \"What are macros?\""
    );
    println!();
    println!(
        "   View dashboard: {}",
        "http://localhost:6333/dashboard".blue().underline()
    );

    Ok(())
}
