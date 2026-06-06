use crate::error::StoreError;
use crate::log::{append_record, replay_latest};
use crate::types::{
    SearchIndexCompactInput, SearchIndexCompactResult, SearchIndexManifestRecord,
    SearchIndexSegmentRecord,
};
use std::path::Path;

fn manifests_log(data_dir: &Path) -> std::path::PathBuf {
    data_dir.join("search/manifests.tdb")
}

fn segments_log(data_dir: &Path) -> std::path::PathBuf {
    data_dir.join("search/segments.tdb")
}

fn latest_key(repo_id: &str, ref_name: &str) -> String {
    format!("{repo_id}|{ref_name}")
}

pub fn put_search_index_manifest(
    data_dir: &Path,
    record: SearchIndexManifestRecord,
) -> Result<SearchIndexManifestRecord, StoreError> {
    append_record(
        &manifests_log(data_dir),
        "search_index_manifest",
        &latest_key(&record.repo_id, &record.ref_name),
        &record,
    )?;
    Ok(record)
}

pub fn get_search_index_manifest(
    data_dir: &Path,
    repo_id: &str,
    ref_name: &str,
) -> Result<Option<SearchIndexManifestRecord>, StoreError> {
    Ok(replay_latest::<SearchIndexManifestRecord>(
        &manifests_log(data_dir),
        "search_index_manifest",
    )?
    .remove(&latest_key(repo_id, ref_name)))
}

pub fn put_search_index_segment(
    data_dir: &Path,
    record: SearchIndexSegmentRecord,
) -> Result<SearchIndexSegmentRecord, StoreError> {
    append_record(
        &segments_log(data_dir),
        "search_index_segment",
        &record.segment_id,
        &record,
    )?;
    Ok(record)
}

pub fn list_search_index_segments(
    data_dir: &Path,
    repo_id: &str,
    ref_name: &str,
) -> Result<Vec<SearchIndexSegmentRecord>, StoreError> {
    Ok(
        replay_latest::<SearchIndexSegmentRecord>(&segments_log(data_dir), "search_index_segment")?
            .into_values()
            .filter(|record| record.repo_id == repo_id && record.ref_name == ref_name)
            .collect(),
    )
}

pub fn compact_search_index(
    data_dir: &Path,
    input: SearchIndexCompactInput,
) -> Result<SearchIndexCompactResult, StoreError> {
    let segments = list_search_index_segments(data_dir, &input.repo_id, &input.ref_name)?;
    let latest = get_search_index_manifest(data_dir, &input.repo_id, &input.ref_name)?;
    let keep: std::collections::BTreeSet<String> = latest
        .as_ref()
        .map(|manifest| manifest.segment_ids.iter().cloned().collect())
        .unwrap_or_default();
    let before = segments.len() as u64;
    let after = if keep.is_empty() {
        before
    } else {
        segments
            .iter()
            .filter(|segment| keep.contains(&segment.segment_id))
            .count() as u64
    };
    Ok(SearchIndexCompactResult {
        repo_id: input.repo_id,
        ref_name: input.ref_name,
        dry_run: input.dry_run,
        segments_before: before,
        segments_after: after,
        compacted: !input.dry_run && after < before,
    })
}
