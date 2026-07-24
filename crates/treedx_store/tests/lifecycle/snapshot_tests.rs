use base64::Engine;
use chrono::Utc;
use std::io::Read;
use tempfile::tempdir;
use treedx_store::*;

#[test]
fn repeated_identical_snapshot_reuses_existing_artifact() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    let input = SnapshotBuildInput {
        snapshot_id: None,
        repo_id: "repo_demo".to_string(),
        ref_name: "refs/heads/main".to_string(),
        commit_sha: "abc123".to_string(),
        kind: "repository_snapshot".to_string(),
        included_paths: vec!["docs/**".to_string()],
        graph_version: None,
        files: vec![SnapshotArtifactFileInput {
            path: "docs/readme.md".to_string(),
            object_id: "blob1".to_string(),
            content_base64: base64::engine::general_purpose::STANDARD.encode("hello"),
        }],
        created_by_actor_id: Some("actor_demo".to_string()),
    };

    let first = build_snapshot_artifact(dir.path(), input.clone()).unwrap();
    let artifact_path = dir
        .path()
        .join("snapshots")
        .join(&first.snapshot_id)
        .join("artifact.tar.zst");
    let first_modified = std::fs::metadata(&artifact_path)
        .unwrap()
        .modified()
        .unwrap();
    std::thread::sleep(std::time::Duration::from_millis(20));

    let second = build_snapshot_artifact(dir.path(), input).unwrap();
    let second_modified = std::fs::metadata(&artifact_path)
        .unwrap()
        .modified()
        .unwrap();

    assert_eq!(first.snapshot_id, second.snapshot_id);
    assert_eq!(
        first.artifact.as_ref().unwrap().checksum,
        second.artifact.as_ref().unwrap().checksum
    );
    assert_eq!(first_modified, second_modified);
}

#[test]
fn changed_snapshot_input_creates_distinct_snapshot() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    let mut input = SnapshotBuildInput {
        snapshot_id: None,
        repo_id: "repo_demo".to_string(),
        ref_name: "refs/heads/main".to_string(),
        commit_sha: "abc123".to_string(),
        kind: "repository_snapshot".to_string(),
        included_paths: vec!["docs/**".to_string()],
        graph_version: None,
        files: vec![SnapshotArtifactFileInput {
            path: "docs/readme.md".to_string(),
            object_id: "blob1".to_string(),
            content_base64: base64::engine::general_purpose::STANDARD.encode("hello"),
        }],
        created_by_actor_id: Some("actor_demo".to_string()),
    };

    let first = build_snapshot_artifact(dir.path(), input.clone()).unwrap();
    input.commit_sha = "def456".to_string();
    let second = build_snapshot_artifact(dir.path(), input).unwrap();

    assert_ne!(first.snapshot_id, second.snapshot_id);
}

#[test]
fn build_snapshot_writes_manifest_and_tar_zst_artifact() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    let manifest = build_snapshot_artifact(
        dir.path(),
        SnapshotBuildInput {
            snapshot_id: None,
            repo_id: "repo_demo".to_string(),
            ref_name: "refs/heads/main".to_string(),
            commit_sha: "abc123".to_string(),
            kind: "repository_snapshot".to_string(),
            included_paths: vec!["docs/**".to_string()],
            graph_version: Some("graph_1".to_string()),
            files: vec![SnapshotArtifactFileInput {
                path: "docs/readme.md".to_string(),
                object_id: "blob1".to_string(),
                content_base64: base64::engine::general_purpose::STANDARD.encode("hello"),
            }],
            created_by_actor_id: Some("actor_demo".to_string()),
        },
    )
    .unwrap();

    assert!(dir
        .path()
        .join("snapshots")
        .join(&manifest.snapshot_id)
        .join("manifest.tdb")
        .exists());
    assert_eq!(manifest.file_count, 1);
    assert_eq!(manifest.total_bytes, 5);
    assert_eq!(manifest.graph_version.as_deref(), Some("graph_1"));
    assert_eq!(
        get_snapshot_manifest(dir.path(), &manifest.snapshot_id)
            .unwrap()
            .unwrap()
            .snapshot_id,
        manifest.snapshot_id
    );
    assert_eq!(
        get_artifact(dir.path(), &manifest.snapshot_id)
            .unwrap()
            .unwrap()
            .checksum,
        manifest.artifact.as_ref().unwrap().checksum
    );

    let artifact = read_artifact_bytes(dir.path(), &manifest.snapshot_id).unwrap();
    let decoded = zstd::stream::decode_all(artifact.as_slice()).unwrap();
    let mut archive = tar::Archive::new(decoded.as_slice());
    let mut names = archive
        .entries()
        .unwrap()
        .map(|entry| entry.unwrap().path().unwrap().to_string_lossy().to_string())
        .collect::<Vec<_>>();
    names.sort();
    assert_eq!(names, vec!["manifest.json", "repo/docs/readme.md"]);
}

