use std::process::{Command, Output};
use treedx_store::{init_data_dir, InitOptions};

fn invoke(root: &std::path::Path, extra: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_treedx_store_recover"))
        .arg(root)
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
