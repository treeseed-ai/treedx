use crate::catalog::{get_record, list_records, put_record};
use crate::error::StoreError;
use crate::ids::{lease_id, workspace_id};
use crate::types::{
    CleanupReport, LeaseRecord, WorkspaceCommitMarkInput, WorkspaceInput,
    WorkspacePolicyUpdateInput, WorkspaceQuarantineInput, WorkspaceRecord,
};
use chrono::{Duration, Utc};
use std::path::Path;

pub fn put_workspace(
    data_dir: &Path,
    input: WorkspaceInput,
) -> Result<WorkspaceRecord, StoreError> {
    if input.mode != "read_only" && input.mode != "writable" {
        return Err(StoreError::Validation(
            "workspace mode must be read_only or writable".to_string(),
        ));
    }
    if input.ttl_seconds <= 0 {
        return Err(StoreError::Validation(
            "ttlSeconds must be positive".to_string(),
        ));
    }

    let now = Utc::now();
    let expires_at = now + Duration::seconds(input.ttl_seconds);
    let id = input.id.clone().unwrap_or_else(|| {
        workspace_id(
            &input.repository_id,
            &input.actor_id,
            input.branch_name.as_deref(),
            &now.to_rfc3339(),
        )
    });

    if let Some(existing) = get_workspace(data_dir, &id)? {
        let same_request = existing.repository_id == input.repository_id
            && existing.actor_id == input.actor_id
            && existing.tenant_id == input.tenant_id
            && existing.base_ref == input.base_ref
            && existing.base_commit_sha == input.base_commit_sha
            && existing.branch_name == input.branch_name
            && existing.mode == input.mode
            && existing.allowed_paths == input.allowed_paths;
        if existing.status == "ready" && existing.expires_at > now && same_request {
            return Ok(existing);
        }
        if existing.status == "ready" || existing.status == "committed" || !same_request {
            return Err(StoreError::Conflict(format!(
                "workspace id already exists with different state: {id}"
            )));
        }
    }

    let mut lease = None;
    if input.mode == "writable" {
        let branch_name = input.branch_name.clone().ok_or_else(|| {
            StoreError::Validation("branchName is required for writable workspaces".to_string())
        })?;
        lease = Some(acquire_writable_lease(
            data_dir,
            &input.repository_id,
            &branch_name,
            &id,
            &input.actor_id,
            expires_at,
        )?);
    }

    let record = WorkspaceRecord {
        id: id.clone(),
        repository_id: input.repository_id,
        node_id: input.node_id,
        actor_id: input.actor_id,
        tenant_id: input.tenant_id,
        base_ref: input.base_ref,
        base_commit_sha: input.base_commit_sha,
        branch_name: input.branch_name,
        mode: input.mode,
        allowed_paths: input.allowed_paths,
        capabilities: input.capabilities,
        status: "ready".to_string(),
        materialized_path: input.materialized_path,
        policy_version: input.effective_scope.policy_version.clone(),
        policy_hash: input.effective_scope.policy_hash.clone(),
        effective_scope: input.effective_scope,
        revoked_at: None,
        revoked_reason: None,
        lease_id: lease.map(|record| record.id),
        commit_sha: None,
        created_at: now,
        expires_at,
        closed_at: None,
    };

    put_record(
        data_dir,
        "workspaces/sessions.tdb",
        "workspace",
        &id,
        &record,
    )?;
    Ok(record)
}

pub fn quarantine_workspace(
    data_dir: &Path,
    input: WorkspaceQuarantineInput,
) -> Result<WorkspaceRecord, StoreError> {
    let Some(mut record) = get_workspace(data_dir, &input.workspace_id)? else {
        return Err(StoreError::NotFound(format!(
            "workspace not found: {}",
            input.workspace_id
        )));
    };
    if record.status == "ready" {
        record.status = "quarantined".to_string();
        record.closed_at = Some(Utc::now());
        if let Some(lease_id) = record.lease_id.as_deref() {
            release_lease(data_dir, lease_id)?;
        }
    }
    record.policy_version = input.policy_version;
    record.policy_hash = input.policy_hash;
    record.revoked_at = Some(Utc::now());
    record.revoked_reason = Some(input.reason);
    put_record(
        data_dir,
        "workspaces/sessions.tdb",
        "workspace",
        &record.id,
        &record,
    )?;
    Ok(record)
}

pub fn update_workspace_policy(
    data_dir: &Path,
    input: WorkspacePolicyUpdateInput,
) -> Result<WorkspaceRecord, StoreError> {
    let Some(mut record) = get_workspace(data_dir, &input.workspace_id)? else {
        return Err(StoreError::NotFound(format!(
            "workspace not found: {}",
            input.workspace_id
        )));
    };
    record.policy_version = Some(input.policy_version);
    record.policy_hash = Some(input.policy_hash);
    record.effective_scope.policy_version = record.policy_version.clone();
    record.effective_scope.policy_hash = record.policy_hash.clone();
    put_record(
        data_dir,
        "workspaces/sessions.tdb",
        "workspace",
        &record.id,
        &record,
    )?;
    Ok(record)
}

