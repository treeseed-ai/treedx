use super::*;
use serde_json::{json, Value};

#[test]
fn exact_record_lookup_stays_bounded_after_payload_eviction() {
    let root = tempfile::tempdir().unwrap();
    let path = root.path().join("workspace-records.tdb");
    set_cache_budget(65_536);
    append_records(
        &path,
        "workspace",
        (0..256)
            .map(|n| {
                (
                    format!("workspace-{n}"),
                    json!({"id":n,"body":"x".repeat(512)}),
                )
            })
            .collect(),
    )
    .unwrap();
    assert!(cache_stats().1 <= 65_536);
    assert!(with_index_unlocked(&path, "workspace", |index| index.latest.is_none()).unwrap());
    assert_eq!(
        replay_record::<Value>(&path, "workspace", "workspace-255")
            .unwrap()
            .unwrap()["id"],
        255
    );
    VALIDATED_RECORDS.with(|count| count.set(0));
    let actual = replay_record::<Value>(&path, "workspace", "workspace-128")
        .unwrap()
        .unwrap();
    assert_eq!(actual, json!({"id":128,"body":"x".repeat(512)}));
    let replayed = VALIDATED_RECORDS.with(|count| count.get());
    assert!(
        replayed <= 1,
        "one warm exact lookup replayed {replayed} historical records"
    );
    assert!(with_index_unlocked(&path, "workspace", |index| index.positions.is_some()).unwrap());
    assert_eq!(bounded_read(&path, "missing"), None);
    assert_eq!(VALIDATED_RECORDS.with(|count| count.get()), 0);

    let updated = json!({"id":128,"body":"updated Å🍃"});
    append_record(&path, "workspace", "workspace-128", &updated).unwrap();
    assert_eq!(bounded_read(&path, "workspace-128"), Some(updated));
    append_delete(&path, "workspace", "workspace-128").unwrap();
    assert_eq!(bounded_read(&path, "workspace-128"), None);
    assert_eq!(VALIDATED_RECORDS.with(|count| count.get()), 0);

    // External blank lines and multibyte UTF-8 must not move a cached record
    // onto a neighbouring envelope or change reported corruption line numbers.
    OpenOptions::new()
        .append(true)
        .open(&path)
        .unwrap()
        .write_all(b"\r\n")
        .unwrap();
    let leaf = json!({"id":300,"body":"new Å🍃"});
    append_record(&path, "workspace", "leaf", &leaf).unwrap();
    assert_eq!(bounded_read(&path, "leaf"), Some(leaf.clone()));
    let position = with_index_unlocked(&path, "workspace", |index| {
        index.positions.as_ref().unwrap()["leaf"]
    })
    .unwrap();
    assert_eq!(
        position.line,
        fs::read_to_string(&path).unwrap().lines().count()
    );
    let wrong_record =
        read::read_indexed_record(&path, "workspace", "wrong-record", position).unwrap_err();
    assert!(
        matches!(wrong_record, StoreError::InvalidRecord { line, .. } if line == position.line)
    );

    let before_corruption = fs::read_to_string(&path).unwrap();
    let corrupted = before_corruption.replacen("\"id\":17}", "\"id\":170}", 1);
    assert_ne!(corrupted, before_corruption);
    fs::write(&path, corrupted).unwrap();
    let failure = replay_record::<Value>(&path, "workspace", "leaf").unwrap_err();
    assert!(matches!(failure, StoreError::Checksum { line: 19, .. }));
    fs::write(&path, &before_corruption).unwrap();
    assert_eq!(
        replay_record::<Value>(&path, "workspace", "leaf").unwrap(),
        Some(leaf)
    );

    append_records_unindexed(
        &path,
        "workspace",
        vec![("unindexed".to_string(), json!({"id":900}))],
    )
    .unwrap();
    assert_eq!(
        replay_record::<Value>(&path, "workspace", "unindexed").unwrap(),
        Some(json!({"id":900}))
    );
    let latest = replay_latest::<Value>(&path, "workspace").unwrap();
    assert_eq!(latest.len(), 257);
    assert!(!latest.contains_key("workspace-128"));

    // A moved/truncated durable file invalidates both payload and position
    // indexes. An old byte offset cannot turn into stale positive read-back.
    fs::write(&path, "# treedx:workspace:v1\n").unwrap();
    assert_eq!(
        replay_record::<Value>(&path, "workspace", "leaf").unwrap(),
        None
    );
    assert!(cache_stats().1 <= 65_536);
    set_cache_budget(0);
}

fn bounded_read(path: &Path, id: &str) -> Option<Value> {
    VALIDATED_RECORDS.with(|count| count.set(0));
    let result = replay_record(path, "workspace", id).unwrap();
    assert!(VALIDATED_RECORDS.with(|count| count.get()) <= 1);
    assert!(cache_stats().1 <= 65_536);
    result
}
