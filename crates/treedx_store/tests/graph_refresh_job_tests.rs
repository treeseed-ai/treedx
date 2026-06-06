use chrono::Utc;
use tempfile::tempdir;
use treedx_store::*;

#[test]
fn graph_refresh_jobs_persist_and_replay() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    let record = GraphRefreshJobRecord {
        job_id: "grjob_test".to_string(),
        repo_id: "repo_test".to_string(),
        ref_name: "refs/heads/main".to_string(),
        requested_paths: vec!["docs/**".to_string()],
        changed_paths: vec!["docs/readme.md".to_string()],
        base_graph_version: Some("graph_old".to_string()),
        graph_version: Some("graph_new".to_string()),
        refresh_mode: "incremental".to_string(),
        fallback_reason: None,
        stale: false,
        status: "completed".to_string(),
        started_at: Utc::now(),
        completed_at: Some(Utc::now()),
        indexed_path_count: 1,
        removed_path_count: 0,
        error_code: None,
    };

    put_graph_refresh_job(dir.path(), record).unwrap();
    let replayed = get_graph_refresh_job(dir.path(), "repo_test", "grjob_test")
        .unwrap()
        .unwrap();

    assert_eq!(replayed.refresh_mode, "incremental");
    assert_eq!(replayed.changed_paths, vec!["docs/readme.md"]);
    assert_eq!(replayed.indexed_path_count, 1);
    assert!(
        get_graph_refresh_job(dir.path(), "repo_other", "grjob_test")
            .unwrap()
            .is_none()
    );
}
