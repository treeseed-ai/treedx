use crate::ids::{edge_id, normalize_id_value};
use crate::types::{GraphEdge, GraphNode};
use serde_json::json;

pub(super) fn edge(source: &str, edge_type: &str, target: &str, owner: Option<&str>) -> GraphEdge {
    GraphEdge {
        id: edge_id(source, edge_type, target, owner),
        edge_type: edge_type.to_string(),
        source_id: source.to_string(),
        target_id: target.to_string(),
        owner_file_id: owner.map(ToString::to_string),
        data: json!({}),
    }
}

pub(super) fn metadata_node(id: &str, entity_type: &str, title: &str) -> GraphNode {
    GraphNode {
        id: id.to_string(),
        node_type: entity_type.to_string(),
        entity_type: Some(entity_type.to_string()),
        owner_file_id: None,
        path: None,
        slug: Some(normalize_id_value(title)),
        title: Some(title.to_string()),
        heading: None,
        heading_path: None,
        level: None,
        text: None,
        tags: Vec::new(),
        series: None,
        file_id: None,
        status: None,
        canonical: None,
        version: None,
        domain: None,
        audience: Vec::new(),
        updated_at: None,
        data: json!({}),
    }
}

pub(super) struct SectionSpec<'a> {
    pub(super) id: &'a str,
    pub(super) file_id: &'a str,
    pub(super) path: &'a str,
    pub(super) heading: Option<&'a str>,
    pub(super) heading_path: &'a str,
    pub(super) level: u32,
    pub(super) text: &'a str,
    pub(super) start: usize,
    pub(super) end: usize,
}

pub(super) fn section_node(spec: SectionSpec<'_>) -> GraphNode {
    GraphNode {
        id: spec.id.to_string(),
        node_type: "Section".to_string(),
        entity_type: None,
        owner_file_id: Some(spec.file_id.to_string()),
        path: Some(spec.path.to_string()),
        slug: Some(format!(
            "{}#{}",
            super::strip_extension(spec.path),
            spec.heading_path
        )),
        title: spec.heading.map(ToString::to_string),
        heading: spec.heading.map(ToString::to_string),
        heading_path: Some(spec.heading_path.to_string()),
        level: Some(spec.level),
        text: Some(spec.text.to_string()),
        tags: Vec::new(),
        series: None,
        file_id: Some(spec.file_id.to_string()),
        status: None,
        canonical: None,
        version: None,
        domain: None,
        audience: Vec::new(),
        updated_at: None,
        data: json!({"startOffset": spec.start, "endOffset": spec.end}),
    }
}
