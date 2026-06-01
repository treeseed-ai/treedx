//! Tree traversal operations are deferred beyond Phase 1.
use crate::error::GitError;
use crate::refs::resolve_ref;
use crate::types::TreeEntrySummary;
use std::path::Path;

pub fn list_tree(
    repo_path: &Path,
    ref_name: &str,
    tree_path: Option<&str>,
) -> Result<Vec<TreeEntrySummary>, GitError> {
    let repo = gix::open(repo_path).map_err(|err| GitError::Git(err.to_string()))?;
    let resolved = resolve_ref(repo_path, ref_name)?;
    let object_id = gix::ObjectId::from_hex(resolved.target.as_bytes())
        .map_err(|err| GitError::Git(err.to_string()))?;
    let commit = repo
        .find_object(object_id)
        .map_err(|err| GitError::Git(err.to_string()))?
        .peel_to_commit()
        .map_err(|err| GitError::Git(err.to_string()))?;
    let root = commit
        .tree()
        .map_err(|err| GitError::Git(err.to_string()))?;
    let path = tree_path.unwrap_or("").trim_matches('/');
    let tree = if path.is_empty() {
        root
    } else {
        let entry = root
            .lookup_entry(path.split('/'))
            .map_err(|err| GitError::Git(err.to_string()))?
            .ok_or_else(|| GitError::NotFound(format!("tree path not found: {path}")))?;
        let object = entry
            .object()
            .map_err(|err| GitError::Git(err.to_string()))?;
        object
            .try_into_tree()
            .map_err(|err| GitError::Git(err.to_string()))?
    };

    let mut entries = Vec::new();
    for entry in tree.iter() {
        let entry = entry.map_err(|err| GitError::Git(err.to_string()))?;
        let name = entry.inner.filename.to_string();
        let full_path = if path.is_empty() {
            name.clone()
        } else {
            format!("{path}/{name}")
        };
        entries.push(TreeEntrySummary {
            path: full_path,
            name,
            object_id: entry.inner.oid.to_string(),
            kind: format!("{:?}", entry.inner.mode.kind()).to_lowercase(),
            mode: format!("{:o}", entry.inner.mode),
        });
    }
    entries.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(entries)
}
