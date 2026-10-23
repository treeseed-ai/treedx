use std::process::{Command, Output};
use treedx_store::{init_data_dir, InitOptions};

fn invoke(root: &std::path::Path, extra: &[&str]) -> Output {
    invoke_log(root, "catalog/connected_tokens.tdb", extra)
}

fn invoke_log(root: &std::path::Path, log: &str, extra: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_treedx_store_recover"))
        .arg(root)
        .arg(log)
        .args(extra)
        .output()
        .unwrap()
}

#[test]
fn offline_command_denies_empty_wrong_header_oversized_and_missing_owner_inputs_without_mutation() {
    for mode in [
        "empty",
        "header",
        "oversized",
        "missing-marker",
        "lock-symlink",
    ] {
        let root = tempfile::tempdir().unwrap();
        init_data_dir(
            root.path(),
            InitOptions {
                node_id: "node_local".into(),
            },
        )
        .unwrap();
        let marker = root.path().join(".treedx.lock");
        if mode != "missing-marker" {
            std::fs::write(&marker, "stopped\n").unwrap();
        }
        let path = root.path().join("catalog/connected_tokens.tdb");
        if mode == "empty" {
            std::fs::write(&path, "").unwrap();
        }
        if mode == "header" {
            std::fs::write(&path, "# treedx:other:v1\n").unwrap();
        }
        if mode == "oversized" {
            use std::io::Write;
            std::fs::OpenOptions::new()
                .append(true)
                .open(&path)
                .unwrap()
                .write_all(&vec![b'x'; 1_048_577])
                .unwrap();
        }
        if mode == "lock-symlink" {
            std::fs::remove_file(&marker).unwrap();
            std::os::unix::fs::symlink(&path, &marker).unwrap();
        }
        let before = std::fs::read(&path).unwrap();
        assert!(!invoke(root.path(), &[]).status.success(), "{mode}");
        assert_eq!(std::fs::read(&path).unwrap(), before);
        assert!(!root.path().join("recovery/backups").exists());
    }
}

#[test]
fn offline_command_accepts_healthy_empty_history_and_refuses_unknown_arguments_or_missing_directory(
) {
    let root = tempfile::tempdir().unwrap();
    init_data_dir(
        root.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();
    std::fs::write(root.path().join(".treedx.lock"), "stopped\n").unwrap();
    let plan = invoke(root.path(), &[]);
    assert!(plan.status.success());
    let value: serde_json::Value = serde_json::from_slice(&plan.stdout).unwrap();
    assert_eq!(value["retainedRecords"], 0);
    assert_eq!(value["incompleteBytes"], 0);
    assert_eq!(value["applied"], false);
    assert_eq!(
        invoke(root.path(), &["--force", "ignored"]).status.code(),
        Some(2)
    );
    let missing = root.path().join("absent");
    assert!(!invoke(&missing, &[]).status.success());
    assert!(!missing.exists());
}

#[test]
fn native_audit_tail_recovery_preserves_every_complete_event_and_the_entire_original() {
    use std::io::Write;
    let root = tempfile::tempdir().unwrap();
    init_data_dir(
        root.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();
    std::fs::write(root.path().join(".treedx.lock"), "stopped\n").unwrap();
    let path = root.path().join("audit/events.tdb");
    treedx_store::log::append_record(
        &path,
        "audit_event",
        "original-event",
        &serde_json::json!({"status":"original"}),
    )
    .unwrap();
    let complete = std::fs::read(&path).unwrap();
    std::fs::OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(b"{\"schemaVersion\":")
        .unwrap();
    let original = std::fs::read(&path).unwrap();
    let planned = invoke_log(root.path(), "audit/events.tdb", &[]);
    assert!(
        planned.status.success(),
        "{}",
        String::from_utf8_lossy(&planned.stderr)
    );
    let plan: serde_json::Value = serde_json::from_slice(&planned.stdout).unwrap();
    assert_eq!(std::fs::read(&path).unwrap(), original);
    let result = invoke_log(
        root.path(),
        "audit/events.tdb",
        &["--apply", plan["sourceDigest"].as_str().unwrap()],
    );
    assert!(result.status.success());
    let report: serde_json::Value = serde_json::from_slice(&result.stdout).unwrap();
    let relative = report["backup"]
        .as_str()
        .unwrap()
        .strip_prefix("treedx://backup/")
        .unwrap();
    assert_eq!(
        std::fs::read(root.path().join("recovery/backups").join(relative)).unwrap(),
        original
    );
    assert_eq!(std::fs::read(&path).unwrap(), complete);
    init_data_dir(
        root.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();
}

#[test]
fn offline_recovery_refuses_unregistered_paths_and_cannot_escape_the_store_registry() {
    let root = tempfile::tempdir().unwrap();
    for log in [
        "",
        "../audit/events.tdb",
        "/audit/events.tdb",
        "catalog/unknown.tdb",
        "catalog/../audit/events.tdb",
    ] {
        assert!(!invoke_log(root.path(), log, &[]).status.success());
    }
    assert_eq!(std::fs::read_dir(root.path()).unwrap().count(), 0);
}
