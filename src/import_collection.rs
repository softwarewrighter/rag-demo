// Copyright (c) 2025 Michael A. Wright
// Licensed under the MIT License

//! Import Qdrant collections from JSON backup files.

use anyhow::{Context, Result};
use clap::Parser;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(author, version, about = "Import Qdrant collection from JSON", long_about = None)]
struct Args {
    #[arg(help = "Path to JSON export file")]
    input: PathBuf,

    #[arg(
        short,
        long,
        help = "Target collection name (default: use name from export)"
    )]
    collection: Option<String>,

    #[arg(long, default_value = "http://localhost:6333", help = "Qdrant URL")]
    qdrant_url: String,

    #[arg(long, help = "Skip creating collection (assume it exists)")]
    skip_create: bool,

    #[arg(long, help = "Batch size for uploading points (default: 100)")]
    batch_size: Option<usize>,

    #[arg(long, help = "Force import even if collection exists (will merge)")]
    force: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct CollectionInfo {
    name: String,
    vectors_count: usize,
    indexed_vectors_count: usize,
    points_count: usize,
    config: serde_json::Value,
}

#[derive(Debug, Serialize, Deserialize)]
struct PointData {
    id: String,
    vector: Option<Vec<f32>>,
    payload: serde_json::Value,
}

#[derive(Debug, Serialize, Deserialize)]
struct ExportData {
    version: String,
    exported_at: String,
    collection_info: CollectionInfo,
    points: Vec<PointData>,
}

#[derive(Debug, Serialize)]
struct QdrantPoint {
    id: String,
    vector: Vec<f32>,
    payload: serde_json::Value,
}

#[derive(Debug, Serialize)]
struct UpsertRequest {
    points: Vec<QdrantPoint>,
}

fn check_collection_exists(client: &Client, qdrant_url: &str, collection: &str) -> Result<bool> {
    let url = format!("{}/collections/{}", qdrant_url, collection);
    let response = client.get(&url).send()?;
    Ok(response.status().is_success())
}

fn create_collection(
    client: &Client,
    qdrant_url: &str,
    collection: &str,
    config: &serde_json::Value,
) -> Result<()> {
    let url = format!("{}/collections/{}", qdrant_url, collection);

    // Extract vector size from config
    let vector_size = config
        .get("params")
        .and_then(|p| p.get("vectors"))
        .and_then(|v| v.get("size"))
        .and_then(|s| s.as_u64())
        .unwrap_or(768);

    let distance = config
        .get("params")
        .and_then(|p| p.get("vectors"))
        .and_then(|v| v.get("distance"))
        .and_then(|d| d.as_str())
        .unwrap_or("Cosine");

    let create_request = serde_json::json!({
        "vectors": {
            "size": vector_size,
            "distance": distance
        }
    });

    client
        .put(&url)
        .json(&create_request)
        .send()
        .context("Failed to create collection")?;

    Ok(())
}

fn upload_points(
    client: &Client,
    qdrant_url: &str,
    collection: &str,
    points: &[PointData],
    batch_size: usize,
) -> Result<()> {
    let total_points = points.len();
    let mut uploaded = 0;

    println!("Uploading points in batches of {}...", batch_size);

    for batch in points.chunks(batch_size) {
        let qdrant_points: Vec<QdrantPoint> = batch
            .iter()
            .filter_map(|p| {
                // Skip points without vectors
                let vector = p.vector.as_ref()?;

                Some(QdrantPoint {
                    id: p.id.clone(),
                    vector: vector.clone(),
                    payload: p.payload.clone(),
                })
            })
            .collect();

        if qdrant_points.is_empty() {
            println!("\n⚠️  Batch has no vectors - skipping");
            continue;
        }

        let url = format!("{}/collections/{}/points", qdrant_url, collection);
        let request = UpsertRequest {
            points: qdrant_points,
        };

        client
            .put(&url)
            .json(&request)
            .send()
            .context("Failed to upload batch")?;

        uploaded += batch.len();
        print!("\rUploaded {}/{} points...", uploaded, total_points);
        std::io::Write::flush(&mut std::io::stdout())?;
    }

    println!("\n✅ Upload complete!");

    Ok(())
}

