use crate::error::GitError;
use crate::tree::list_tree_recursive;
use crate::types::{ChangedPath, RecursiveTreeEntry};
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

pub fn changed_paths(
    repo_path: &Path,
    base_ref: &str,
    head_ref: &str,
) -> Result<Vec<ChangedPath>, GitError> {
    let base = tree_map(list_tree_recursive(repo_path, base_ref, None)?);
    let head = tree_map(list_tree_recursive(repo_path, head_ref, None)?);
    let paths: BTreeSet<String> = base.keys().chain(head.keys()).cloned().collect();

    let mut changes = Vec::new();
    for path in paths {
        match (base.get(&path), head.get(&path)) {
            (Some(base_entry), Some(head_entry))
                if base_entry.object_id != head_entry.object_id =>
            {
                changes.push(ChangedPath {
                    path,
                    status: "modified".to_string(),
                    base_object_id: Some(base_entry.object_id.clone()),
                    object_id: Some(head_entry.object_id.clone()),
                    kind: head_entry.kind.clone(),
                });
            }
            (Some(base_entry), None) => changes.push(ChangedPath {
                path,
                status: "deleted".to_string(),
                base_object_id: Some(base_entry.object_id.clone()),
                object_id: None,
                kind: base_entry.kind.clone(),
            }),
            (None, Some(head_entry)) => changes.push(ChangedPath {
                path,
                status: "added".to_string(),
                base_object_id: None,
                object_id: Some(head_entry.object_id.clone()),
                kind: head_entry.kind.clone(),
            }),
            _ => {}
        }
    }

    Ok(changes)
}

fn tree_map(entries: Vec<RecursiveTreeEntry>) -> BTreeMap<String, RecursiveTreeEntry> {
    entries
        .into_iter()
        .filter(|entry| entry.kind == "blob")
        .map(|entry| (entry.path.clone(), entry))
        .collect()
}
