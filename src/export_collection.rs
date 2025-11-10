// Copyright (c) 2025 Michael A. Wright
// Licensed under the MIT License

//! Export Qdrant collections to JSON format for backup and sharing.

use anyhow::{Context, Result};
use clap::Parser;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(author, version, about = "Export Qdrant collection to JSON", long_about = None)]
struct Args {
    #[arg(help = "Collection name to export")]
    collection: String,

    #[arg(short, long, help = "Output file path (default: <collection>.json)")]
    output: Option<PathBuf>,

    #[arg(long, default_value = "http://localhost:6333", help = "Qdrant URL")]
    qdrant_url: String,

    #[arg(long, help = "Include vectors in export (increases file size significantly)")]
    include_vectors: bool,

    #[arg(long, help = "Pretty print JSON output")]
    pretty: bool,

    #[arg(long, help = "Batch size for fetching points (default: 100)")]
    batch_size: Option<usize>,
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

#[derive(Debug, Deserialize)]
struct QdrantCollectionResponse {
    result: CollectionResult,
}

#[derive(Debug, Deserialize)]
struct CollectionResult {
    vectors_count: Option<usize>,
    indexed_vectors_count: Option<usize>,
    points_count: Option<usize>,
    config: serde_json::Value,
}

#[derive(Debug, Deserialize)]
struct ScrollResponse {
    result: ScrollResult,
}

#[derive(Debug, Deserialize)]
struct ScrollResult {
    points: Vec<QdrantPoint>,
    next_page_offset: Option<String>,
}

#[derive(Debug, Deserialize)]
struct QdrantPoint {
    id: serde_json::Value,
    vector: Option<Vec<f32>>,
    payload: Option<serde_json::Value>,
}

fn get_collection_info(
    client: &Client,
    qdrant_url: &str,
    collection: &str,
) -> Result<CollectionInfo> {
    let url = format!("{}/collections/{}", qdrant_url, collection);
    let response: QdrantCollectionResponse = client
        .get(&url)
        .send()
        .context("Failed to get collection info")?
        .json()
        .context("Failed to parse collection info")?;

    Ok(CollectionInfo {
        name: collection.to_string(),
        vectors_count: response.result.vectors_count.unwrap_or(0),
        indexed_vectors_count: response.result.indexed_vectors_count.unwrap_or(0),
        points_count: response.result.points_count.unwrap_or(0),
        config: response.result.config,
    })
}

fn export_points(
    client: &Client,
    qdrant_url: &str,
    collection: &str,
    include_vectors: bool,
    batch_size: usize,
) -> Result<Vec<PointData>> {
    let mut all_points = Vec::new();
    let mut offset: Option<String> = None;

    println!("Exporting points...");

    loop {
        let url = format!("{}/collections/{}/points/scroll", qdrant_url, collection);

        let mut request_body = serde_json::json!({
            "limit": batch_size,
            "with_payload": true,
            "with_vector": include_vectors,
        });

        if let Some(ref off) = offset {
            request_body["offset"] = serde_json::json!(off);
        }

        let response: ScrollResponse = client
            .post(&url)
            .json(&request_body)
            .send()
            .context("Failed to scroll points")?
            .json()
            .context("Failed to parse scroll response")?;

        let batch_count = response.result.points.len();
        if batch_count == 0 {
            break;
        }

        for point in response.result.points {
            let id_str = match point.id {
                serde_json::Value::String(s) => s,
                serde_json::Value::Number(n) => n.to_string(),
                _ => point.id.to_string(),
            };

            all_points.push(PointData {
                id: id_str,
                vector: if include_vectors { point.vector } else { None },
                payload: point.payload.unwrap_or_else(|| serde_json::json!({})),
            });
        }

        print!("\rExported {} points...", all_points.len());
        std::io::Write::flush(&mut std::io::stdout())?;

        offset = response.result.next_page_offset;
        if offset.is_none() {
            break;
        }
    }

    println!("\rExported {} points total", all_points.len());

    Ok(all_points)
}

fn main() -> Result<()> {
    let args = Args::parse();
    let client = Client::new();

    println!("🔍 Fetching collection info for '{}'...", args.collection);

    let collection_info = get_collection_info(&client, &args.qdrant_url, &args.collection)
        .context("Failed to get collection information")?;

    println!("✅ Collection found:");
    println!("   Vectors: {}", collection_info.vectors_count);
    println!("   Points: {}", collection_info.points_count);
    println!("   Indexed: {}", collection_info.indexed_vectors_count);

    if !args.include_vectors {
        println!("\n⚠️  Vectors will NOT be included (use --include-vectors to include them)");
    }

    let batch_size = args.batch_size.unwrap_or(100);
    let points =
        export_points(&client, &args.qdrant_url, &args.collection, args.include_vectors, batch_size)?;

    let export_data = ExportData {
        version: "1.0".to_string(),
        exported_at: chrono::Utc::now().to_rfc3339(),
        collection_info,
        points,
    };

    let output_path = args
        .output
        .unwrap_or_else(|| PathBuf::from(format!("{}.json", args.collection)));

    println!("\n💾 Writing to {}...", output_path.display());

    let json_data = if args.pretty {
        serde_json::to_string_pretty(&export_data)?
    } else {
        serde_json::to_string(&export_data)?
    };

    fs::write(&output_path, json_data).context("Failed to write export file")?;

    let file_size = fs::metadata(&output_path)?.len();
    let size_mb = file_size as f64 / 1_048_576.0;

    println!("✅ Export complete!");
    println!("   File: {}", output_path.display());
    println!("   Size: {:.2} MB", size_mb);
    println!("   Points exported: {}", export_data.points.len());

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_collection_info_serialization() {
        let info = CollectionInfo {
            name: "test-collection".to_string(),
            vectors_count: 100,
            indexed_vectors_count: 95,
            points_count: 100,
            config: json!({"vector_size": 768}),
        };

        let json = serde_json::to_value(&info).unwrap();
        assert_eq!(json["name"], "test-collection");
        assert_eq!(json["vectors_count"], 100);
    }

    #[test]
    fn test_point_data_without_vectors() {
        let point = PointData {
            id: "test-id".to_string(),
            vector: None,
            payload: json!({"text": "Test content"}),
        };

        let json = serde_json::to_value(&point).unwrap();
        assert!(json["vector"].is_null());
        assert_eq!(json["payload"]["text"], "Test content");
    }

    #[test]
    fn test_point_data_with_vectors() {
        let point = PointData {
            id: "test-id".to_string(),
            vector: Some(vec![0.1, 0.2, 0.3]),
            payload: json!({"text": "Test"}),
        };

        let json = serde_json::to_value(&point).unwrap();
        assert!(json["vector"].is_array());
        assert_eq!(json["vector"].as_array().unwrap().len(), 3);
    }

    #[test]
    fn test_export_data_structure() {
        let info = CollectionInfo {
            name: "test".to_string(),
            vectors_count: 10,
            indexed_vectors_count: 10,
            points_count: 10,
            config: json!({}),
        };

        let export = ExportData {
            version: "1.0".to_string(),
            exported_at: "2025-01-01T00:00:00Z".to_string(),
            collection_info: info,
            points: vec![],
        };

        let json = serde_json::to_value(&export).unwrap();
        assert_eq!(json["version"], "1.0");
        assert!(json["points"].is_array());
    }
}