#[test]
fn snapshot_artifact_preserves_binary_files_and_checksums() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    let bytes = vec![0, 159, 146, 150, 255, 10, 13];
    let expected_hash = hash_bytes(&bytes);

    let manifest = build_snapshot_artifact(
        dir.path(),
        SnapshotBuildInput {
            snapshot_id: Some("snap_binary".to_string()),
            repo_id: "repo_demo".to_string(),
            ref_name: "refs/heads/main".to_string(),
            commit_sha: "abc123".to_string(),
            kind: "repository_snapshot".to_string(),
            included_paths: vec!["assets/**".to_string()],
            graph_version: None,
            files: vec![SnapshotArtifactFileInput {
                path: "assets/logo.bin".to_string(),
                object_id: "blob_binary".to_string(),
                content_base64: base64::engine::general_purpose::STANDARD.encode(&bytes),
            }],
            created_by_actor_id: Some("actor_demo".to_string()),
        },
    )
    .unwrap();

    assert_eq!(manifest.file_count, 1);
    assert_eq!(manifest.total_bytes, bytes.len() as u64);
    assert_eq!(manifest.files[0].content_hash, expected_hash);
    assert!(!serde_json::to_string(&manifest)
        .unwrap()
        .contains(dir.path().to_string_lossy().as_ref()));

    let artifact = read_artifact_bytes(dir.path(), &manifest.snapshot_id).unwrap();
    let decoded = zstd::stream::decode_all(artifact.as_slice()).unwrap();
    let mut archive = tar::Archive::new(decoded.as_slice());
    let mut found = false;

    for entry in archive.entries().unwrap() {
        let mut entry = entry.unwrap();
        let path = entry.path().unwrap().to_string_lossy().to_string();
        if path == "repo/assets/logo.bin" {
            let mut actual = Vec::new();
            entry.read_to_end(&mut actual).unwrap();
            assert_eq!(actual, bytes);
            found = true;
        }
    }

    assert!(found, "binary file was not present in snapshot artifact");
}

#[test]
fn snapshot_rejects_path_traversal() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    let err = build_snapshot_artifact(
        dir.path(),
        SnapshotBuildInput {
            snapshot_id: None,
            repo_id: "repo_demo".to_string(),
            ref_name: "refs/heads/main".to_string(),
            commit_sha: "abc123".to_string(),
            kind: "repository_snapshot".to_string(),
            included_paths: vec!["**".to_string()],
            graph_version: None,
            files: vec![SnapshotArtifactFileInput {
                path: "../secret".to_string(),
                object_id: "blob1".to_string(),
                content_base64: base64::engine::general_purpose::STANDARD.encode("nope"),
            }],
            created_by_actor_id: None,
        },
    )
    .unwrap_err();
    assert_eq!(err.code(), "validation_error");
}

#[test]
fn mirror_sync_and_migration_records_persist_and_replay() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    let sync = put_mirror_sync(
        dir.path(),
        MirrorSyncRecord {
            id: String::new(),
            mirror_id: "mirror_1".to_string(),
            repository_id: "repo_demo".to_string(),
            source_node_id: "node_a".to_string(),
            target_node_id: "node_b".to_string(),
            remote_url: Some("file:///tmp/repo.git".to_string()),
            remote_name: "origin".to_string(),
            refspecs: vec!["+refs/heads/*:refs/remotes/origin/*".to_string()],
            before_commit: None,
            after_commit: Some("abc123".to_string()),
            updated_refs: vec!["refs/remotes/origin/main".to_string()],
            received_pack: true,
            behind_by: Some(0),
            status: "synced".to_string(),
            error: None,
            started_at: Utc::now(),
            completed_at: Some(Utc::now()),
        },
    )
    .unwrap();

    assert!(get_mirror_sync(dir.path(), &sync.id).unwrap().is_some());
    assert_eq!(
        list_mirror_syncs(dir.path(), "repo_demo", Some("mirror_1"))
            .unwrap()
            .len(),
        1
    );
    assert!(dir
        .path()
        .join("federation/mirrors/repo_demo/node_b.tdb")
        .exists());

    let migration = put_migration(
        dir.path(),
        MigrationRecord {
            id: String::new(),
            repository_id: "repo_demo".to_string(),
            source_node_id: "node_a".to_string(),
            target_node_id: "node_b".to_string(),
            mode: "primary_transfer".to_string(),
            status: "planned".to_string(),
            plan: true,
            require_mirror_synced: false,
            previous_placement: None,
            resulting_placement: None,
            validation: serde_json::json!({"mirrorSynced": true}),
            created_by_actor_id: Some("actor_demo".to_string()),
            created_at: Utc::now(),
            completed_at: None,
        },
    )
    .unwrap();

    assert_eq!(
        get_migration(dir.path(), "repo_demo", &migration.id)
            .unwrap()
            .unwrap()
            .status,
        "planned"
    );
    assert!(dir
        .path()
        .join(format!(
            "federation/migrations/repo_demo/{}.tdb",
            migration.id
        ))
        .exists());
}
