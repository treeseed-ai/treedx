use crate::error::GitError;
use crate::refs::list_refs;
use crate::types::{FetchRemoteInput, FetchRemoteResult};
use std::collections::BTreeMap;
use std::path::Path;
use std::sync::atomic::AtomicBool;

pub fn fetch_remote(input: FetchRemoteInput) -> Result<FetchRemoteResult, GitError> {
    let repo_path = Path::new(&input.repo_path);
    let before_head = current_head(repo_path);
    let before_refs = ref_map(repo_path)?;
    let remote_name = input.remote_name.unwrap_or_else(|| "origin".to_string());
    let refspecs = if input.refspecs.is_empty() {
        vec![format!("+refs/heads/*:refs/remotes/{remote_name}/*")]
    } else {
        input.refspecs
    };

    if let Some(url) = input.remote_url.as_deref() {
        if is_unsupported_ssh(url) {
            return Err(GitError::UnsupportedTransport(url.to_string()));
        }
    }

    let repo = gix::open(repo_path).map_err(|err| GitError::Git(err.to_string()))?;
    let mut remote = if let Some(url) = input.remote_url.as_deref() {
        repo.remote_at(url)
            .map_err(|err| GitError::Git(err.to_string()))?
    } else {
        repo.find_remote(remote_name.as_str())
            .map_err(|err| GitError::Git(err.to_string()))?
    };
    remote = remote
        .with_refspecs(
            refspecs.iter().map(String::as_str),
            gix::remote::Direction::Fetch,
        )
        .map_err(|err| GitError::Git(err.to_string()))?;

    let connection = remote
        .connect(gix::remote::Direction::Fetch)
        .map_err(|err| GitError::Git(err.to_string()))?;
    let prepare = connection
        .prepare_fetch(gix::progress::Discard, Default::default())
        .map_err(|err| GitError::Git(err.to_string()))?;
    let interrupt = AtomicBool::new(false);
    let outcome = prepare
        .with_dry_run(input.dry_run)
        .receive(gix::progress::Discard, &interrupt)
        .map_err(|err| GitError::Git(err.to_string()))?;

    let after_head = current_head(repo_path);
    let after_refs = ref_map(repo_path)?;
    let updated_refs = after_refs
        .iter()
        .filter(|(name, target)| before_refs.get(*name) != Some(*target))
        .map(|(name, _target)| name.clone())
        .collect::<Vec<_>>();
    let received_pack = matches!(outcome.status, gix::remote::fetch::Status::Change { .. });
    Ok(FetchRemoteResult {
        remote_name,
        remote_url: input.remote_url,
        refspecs,
        updated_refs,
        received_pack,
        before_head,
        after_head,
        status: if input.dry_run { "dry_run" } else { "synced" }.to_string(),
    })
}

fn ref_map(path: &Path) -> Result<BTreeMap<String, String>, GitError> {
    Ok(list_refs(path)?
        .into_iter()
        .filter_map(|reference| reference.target.map(|target| (reference.name, target)))
        .collect())
}

fn current_head(path: &Path) -> Option<String> {
    list_refs(path).ok()?.into_iter().find_map(|reference| {
        (reference.name == "HEAD")
            .then_some(reference.target)
            .flatten()
    })
}

fn is_unsupported_ssh(url: &str) -> bool {
    url.starts_with("ssh://") || url.contains('@') && url.contains(':') && !url.starts_with("file:")
}
