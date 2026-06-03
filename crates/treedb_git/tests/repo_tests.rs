use base64::Engine;
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

    let recursive = list_tree_recursive(dir.path(), "refs/heads/main", None).unwrap();
    assert!(recursive
        .iter()
        .any(|entry| entry.path == "docs/readme.md" && entry.kind == "blob"));
}

#[test]
fn blob_read_is_binary_safe() {
    let dir = tempdir().unwrap();
    git(dir.path(), &["init", "-b", "main"]);
    git(dir.path(), &["config", "user.name", "TreeDB Test"]);
    git(
        dir.path(),
        &["config", "user.email", "test@example.invalid"],
    );
    std::fs::create_dir_all(dir.path().join("assets")).unwrap();
    let bytes = vec![0, 159, 146, 150, 255];
    std::fs::write(dir.path().join("assets/logo.bin"), &bytes).unwrap();
    git(dir.path(), &["add", "assets/logo.bin"]);
    git(dir.path(), &["commit", "-m", "binary"]);

    let blob = read_blob(dir.path(), "refs/heads/main", "assets/logo.bin").unwrap();
    assert_eq!(blob.byte_length, bytes.len());
    assert_eq!(
        blob.content_base64,
        base64::engine::general_purpose::STANDARD.encode(bytes)
    );
}

#[test]
fn bare_repo_can_be_inspected() {
    let dir = tempdir().unwrap();
    git(dir.path(), &["init", "--bare"]);
    let result = inspect_repository(dir.path()).unwrap();
    assert!(result.is_git_repository);
    assert_eq!(result.is_bare, Some(true));
}

#[test]
fn commit_overlay_writes_modifies_and_deletes_files() {
    let dir = tempdir().unwrap();
    git(dir.path(), &["init", "-b", "main"]);
    git(dir.path(), &["config", "user.name", "TreeDB Test"]);
    git(
        dir.path(),
        &["config", "user.email", "test@example.invalid"],
    );
    std::fs::create_dir_all(dir.path().join("docs")).unwrap();
    std::fs::write(dir.path().join("docs/readme.md"), "hello\n").unwrap();
    std::fs::write(dir.path().join("docs/delete.md"), "remove me\n").unwrap();
    git(dir.path(), &["add", "docs/readme.md", "docs/delete.md"]);
    git(dir.path(), &["commit", "-m", "init"]);
    let base = git_stdout(dir.path(), &["rev-parse", "HEAD"]);

    let result = commit_overlay(CommitOverlayInput {
        repo_path: dir.path().display().to_string(),
        base_commit_sha: base,
        branch_name: "refs/heads/agent/overlay".to_string(),
        message: "overlay commit".to_string(),
        author_name: "TreeDB Test".to_string(),
        author_email: "test@example.invalid".to_string(),
        changes: vec![
            FileChange {
                path: "docs/readme.md".to_string(),
                op: "put".to_string(),
                content_base64: Some(base64::engine::general_purpose::STANDARD.encode("updated\n")),
                expected_sha: None,
            },
            FileChange {
                path: "docs/new.md".to_string(),
                op: "put".to_string(),
                content_base64: Some(base64::engine::general_purpose::STANDARD.encode("new\n")),
                expected_sha: None,
            },
            FileChange {
                path: "docs/delete.md".to_string(),
                op: "delete".to_string(),
                content_base64: None,
                expected_sha: None,
            },
        ],
    })
    .unwrap();

    assert_eq!(result.status, "committed");
    assert!(result.changed_paths.contains(&"docs/new.md".to_string()));
    assert_eq!(
        resolve_ref(dir.path(), "refs/heads/agent/overlay")
            .unwrap()
            .target,
        result.commit_sha
    );
    let updated = read_blob(dir.path(), "refs/heads/agent/overlay", "docs/readme.md").unwrap();
    assert_eq!(updated.byte_length, "updated\n".len());
    assert!(read_blob(dir.path(), "refs/heads/agent/overlay", "docs/new.md").is_ok());
    assert!(read_blob(dir.path(), "refs/heads/agent/overlay", "docs/delete.md").is_err());
}

#[test]
fn changed_paths_reports_added_modified_and_deleted_files() {
    let dir = tempdir().unwrap();
    git(dir.path(), &["init", "-b", "main"]);
    git(dir.path(), &["config", "user.name", "TreeDB Test"]);
    git(
        dir.path(),
        &["config", "user.email", "test@example.invalid"],
    );
    std::fs::create_dir_all(dir.path().join("docs")).unwrap();
    std::fs::write(dir.path().join("docs/readme.md"), "hello\n").unwrap();
    std::fs::write(dir.path().join("docs/delete.md"), "remove\n").unwrap();
    git(dir.path(), &["add", "docs/readme.md", "docs/delete.md"]);
    git(dir.path(), &["commit", "-m", "init"]);
    git(dir.path(), &["checkout", "-b", "feature"]);
    std::fs::write(dir.path().join("docs/readme.md"), "updated\n").unwrap();
    std::fs::write(dir.path().join("docs/new.md"), "new\n").unwrap();
    std::fs::remove_file(dir.path().join("docs/delete.md")).unwrap();
    git(dir.path(), &["add", "-A"]);
    git(dir.path(), &["commit", "-m", "feature"]);

    let changes = changed_paths(dir.path(), "refs/heads/main", "refs/heads/feature").unwrap();
    assert_eq!(
        changes
            .iter()
            .map(|change| change.path.as_str())
            .collect::<Vec<_>>(),
        vec!["docs/delete.md", "docs/new.md", "docs/readme.md"]
    );
    assert_eq!(
        changes
            .iter()
            .find(|change| change.path == "docs/delete.md")
            .unwrap()
            .status,
        "deleted"
    );
    assert_eq!(
        changes
            .iter()
            .find(|change| change.path == "docs/new.md")
            .unwrap()
            .status,
        "added"
    );
    assert_eq!(
        changes
            .iter()
            .find(|change| change.path == "docs/readme.md")
            .unwrap()
            .status,
        "modified"
    );
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
