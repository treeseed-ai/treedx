use crate::error::GraphError;
use crate::ids::{payload_hash, short_hash};
use crate::types::*;
use chrono::{DateTime, Utc};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SegmentEnvelope<T> {
    schema_version: u32,
    record_kind: String,
    record_id: String,
    recorded_at: DateTime<Utc>,
    payload_hash: String,
    payload: T,
}

pub fn write_graph_segments(
    data_dir: &Path,
    index: &GraphIndex,
) -> Result<GraphManifest, GraphError> {
    let root = graph_root(
        data_dir,
        &index.manifest.repo_id,
        &index.manifest.graph_version,
    );
    if root.exists() {
        fs::remove_dir_all(&root)?;
    }
    fs::create_dir_all(&root)?;
    write_records(
        &root.join("manifest.tdb"),
        "graph_manifest",
        &[("manifest".to_string(), index.manifest.clone())],
    )?;
    write_records(
        &root.join("documents.tdb"),
        "graph_document",
        &index
            .documents
            .iter()
            .map(|doc| (doc.path.clone(), doc.clone()))
            .collect::<Vec<_>>(),
    )?;
    write_records(
        &root.join("nodes.tdb"),
        "graph_node",
        &index
            .nodes
            .iter()
            .map(|node| (node.id.clone(), node.clone()))
            .collect::<Vec<_>>(),
    )?;
    write_records(
        &root.join("edges.tdb"),
        "graph_edge",
        &index
            .edges
            .iter()
            .map(|edge| (edge.id.clone(), edge.clone()))
            .collect::<Vec<_>>(),
    )?;
    let latest_dir = data_dir
        .join("graph/repos")
        .join(&index.manifest.repo_id)
        .join("latest");
    fs::create_dir_all(&latest_dir)?;
    write_records(
        &latest_dir.join(format!("{}.tdb", short_hash(&index.manifest.ref_name))),
        "graph_latest",
        &[("latest".to_string(), index.manifest.clone())],
    )?;
    Ok(index.manifest.clone())
}

pub fn read_graph_segments(
    data_dir: &Path,
    repo_id: &str,
    graph_version: &str,
) -> Result<GraphIndex, GraphError> {
    let root = graph_root(data_dir, repo_id, graph_version);
    if !root.exists() {
        return Err(GraphError::NotReady);
    }
    let manifest = read_records::<GraphManifest>(&root.join("manifest.tdb"), "graph_manifest")?
        .remove("manifest")
        .ok_or_else(|| GraphError::NotFound("graph manifest".to_string()))?;
    let documents = read_records::<GraphDocument>(&root.join("documents.tdb"), "graph_document")?
        .into_values()
        .collect::<Vec<_>>();
    let nodes = read_records::<GraphNode>(&root.join("nodes.tdb"), "graph_node")?
        .into_values()
        .collect::<Vec<_>>();
    let edges = read_records::<GraphEdge>(&root.join("edges.tdb"), "graph_edge")?
        .into_values()
        .collect::<Vec<_>>();
    Ok(GraphIndex {
        metrics: manifest.metrics.clone(),
        manifest,
        documents,
        nodes,
        edges,
        diagnostics: GraphDiagnostics::default(),
    })
}

pub fn read_latest_graph_manifest(
    data_dir: &Path,
    repo_id: &str,
    ref_name: &str,
) -> Result<Option<GraphManifest>, GraphError> {
    let path = data_dir
        .join("graph/repos")
        .join(repo_id)
        .join("latest")
        .join(format!("{}.tdb", short_hash(ref_name)));
    if !path.exists() {
        return Ok(None);
    }
    Ok(read_records::<GraphManifest>(&path, "graph_latest")?.remove("latest"))
}

fn graph_root(data_dir: &Path, repo_id: &str, graph_version: &str) -> PathBuf {
    data_dir
        .join("graph/repos")
        .join(repo_id)
        .join(graph_version)
}

fn write_records<T: Serialize + Clone>(
    path: &Path,
    kind: &str,
    records: &[(String, T)],
) -> Result<(), GraphError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(path)?;
    writeln!(file, "# treedx:{kind}:v1")?;
    for (id, payload) in records {
        let envelope = SegmentEnvelope {
            schema_version: 1,
            record_kind: kind.to_string(),
            record_id: id.clone(),
            recorded_at: Utc::now(),
            payload_hash: payload_hash(payload)?,
            payload: payload.clone(),
        };
        writeln!(file, "{}", serde_json::to_string(&envelope)?)?;
    }
    file.sync_data()?;
    Ok(())
}

fn read_records<T: DeserializeOwned + Serialize>(
    path: &Path,
    kind: &str,
) -> Result<BTreeMap<String, T>, GraphError> {
    let file = fs::File::open(path)?;
    let mut records = BTreeMap::new();
    for (index, line) in BufReader::new(file).lines().enumerate() {
        let line_no = index + 1;
        let line = line?;
        if line_no == 1 && line.starts_with("# treedx:") {
            continue;
        }
        if line.trim().is_empty() {
            continue;
        }
        let envelope: SegmentEnvelope<T> =
            serde_json::from_str(&line).map_err(|error| GraphError::InvalidRecord {
                file: path.display().to_string(),
                line: line_no,
                message: error.to_string(),
            })?;
        if envelope.record_kind != kind {
            return Err(GraphError::InvalidRecord {
                file: path.display().to_string(),
                line: line_no,
                message: format!("expected {kind}, got {}", envelope.record_kind),
            });
        }
        if payload_hash(&envelope.payload)? != envelope.payload_hash {
            return Err(GraphError::Checksum {
                file: path.display().to_string(),
                line: line_no,
            });
        }
        records.insert(envelope.record_id, envelope.payload);
    }
    Ok(records)
}
