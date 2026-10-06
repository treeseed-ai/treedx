use crate::error::GitError;
use crate::types::{GitRefSummary, ResolvedRef};
use std::path::Path;

pub fn list_refs(path: &Path) -> Result<Vec<GitRefSummary>, GitError> {
    let repo = gix::open(path).map_err(|err| GitError::Git(err.to_string()))?;
    let references = repo
        .references()
        .map_err(|err| GitError::Git(err.to_string()))?;
    let mut refs = Vec::new();
    for item in references
        .all()
        .map_err(|err| GitError::Git(err.to_string()))?
    {
        let reference = item.map_err(|err| GitError::Git(err.to_string()))?;
        let name = reference.name().to_string();
        let kind = if name.starts_with("refs/heads/") {
            "branch"
        } else if name.starts_with("refs/remotes/") {
            "remote"
        } else if name.starts_with("refs/tags/") {
            "tag"
        } else if name.starts_with("refs/treedx/commits/") {
            "preserved_commit"
        } else {
            continue;
        };
        refs.push(GitRefSummary {
            name,
            target: reference.try_id().map(|id| id.to_string()),
            kind: kind.to_string(),
        });
    }
    refs.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(refs)
}

pub fn resolve_ref(path: &Path, ref_name: &str) -> Result<ResolvedRef, GitError> {
    let repo = gix::open(path).map_err(|err| GitError::Git(err.to_string()))?;
    if let Ok(mut reference) = repo.find_reference(ref_name) {
        let commit = reference
            .peel_to_commit()
            .map_err(|err| GitError::Git(err.to_string()))?;
        return Ok(ResolvedRef {
            name: ref_name.to_string(),
            target: commit.id.to_string(),
            kind: "commit".to_string(),
        });
    }

    let object_id = gix::ObjectId::from_hex(ref_name.as_bytes())
        .map_err(|_| GitError::NotFound(format!("ref or object not found: {ref_name}")))?;
    let object = repo
        .find_object(object_id)
        .map_err(|err| GitError::Git(err.to_string()))?;
    let peeled = object
        .peel_to_kind(gix::object::Kind::Commit)
        .map_err(|err| GitError::Git(err.to_string()))?;
    Ok(ResolvedRef {
        name: ref_name.to_string(),
        target: peeled.id.to_string(),
        kind: "commit".to_string(),
    })
}
