use serde::Serialize;

pub fn short_hash(input: &str) -> String {
    blake3::hash(input.as_bytes()).to_hex()[..16].to_string()
}

pub fn graph_version(repo_id: &str, ref_name: &str, commit_sha: &str, paths_hash: &str) -> String {
    format!(
        "graph_{}",
        short_hash(&format!("{repo_id}|{ref_name}|{commit_sha}|{paths_hash}"))
    )
}

pub fn file_id(path: &str) -> String {
    format!("file:{}", short_hash(path))
}

pub fn section_id(file_id: &str, heading_slug: &str, ordinal: usize) -> String {
    format!("section:{file_id}:{heading_slug}:{ordinal}")
}

pub fn tag_id(tag: &str) -> String {
    format!("tag:{}", normalize_id_value(tag))
}

pub fn reference_id(value: &str) -> String {
    format!("ref:{}", short_hash(value))
}

pub fn directory_id(value: &str) -> String {
    format!("ref:dir:{}", short_hash(value))
}

pub fn commit_id(value: &str) -> String {
    format!("ref:commit:{value}")
}

pub fn git_ref_id(value: &str) -> String {
    format!("ref:gitref:{}", short_hash(value))
}

pub fn edge_id(source: &str, edge_type: &str, target: &str, owner: Option<&str>) -> String {
    format!(
        "edge:{}",
        short_hash(&format!(
            "{}|{}|{}|{}",
            source,
            edge_type,
            target,
            owner.unwrap_or("")
        ))
    )
}

pub fn payload_hash<T: Serialize>(payload: &T) -> Result<String, serde_json::Error> {
    let value = serde_json::to_value(payload)?;
    let bytes = serde_json::to_vec(&value)?;
    Ok(format!("blake3:{}", blake3::hash(&bytes).to_hex()))
}

pub fn normalize_id_value(value: &str) -> String {
    value
        .trim()
        .to_lowercase()
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}
