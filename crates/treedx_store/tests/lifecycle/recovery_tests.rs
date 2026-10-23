use std::io::Write;
use tempfile::tempdir;
use treedx_store::*;

#[test]
fn interrupted_seen_token_append_blocks_startup_and_preserves_all_original_bytes() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();
    let path = dir.path().join("catalog/connected_tokens.tdb");
    let mut file = std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap();
    file.write_all(br#"{"schemaVersion":1,"seq":1,"op":"put","recordKind":"connected_token","recordId":"interrupted"#).unwrap();
    file.sync_all().unwrap();
    let original = std::fs::read(&path).unwrap();
    let error = init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap_err();
    assert_eq!(error.code(), "invalid_record");
    assert!(error.to_string().contains("EOF"));
    assert_eq!(std::fs::read(&path).unwrap(), original);
}

fn seen_token_fixture() -> (tempfile::TempDir, std::path::PathBuf, ConnectedTokenRecord) {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();
    std::fs::write(dir.path().join(".treedx.lock"), "stopped\n").unwrap();
    let record = ConnectedTokenRecord {
        jti: "private-jti".into(),
        actor_id: "private-actor".into(),
        tenant_id: "tenant".into(),
        issuer: "issuer".into(),
        audience: "audience".into(),
        subject: "subject".into(),
        expires_at: chrono::Utc::now(),
        seen_at: chrono::Utc::now(),
    };
    put_connected_token(dir.path(), record.clone()).unwrap();
    let path = dir.path().join("catalog/connected_tokens.tdb");
    (dir, path, record)
}

fn run_recovery(dir: &std::path::Path, digest: Option<&str>) -> std::process::Output {
    let mut command = std::process::Command::new(env!("CARGO_BIN_EXE_treedx_store_recover"));
    command.arg(dir);
    command.arg("catalog/connected_tokens.tdb");
    if let Some(digest) = digest {
        command.args(["--apply", digest]);
    }
    command.output().unwrap()
}

