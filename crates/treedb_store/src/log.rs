use crate::error::StoreError;
use crate::ids::payload_hash;
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::collections::BTreeMap;
use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LogEnvelope<T> {
    pub schema_version: u32,
    pub seq: u64,
    pub op: String,
    pub record_kind: String,
    pub record_id: String,
    pub recorded_at: chrono::DateTime<chrono::Utc>,
    pub payload_hash: String,
    pub payload: T,
}

static LOG_LOCKS: OnceLock<Mutex<HashMap<PathBuf, Arc<Mutex<()>>>>> = OnceLock::new();

fn lock_for(path: &Path) -> Arc<Mutex<()>> {
    let key = path.to_path_buf();
    let locks = LOG_LOCKS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut locks = locks.lock().expect("treedb log lock registry poisoned");
    locks
        .entry(key)
        .or_insert_with(|| Arc::new(Mutex::new(())))
        .clone()
}

pub fn ensure_log(path: &Path, kind: &str) -> Result<(), StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedb log lock poisoned");
    ensure_log_unlocked(path, kind)
}

fn ensure_log_unlocked(path: &Path, kind: &str) -> Result<(), StoreError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    if !path.exists() {
        let mut file = OpenOptions::new().create(true).append(true).open(path)?;
        writeln!(file, "# treedb:{kind}:v1")?;
        file.sync_data()?;
    }
    Ok(())
}

pub fn append_record<T: Serialize>(
    path: &Path,
    kind: &str,
    record_id: &str,
    payload: &T,
) -> Result<(), StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedb log lock poisoned");
    ensure_log_unlocked(path, kind)?;
    let seq = next_seq_unlocked(path, kind)?;
    let envelope = LogEnvelope {
        schema_version: 1,
        seq,
        op: "put".to_string(),
        record_kind: kind.to_string(),
        record_id: record_id.to_string(),
        recorded_at: chrono::Utc::now(),
        payload_hash: payload_hash(payload)?,
        payload,
    };
    let mut file = OpenOptions::new().append(true).open(path)?;
    writeln!(file, "{}", serde_json::to_string(&envelope)?)?;
    file.sync_data()?;
    Ok(())
}

pub fn append_records<T: Serialize>(
    path: &Path,
    kind: &str,
    records: Vec<(String, T)>,
) -> Result<(), StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedb log lock poisoned");
    ensure_log_unlocked(path, kind)?;

    if records.is_empty() {
        return Ok(());
    }

    let mut file = OpenOptions::new().append(true).open(path)?;

    for (seq, (record_id, payload)) in (next_seq_unlocked(path, kind)?..).zip(records) {
        let envelope = LogEnvelope {
            schema_version: 1,
            seq,
            op: "put".to_string(),
            record_kind: kind.to_string(),
            record_id,
            recorded_at: chrono::Utc::now(),
            payload_hash: payload_hash(&payload)?,
            payload,
        };
        writeln!(file, "{}", serde_json::to_string(&envelope)?)?;
    }

    file.sync_data()?;
    Ok(())
}

pub fn replay_latest<T: DeserializeOwned + Serialize + Clone>(
    path: &Path,
    kind: &str,
) -> Result<BTreeMap<String, T>, StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedb log lock poisoned");
    ensure_log_unlocked(path, kind)?;
    let file = fs::File::open(path)?;
    let mut latest = BTreeMap::new();
    for (index, line) in BufReader::new(file).lines().enumerate() {
        let line_no = index + 1;
        let line = line?;
        if line_no == 1 && line.starts_with("# treedb:") {
            continue;
        }
        if line.trim().is_empty() {
            continue;
        }
        let envelope: LogEnvelope<T> =
            serde_json::from_str(&line).map_err(|err| StoreError::InvalidRecord {
                file: path.display().to_string(),
                line: line_no,
                message: err.to_string(),
            })?;
        if envelope.record_kind != kind {
            return Err(StoreError::InvalidRecord {
                file: path.display().to_string(),
                line: line_no,
                message: format!("expected kind {kind}, got {}", envelope.record_kind),
            });
        }
        if payload_hash(&envelope.payload)? != envelope.payload_hash {
            return Err(StoreError::Checksum {
                file: path.display().to_string(),
                line: line_no,
            });
        }
        if envelope.op == "delete" {
            latest.remove(&envelope.record_id);
        } else {
            latest.insert(envelope.record_id, envelope.payload);
        }
    }
    Ok(latest)
}

fn next_seq_unlocked(path: &Path, kind: &str) -> Result<u64, StoreError> {
    Ok(replay_envelopes_unlocked::<serde_json::Value>(path, kind)?
        .last()
        .map(|entry| entry.seq + 1)
        .unwrap_or(1))
}

fn replay_envelopes_unlocked<T: DeserializeOwned + Serialize>(
    path: &Path,
    kind: &str,
) -> Result<Vec<LogEnvelope<T>>, StoreError> {
    let file = fs::File::open(path)?;
    let mut out = Vec::new();
    for (index, line) in BufReader::new(file).lines().enumerate() {
        let line_no = index + 1;
        let line = line?;
        if line_no == 1 && line.starts_with("# treedb:") {
            continue;
        }
        if line.trim().is_empty() {
            continue;
        }
        let envelope: LogEnvelope<T> =
            serde_json::from_str(&line).map_err(|err| StoreError::InvalidRecord {
                file: path.display().to_string(),
                line: line_no,
                message: err.to_string(),
            })?;
        if envelope.record_kind != kind {
            return Err(StoreError::InvalidRecord {
                file: path.display().to_string(),
                line: line_no,
                message: format!("expected kind {kind}, got {}", envelope.record_kind),
            });
        }
        if payload_hash(&envelope.payload)? != envelope.payload_hash {
            return Err(StoreError::Checksum {
                file: path.display().to_string(),
                line: line_no,
            });
        }
        out.push(envelope);
    }
    Ok(out)
}