pub fn list_quarantined_workspaces(data_dir: &Path) -> Result<Vec<WorkspaceRecord>, StoreError> {
    Ok(
        list_records::<WorkspaceRecord>(data_dir, "workspaces/sessions.tdb", "workspace")?
            .into_iter()
            .filter(|workspace| workspace.status == "quarantined" || workspace.status == "revoked")
            .collect(),
    )
}

pub fn mark_workspace_committed(
    data_dir: &Path,
    input: WorkspaceCommitMarkInput,
) -> Result<WorkspaceRecord, StoreError> {
    let Some(mut record) = get_workspace(data_dir, &input.workspace_id)? else {
        return Err(StoreError::NotFound(format!(
            "workspace not found: {}",
            input.workspace_id
        )));
    };
    if record.status != "ready" {
        return Err(StoreError::Conflict(format!(
            "workspace is not ready: {}",
            record.status
        )));
    }
    record.status = "committed".to_string();
    record.commit_sha = Some(input.commit_sha);
    record.closed_at = Some(Utc::now());
    if let Some(lease_id) = record.lease_id.as_deref() {
        release_lease(data_dir, lease_id)?;
    }
    put_record(
        data_dir,
        "workspaces/sessions.tdb",
        "workspace",
        &record.id,
        &record,
    )?;
    Ok(record)
}

pub fn get_workspace(
    data_dir: &Path,
    workspace_id: &str,
) -> Result<Option<WorkspaceRecord>, StoreError> {
    get_record(
        data_dir,
        "workspaces/sessions.tdb",
        "workspace",
        workspace_id,
    )
}

pub fn close_workspace(
    data_dir: &Path,
    workspace_id: &str,
) -> Result<Option<WorkspaceRecord>, StoreError> {
    let Some(mut record) = get_workspace(data_dir, workspace_id)? else {
        return Ok(None);
    };
    if record.status != "closed" {
        record.status = "closed".to_string();
        record.closed_at = Some(Utc::now());
        if let Some(lease_id) = record.lease_id.as_deref() {
            release_lease(data_dir, lease_id)?;
        }
        put_record(
            data_dir,
            "workspaces/sessions.tdb",
            "workspace",
            workspace_id,
            &record,
        )?;
    }
    Ok(Some(record))
}

pub fn cleanup_expired_workspaces(data_dir: &Path) -> Result<CleanupReport, StoreError> {
    let now = Utc::now();
    let mut expired_workspace_ids = Vec::new();
    let mut released_lease_ids = Vec::new();

    for mut workspace in
        list_records::<WorkspaceRecord>(data_dir, "workspaces/sessions.tdb", "workspace")?
    {
        if workspace.status == "ready" && workspace.expires_at <= now {
            workspace.status = "expired".to_string();
            workspace.closed_at = Some(now);
            if let Some(lease_id) = workspace.lease_id.as_deref() {
                release_lease(data_dir, lease_id)?;
                released_lease_ids.push(lease_id.to_string());
            }
            expired_workspace_ids.push(workspace.id.clone());
            put_record(
                data_dir,
                "workspaces/sessions.tdb",
                "workspace",
                &workspace.id,
                &workspace,
            )?;
        }
    }

    Ok(CleanupReport {
        expired_workspace_ids,
        released_lease_ids,
    })
}

pub fn get_lease(data_dir: &Path, id: &str) -> Result<Option<LeaseRecord>, StoreError> {
    get_record(data_dir, "leases/leases.tdb", "lease", id)
}

fn acquire_writable_lease(
    data_dir: &Path,
    repo_id: &str,
    branch_name: &str,
    workspace_id: &str,
    actor_id: &str,
    expires_at: chrono::DateTime<Utc>,
) -> Result<LeaseRecord, StoreError> {
    let id = lease_id(repo_id, branch_name);
    if let Some(existing) = get_lease(data_dir, &id)? {
        if existing.status == "active" && existing.expires_at > Utc::now() {
            if existing.workspace_id == workspace_id && existing.actor_id == actor_id {
                return Ok(existing);
            }
            return Err(StoreError::Conflict(format!(
                "writable lease already exists for {repo_id} {branch_name}"
            )));
        }
    }

    let record = LeaseRecord {
        id: id.clone(),
        repository_id: repo_id.to_string(),
        branch_name: branch_name.to_string(),
        workspace_id: workspace_id.to_string(),
        actor_id: actor_id.to_string(),
        mode: "writable".to_string(),
        status: "active".to_string(),
        acquired_at: Utc::now(),
        expires_at,
        released_at: None,
    };
    put_record(data_dir, "leases/leases.tdb", "lease", &id, &record)?;
    Ok(record)
}

fn release_lease(data_dir: &Path, id: &str) -> Result<(), StoreError> {
    if let Some(mut lease) = get_lease(data_dir, id)? {
        lease.status = "released".to_string();
        lease.released_at = Some(Utc::now());
        put_record(data_dir, "leases/leases.tdb", "lease", id, &lease)?;
    }
    Ok(())
}
