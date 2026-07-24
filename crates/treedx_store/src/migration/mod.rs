use crate::catalog::{get_record, list_records, put_record};
use crate::error::StoreError;
use crate::ids::{migration_id, mirror_sync_id};
use crate::types::*;
use std::path::Path;

pub fn put_mirror_sync(
    data_dir: &Path,
    mut record: MirrorSyncRecord,
) -> Result<MirrorSyncRecord, StoreError> {
    if record.id.is_empty() {
        record.id = mirror_sync_id(&record.mirror_id, &record.started_at.to_rfc3339());
    }
    put_record(
        data_dir,
        "federation/mirror_syncs.tdb",
        "mirror_sync",
        &record.id,
        &record,
    )?;
    let per_repo = format!(
        "federation/mirrors/{}/{}.tdb",
        record.repository_id, record.target_node_id
    );
    put_record(data_dir, &per_repo, "mirror_sync", &record.id, &record)?;
    Ok(record)
}

pub fn get_mirror_sync(data_dir: &Path, id: &str) -> Result<Option<MirrorSyncRecord>, StoreError> {
    get_record(data_dir, "federation/mirror_syncs.tdb", "mirror_sync", id)
}

pub fn list_mirror_syncs(
    data_dir: &Path,
    repo_id: &str,
    mirror_id: Option<&str>,
) -> Result<Vec<MirrorSyncRecord>, StoreError> {
    let mut records =
        list_records::<MirrorSyncRecord>(data_dir, "federation/mirror_syncs.tdb", "mirror_sync")?
            .into_iter()
            .filter(|record| record.repository_id == repo_id)
            .filter(|record| mirror_id.map(|id| record.mirror_id == id).unwrap_or(true))
            .collect::<Vec<_>>();
    records.sort_by_key(|record| std::cmp::Reverse(record.started_at));
    Ok(records)
}

pub fn put_migration(
    data_dir: &Path,
    mut record: MigrationRecord,
) -> Result<MigrationRecord, StoreError> {
    if record.id.is_empty() {
        record.id = migration_id(
            &record.repository_id,
            &record.source_node_id,
            &record.target_node_id,
            &record.mode,
            &record.created_at.to_rfc3339(),
        );
    }
    put_record(
        data_dir,
        "federation/migrations.tdb",
        "migration",
        &record.id,
        &record,
    )?;
    let per_repo = format!(
        "federation/migrations/{}/{}.tdb",
        record.repository_id, record.id
    );
    put_record(data_dir, &per_repo, "migration", &record.id, &record)?;
    Ok(record)
}

pub fn get_migration(
    data_dir: &Path,
    repo_id: &str,
    migration_id: &str,
) -> Result<Option<MigrationRecord>, StoreError> {
    let record = get_record::<MigrationRecord>(
        data_dir,
        "federation/migrations.tdb",
        "migration",
        migration_id,
    )?;
    Ok(record.filter(|record| record.repository_id == repo_id))
}
