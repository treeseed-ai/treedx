use serde::Serialize;

pub fn short_hash(input: &str) -> String {
    blake3::hash(input.as_bytes()).to_hex()[..16].to_string()
}

pub fn hash_token(token: &str) -> String {
    format!("blake3:{}", blake3::hash(token.as_bytes()).to_hex())
}

pub fn payload_hash<T: Serialize>(payload: &T) -> Result<String, serde_json::Error> {
    let value = serde_json::to_value(payload)?;
    let bytes = serde_json::to_vec(&value)?;
    Ok(format!("blake3:{}", blake3::hash(&bytes).to_hex()))
}

pub fn repository_id(name: &str, local_path: &str, remote_url: Option<&str>) -> String {
    format!(
        "repo_{}",
        short_hash(&format!(
            "{}|{}|{}",
            name.trim(),
            local_path.trim(),
            remote_url.unwrap_or("").trim()
        ))
    )
}

pub fn capability_id(
    actor_id: &str,
    tenant_id: &str,
    capabilities: &[String],
    refs: &[String],
    paths: &[String],
) -> String {
    format!(
        "cap_{}",
        short_hash(&format!(
            "{}|{}|{}|{}|{}",
            actor_id,
            tenant_id,
            capabilities.join(","),
            refs.join(","),
            paths.join(",")
        ))
    )
}

pub fn mirror_id(repo_id: &str, source: &str, target: &str, mode: &str) -> String {
    format!(
        "mirror_{}",
        short_hash(&format!("{repo_id}|{source}|{target}|{mode}"))
    )
}

pub fn snapshot_id(
    repo_id: &str,
    ref_name: &str,
    commit_sha: &str,
    kind: &str,
    paths: &[String],
) -> String {
    format!(
        "snap_{}",
        short_hash(&format!(
            "{}|{}|{}|{}|{}",
            repo_id,
            ref_name,
            commit_sha,
            kind,
            paths.join(",")
        ))
    )
}

pub fn artifact_id(snapshot_id: &str, format: &str) -> String {
    format!(
        "artifact_{}",
        short_hash(&format!("{snapshot_id}|{format}"))
    )
}

pub fn mirror_sync_id(mirror_id: &str, started_at: &str) -> String {
    format!("msync_{}", short_hash(&format!("{mirror_id}|{started_at}")))
}

pub fn migration_id(
    repo_id: &str,
    source_node_id: &str,
    target_node_id: &str,
    mode: &str,
    created_at: &str,
) -> String {
    format!(
        "mig_{}",
        short_hash(&format!(
            "{repo_id}|{source_node_id}|{target_node_id}|{mode}|{created_at}"
        ))
    )
}

pub fn audit_event_id(event_type: &str, recorded_at: &str, request_id: Option<&str>) -> String {
    format!(
        "evt_{}",
        short_hash(&format!(
            "{}|{}|{}",
            event_type,
            recorded_at,
            request_id.unwrap_or("")
        ))
    )
}

pub fn workspace_id(
    repo_id: &str,
    actor_id: &str,
    branch_name: Option<&str>,
    created_at: &str,
) -> String {
    format!(
        "ws_{}",
        short_hash(&format!(
            "{}|{}|{}|{}|{}",
            repo_id,
            actor_id,
            branch_name.unwrap_or(""),
            created_at,
            uuid::Uuid::new_v4()
        ))
    )
}

pub fn lease_id(repo_id: &str, branch_name: &str) -> String {
    format!("lease_{}", short_hash(&format!("{repo_id}|{branch_name}")))
}

pub fn workspace_file_id(workspace_id: &str, path: &str) -> String {
    format!("wsfile_{}", short_hash(&format!("{workspace_id}|{path}")))
}