fn main() -> Result<()> {
    let args = Args::parse();

    println!("📂 Reading export file: {}", args.input.display());

    let file_contents = fs::read_to_string(&args.input).context("Failed to read export file")?;

    let export_data: ExportData =
        serde_json::from_str(&file_contents).context("Failed to parse export JSON")?;

    let collection_name = args
        .collection
        .unwrap_or_else(|| export_data.collection_info.name.clone());

    println!("✅ Export data loaded:");
    println!("   Version: {}", export_data.version);
    println!("   Exported at: {}", export_data.exported_at);
    println!(
        "   Original collection: {}",
        export_data.collection_info.name
    );
    println!("   Points: {}", export_data.points.len());

    // Check if vectors are included
    let has_vectors = export_data.points.iter().any(|p| p.vector.is_some());
    if !has_vectors {
        anyhow::bail!(
            "❌ Export file does not contain vectors!\n\
             Vectors are required for import. Re-export with --include-vectors flag."
        );
    }

    let client = Client::new();

    // Check if collection exists
    let exists = check_collection_exists(&client, &args.qdrant_url, &collection_name)?;

    if exists && !args.force {
        anyhow::bail!(
            "❌ Collection '{}' already exists!\n\
             Use --force to merge with existing collection, or choose a different name with --collection",
            collection_name
        );
    }

    if !args.skip_create && !exists {
        println!("\n🔨 Creating collection '{}'...", collection_name);
        create_collection(
            &client,
            &args.qdrant_url,
            &collection_name,
            &export_data.collection_info.config,
        )?;
        println!("✅ Collection created");
    } else if exists {
        println!(
            "\n⚠️  Collection '{}' exists - merging points",
            collection_name
        );
    }

    let batch_size = args.batch_size.unwrap_or(100);
    upload_points(
        &client,
        &args.qdrant_url,
        &collection_name,
        &export_data.points,
        batch_size,
    )?;

    println!("\n🎉 Import complete!");
    println!("   Collection: {}", collection_name);
    println!("   Points imported: {}", export_data.points.len());

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_export_data_deserialization() {
        let json_str = r#"{
            "version": "1.0",
            "exported_at": "2025-01-01T00:00:00Z",
            "collection_info": {
                "name": "test",
                "vectors_count": 10,
                "indexed_vectors_count": 10,
                "points_count": 10,
                "config": {"vector_size": 768}
            },
            "points": []
        }"#;

        let export: ExportData = serde_json::from_str(json_str).unwrap();
        assert_eq!(export.version, "1.0");
        assert_eq!(export.collection_info.name, "test");
    }

    #[test]
    fn test_point_data_deserialization() {
        let json_data = json!({
            "id": "test-123",
            "vector": [0.1, 0.2, 0.3],
            "payload": {"text": "Test"}
        });

        let point: PointData = serde_json::from_value(json_data).unwrap();
        assert_eq!(point.id, "test-123");
        assert!(point.vector.is_some());
        assert_eq!(point.vector.unwrap().len(), 3);
    }

    #[test]
    fn test_qdrant_point_serialization() {
        let point = QdrantPoint {
            id: "test-id".to_string(),
            vector: vec![0.1, 0.2, 0.3],
            payload: json!({"text": "Test"}),
        };

        let json = serde_json::to_value(&point).unwrap();
        assert_eq!(json["id"], "test-id");
        assert!(json["vector"].is_array());
        assert_eq!(json["payload"]["text"], "Test");
    }

    #[test]
    fn test_upsert_request_structure() {
        let point = QdrantPoint {
            id: "1".to_string(),
            vector: vec![0.5],
            payload: json!({}),
        };

        let request = UpsertRequest {
            points: vec![point],
        };

        let json = serde_json::to_value(&request).unwrap();
        assert!(json["points"].is_array());
        assert_eq!(json["points"].as_array().unwrap().len(), 1);
    }
}