#[test]
fn native_offline_tail_plan_apply_preserves_original_and_restores_exact_startup_readback() {
    let (dir, path, record) = seen_token_fixture();
    let complete = std::fs::read(&path).unwrap();
    std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(br#"{"schemaVersion":1,"recordId":"unfinished"#)
        .unwrap();
    let original = std::fs::read(&path).unwrap();
    let planned = run_recovery(dir.path(), None);
    assert!(
        planned.status.success(),
        "{}",
        String::from_utf8_lossy(&planned.stderr)
    );
    let plan: serde_json::Value = serde_json::from_slice(&planned.stdout).unwrap();
    assert_eq!(plan["originalBytes"], original.len());
    assert_eq!(plan["retainedBytes"], complete.len());
    assert_eq!(plan["retainedRecords"], 1);
    assert_eq!(plan["incompleteBytes"], original.len() - complete.len());
    assert_eq!(plan["applied"], false);
    assert!(plan["backup"].is_null());
    assert_eq!(std::fs::read(&path).unwrap(), original);
    assert!(!dir.path().join("recovery/backups").exists());
    assert!(!String::from_utf8_lossy(&planned.stdout).contains("private-"));
    assert!(!run_recovery(dir.path(), Some("blake3:changed"))
        .status
        .success());
    assert_eq!(std::fs::read(&path).unwrap(), original);
    let expected = plan["sourceDigest"].as_str().unwrap();
    let applied = run_recovery(dir.path(), Some(expected));
    assert!(
        applied.status.success(),
        "{}",
        String::from_utf8_lossy(&applied.stderr)
    );
    let report: serde_json::Value = serde_json::from_slice(&applied.stdout).unwrap();
    assert_eq!(report["applied"], true);
    let relative = report["backup"]
        .as_str()
        .unwrap()
        .strip_prefix("treedx://backup/")
        .unwrap();
    assert_eq!(
        std::fs::read(dir.path().join("recovery/backups").join(relative)).unwrap(),
        original
    );
    assert_eq!(std::fs::read(&path).unwrap(), complete);
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();
    assert_eq!(
        serde_json::to_value(
            get_connected_token(dir.path(), &record.jti)
                .unwrap()
                .unwrap()
        )
        .unwrap(),
        serde_json::to_value(record).unwrap()
    );
    assert!(!run_recovery(dir.path(), Some(expected)).status.success());
    assert_eq!(std::fs::read(&path).unwrap(), complete);
    assert!(run_recovery(dir.path(), None).status.success());
}

#[test]
fn native_tail_recovery_denies_active_owner_changed_input_and_corrupt_complete_records() {
    for suffix in [
        b"{\"schemaVersion\":\n".as_slice(),
        b"{invalid}\n",
        b"{\"schemaVersion\":\n{}",
    ] {
        let (dir, path, _) = seen_token_fixture();
        std::fs::OpenOptions::new()
            .append(true)
            .open(&path)
            .unwrap()
            .write_all(suffix)
            .unwrap();
        let original = std::fs::read(&path).unwrap();
        assert!(!run_recovery(dir.path(), None).status.success());
        assert_eq!(std::fs::read(&path).unwrap(), original);
        assert!(!dir.path().join("recovery/backups").exists());
    }
    let (dir, path, _) = seen_token_fixture();
    let lock = std::fs::File::open(dir.path().join(".treedx.lock")).unwrap();
    lock.try_lock().unwrap();
    assert!(!run_recovery(dir.path(), None).status.success());
    drop(lock);
    std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(b"{\"schemaVersion\":")
        .unwrap();
    let plan: serde_json::Value =
        serde_json::from_slice(&run_recovery(dir.path(), None).stdout).unwrap();
    std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(b"1")
        .unwrap();
    let changed = std::fs::read(&path).unwrap();
    assert!(
        !run_recovery(dir.path(), Some(plan["sourceDigest"].as_str().unwrap()))
            .status
            .success()
    );
    assert_eq!(std::fs::read(&path).unwrap(), changed);
}

#[test]
fn native_tail_recovery_keeps_checksum_kind_and_symlink_denials() {
    use std::os::unix::fs::symlink;
    for mode in ["checksum", "kind", "source-link", "backup-link"] {
        let (dir, path, _) = seen_token_fixture();
        let bytes = std::fs::read_to_string(&path).unwrap();
        if mode == "checksum" {
            std::fs::write(&path, bytes.replace("private-actor", "changed-actor")).unwrap();
        }
        if mode == "kind" {
            std::fs::write(
                &path,
                bytes.replace(
                    "\"recordKind\":\"connected_token\"",
                    "\"recordKind\":\"other\"",
                ),
            )
            .unwrap();
        }
        std::fs::OpenOptions::new()
            .append(true)
            .open(&path)
            .unwrap()
            .write_all(b"{\"schemaVersion\":")
            .unwrap();
        let original = std::fs::read(&path).unwrap();
        let external = tempdir().unwrap();
        if mode == "source-link" {
            std::fs::rename(&path, external.path().join("original")).unwrap();
            symlink(external.path().join("original"), &path).unwrap();
        }
        if mode == "backup-link" {
            symlink(external.path(), dir.path().join("recovery/backups")).unwrap();
        }
        let planned = run_recovery(dir.path(), None);
        if mode == "backup-link" {
            assert!(planned.status.success());
            let plan: serde_json::Value = serde_json::from_slice(&planned.stdout).unwrap();
            assert!(
                !run_recovery(dir.path(), Some(plan["sourceDigest"].as_str().unwrap()))
                    .status
                    .success()
            );
            assert_eq!(std::fs::read_dir(external.path()).unwrap().count(), 0);
        } else {
            assert!(!planned.status.success());
        }
        assert_eq!(std::fs::read(&path).unwrap(), original);
    }
}

#[test]
fn managed_entrypoint_holds_the_same_offline_recovery_lock_until_service_exit() {
    use std::io::BufRead;
    use std::process::{Command, Stdio};
    let (dir, path, _) = seen_token_fixture();
    let before = std::fs::read(&path).unwrap();
    let entrypoint =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docker-entrypoint.sh");
    let mut service = Command::new("sh")
        .arg(entrypoint)
        .args(["/bin/sh", "-c", "printf 'locked\\n'; exec sleep 30"])
        .env("TREEDX_DATA_DIR", dir.path())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut ready = String::new();
    std::io::BufReader::new(service.stdout.take().unwrap())
        .read_line(&mut ready)
        .unwrap();
    let denied = run_recovery(dir.path(), None);
    service.kill().unwrap();
    service.wait().unwrap();
    assert_eq!(ready, "locked\n");
    assert!(!denied.status.success());
    assert!(String::from_utf8_lossy(&denied.stderr).contains("Stop the TreeDX service"));
    assert!(run_recovery(dir.path(), None).status.success());
    assert_eq!(std::fs::read(&path).unwrap(), before);
}

#[test]
fn interrupted_recovery_staging_is_retained_and_does_not_block_an_exact_retry() {
    let (dir, path, _) = seen_token_fixture();
    std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(b"{\"schemaVersion\":")
        .unwrap();
    let planned = run_recovery(dir.path(), None);
    let plan: serde_json::Value = serde_json::from_slice(&planned.stdout).unwrap();
    let id = plan["sourceDigest"]
        .as_str()
        .unwrap()
        .strip_prefix("blake3:")
        .unwrap();
    let backup = dir
        .path()
        .join("recovery/backups")
        .join(format!("log-tail-{id}"));
    std::fs::create_dir_all(&backup).unwrap();
    std::fs::write(
        backup.join("interrupted.pending"),
        b"failed backup copy evidence",
    )
    .unwrap();
    let audit = dir.path().join("audit/events.tdb");
    let original_audit = std::fs::read(&audit).unwrap();
    let applied = run_recovery(dir.path(), plan["sourceDigest"].as_str());
    assert!(applied.status.success());
    assert_eq!(
        std::fs::read(backup.join("interrupted.pending")).unwrap(),
        b"failed backup copy evidence"
    );
    assert_eq!(std::fs::read(audit).unwrap(), original_audit);
}

#[test]
fn native_tail_recovery_retains_completed_delete_history_without_resurrecting_a_token() {
    let (dir, path, record) = seen_token_fixture();
    treedx_store::log::append_delete(&path, "connected_token", &record.jti).unwrap();
    let complete = std::fs::read(&path).unwrap();
    std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(b"{\"schemaVersion\":")
        .unwrap();
    let plan: serde_json::Value =
        serde_json::from_slice(&run_recovery(dir.path(), None).stdout).unwrap();
    assert_eq!(plan["retainedRecords"], 2);
    assert!(run_recovery(dir.path(), plan["sourceDigest"].as_str())
        .status
        .success());
    assert_eq!(std::fs::read(path).unwrap(), complete);
    assert!(get_connected_token(dir.path(), &record.jti)
        .unwrap()
        .is_none());
}

#[test]
fn corrupt_payload_checksum_returns_recovery_error() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    put_repository(
        dir.path(),
        RepositoryInput {
            name: "demo".to_string(),
            repository_name: Some("demo".to_string()),
            local_path: Some("/var/lib/treedx/repos/bare/demo.git".to_string()),
            storage_relative_path: Some("repositories/demo".to_string()),
            default_ref: None,
            remote_url: None,
        },
    )
    .unwrap();
    let path = dir.path().join("catalog/repositories.tdb");
    let mut raw = std::fs::read_to_string(&path).unwrap();
    raw = raw.replace("\"name\":\"demo\"", "\"name\":\"tampered\"");
    let mut file = std::fs::File::create(&path).unwrap();
    file.write_all(raw.as_bytes()).unwrap();
    let err = list_repositories(dir.path()).unwrap_err();
    assert_eq!(err.code(), "checksum_mismatch");
}

