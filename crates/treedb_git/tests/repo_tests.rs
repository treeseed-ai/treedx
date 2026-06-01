use std::process::Command;
use tempfile::tempdir;
use treedb_git::*;

#[test]
fn missing_path_returns_exists_false() {
    let dir = tempdir().unwrap();
    let result = inspect_repository(&dir.path().join("missing")).unwrap();
    assert!(!result.exists);
    assert!(!result.is_git_repository);
}

#[test]
fn non_git_directory_returns_not_git() {
    let dir = tempdir().unwrap();
    let result = inspect_repository(dir.path()).unwrap();
    assert!(result.exists);
    assert!(!result.is_git_repository);
}

#[test]
fn non_bare_repo_can_be_inspected() {
    let dir = tempdir().unwrap();
    git(dir.path(), &["init", "-b", "main"]);
    git(dir.path(), &["config", "user.name", "TreeDB Test"]);
    git(
        dir.path(),
        &["config", "user.email", "test@example.invalid"],
    );
    std::fs::write(dir.path().join("README.md"), "hello").unwrap();
    git(dir.path(), &["add", "README.md"]);
    git(dir.path(), &["commit", "-m", "init"]);
    git(
        dir.path(),
        &[
            "remote",
            "add",
            "origin",
            "https://example.invalid/demo.git",
        ],
    );

    let result = inspect_repository(dir.path()).unwrap();
    assert!(result.exists);
    assert!(result.is_git_repository);
    assert_eq!(result.is_bare, Some(false));
    assert!(result.refs.iter().any(|r| r.name == "refs/heads/main"));
    assert!(result.remotes.iter().any(|r| r.name == "origin"));
}

#[test]
fn refs_remotes_tree_and_blob_can_be_read() {
    let dir = tempdir().unwrap();
    git(dir.path(), &["init", "-b", "main"]);
    git(dir.path(), &["config", "user.name", "TreeDB Test"]);
    git(
        dir.path(),
        &["config", "user.email", "test@example.invalid"],
    );
    std::fs::create_dir_all(dir.path().join("docs")).unwrap();
    std::fs::write(dir.path().join("docs/readme.md"), "hello tree").unwrap();
    git(dir.path(), &["add", "docs/readme.md"]);
    git(dir.path(), &["commit", "-m", "init"]);
    git(dir.path(), &["tag", "v1"]);
    git(
        dir.path(),
        &[
            "remote",
            "add",
            "origin",
            "https://example.invalid/demo.git",
        ],
    );
    let sha = git_stdout(dir.path(), &["rev-parse", "HEAD"]);

    assert!(list_refs(dir.path())
        .unwrap()
        .iter()
        .any(|entry| entry.name == "refs/heads/main"));
    assert_eq!(
        list_remotes(dir.path()).unwrap()[0].url.as_deref(),
        Some("https://example.invalid/demo.git")
    );
    assert_eq!(
        resolve_ref(dir.path(), "refs/heads/main").unwrap().target,
        sha
    );
    assert_eq!(resolve_ref(dir.path(), "refs/tags/v1").unwrap().target, sha);
    assert_eq!(resolve_ref(dir.path(), &sha).unwrap().target, sha);

    let root = list_tree(dir.path(), "refs/heads/main", None).unwrap();
    assert!(root.iter().any(|entry| entry.path == "docs"));
    let docs = list_tree(dir.path(), "refs/heads/main", Some("docs")).unwrap();
    assert!(docs.iter().any(|entry| entry.path == "docs/readme.md"));
    let blob = read_blob(dir.path(), "refs/heads/main", "docs/readme.md").unwrap();
    assert_eq!(blob.byte_length, "hello tree".len());
}

#[test]
fn bare_repo_can_be_inspected() {
    let dir = tempdir().unwrap();
    git(dir.path(), &["init", "--bare"]);
    let result = inspect_repository(dir.path()).unwrap();
    assert!(result.is_git_repository);
    assert_eq!(result.is_bare, Some(true));
}

fn git(cwd: &std::path::Path, args: &[&str]) {
    let output = Command::new("git")
        .args(args)
        .current_dir(cwd)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {:?} failed: {}\n{}",
        args,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn git_stdout(cwd: &std::path::Path, args: &[&str]) -> String {
    let output = Command::new("git")
        .args(args)
        .current_dir(cwd)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {:?} failed: {}\n{}",
        args,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap().trim().to_string()
}
