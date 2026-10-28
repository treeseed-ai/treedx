use super::read::visit_positioned_envelopes;
use super::{LogIndex, RecordPosition, LOG_INDEXES};
use crate::error::StoreError;
use serde_json::Value;
use std::collections::BTreeMap;
use std::collections::HashMap;
use std::fs;
use std::mem::size_of;
use std::path::Path;
use std::path::PathBuf;

/// The runtime supplies one finite share of its cache budget. Standalone store
/// consumers use a bounded 64 MiB default until explicitly configured.
pub(super) struct IndexCache {
    pub indexes: HashMap<(PathBuf, String), LogIndex>,
    pub budget: usize,
}

impl Default for IndexCache {
    fn default() -> Self {
        Self {
            indexes: HashMap::new(),
            budget: 64 * 1024 * 1024,
        }
    }
}

impl IndexCache {
    pub fn bytes(&self) -> usize {
        self.indexes
            .iter()
            .map(|((path, kind), index)| {
                path.capacity()
                    + kind.capacity()
                    + index.bytes
                    + index.position_bytes
                    + size_of::<(PathBuf, String)>()
                    + size_of::<LogIndex>()
                    + 128
            })
            .sum::<usize>()
            + self.indexes.capacity() * (size_of::<((PathBuf, String), LogIndex)>() + 32)
    }

    pub fn enforce(&mut self) {
        if self.budget == 0 {
            self.indexes.clear();
            self.indexes.shrink_to_fit();
            return;
        }
        while self.bytes() > self.budget {
            // Keep each log's validated length and next sequence when its
            // payloads no longer fit. Dropping the entire index makes every
            // subsequent append replay durable history just to find its seq.
            if let Some(key) = self
                .indexes
                .iter()
                .filter(|(_, index)| index.bytes > 0)
                .max_by_key(|(_, index)| index.bytes)
                .map(|(key, _)| key.clone())
            {
                let index = self
                    .indexes
                    .get_mut(&key)
                    .expect("selected log index exists");
                index.latest = None;
                index.bytes = 0;
                continue;
            }
            if let Some(key) = self
                .indexes
                .iter()
                .filter(|(_, index)| index.position_bytes > 0)
                .max_by_key(|(_, index)| index.position_bytes)
                .map(|(key, _)| key.clone())
            {
                let index = self
                    .indexes
                    .get_mut(&key)
                    .expect("selected position index exists");
                index.positions = None;
                index.position_bytes = 0;
                continue;
            }
            let Some(key) = self.indexes.keys().next().cloned() else {
                break;
            };
            self.indexes.remove(&key);
            self.indexes.shrink_to_fit();
        }
    }
}

/// Include owned JSON allocations and conservative BTree node overhead, rather
/// than treating the much smaller serialized or NIF reference size as RAM.
pub(super) fn payload_bytes(value: &Value) -> usize {
    match value {
        Value::String(text) => text.capacity(),
        Value::Array(items) => {
            items.capacity() * size_of::<Value>() + items.iter().map(payload_bytes).sum::<usize>()
        }
        Value::Object(items) => items
            .iter()
            .map(|(key, value)| 1024 + key.capacity() + size_of::<Value>() + payload_bytes(value))
            .sum(),
        _ => 0,
    }
}

pub(super) fn record_bytes(key: &String, value: &Value) -> usize {
    1024 + key.capacity() + size_of::<Value>() + payload_bytes(value)
}

pub(super) fn next_seq_unlocked(path: &Path, kind: &str) -> Result<u64, StoreError> {
    with_index_unlocked(path, kind, |index| index.next_seq)
}

pub(super) fn with_index_unlocked<T>(
    path: &Path,
    kind: &str,
    read: impl FnOnce(&LogIndex) -> T,
) -> Result<T, StoreError> {
    let metadata = fs::metadata(path)?;
    let modified = metadata.modified().ok();
    let key = (path.to_path_buf(), kind.to_string());
    let indexes = LOG_INDEXES.get_or_init(Default::default);
    let budget = {
        let cache = indexes.lock().expect("treedx log index poisoned");
        if let Some(index) = cache
            .indexes
            .get(&key)
            .filter(|index| index.file_len == metadata.len() && index.modified == modified)
        {
            return Ok(read(index));
        }
        cache.budget
    };
    let mut index = LogIndex {
        file_len: metadata.len(),
        modified,
        next_seq: 1,
        line_count: 0,
        latest: Some(BTreeMap::new()),
        bytes: 0,
        positions: Some(BTreeMap::new()),
        position_bytes: 0,
    };
    index.line_count = visit_positioned_envelopes::<Value>(
        path,
        kind,
        RecordPosition { offset: 0, line: 1 },
        |envelope, position| {
            index.next_seq = envelope.seq + 1;
            let deleted = envelope.op == "delete";
            update_position(
                &mut index,
                envelope.record_id.clone(),
                if deleted { None } else { Some(position) },
                budget,
            );
            update_payload(
                &mut index,
                envelope.record_id,
                if deleted {
                    None
                } else {
                    Some(envelope.payload)
                },
                budget,
            );
        },
    )?;
    let result = read(&index);
    let mut cache = indexes.lock().expect("treedx log index poisoned");
    cache.indexes.insert(key, index);
    cache.enforce();
    Ok(result)
}

fn update_payload(index: &mut LogIndex, key: String, payload: Option<Value>, budget: usize) {
    let Some(latest) = index.latest.as_mut() else {
        return;
    };
    if let Some((old_key, old_value)) = latest.remove_entry(&key) {
        index.bytes -= record_bytes(&old_key, &old_value);
    }
    if let Some(payload) = payload {
        let bytes = record_bytes(&key, &payload);
        if bytes > budget.saturating_sub(index.bytes + index.position_bytes) {
            index.latest = None;
            index.bytes = 0;
        } else {
            index.bytes += bytes;
            latest.insert(key, payload);
        }
    }
}

