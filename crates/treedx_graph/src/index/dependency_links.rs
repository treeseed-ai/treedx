use super::nodes::edge;
use crate::ids::reference_id;
use crate::types::{GraphDiagnostics, GraphEdge, GraphNode};
use serde_json::{json, Value};

pub(super) fn append_typed_dependency_links(
    frontmatter: &Value,
    path: &str,
    file_id: &str,
    nodes: &mut Vec<GraphNode>,
    edges: &mut Vec<GraphEdge>,
    diagnostics: &mut GraphDiagnostics,
) {
    let Some(links) = frontmatter.get("links").and_then(Value::as_array) else {
        return;
    };
    for link in links {
        if link.get("relation").and_then(Value::as_str) != Some("depends_on") {
            continue;
        }
        let ends = [link.get("from"), link.get("to")];
        if ends.iter().any(|end| {
            let Some(end) = end else {
                return true;
            };
            ["repository", "commit", "path", "anchor", "digest", "id"]
                .iter()
                .any(|key| {
                    end.get(*key)
                        .and_then(Value::as_str)
                        .is_none_or(str::is_empty)
                })
        }) {
            diagnostics
                .warnings
                .push(format!("Invalid depends_on link in {path}"));
            continue;
        }
        let mut ids = Vec::new();
        for end in ends.into_iter().flatten() {
            let encoded = serde_json::to_string(end).unwrap_or_default();
            let id = reference_id(&format!("{file_id}:{encoded}"));
            nodes.push(GraphNode {
                id: id.clone(),
                node_type: "Reference".to_string(),
                entity_type: Some("ExactEntityReference".to_string()),
                owner_file_id: Some(file_id.to_string()),
                path: None,
                slug: None,
                title: end.get("id").and_then(Value::as_str).map(str::to_string),
                heading: None,
                heading_path: None,
                level: None,
                text: None,
                group_ids: Vec::new(),
                effective_group_ids: Vec::new(),
                series: None,
                file_id: None,
                status: None,
                canonical: None,
                version: None,
                domain: None,
                audience: Vec::new(),
                updated_at: None,
                data: end.clone(),
            });
            ids.push(id);
        }
        let mut dependency = edge(&ids[0], "DEPENDS_ON", &ids[1], Some(file_id));
        dependency.data = json!({"link": link, "ownerPath": path});
        edges.push(dependency);
    }
}
