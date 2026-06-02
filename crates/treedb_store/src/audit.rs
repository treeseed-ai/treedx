use crate::catalog::{list_records, put_record};
use crate::error::StoreError;
use crate::ids::audit_event_id;
use crate::types::{AuditEventInput, AuditEventRecord, AuditQuery};
use chrono::Utc;
use std::cmp::Reverse;
use std::path::Path;

pub fn append_audit_event(
    data_dir: &Path,
    input: AuditEventInput,
) -> Result<AuditEventRecord, StoreError> {
    let recorded_at = Utc::now();
    let id = audit_event_id(
        &input.event_type,
        &recorded_at.to_rfc3339(),
        input.request_id.as_deref(),
    );
    let record = AuditEventRecord {
        id: id.clone(),
        event_type: input.event_type,
        actor_id: input.actor_id,
        tenant_id: input.tenant_id,
        repo_id: input.repo_id,
        node_id: input.node_id,
        workspace_id: input.workspace_id,
        operation: input.operation,
        status: input.status,
        request_id: input.request_id,
        requested_scope: input.requested_scope,
        effective_scope: input.effective_scope,
        data: input.data,
        recorded_at,
    };
    put_record(data_dir, "audit/events.tdb", "audit_event", &id, &record)?;
    Ok(record)
}

pub fn list_audit_events(
    data_dir: &Path,
    query: AuditQuery,
) -> Result<Vec<AuditEventRecord>, StoreError> {
    let limit = query.limit.unwrap_or(100).min(500) as usize;
    let mut records =
        list_records::<AuditEventRecord>(data_dir, "audit/events.tdb", "audit_event")?;
    records.sort_by_key(|event| Reverse(event.recorded_at));
    Ok(records
        .into_iter()
        .filter(|event| {
            query
                .actor_id
                .as_ref()
                .map(|actor| event.actor_id.as_ref() == Some(actor))
                .unwrap_or(true)
        })
        .filter(|event| {
            query
                .tenant_id
                .as_ref()
                .map(|tenant| event.tenant_id.as_ref() == Some(tenant))
                .unwrap_or(true)
        })
        .filter(|event| {
            query
                .repo_id
                .as_ref()
                .map(|repo| event.repo_id.as_ref() == Some(repo))
                .unwrap_or(true)
        })
        .filter(|event| {
            query
                .event_type
                .as_ref()
                .map(|event_type| event.event_type == *event_type)
                .unwrap_or(true)
        })
        .take(limit)
        .collect())
}
