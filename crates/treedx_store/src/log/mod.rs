use crate::error::StoreError;
use crate::ids::payload_hash;
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::collections::BTreeMap;
use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::SystemTime;

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
static LOG_INDEXES: OnceLock<Mutex<HashMap<(PathBuf, String), LogIndex>>> = OnceLock::new();

#[derive(Clone)]
struct LogIndex {
    file_len: u64,
    modified: Option<SystemTime>,
    next_seq: u64,
    latest: BTreeMap<String, serde_json::Value>,
}

fn lock_for(path: &Path) -> Arc<Mutex<()>> {
    let key = path.to_path_buf();
    let locks = LOG_LOCKS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut locks = locks.lock().expect("treedx log lock registry poisoned");
    locks
        .entry(key)
        .or_insert_with(|| Arc::new(Mutex::new(())))
        .clone()
}

pub fn ensure_log(path: &Path, kind: &str) -> Result<(), StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedx log lock poisoned");
    ensure_log_unlocked(path, kind)
}

pub fn warm_log(path: &Path, kind: &str) -> Result<(), StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedx log lock poisoned");
    ensure_log_unlocked(path, kind)?;
    load_index_unlocked(path, kind).map(|_| ())
}

fn ensure_log_unlocked(path: &Path, kind: &str) -> Result<(), StoreError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    if !path.exists() {
        let mut file = OpenOptions::new().create(true).append(true).open(path)?;
        writeln!(file, "# treedx:{kind}:v1")?;
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
    let _guard = lock.lock().expect("treedx log lock poisoned");
    ensure_log_unlocked(path, kind)?;
    let seq = next_seq_unlocked(path, kind)?;
    let index_payload = serde_json::to_value(payload)?;
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
    update_index_after_write(
        path,
        kind,
        seq + 1,
        vec![(record_id.to_string(), index_payload)],
    )?;
    Ok(())
}

pub fn append_records<T: Serialize>(
    path: &Path,
    kind: &str,
    records: Vec<(String, T)>,
) -> Result<(), StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedx log lock poisoned");
    ensure_log_unlocked(path, kind)?;

    if records.is_empty() {
        return Ok(());
    }

    let mut output = Vec::new();
    let first_seq = next_seq_unlocked(path, kind)?;
    let mut indexed = Vec::new();
    let mut next_seq = first_seq;

    for (seq, (record_id, payload)) in (first_seq..).zip(records) {
        let index_payload = serde_json::to_value(&payload)?;
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
        serde_json::to_writer(&mut output, &envelope)?;
        output.push(b'\n');
        indexed.push((envelope.record_id, index_payload));
        next_seq = seq + 1;
    }

    let mut file = OpenOptions::new().append(true).open(path)?;
    file.write_all(&output)?;
    file.sync_data()?;
    update_index_after_write(path, kind, next_seq, indexed)?;
    Ok(())
}

pub fn append_records_unindexed<T: Serialize>(
    path: &Path,
    kind: &str,
    records: Vec<(String, T)>,
) -> Result<(), StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedx log lock poisoned");
    ensure_log_unlocked(path, kind)?;

    if records.is_empty() {
        return Ok(());
    }

    let mut output = Vec::new();
    let first_seq = next_seq_unlocked(path, kind)?;
    let mut next_seq = first_seq;

    for (seq, (record_id, payload)) in (first_seq..).zip(records) {
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
        serde_json::to_writer(&mut output, &envelope)?;
        output.push(b'\n');
        next_seq = seq + 1;
    }

    let mut file = OpenOptions::new().append(true).open(path)?;
    file.write_all(&output)?;
    file.sync_data()?;
    update_index_after_write(path, kind, next_seq, Vec::new())?;
    Ok(())
}

pub fn replay_all<T: DeserializeOwned + Serialize>(
    path: &Path,
    kind: &str,
) -> Result<Vec<T>, StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedx log lock poisoned");
    ensure_log_unlocked(path, kind)?;

    Ok(replay_envelopes_unlocked(path, kind)?
        .into_iter()
        .filter(|envelope| envelope.op != "delete")
        .map(|envelope| envelope.payload)
        .collect())
}

pub fn replay_latest<T: DeserializeOwned + Serialize + Clone>(
    path: &Path,
    kind: &str,
) -> Result<BTreeMap<String, T>, StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedx log lock poisoned");
    ensure_log_unlocked(path, kind)?;
    let index = load_index_unlocked(path, kind)?;
    index
        .latest
        .into_iter()
        .map(|(id, value)| Ok((id, serde_json::from_value(value)?)))
        .collect()
}

pub fn replay_record<T: DeserializeOwned + Serialize + Clone>(
    path: &Path,
    kind: &str,
    record_id: &str,
) -> Result<Option<T>, StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedx log lock poisoned");
    ensure_log_unlocked(path, kind)?;
    load_index_unlocked(path, kind)?
        .latest
        .get(record_id)
        .cloned()
        .map(serde_json::from_value)
        .transpose()
        .map_err(Into::into)
}

fn next_seq_unlocked(path: &Path, kind: &str) -> Result<u64, StoreError> {
    Ok(load_index_unlocked(path, kind)?.next_seq)
}

fn load_index_unlocked(path: &Path, kind: &str) -> Result<LogIndex, StoreError> {
    let metadata = fs::metadata(path)?;
    let modified = metadata.modified().ok();
    let key = (path.to_path_buf(), kind.to_string());
    let indexes = LOG_INDEXES.get_or_init(|| Mutex::new(HashMap::new()));
    if let Some(index) = indexes
        .lock()
        .expect("treedx log index poisoned")
        .get(&key)
        .filter(|index| index.file_len == metadata.len() && index.modified == modified)
        .cloned()
    {
        return Ok(index);
    }
    let envelopes = replay_envelopes_unlocked::<serde_json::Value>(path, kind)?;
    let mut latest = BTreeMap::new();
    for envelope in &envelopes {
        if envelope.op == "delete" {
            latest.remove(&envelope.record_id);
        } else {
            latest.insert(envelope.record_id.clone(), envelope.payload.clone());
        }
    }
    let index = LogIndex {
        file_len: metadata.len(),
        modified,
        next_seq: envelopes.last().map(|entry| entry.seq + 1).unwrap_or(1),
        latest,
    };
    indexes
        .lock()
        .expect("treedx log index poisoned")
        .insert(key, index.clone());
    Ok(index)
}

fn update_index_after_write(
    path: &Path,
    kind: &str,
    next_seq: u64,
    records: Vec<(String, serde_json::Value)>,
) -> Result<(), StoreError> {
    let metadata = fs::metadata(path)?;
    let key = (path.to_path_buf(), kind.to_string());
    let indexes = LOG_INDEXES.get_or_init(|| Mutex::new(HashMap::new()));
    let mut indexes = indexes.lock().expect("treedx log index poisoned");
    let index = indexes.entry(key).or_insert(LogIndex {
        file_len: 0,
        modified: None,
        next_seq: 1,
        latest: BTreeMap::new(),
    });
    for (record_id, payload) in records {
        index.latest.insert(record_id, payload);
    }
    index.file_len = metadata.len();
    index.modified = metadata.modified().ok();
    index.next_seq = next_seq;
    Ok(())
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
        if line_no == 1 && line.starts_with("# treedx:") {
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
