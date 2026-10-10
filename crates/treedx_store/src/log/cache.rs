use super::LogIndex;
use serde_json::Value;
use std::collections::HashMap;
use std::mem::size_of;
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

#[cfg(test)]
mod tests {
    use super::*;
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