#[test]
fn compaction_preserves_latest_records_and_skips_audit_logs() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    for name in ["one", "two"] {
        put_repository(
            dir.path(),
            RepositoryInput {
                name: name.to_string(),
                repository_name: Some(name.to_string()),
                local_path: Some(format!("/var/lib/treedx/repos/bare/{name}.git")),
                storage_relative_path: Some(format!("repositories/{name}")),
                default_ref: None,
                remote_url: None,
            },
        )
        .unwrap();
    }
    append_audit_event(
        dir.path(),
        AuditEventInput {
            event_type: "storage.test".to_string(),
            actor_id: None,
            tenant_id: None,
            repo_id: None,
            node_id: None,
            workspace_id: None,
            operation: None,
            status: Some("ok".to_string()),
            request_id: None,
            requested_scope: None,
            effective_scope: None,
            data: serde_json::json!({}),
        },
    )
    .unwrap();
    let audit_before = std::fs::metadata(dir.path().join("audit/events.tdb"))
        .unwrap()
        .len();

    let result = compact_storage(
        dir.path(),
        StorageCompactInput {
            logs: vec![],
            plan: false,
            backup_before: true,
        },
    )
    .unwrap();

    assert_eq!(result.status, "ok");
    assert!(result.backup_id.is_some());
    assert!(result
        .files
        .iter()
        .any(|file| file.file == "catalog/repositories.tdb"));
    assert_eq!(list_repositories(dir.path()).unwrap().len(), 2);
    assert_eq!(
        std::fs::metadata(dir.path().join("audit/events.tdb"))
            .unwrap()
            .len(),
        audit_before
    );
}

#[test]
fn backup_archive_verifies_and_uses_logical_uri() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    let backup = create_backup(
        dir.path(),
        StorageBackupInput {
            include: vec!["catalog".to_string(), "snapshots".to_string()],
            verify: true,
        },
    )
    .unwrap();

    assert_eq!(backup.format, "tar.zst");
    assert!(backup.uri.starts_with("treedx://backup/"));
    assert!(backup.checksum.starts_with("blake3:"));
    assert!(backup.byte_length > 0);
    assert!(backup.verified);
    assert!(!serde_json::to_string(&backup)
        .unwrap()
        .contains(dir.path().to_string_lossy().as_ref()));
}
