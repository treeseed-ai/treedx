use crate::error::GitError;
use crate::refs::list_refs;
use crate::remotes::list_remotes;
use crate::types::RepositoryInspection;
use std::path::{Path, PathBuf};

pub fn inspect_repository(path: &Path) -> Result<RepositoryInspection, GitError> {
    if !path.exists() {
        return Ok(RepositoryInspection {
            path: path.display().to_string(),
            exists: false,
            is_git_repository: false,
            is_bare: None,
            head: None,
            refs: vec![],
            remotes: vec![],
        });
    }

    let repo = match gix::open(path) {
        Ok(repo) => repo,
        Err(_) => {
            return Ok(RepositoryInspection {
                path: path.display().to_string(),
                exists: true,
                is_git_repository: false,
                is_bare: None,
                head: None,
                refs: vec![],
                remotes: vec![],
            });
        }
    };

    let is_bare = is_bare_repo(path);
    let head = read_head(path, is_bare);

    drop(repo);
    Ok(RepositoryInspection {
        path: path.display().to_string(),
        exists: true,
        is_git_repository: true,
        is_bare: Some(is_bare),
        head,
        refs: list_refs(path)?,
        remotes: list_remotes(path)?,
    })
}

pub(crate) fn git_dir(path: &Path) -> PathBuf {
    let dot_git = path.join(".git");
    if dot_git.is_dir() {
        dot_git
    } else {
        path.to_path_buf()
    }
}

fn is_bare_repo(path: &Path) -> bool {
    path.join("HEAD").is_file() && path.join("objects").is_dir() && path.join("refs").is_dir()
}

fn read_head(path: &Path, is_bare: bool) -> Option<String> {
    let head_path = if is_bare {
        path.join("HEAD")
    } else {
        path.join(".git/HEAD")
    };
    let raw = std::fs::read_to_string(head_path).ok()?;
    let trimmed = raw.trim();
    Some(trimmed.strip_prefix("ref: ").unwrap_or(trimmed).to_string())
}
