use crate::error::GitError;
use crate::repo::git_dir;
use crate::types::{GitRefSummary, ResolvedRef};
use std::path::Path;

pub fn list_refs(path: &Path) -> Result<Vec<GitRefSummary>, GitError> {
    let git_dir = git_dir(path);
    let mut refs = Vec::new();
    collect_refs(
        &git_dir.join("refs/heads"),
        "refs/heads",
        "branch",
        &mut refs,
    )?;
    collect_refs(&git_dir.join("refs/tags"), "refs/tags", "tag", &mut refs)?;
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

fn collect_refs(
    dir: &Path,
    prefix: &str,
    kind: &str,
    refs: &mut Vec<GitRefSummary>,
) -> Result<(), GitError> {
    if !dir.exists() {
        return Ok(());
    }
    for entry in std::fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            let name = entry.file_name().to_string_lossy().to_string();
            collect_refs(&path, &format!("{prefix}/{name}"), kind, refs)?;
        } else if path.is_file() {
            let name = entry.file_name().to_string_lossy().to_string();
            let target = std::fs::read_to_string(&path)
                .ok()
                .map(|value| value.trim().to_string());
            refs.push(GitRefSummary {
                name: format!("{prefix}/{name}"),
                target,
                kind: kind.to_string(),
            });
        }
    }
    Ok(())
}
