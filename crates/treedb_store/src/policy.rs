use crate::catalog::{get_record, list_records, put_record};
use crate::error::StoreError;
use crate::ids::capability_id;
use crate::types::{
    CapabilityGrantRecord, ConnectedTokenRecord, DevTokenRecord, EffectiveScope,
    PolicyRefreshRecord,
};
use chrono::Utc;
use std::path::Path;

pub fn put_dev_token(data_dir: &Path, record: DevTokenRecord) -> Result<(), StoreError> {
    put_record(
        data_dir,
        "config/dev_tokens.tdb",
        "dev_token",
        &record.token_hash,
        &record,
    )
}

pub fn get_dev_token_by_hash(
    data_dir: &Path,
    token_hash: &str,
) -> Result<Option<DevTokenRecord>, StoreError> {
    get_record(data_dir, "config/dev_tokens.tdb", "dev_token", token_hash)
}

pub fn resolve_effective_scope(
    data_dir: &Path,
    actor_id: &str,
    repo_id: Option<&str>,
) -> Result<EffectiveScope, StoreError> {
    let grants = list_records::<CapabilityGrantRecord>(
        data_dir,
        "catalog/capability_grants.tdb",
        "capability_grant",
    )?;
    let mut tenant_id = String::new();
    let mut repo_ids = Vec::new();
    let mut capabilities = Vec::new();
    let mut refs = Vec::new();
    let mut paths = Vec::new();

    let now = Utc::now();
    let mut expires_at: Option<chrono::DateTime<Utc>> = None;

    for grant in grants
        .into_iter()
        .filter(|grant| grant.actor_id == actor_id)
    {
        if grant
            .expires_at
            .map(|expires| expires <= now)
            .unwrap_or(false)
        {
            continue;
        }
        if let Some(target_repo) = repo_id {
            if !grant
                .repo_ids
                .iter()
                .any(|id| id == "*" || id == target_repo)
            {
                continue;
            }
        }
        if tenant_id.is_empty() {
            tenant_id = grant.tenant_id.clone();
        }
        extend_unique(&mut repo_ids, grant.repo_ids);
        extend_unique(&mut capabilities, grant.capabilities);
        extend_unique(&mut refs, grant.refs);
        extend_unique(&mut paths, grant.paths);
        expires_at = match (expires_at, grant.expires_at) {
            (Some(current), Some(next)) => Some(current.min(next)),
            (None, Some(next)) => Some(next),
            (current, None) => current,
        };
    }

    if tenant_id.is_empty() {
        return Err(StoreError::NotFound(format!(
            "actor {actor_id} has no grants"
        )));
    }

    Ok(EffectiveScope {
        actor_id: actor_id.to_string(),
        tenant_id,
        repo_ids,
        capabilities,
        refs,
        paths,
        source: Some("catalog".to_string()),
        expires_at,
    })
}

pub fn put_capability_grant(
    data_dir: &Path,
    mut record: CapabilityGrantRecord,
) -> Result<CapabilityGrantRecord, StoreError> {
    if record.id.trim().is_empty() {
        record.id = capability_id(
            &record.actor_id,
            &record.tenant_id,
            &record.capabilities,
            &record.refs,
            &record.paths,
        );
    }
    put_record(
        data_dir,
        "catalog/capability_grants.tdb",
        "capability_grant",
        &record.id,
        &record,
    )?;
    Ok(record)
}

pub fn list_capability_grants(
    data_dir: &Path,
    actor_id: Option<&str>,
    repo_id: Option<&str>,
) -> Result<Vec<CapabilityGrantRecord>, StoreError> {
    let grants = list_records::<CapabilityGrantRecord>(
        data_dir,
        "catalog/capability_grants.tdb",
        "capability_grant",
    )?;
    Ok(grants
        .into_iter()
        .filter(|grant| actor_id.map(|id| grant.actor_id == id).unwrap_or(true))
        .filter(|grant| {
            repo_id
                .map(|id| grant.repo_ids.iter().any(|repo| repo == "*" || repo == id))
                .unwrap_or(true)
        })
        .collect())
}

pub fn put_connected_token(
    data_dir: &Path,
    record: ConnectedTokenRecord,
) -> Result<(), StoreError> {
    put_record(
        data_dir,
        "catalog/connected_tokens.tdb",
        "connected_token",
        &record.jti,
        &record,
    )
}

pub fn get_connected_token(
    data_dir: &Path,
    jti: &str,
) -> Result<Option<ConnectedTokenRecord>, StoreError> {
    get_record(
        data_dir,
        "catalog/connected_tokens.tdb",
        "connected_token",
        jti,
    )
}

pub fn put_policy_refresh(
    data_dir: &Path,
    record: PolicyRefreshRecord,
) -> Result<PolicyRefreshRecord, StoreError> {
    put_record(
        data_dir,
        "catalog/policy_refreshes.tdb",
        "policy_refresh",
        &record.id,
        &record,
    )?;
    Ok(record)
}

fn extend_unique(target: &mut Vec<String>, values: Vec<String>) {
    for value in values {
        if !target.contains(&value) {
            target.push(value);
        }
    }
}
