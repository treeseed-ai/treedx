use std::process::Command;
use tempfile::tempdir;
use treedb_git::*;

#[test]
fn remote_security_rejects_credentials_ssh_wildcards_and_delete_refspecs() {
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

    let credential_url = push_remote(input(
        dir.path(),
        "https://token@example.invalid/repo.git",
        "refs/heads/main:refs/heads/main",
    ))
    .unwrap_err();
    assert_eq!(credential_url.code(), "validation_error");

    let ssh = push_remote(input(
        dir.path(),
        "ssh://example.invalid/repo.git",
        "refs/heads/main:refs/heads/main",
    ))
    .unwrap_err();
    assert_eq!(ssh.code(), "unsupported_transport");

    let wildcard = push_remote(input(
        dir.path(),
        "file:///tmp/remote.git",
        "refs/heads/*:refs/heads/*",
    ))
    .unwrap_err();
    assert_eq!(wildcard.code(), "validation_error");

    let delete_ref = push_remote(input(
        dir.path(),
        "file:///tmp/remote.git",
        ":refs/heads/main",
    ))
    .unwrap_err();
    assert_eq!(delete_ref.code(), "validation_error");
}

fn input(path: &std::path::Path, remote_url: &str, refspec: &str) -> PushRemoteInput {
    PushRemoteInput {
        repo_path: path.display().to_string(),
        remote_url: Some(remote_url.to_string()),
        remote_name: None,
        refspecs: vec![refspec.to_string()],
        dry_run: true,
        expected_remote_head: None,
    }
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
