//! Blob operations are deferred beyond Phase 1.
use crate::error::GitError;
use crate::refs::resolve_ref;
use crate::types::BlobRead;
use base64::Engine;
use std::path::Path;

pub fn read_blob(repo_path: &Path, ref_name: &str, blob_path: &str) -> Result<BlobRead, GitError> {
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
    let clean_path = blob_path.trim_matches('/');
    let entry = root
        .lookup_entry(clean_path.split('/'))
        .map_err(|err| GitError::Git(err.to_string()))?
        .ok_or_else(|| GitError::NotFound(format!("blob path not found: {clean_path}")))?;
    let object = entry
        .object()
        .map_err(|err| GitError::Git(err.to_string()))?;
    let mut blob = object
        .try_into_blob()
        .map_err(|err| GitError::Git(err.to_string()))?;
    let data = blob.take_data();
    Ok(BlobRead {
        path: clean_path.to_string(),
        object_id: entry.object_id().to_string(),
        byte_length: data.len(),
        content_base64: base64::engine::general_purpose::STANDARD.encode(data),
    })
}
