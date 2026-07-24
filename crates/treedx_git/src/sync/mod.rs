use crate::error::GitError;
use crate::refs::list_refs;
use crate::types::{FetchRemoteInput, FetchRemoteResult, PushRemoteInput, PushRemoteResult};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
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

    if input.plan {
        return Ok(FetchRemoteResult {
            remote_name,
            remote_url: input.remote_url,
            refspecs,
            updated_refs: Vec::new(),
            received_pack: false,
            before_head: before_head.clone(),
            after_head: before_head,
            status: "plan".to_string(),
        });
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
        status: if input.plan { "plan" } else { "synced" }.to_string(),
    })
}

pub fn push_remote(input: PushRemoteInput) -> Result<PushRemoteResult, GitError> {
    let repo_path = Path::new(&input.repo_path);
    let remote_name = input.remote_name.unwrap_or_else(|| "origin".to_string());
    let refspecs = validate_push_refspecs(input.refspecs)?;
    let remote_url = resolve_remote_url(repo_path, input.remote_url, &remote_name)?;

    if has_url_credentials(&remote_url) {
        return Err(GitError::Validation(
            "remoteUrl must not contain credentials".to_string(),
        ));
    }
    if is_unsupported_ssh(&remote_url) {
        return Err(GitError::UnsupportedTransport(remote_url));
    }
    if (remote_url.starts_with("http://") || remote_url.starts_with("https://")) && !input.plan {
        return Err(GitError::UnsupportedTransport(remote_url));
    }

    let updates = resolve_push_updates(repo_path, &refspecs)?;
    let remote_path = local_remote_path(&remote_url);
    let before_refs = remote_path
        .as_deref()
        .map(ref_map)
        .transpose()?
        .unwrap_or_default();
    let before_head = remote_path.as_deref().and_then(current_head);

    if let Some(expected) = input.expected_remote_head.as_deref() {
        if before_head.as_deref() != Some(expected) {
            return Err(GitError::Conflict(
                "expectedRemoteHead does not match remote HEAD".to_string(),
            ));
        }
    }

    if !input.plan {
        let remote_path = remote_path
            .as_ref()
            .ok_or_else(|| GitError::UnsupportedTransport(remote_url.clone()))?;
        let local_git_dir = git_dir(repo_path)?;
        let remote_git_dir = git_dir(remote_path)?;
        copy_loose_objects(&local_git_dir, &remote_git_dir)?;

        for (src, dst, oid) in &updates {
            let _ = src;
            write_ref(&remote_git_dir, dst, oid)?;
        }
    }

    let after_refs = remote_path
        .as_deref()
        .map(ref_map)
        .transpose()?
        .unwrap_or_default();
    let after_head = remote_path.as_deref().and_then(current_head);
    let updated_refs = if input.plan {
        updates.iter().map(|(_, dst, _)| dst.clone()).collect()
    } else {
        after_refs
            .iter()
            .filter(|(name, target)| before_refs.get(*name) != Some(*target))
            .map(|(name, _target)| name.clone())
            .collect()
    };

    Ok(PushRemoteResult {
        remote_name,
        remote_url: Some(remote_url),
        refspecs,
        updated_refs,
        rejected_refs: Vec::new(),
        before_head,
        after_head,
        status: if input.plan { "plan" } else { "pushed" }.to_string(),
        backend: "gix".to_string(),
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

fn validate_push_refspecs(refspecs: Vec<String>) -> Result<Vec<String>, GitError> {
    if refspecs.is_empty() {
        return Err(GitError::Validation(
            "at least one explicit refspec is required".to_string(),
        ));
    }
    for refspec in &refspecs {
        if refspec.contains('*') {
            return Err(GitError::Validation(
                "wildcard push refspecs are not supported".to_string(),
            ));
        }
        let stripped = refspec.strip_prefix('+').unwrap_or(refspec);
        let Some((src, dst)) = stripped.split_once(':') else {
            return Err(GitError::Validation(
                "push refspec must include source and destination".to_string(),
            ));
        };
        if src.is_empty() || dst.is_empty() {
            return Err(GitError::Validation(
                "delete push refspecs are not supported".to_string(),
            ));
        }
        if !is_push_ref(src) || !is_push_ref(dst) {
            return Err(GitError::Validation(
                "push refspecs must use refs/heads or refs/tags".to_string(),
            ));
        }
    }
    Ok(refspecs)
}

fn is_push_ref(value: &str) -> bool {
    value.starts_with("refs/heads/") || value.starts_with("refs/tags/")
}

fn resolve_remote_url(
    repo_path: &Path,
    remote_url: Option<String>,
    remote_name: &str,
) -> Result<String, GitError> {
    if let Some(url) = remote_url {
        return Ok(url);
    }
    let repo = gix::open(repo_path).map_err(|err| GitError::Git(err.to_string()))?;
    let remote = repo
        .find_remote(remote_name)
        .map_err(|err| GitError::Git(err.to_string()))?;
    remote
        .url(gix::remote::Direction::Push)
        .map(|url| url.to_bstring().to_string())
        .ok_or_else(|| GitError::NotFound(format!("remote {remote_name} has no URL")))
}

fn has_url_credentials(url: &str) -> bool {
    (url.starts_with("http://") || url.starts_with("https://") || url.starts_with("file://"))
        && url
            .split_once("://")
            .map(|(_, rest)| rest.split('/').next().unwrap_or("").contains('@'))
            .unwrap_or(false)
}

fn local_remote_path(url: &str) -> Option<PathBuf> {
    if let Some(path) = url.strip_prefix("file://") {
        Some(PathBuf::from(path))
    } else if url.starts_with("http://") || url.starts_with("https://") {
        None
    } else {
        Some(PathBuf::from(url))
    }
}

fn resolve_push_updates(
    repo_path: &Path,
    refspecs: &[String],
) -> Result<Vec<(String, String, String)>, GitError> {
    let refs = ref_map(repo_path)?;
    refspecs
        .iter()
        .map(|refspec| {
            let stripped = refspec.strip_prefix('+').unwrap_or(refspec);
            let (src, dst) = stripped.split_once(':').ok_or_else(|| {
                GitError::Validation("push refspec must include source and destination".to_string())
            })?;
            let oid = refs
                .get(src)
                .ok_or_else(|| GitError::NotFound(format!("source ref {src} not found")))?;
            Ok((src.to_string(), dst.to_string(), oid.clone()))
        })
        .collect()
}

fn git_dir(path: &Path) -> Result<PathBuf, GitError> {
    let dot_git = path.join(".git");
    if dot_git.is_dir() {
        Ok(dot_git)
    } else if path.join("objects").is_dir() && path.join("refs").is_dir() {
        Ok(path.to_path_buf())
    } else {
        Err(GitError::Validation(format!(
            "{} is not a local git repository",
            path.display()
        )))
    }
}

fn copy_loose_objects(local_git_dir: &Path, remote_git_dir: &Path) -> Result<(), GitError> {
    let local_objects = local_git_dir.join("objects");
    let remote_objects = remote_git_dir.join("objects");
    fs::create_dir_all(&remote_objects)?;
    for entry in fs::read_dir(&local_objects)? {
        let entry = entry?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.len() != 2 {
            continue;
        }
        let file_type = entry.file_type()?;
        if !file_type.is_dir() {
            continue;
        }
        let target_dir = remote_objects.join(name.as_ref());
        fs::create_dir_all(&target_dir)?;
        for object in fs::read_dir(entry.path())? {
            let object = object?;
            if object.file_type()?.is_file() {
                let target = target_dir.join(object.file_name());
                if !target.exists() {
                    fs::copy(object.path(), target)?;
                }
            }
        }
    }
    Ok(())
}

fn write_ref(remote_git_dir: &Path, ref_name: &str, oid: &str) -> Result<(), GitError> {
    let path = remote_git_dir.join(ref_name);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, format!("{oid}\n"))?;
    Ok(())
}
