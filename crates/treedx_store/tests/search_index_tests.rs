use chrono::Utc;
use tempfile::tempdir;
use treedx_store::*;

#[test]
fn search_index_manifests_segments_and_compaction_replay() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    put_search_index_segment(
        dir.path(),
        SearchIndexSegmentRecord {
            segment_id: "sseg_old".to_string(),
            repo_id: "repo_test".to_string(),
            ref_name: "refs/heads/main".to_string(),
            path_count: 1,
            document_count: 1,
            content_hash: "blake3:old".to_string(),
            created_at: Utc::now(),
        },
    )
    .unwrap();
    put_search_index_segment(
        dir.path(),
        SearchIndexSegmentRecord {
            segment_id: "sseg_new".to_string(),
            repo_id: "repo_test".to_string(),
            ref_name: "refs/heads/main".to_string(),
            path_count: 2,
            document_count: 2,
            content_hash: "blake3:new".to_string(),
            created_at: Utc::now(),
        },
    )
    .unwrap();
    put_search_index_manifest(
        dir.path(),
        SearchIndexManifestRecord {
            index_version: "sidx_new".to_string(),
            repo_id: "repo_test".to_string(),
            ref_name: "refs/heads/main".to_string(),
            graph_version: Some("graph_new".to_string()),
            segment_ids: vec!["sseg_new".to_string()],
            indexed_paths: vec!["docs/a.md".to_string(), "docs/b.md".to_string()],
            source_commit: Some("abc".to_string()),
            stale: false,
            created_at: Utc::now(),
        },
    )
    .unwrap();

    let manifest = get_search_index_manifest(dir.path(), "repo_test", "refs/heads/main")
        .unwrap()
        .unwrap();
    assert_eq!(manifest.index_version, "sidx_new");
    assert_eq!(manifest.segment_ids, vec!["sseg_new"]);
    assert_eq!(
        list_search_index_segments(dir.path(), "repo_test", "refs/heads/main")
            .unwrap()
            .len(),
        2
    );

    let dry_run = compact_search_index(
        dir.path(),
        SearchIndexCompactInput {
            repo_id: "repo_test".to_string(),
            ref_name: "refs/heads/main".to_string(),
            dry_run: true,
        },
    )
    .unwrap();
    assert_eq!(dry_run.segments_before, 2);
    assert_eq!(dry_run.segments_after, 1);
    assert!(!dry_run.compacted);

    let compacted = compact_search_index(
        dir.path(),
        SearchIndexCompactInput {
            repo_id: "repo_test".to_string(),
            ref_name: "refs/heads/main".to_string(),
            dry_run: false,
        },
    )
    .unwrap();
    assert!(compacted.compacted);
}
