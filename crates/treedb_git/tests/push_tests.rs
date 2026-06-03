use std::process::Command;
use tempfile::tempdir;
use treedb_git::*;

#[test]
fn local_bare_repo_push_updates_explicit_ref() {
    let local = tempdir().unwrap();
    let remote = tempdir().unwrap();
    git(local.path(), &["init", "-b", "main"]);
    git(local.path(), &["config", "user.name", "TreeDB Test"]);
    git(
        local.path(),
        &["config", "user.email", "test@example.invalid"],
    );
    std::fs::write(local.path().join("README.md"), "hello\n").unwrap();
    git(local.path(), &["add", "README.md"]);
    git(local.path(), &["commit", "-m", "init"]);
    git(remote.path(), &["init", "--bare"]);
    let local_head = git_stdout(local.path(), &["rev-parse", "refs/heads/main"]);

    let result = push_remote(PushRemoteInput {
        repo_path: local.path().display().to_string(),
        remote_url: Some(format!("file://{}", remote.path().display())),
        remote_name: Some("origin".to_string()),
        refspecs: vec!["refs/heads/main:refs/heads/main".to_string()],
        dry_run: false,
        expected_remote_head: None,
    })
    .unwrap();

    assert_eq!(result.status, "pushed");
    assert_eq!(result.backend, "gix");
    assert_eq!(result.updated_refs, vec!["refs/heads/main"]);
    assert_eq!(
        git_stdout_bare(remote.path(), &["rev-parse", "refs/heads/main"]),
        local_head
    );
}

#[test]
fn dry_run_validates_without_remote_mutation() {
    let local = tempdir().unwrap();
    let remote = tempdir().unwrap();
    git(local.path(), &["init", "-b", "main"]);
    git(local.path(), &["config", "user.name", "TreeDB Test"]);
    git(
        local.path(),
        &["config", "user.email", "test@example.invalid"],
    );
    std::fs::write(local.path().join("README.md"), "hello\n").unwrap();
    git(local.path(), &["add", "README.md"]);
    git(local.path(), &["commit", "-m", "init"]);
    git(remote.path(), &["init", "--bare"]);

    let result = push_remote(PushRemoteInput {
        repo_path: local.path().display().to_string(),
        remote_url: Some(format!("file://{}", remote.path().display())),
        remote_name: Some("origin".to_string()),
        refspecs: vec!["refs/heads/main:refs/heads/main".to_string()],
        dry_run: true,
        expected_remote_head: None,
    })
    .unwrap();

    assert_eq!(result.status, "dry_run");
    assert_eq!(result.updated_refs, vec!["refs/heads/main"]);
    assert!(git_stdout_bare_result(remote.path(), &["rev-parse", "refs/heads/main"]).is_err());
}

#[test]
fn push_rejects_unsafe_or_unsupported_refspecs_and_urls() {
    let dir = tempdir().unwrap();
    git(dir.path(), &["init", "-b", "main"]);
    git(dir.path(), &["config", "user.name", "TreeDB Test"]);
    git(
        dir.path(),
        &["config", "user.email", "test@example.invalid"],
    );
    std::fs::write(dir.path().join("README.md"), "hello\n").unwrap();
    git(dir.path(), &["add", "README.md"]);
    git(dir.path(), &["commit", "-m", "init"]);

    let wildcard = push_remote(PushRemoteInput {
        repo_path: dir.path().display().to_string(),
        remote_url: Some("file:///tmp/remote.git".to_string()),
        remote_name: None,
        refspecs: vec!["refs/heads/*:refs/heads/*".to_string()],
        dry_run: true,
        expected_remote_head: None,
    })
    .unwrap_err();
    assert_eq!(wildcard.code(), "validation_error");

    let credentials = push_remote(PushRemoteInput {
        repo_path: dir.path().display().to_string(),
        remote_url: Some("https://token@example.invalid/repo.git".to_string()),
        remote_name: None,
        refspecs: vec!["refs/heads/main:refs/heads/main".to_string()],
        dry_run: true,
        expected_remote_head: None,
    })
    .unwrap_err();
    assert_eq!(credentials.code(), "validation_error");

    let ssh = push_remote(PushRemoteInput {
        repo_path: dir.path().display().to_string(),
        remote_url: Some("ssh://example.invalid/repo.git".to_string()),
        remote_name: None,
        refspecs: vec!["refs/heads/main:refs/heads/main".to_string()],
        dry_run: true,
        expected_remote_head: None,
    })
    .unwrap_err();
    assert_eq!(ssh.code(), "unsupported_transport");
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
    assert!(output.status.success());
    String::from_utf8(output.stdout).unwrap().trim().to_string()
}

fn git_stdout_bare(cwd: &std::path::Path, args: &[&str]) -> String {
    git_stdout_bare_result(cwd, args).unwrap()
}

fn git_stdout_bare_result(cwd: &std::path::Path, args: &[&str]) -> Result<String, String> {
    let output = Command::new("git")
        .arg("--git-dir")
        .arg(cwd)
        .args(args)
        .output()
        .unwrap();
    if output.status.success() {
        Ok(String::from_utf8(output.stdout).unwrap().trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).to_string())
    }
}
