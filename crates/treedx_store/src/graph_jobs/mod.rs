use crate::error::StoreError;
use crate::log::{append_record, replay_latest};
use crate::types::GraphRefreshJobRecord;
use std::path::Path;

fn jobs_log(data_dir: &Path) -> std::path::PathBuf {
    data_dir.join("graph/refresh_jobs.tdb")
}

pub fn put_graph_refresh_job(
    data_dir: &Path,
    record: GraphRefreshJobRecord,
) -> Result<GraphRefreshJobRecord, StoreError> {
    append_record(
        &jobs_log(data_dir),
        "graph_refresh_job",
        &record.job_id,
        &record,
    )?;
    Ok(record)
}

pub fn get_graph_refresh_job(
    data_dir: &Path,
    repo_id: &str,
    job_id: &str,
) -> Result<Option<GraphRefreshJobRecord>, StoreError> {
    Ok(
        replay_latest::<GraphRefreshJobRecord>(&jobs_log(data_dir), "graph_refresh_job")?
            .remove(job_id)
            .filter(|record| record.repo_id == repo_id),
    )
}
