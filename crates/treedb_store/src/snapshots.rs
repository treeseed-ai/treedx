use crate::catalog::{get_record, put_record};
use crate::error::StoreError;
use crate::ids::{artifact_id, snapshot_id};
use crate::log::append_record;
use crate::types::*;
use base64::Engine;
use chrono::Utc;
use std::fs;
use std::io::{Cursor, Write};
use std::path::{Component, Path, PathBuf};

pub fn build_snapshot_artifact(
    data_dir: &Path,
    input: SnapshotBuildInput,
) -> Result<SnapshotManifestRecord, StoreError> {
    validate_kind(&input.kind)?;
    let snapshot_id = input.snapshot_id.clone().unwrap_or_else(|| {
        snapshot_id(
            &input.repo_id,
            &input.ref_name,
            &input.commit_sha,
            &input.kind,
            &input.included_paths,
        )
    });
    let tmp_dir = data_dir.join("tmp/snapshots").join(&snapshot_id);
    if tmp_dir.exists() {
        fs::remove_dir_all(&tmp_dir)?;
    }
    fs::create_dir_all(&tmp_dir)?;

    let created_at = Utc::now();
    let mut files = Vec::new();
    let mut decoded_files = Vec::new();
    let mut total_bytes = 0u64;

    for file in input.files {
        validate_repo_path(&file.path)?;
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(file.content_base64.as_bytes())
            .map_err(|err| StoreError::Validation(format!("invalid file content base64: {err}")))?;
        let size = bytes.len() as u64;
        total_bytes += size;
        files.push(SnapshotFileRecord {
            path: file.path.clone(),
            object_id: file.object_id,
            size,
            content_hash: format!("blake3:{}", blake3::hash(&bytes).to_hex()),
        });
        decoded_files.push((file.path, bytes));
    }

    let mut manifest = SnapshotManifestRecord {
        snapshot_id: snapshot_id.clone(),
        repo_id: input.repo_id.clone(),
        ref_name: input.ref_name,
        commit_sha: input.commit_sha,
        kind: input.kind,
        included_paths: input.included_paths,
        graph_version: input.graph_version,
        file_count: files.len() as u64,
        total_bytes,
        files,
        checksums: serde_json::json!({}),
        artifact: None,
        created_by_actor_id: input.created_by_actor_id,
        created_at,
    };

    let artifact_path = tmp_dir.join("artifact.tar.zst");
    write_artifact(&artifact_path, &manifest, &decoded_files)?;
    let artifact_bytes = fs::read(&artifact_path)?;
    let artifact_checksum = format!("blake3:{}", blake3::hash(&artifact_bytes).to_hex());
    let artifact = ArtifactRecord {
        artifact_id: artifact_id(&snapshot_id, "tar.zst"),
        snapshot_id: snapshot_id.clone(),
        repo_id: input.repo_id,
        format: "tar.zst".to_string(),
        size: artifact_bytes.len() as u64,
        checksum: artifact_checksum.clone(),
        uri: format!("treedb://artifact/{snapshot_id}"),
        created_at,
    };
    manifest.checksums = serde_json::json!({
        "artifact": artifact_checksum,
        "files": manifest.files.iter().map(|file| {
            serde_json::json!({
                "path": file.path,
                "objectId": file.object_id,
                "size": file.size,
                "contentHash": file.content_hash
            })
        }).collect::<Vec<_>>()
    });
    manifest.artifact = Some(artifact.clone());
    append_record(
        &tmp_dir.join("manifest.tdb"),
        "snapshot_manifest",
        &snapshot_id,
        &manifest,
    )?;

    let final_dir = data_dir.join("snapshots").join(&snapshot_id);
    if final_dir.exists() {
        fs::remove_dir_all(&final_dir)?;
    }
    fs::rename(&tmp_dir, &final_dir)?;
    put_record(
        data_dir,
        "snapshots/snapshots.tdb",
        "snapshot",
        &snapshot_id,
        &manifest,
    )?;
    put_record(
        data_dir,
        "snapshots/artifacts.tdb",
        "artifact",
        &snapshot_id,
        &artifact,
    )?;
    Ok(manifest)
}

pub fn get_snapshot_manifest(
    data_dir: &Path,
    snapshot_id: &str,
) -> Result<Option<SnapshotManifestRecord>, StoreError> {
    get_record(data_dir, "snapshots/snapshots.tdb", "snapshot", snapshot_id)
}

pub fn get_artifact(
    data_dir: &Path,
    snapshot_id: &str,
) -> Result<Option<ArtifactRecord>, StoreError> {
    get_record(data_dir, "snapshots/artifacts.tdb", "artifact", snapshot_id)
}

pub fn read_artifact_bytes(data_dir: &Path, snapshot_id: &str) -> Result<Vec<u8>, StoreError> {
    let path = data_dir
        .join("snapshots")
        .join(snapshot_id)
        .join("artifact.tar.zst");
    if !path.exists() {
        return Err(StoreError::NotFound(format!("artifact {snapshot_id}")));
    }
    Ok(fs::read(path)?)
}

fn validate_kind(kind: &str) -> Result<(), StoreError> {
    match kind {
        "repository_snapshot"
        | "index_snapshot"
        | "graph_snapshot"
        | "search_snapshot"
        | "audit_export" => Ok(()),
        _ => Err(StoreError::Validation(format!(
            "unsupported snapshot kind: {kind}"
        ))),
    }
}

fn validate_repo_path(path: &str) -> Result<(), StoreError> {
    if path.is_empty() || path.contains('\0') || path.contains('\\') || path.starts_with('/') {
        return Err(StoreError::Validation(format!(
            "invalid snapshot path: {path}"
        )));
    }
    if Path::new(path).components().any(|component| {
        matches!(
            component,
            Component::ParentDir | Component::RootDir | Component::Prefix(_)
        )
    }) {
        return Err(StoreError::Validation(format!(
            "invalid snapshot path: {path}"
        )));
    }
    Ok(())
}

fn write_artifact(
    path: &Path,
    manifest: &SnapshotManifestRecord,
    files: &[(String, Vec<u8>)],
) -> Result<(), StoreError> {
    let file = fs::File::create(path)?;
    let encoder = zstd::stream::write::Encoder::new(file, 0)?;
    let mut builder = tar::Builder::new(encoder);
    let manifest_json = serde_json::to_vec_pretty(manifest)?;
    append_bytes(&mut builder, "manifest.json", &manifest_json)?;
    for (repo_path, bytes) in files {
        append_bytes(&mut builder, &format!("repo/{repo_path}"), bytes)?;
    }
    let encoder = builder.into_inner()?;
    encoder.finish()?;
    Ok(())
}

fn append_bytes<W: Write>(
    builder: &mut tar::Builder<W>,
    path: &str,
    bytes: &[u8],
) -> Result<(), StoreError> {
    let mut header = tar::Header::new_gnu();
    header.set_size(bytes.len() as u64);
    header.set_mode(0o644);
    header.set_cksum();
    builder.append_data(&mut header, PathBuf::from(path), Cursor::new(bytes))?;
    Ok(())
}
