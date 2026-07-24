use crate::error::StoreError;
use crate::ids::{hash_bytes, short_hash};
use crate::types::{
    StorageBackupInput, StorageBackupResult, StorageCompactFileResult, StorageCompactInput,
    StorageCompactResult,
};
use chrono::Utc;
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};

pub fn compact_storage(
    data_dir: &Path,
    input: StorageCompactInput,
) -> Result<StorageCompactResult, StoreError> {
    let logs = if input.logs.is_empty() {
        list_tdb_logs(data_dir)?
            .into_iter()
            .filter(|path| !path.starts_with("audit/"))
            .collect::<Vec<_>>()
    } else {
        input.logs
    };
    let backup_id = if input.backup_before && !input.plan {
        Some(
            create_backup(
                data_dir,
                StorageBackupInput {
                    include: vec![
                        "catalog".into(),
                        "policy".into(),
                        "graph".into(),
                        "snapshots".into(),
                        "federation".into(),
                        "workspaces".into(),
                        "leases".into(),
                    ],
                    verify: true,
                },
            )?
            .backup_id,
        )
    } else {
        None
    };

    let mut files = Vec::new();
    for relative in logs {
        if relative.starts_with("audit/") {
            continue;
        }
        let result = compact_one(data_dir, &relative, input.plan)?;
        files.push(result);
    }

    Ok(StorageCompactResult {
        status: "ok".to_string(),
        plan: input.plan,
        backup_id,
        files,
    })
}

pub fn create_backup(
    data_dir: &Path,
    input: StorageBackupInput,
) -> Result<StorageBackupResult, StoreError> {
    let include = if input.include.is_empty() {
        vec![
            "catalog".to_string(),
            "audit".to_string(),
            "graph".to_string(),
            "snapshots".to_string(),
            "federation".to_string(),
            "workspaces".to_string(),
            "leases".to_string(),
        ]
    } else {
        input.include
    };
    let backup_id = format!("backup_{}", short_hash(&Utc::now().to_rfc3339()));
    let backup_dir = data_dir.join("recovery").join("backups").join(&backup_id);
    fs::create_dir_all(&backup_dir)?;
    let archive_path = backup_dir.join("treedx-backup.tar.zst");
    let file = File::create(&archive_path)?;
    let encoder = zstd::Encoder::new(file, 3)?;
    let mut builder = tar::Builder::new(encoder);

    for root in include {
        let root_path = data_dir.join(&root);
        if root_path.exists() {
            append_tree(data_dir, &root_path, &mut builder)?;
        }
    }

    let encoder = builder.into_inner()?;
    encoder.finish()?;
    let bytes = fs::read(&archive_path)?;
    let verified = if input.verify {
        verify_backup_bytes(&bytes)?
    } else {
        false
    };

    Ok(StorageBackupResult {
        backup_id: backup_id.clone(),
        format: "tar.zst".to_string(),
        uri: format!("treedx://backup/{backup_id}"),
        checksum: hash_bytes(&bytes),
        byte_length: bytes.len() as u64,
        verified,
    })
}

pub fn list_tdb_logs(data_dir: &Path) -> Result<Vec<String>, StoreError> {
    let mut out = Vec::new();
    collect_tdb_logs(data_dir, data_dir, &mut out)?;
    out.sort();
    Ok(out)
}

fn compact_one(
    data_dir: &Path,
    relative: &str,
    plan: bool,
) -> Result<StorageCompactFileResult, StoreError> {
    let path = data_dir.join(relative);
    if !path.exists() {
        return Ok(StorageCompactFileResult {
            file: relative.to_string(),
            records_before: 0,
            records_after: 0,
            bytes_before: 0,
            bytes_after: 0,
            compacted: false,
        });
    }
    let bytes_before = fs::metadata(&path)?.len();
    let (header, records) = read_json_log(&path)?;
    let records_before = records.len() as u64;
    let mut latest = BTreeMap::<String, Value>::new();

    for record in records {
        let id = record
            .get("recordId")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        if id.is_empty() {
            continue;
        }
        if record.get("op").and_then(Value::as_str) == Some("delete") {
            latest.remove(&id);
        } else {
            latest.insert(id, record);
        }
    }

    let records_after = latest.len() as u64;
    let rendered = render_log(header.as_deref(), latest.values())?;
    let bytes_after = rendered.len() as u64;

    if !plan && bytes_after < bytes_before {
        let tmp = path.with_extension("tdb.compact.tmp");
        {
            let mut file = File::create(&tmp)?;
            file.write_all(rendered.as_bytes())?;
            file.sync_data()?;
        }
        fs::rename(tmp, &path)?;
    }

    Ok(StorageCompactFileResult {
        file: relative.to_string(),
        records_before,
        records_after,
        bytes_before,
        bytes_after,
        compacted: !plan && bytes_after < bytes_before,
    })
}

fn read_json_log(path: &Path) -> Result<(Option<String>, Vec<Value>), StoreError> {
    let file = File::open(path)?;
    let mut header = None;
    let mut records = Vec::new();

    for (index, line) in BufReader::new(file).lines().enumerate() {
        let line_no = index + 1;
        let line = line?;
        if line_no == 1 && line.starts_with("# treedx:") {
            header = Some(line);
            continue;
        }
        if line.trim().is_empty() {
            continue;
        }
        let value: Value =
            serde_json::from_str(&line).map_err(|err| StoreError::InvalidRecord {
                file: path.display().to_string(),
                line: line_no,
                message: err.to_string(),
            })?;
        records.push(value);
    }
    Ok((header, records))
}

fn render_log<'a>(
    header: Option<&str>,
    records: impl Iterator<Item = &'a Value>,
) -> Result<String, StoreError> {
    let mut out = String::new();
    if let Some(header) = header {
        out.push_str(header);
        out.push('\n');
    }
    for record in records {
        out.push_str(&serde_json::to_string(record)?);
        out.push('\n');
    }
    Ok(out)
}

fn append_tree(
    data_dir: &Path,
    path: &Path,
    builder: &mut tar::Builder<zstd::Encoder<'_, File>>,
) -> Result<(), StoreError> {
    if path.is_dir() {
        for entry in fs::read_dir(path)? {
            append_tree(data_dir, &entry?.path(), builder)?;
        }
    } else if path.is_file() {
        let relative = path.strip_prefix(data_dir).unwrap_or(path);
        if relative.starts_with("tmp") || relative.starts_with("recovery/backups") {
            return Ok(());
        }
        builder.append_path_with_name(path, relative)?;
    }
    Ok(())
}

fn verify_backup_bytes(bytes: &[u8]) -> Result<bool, StoreError> {
    let decoded = zstd::stream::decode_all(bytes)?;
    let mut archive = tar::Archive::new(decoded.as_slice());
    for entry in archive.entries()? {
        let mut entry = entry?;
        let mut sink = Vec::new();
        entry.read_to_end(&mut sink)?;
    }
    Ok(true)
}

fn collect_tdb_logs(root: &Path, current: &Path, out: &mut Vec<String>) -> Result<(), StoreError> {
    if !current.exists() {
        return Ok(());
    }
    for entry in fs::read_dir(current)? {
        let path: PathBuf = entry?.path();
        if path.is_dir() {
            collect_tdb_logs(root, &path, out)?;
        } else if path.extension().and_then(|ext| ext.to_str()) == Some("tdb") {
            out.push(
                path.strip_prefix(root)
                    .unwrap_or(&path)
                    .to_string_lossy()
                    .replace('\\', "/"),
            );
        }
    }
    Ok(())
}
