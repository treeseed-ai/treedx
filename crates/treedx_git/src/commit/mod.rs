use crate::error::GitError;
use crate::types::{CommitOverlayInput, CommitOverlayResult};
use base64::Engine;

pub fn commit_overlay(input: CommitOverlayInput) -> Result<CommitOverlayResult, GitError> {
    if input.changes.is_empty() {
        return Err(GitError::Git(
            "at least one file change is required".to_string(),
        ));
    }
    let repo = gix::open(&input.repo_path).map_err(|err| GitError::Git(err.to_string()))?;
    let base_id = gix::ObjectId::from_hex(input.base_commit_sha.as_bytes())
        .map_err(|err| GitError::Git(err.to_string()))?;
    let base_commit = repo
        .find_object(base_id)
        .map_err(|err| GitError::Git(err.to_string()))?
        .peel_to_commit()
        .map_err(|err| GitError::Git(err.to_string()))?;
    let base_tree_id = base_commit
        .tree_id()
        .map_err(|err| GitError::Git(err.to_string()))?
        .detach();
    let mut editor = repo
        .edit_tree(base_tree_id)
        .map_err(|err| GitError::Git(err.to_string()))?;
    let mut changed_paths = Vec::new();

    for change in &input.changes {
        validate_repo_path(&change.path)?;
        match change.op.as_str() {
            "put" => {
                let content_base64 = change.content_base64.as_deref().ok_or_else(|| {
                    GitError::Git(format!("contentBase64 is required for {}", change.path))
                })?;
                let bytes = base64::engine::general_purpose::STANDARD
                    .decode(content_base64)
                    .map_err(|err| GitError::Git(format!("invalid contentBase64: {err}")))?;
                let blob_id = repo
                    .write_object(gix::objs::BlobRef { data: &bytes })
                    .map_err(|err| GitError::Git(err.to_string()))?
                    .detach();
                editor
                    .upsert(
                        change.path.as_str(),
                        gix::objs::tree::EntryKind::Blob,
                        blob_id,
                    )
                    .map_err(|err| GitError::Git(err.to_string()))?;
            }
            "delete" => {
                editor
                    .remove(change.path.as_str())
                    .map_err(|err| GitError::Git(err.to_string()))?;
            }
            other => {
                return Err(GitError::Git(format!(
                    "unsupported file change op: {other}"
                )))
            }
        }
        changed_paths.push(change.path.clone());
    }

    changed_paths.sort();
    changed_paths.dedup();

    let tree_id = editor
        .write()
        .map_err(|err| GitError::Git(err.to_string()))?;

    let timestamp = chrono::Utc::now().timestamp();
    let author = format!(
        "{} <{}> {} +0000",
        input.author_name, input.author_email, timestamp
    );
    let committer = author.clone();
    let author = gix::actor::SignatureRef::from_bytes(author.as_bytes())
        .map_err(|err| GitError::Git(err.to_string()))?;
    let committer = gix::actor::SignatureRef::from_bytes(committer.as_bytes())
        .map_err(|err| GitError::Git(err.to_string()))?;
    let commit = repo
        .new_commit_as(
            committer,
            author,
            input.message.as_str(),
            tree_id,
            [base_id],
        )
        .map_err(|err| GitError::Git(err.to_string()))?
        .detach();
    let commit_id = commit.id;
    repo.reference(
        input.branch_name.as_str(),
        commit_id,
        gix::refs::transaction::PreviousValue::Any,
        format!("treedx commit: {}", input.message),
    )
    .map_err(|err| GitError::Git(err.to_string()))?;

    Ok(CommitOverlayResult {
        commit_sha: commit_id.to_string(),
        branch_name: input.branch_name,
        changed_paths,
        status: "committed".to_string(),
    })
}

fn validate_repo_path(path: &str) -> Result<(), GitError> {
    if path.is_empty()
        || path.starts_with('/')
        || path.contains('\\')
        || path.contains('\0')
        || path.split('/').any(|part| part == ".." || part.is_empty())
    {
        return Err(GitError::Git(format!("invalid repository path: {path}")));
    }
    Ok(())
}
