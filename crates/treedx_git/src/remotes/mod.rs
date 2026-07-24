use crate::error::GitError;
use crate::repo::git_dir;
use crate::types::GitRemoteSummary;
use std::collections::BTreeMap;
use std::path::Path;

pub fn list_remotes(path: &Path) -> Result<Vec<GitRemoteSummary>, GitError> {
    let config_path = git_dir(path).join("config");
    let Ok(config) = std::fs::read_to_string(config_path) else {
        return Ok(vec![]);
    };
    let mut current_remote: Option<String> = None;
    let mut remotes = BTreeMap::new();
    for line in config.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("[remote ") {
            current_remote = trimmed.split('"').nth(1).map(|value| value.to_string());
            continue;
        }
        if trimmed.starts_with('[') {
            current_remote = None;
            continue;
        }
        if let Some(name) = current_remote.as_ref() {
            if let Some(url) = trimmed.strip_prefix("url = ") {
                remotes.insert(name.clone(), Some(url.trim().to_string()));
            }
        }
    }
    Ok(remotes
        .into_iter()
        .map(|(name, url)| GitRemoteSummary { name, url })
        .collect())
}