fn update_position(
    index: &mut LogIndex,
    key: String,
    position: Option<RecordPosition>,
    budget: usize,
) {
    let Some(positions) = index.positions.as_mut() else {
        return;
    };
    if let Some((old_key, _)) = positions.remove_entry(&key) {
        index.position_bytes -= position_bytes(&old_key);
    }
    if let Some(position) = position {
        let bytes = position_bytes(&key);
        if bytes > budget.saturating_sub(index.position_bytes) {
            index.positions = None;
            index.position_bytes = 0;
            return;
        }
        if index.bytes + index.position_bytes + bytes > budget {
            index.latest = None;
            index.bytes = 0;
        }
        index.position_bytes += bytes;
        positions.insert(key, position);
    }
}

fn position_bytes(key: &String) -> usize {
    128 + key.capacity() + size_of::<(String, RecordPosition)>()
}

pub(super) fn update_index_after_write(
    path: &Path,
    kind: &str,
    next_seq: u64,
    records: Vec<(String, Value)>,
) -> Result<(), StoreError> {
    let indexed = !records.is_empty();
    update_written_index(path, kind, next_seq, indexed, |index, budget| {
        for (key, payload) in records {
            update_payload(index, key, Some(payload), budget);
        }
    })
}

pub(super) fn remove_from_index_after_write(
    path: &Path,
    kind: &str,
    next_seq: u64,
    record_id: &str,
) -> Result<(), StoreError> {
    update_written_index(path, kind, next_seq, true, |index, budget| {
        update_payload(index, record_id.to_string(), None, budget)
    })
}

fn update_written_index(
    path: &Path,
    kind: &str,
    next_seq: u64,
    indexed: bool,
    update: impl FnOnce(&mut LogIndex, usize),
) -> Result<(), StoreError> {
    let metadata = fs::metadata(path)?;
    let mut cache = LOG_INDEXES
        .get_or_init(Default::default)
        .lock()
        .expect("treedx log index poisoned");
    let budget = cache.budget;
    let index = cache
        .indexes
        .entry((path.to_path_buf(), kind.to_string()))
        .or_insert(LogIndex {
            file_len: 0,
            modified: None,
            next_seq,
            line_count: 0,
            latest: None,
            bytes: 0,
            positions: None,
            position_bytes: 0,
        });
    if !indexed {
        index.latest = None;
        index.bytes = 0;
        index.positions = None;
        index.position_bytes = 0;
    }
    if index.positions.is_some() {
        // The per-file append lock still owns this tail. Do not replay the
        // durable prefix merely to index the records that were just appended.
        index.line_count = visit_positioned_envelopes::<Value>(
            path,
            kind,
            RecordPosition {
                offset: index.file_len,
                line: index.line_count + 1,
            },
            |envelope, position| {
                update_position(
                    index,
                    envelope.record_id,
                    if envelope.op == "delete" {
                        None
                    } else {
                        Some(position)
                    },
                    budget,
                );
            },
        )?;
    } else {
        index.line_count += next_seq.saturating_sub(index.next_seq) as usize;
    }
    update(index, budget);
    index.file_len = metadata.len();
    index.modified = metadata.modified().ok();
    index.next_seq = next_seq;
    cache.enforce();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    #[test]
    fn payload_pressure_preserves_log_sequences_and_small_catalog_reads() {
        let mut cache = IndexCache::default();
        for (path, payload) in [
            ("small.tdb", "small".to_string()),
            ("large.tdb", "x".repeat(8192)),
        ] {
            let value = Value::String(payload);
            let key = "record".to_string();
            let bytes = record_bytes(&key, &value);
            cache.indexes.insert(
                (PathBuf::from(path), "test".to_string()),
                LogIndex {
                    file_len: 4096,
                    modified: None,
                    next_seq: 42,
                    line_count: 42,
                    positions: Some(BTreeMap::new()),
                    position_bytes: 0,
                    latest: Some(BTreeMap::from([(key, value)])),
                    bytes,
                },
            );
        }
        cache.budget = 4096;
        cache.enforce();
        assert!(cache.bytes() <= cache.budget);
        assert_eq!(
            cache.indexes.len(),
            2,
            "payload eviction must retain bounded sequence metadata"
        );
        let large = &cache.indexes[&(PathBuf::from("large.tdb"), "test".to_string())];
        assert_eq!(large.next_seq, 42);
        assert_eq!(large.file_len, 4096);
        assert!(large.latest.is_none());
        let small = &cache.indexes[&(PathBuf::from("small.tdb"), "test".to_string())];
        assert_eq!(small.latest.as_ref().unwrap()["record"], "small");
        cache.budget = 1;
        cache.enforce();
        assert!(cache.indexes.is_empty());
        assert!(cache.bytes() <= 1);
    }
    #[test]
    fn owned_json_capacity_and_zero_budget_are_charged() {
        let text = String::with_capacity(4096);
        assert_eq!(payload_bytes(&Value::String(text)), 4096);
        assert_eq!(
            payload_bytes(&Value::Array(Vec::with_capacity(8))),
            8 * size_of::<Value>()
        );
        let mut cache = IndexCache::default();
        cache.enforce();
        assert_eq!(cache.bytes(), 0);
        assert_eq!(cache.budget, 64 * 1024 * 1024);
        cache.budget = 0;
        cache.enforce();
        assert_eq!(cache.bytes(), 0);
    }
}
