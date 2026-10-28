use crate::error::StoreError;
use crate::ids::payload_hash;
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::collections::BTreeMap;
use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::SystemTime;

mod cache;
use cache::{
    next_seq_unlocked, remove_from_index_after_write, update_index_after_write,
    with_index_unlocked, IndexCache,
};
mod read;
pub(crate) use read::validate_envelope;
use read::{replay_envelopes_unlocked, visit_envelopes_unlocked};

#[cfg(test)]
thread_local! {
    static VALIDATED_RECORDS: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

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
static LOG_INDEXES: OnceLock<Mutex<IndexCache>> = OnceLock::new();

pub fn set_cache_budget(bytes: usize) {
    let mut cache = LOG_INDEXES
        .get_or_init(Default::default)
        .lock()
        .expect("treedx log index poisoned");
    cache.budget = bytes;
    cache.enforce();
}

pub fn cache_stats() -> (usize, usize, usize) {
    let cache = LOG_INDEXES
        .get_or_init(Default::default)
        .lock()
        .expect("treedx log index poisoned");
    (cache.indexes.len(), cache.bytes(), cache.budget)
}

#[derive(Clone, Copy)]
struct RecordPosition {
    offset: u64,
    line: usize,
}

#[derive(Clone)]
struct LogIndex {
    file_len: u64,
    modified: Option<SystemTime>,
    next_seq: u64,
    line_count: usize,
    // Derived positions in the existing validated log remain useful when its
    // payloads exceed the cache share. They are charged and evicted separately.
    positions: Option<BTreeMap<String, RecordPosition>>,
    position_bytes: usize,
    latest: Option<BTreeMap<String, serde_json::Value>>,
    bytes: usize,
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
    with_index_unlocked(path, kind, |_| ())
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

pub fn append_delete(path: &Path, kind: &str, record_id: &str) -> Result<(), StoreError> {
    let lock = lock_for(path);
    let _guard = lock.lock().expect("treedx log lock poisoned");
    ensure_log_unlocked(path, kind)?;
    let seq = next_seq_unlocked(path, kind)?;
    let payload = serde_json::Value::Null;
    let envelope = LogEnvelope {
        schema_version: 1,
        seq,
        op: "delete".to_string(),
        record_kind: kind.to_string(),
        record_id: record_id.to_string(),
        recorded_at: chrono::Utc::now(),
        payload_hash: payload_hash(&payload)?,
        payload,
    };
    let mut file = OpenOptions::new().append(true).open(path)?;
    writeln!(file, "{}", serde_json::to_string(&envelope)?)?;
    file.sync_data()?;
    remove_from_index_after_write(path, kind, seq + 1, record_id)?;
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
    let cached = with_index_unlocked(path, kind, |index| index.latest.clone())?;
    let latest = match cached {
        Some(latest) => latest,
        None => {
            let mut latest = BTreeMap::new();
            visit_envelopes_unlocked::<serde_json::Value>(path, kind, |envelope| {
                if envelope.op == "delete" {
                    latest.remove(&envelope.record_id);
                } else {
                    latest.insert(envelope.record_id, envelope.payload);
                }
            })?;
            latest
        }
    };
    latest
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
    let (complete, mut payload, indexed, position) = with_index_unlocked(path, kind, |index| {
        (
            index.latest.is_some(),
            index
                .latest
                .as_ref()
                .and_then(|latest| latest.get(record_id))
                .cloned(),
            index.positions.is_some(),
            index
                .positions
                .as_ref()
                .and_then(|positions| positions.get(record_id))
                .copied(),
        )
    })?;
    if !complete {
        if indexed {
            payload = match position {
                Some(position) => read::read_indexed_record(path, kind, record_id, position)?,
                None => None,
            };
        } else {
            visit_envelopes_unlocked::<serde_json::Value>(path, kind, |envelope| {
                if envelope.record_id == record_id {
                    payload = if envelope.op == "delete" {
                        None
                    } else {
                        Some(envelope.payload)
                    };
                }
            })?;
        }
    }
    payload
        .map(serde_json::from_value)
        .transpose()
        .map_err(Into::into)
}

#[cfg(test)]
mod lookup_tests;
