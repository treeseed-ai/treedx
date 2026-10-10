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
            log::append_record(
                &path,
                "test",
                &k.to_string(),
                &json!({"body":"x".repeat(2048),"n":k}),
            )
            .unwrap();
            assert!(log::cache_stats().1 <= budget);
        }
        assert_eq!(
            log::replay_record::<Value>(&path, "test", "0")
                .unwrap()
                .unwrap()["n"],
            0
        );
        assert_eq!(
            log::replay_latest::<Value>(&path, "test").unwrap().len(),
            20
        );
        log::append_delete(&path, "test", "0").unwrap();
        assert!(log::replay_record::<Value>(&path, "test", "0")
            .unwrap()
            .is_none());
        assert_eq!(
            log::replay_latest::<Value>(&path, "test").unwrap().len(),
            19
        );
    }
    let path = root.path().join("concurrent.tdb");
    std::thread::scope(|scope| {
        for n in 0..16 {
            let path = &path;
            scope.spawn(move || {
                log::append_record(path, "test", &n.to_string(), &json!({"n":n})).unwrap()
            });
        }
    });
    assert_eq!(
        log::replay_latest::<Value>(&path, "test").unwrap().len(),
        16
    );
    let lines = std::fs::read_to_string(&path).unwrap();
    let sequences: Vec<u64> = lines
        .lines()
        .skip(1)
        .map(|line| {
            serde_json::from_str::<Value>(line).unwrap()["seq"]
                .as_u64()
                .unwrap()
        })
        .collect();
    assert_eq!(sequences, (1..=16).collect::<Vec<_>>());
    // Cached and uncached paths both validate external durable changes.
    let changed = root.path().join("changed.tdb");
    log::set_cache_budget(65_536);
    log::append_record(&changed, "test", "same", &json!({"n":1})).unwrap();
    log::append_record(&changed, "test", "same", &json!({"n":2})).unwrap();
    assert_eq!(
        log::replay_record::<Value>(&changed, "test", "same")
            .unwrap()
            .unwrap()["n"],
        2
    );
    assert!(log::cache_stats().1 > 0);
    log::set_cache_budget(1);
    assert_eq!(log::cache_stats(), (0, 0, 1));
    for cap in [0, 65_536] {
        log::set_cache_budget(cap);
        let bad = root.path().join(format!("corrupt-{cap}.tdb"));
        log::append_record(&bad, "test", "id", &json!({"n":1})).unwrap();
        assert!(log::replay_record::<Value>(&bad, "wrong-kind", "id").is_err());
        let bytes = std::fs::read_to_string(&bad).unwrap();
        std::fs::write(&bad, bytes.replace("\"n\":1", "\"n\":22")).unwrap();
        assert!(log::replay_record::<Value>(&bad, "test", "id").is_err());
        assert!(log::warm_log(&bad, "test").is_err());
        let interrupted = root.path().join(format!("partial-{cap}.tdb"));
        std::fs::write(&interrupted, "# treedx:test:v1\n{\"schemaVersion\":").unwrap();
        assert!(log::replay_latest::<Value>(&interrupted, "test").is_err());
        assert!(log::append_record(&interrupted, "test", "id", &json!({})).is_err());
    }
    std::thread::scope(|scope| {
        scope.spawn(|| {
            for _ in 0..100 {
                log::set_cache_budget(0);
                log::set_cache_budget(8192);
            }
        });
        for n in 0..8 {
            let path = &path;
            scope.spawn(move || {
                log::append_record(path, "test", &format!("retry-{n}"), &json!({"n":n})).unwrap()
            });
        }
    });
    assert_eq!(
        log::replay_latest::<Value>(&path, "test").unwrap().len(),
        24
    );
    log::set_cache_budget(0);
    assert_eq!(log::cache_stats(), (0, 0, 0));
    log::append_record(&path, "test", "next", &json!({"n":17})).unwrap();
    assert_eq!(
        log::replay_latest::<Value>(&path, "test").unwrap().len(),
        25
    );
    assert_eq!(log::cache_stats(), (0, 0, 0));
}
