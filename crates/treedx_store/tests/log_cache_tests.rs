use serde_json::{json, Value};
use treedx_store::log;

#[test]
fn bounded_native_cache_preserves_durable_reads_sequences_deletes_and_concurrent_writes() {
    let root = tempfile::tempdir().unwrap();
    let budget = 8_192;
    log::set_cache_budget(budget);
    for n in 0..3 {
        let path = root.path().join(format!("records-{n}.tdb"));
        for k in 0..20 {
            log::append_record(&path, "test", &k.to_string(), &json!({"body":"x".repeat(2048),"n":k})).unwrap();
            assert!(log::cache_stats().1 <= budget);
        }
        assert_eq!(log::replay_record::<Value>(&path, "test", "0").unwrap().unwrap()["n"], 0);
        assert_eq!(log::replay_latest::<Value>(&path, "test").unwrap().len(), 20);
        log::append_delete(&path, "test", "0").unwrap();
        assert!(log::replay_record::<Value>(&path, "test", "0").unwrap().is_none());
        assert_eq!(log::replay_latest::<Value>(&path, "test").unwrap().len(), 19);
    }
    let path = root.path().join("concurrent.tdb");
    std::thread::scope(|scope| {
        for n in 0..16 {
            let path = &path;
            scope.spawn(move || log::append_record(path, "test", &n.to_string(), &json!({"n":n})).unwrap());
        }
    });
    assert_eq!(log::replay_latest::<Value>(&path, "test").unwrap().len(), 16);
    let lines = std::fs::read_to_string(&path).unwrap();
    let sequences: Vec<u64> = lines.lines().skip(1).map(|line| serde_json::from_str::<Value>(line).unwrap()["seq"].as_u64().unwrap()).collect();
    assert_eq!(sequences, (1..=16).collect::<Vec<_>>());
    log::set_cache_budget(0);
    assert_eq!(log::cache_stats(), (0, 0, 0));
    log::append_record(&path, "test", "next", &json!({"n":17})).unwrap();
    assert_eq!(log::replay_latest::<Value>(&path, "test").unwrap().len(), 17);
    assert_eq!(log::cache_stats(), (0, 0, 0));
}
