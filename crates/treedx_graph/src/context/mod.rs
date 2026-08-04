use crate::query::query_graph;
use crate::types::*;
use serde_json::json;
use std::collections::BTreeSet;

pub fn build_context_pack(
    index: GraphIndex,
    request: ContextPackRequest,
) -> Result<ContextPack, crate::GraphError> {
    let max_nodes = request.budget.max_nodes.unwrap_or(8).clamp(1, 50) as usize;
    let max_tokens = request.budget.max_tokens.unwrap_or(1800);
    let include_mode = request.budget.include_mode.as_deref().unwrap_or("mixed");
    let result = query_graph(index, request.graph_query)?;
    let mut total = 0u32;
    let mut nodes = Vec::new();
    let mut paths = BTreeSet::new();
    for entry in result.nodes.iter() {
        if nodes.len() >= max_nodes {
            break;
        }
        if include_mode == "files" && entry.node.node_type != "File" {
            continue;
        }
        if include_mode == "sections" && entry.node.node_type != "Section" {
            continue;
        }
        if include_mode == "mixed" && !matches!(entry.node.node_type.as_str(), "File" | "Section") {
            continue;
        }
        let original_text = entry.node.text.clone().unwrap_or_default();
        let remaining_tokens = max_tokens.saturating_sub(total);
        if remaining_tokens == 0 {
            continue;
        }
        let text = truncate_to_token_budget(&original_text, remaining_tokens);
        let estimate = token_estimate(&text).min(remaining_tokens);
        if text.is_empty() || total + estimate > max_tokens {
            continue;
        }
        total += estimate;
        if let Some(path) = &entry.node.path {
            paths.insert(path.clone());
        }
        let mut node = entry.node.clone();
        node.text = Some(text.clone());
        nodes.push(ContextPackNode {
			node,
            score: entry.score,
            depth: entry.depth,
            text,
            token_estimate: estimate,
            reasons: entry.reasons.clone(),
            provenance: json!({
                "seedIds": result.seed_ids,
                "viaEdgeTypes": result.edges.iter()
                    .filter(|edge| edge.source_id == entry.node.id || edge.target_id == entry.node.id)
                    .map(|edge| edge.edge_type.clone())
                    .collect::<Vec<_>>()
            }),
        });
    }
    Ok(ContextPack {
        seed_ids: result.seed_ids,
        total_token_estimate: total,
        included_node_ids: nodes.iter().map(|entry| entry.node.id.clone()).collect(),
        included_paths: paths.into_iter().collect(),
        nodes,
        edges: result.edges,
        diagnostics: json!({}),
    })
}

fn token_estimate(text: &str) -> u32 {
    std::cmp::max(1, ((text.trim().len() as f64) / 4.0).ceil() as u32)
}

fn truncate_to_token_budget(text: &str, max_tokens: u32) -> String {
    let max_chars = max_tokens.saturating_mul(4) as usize;
    if text.chars().count() <= max_chars {
        return text.to_string();
    }
    text.chars().take(max_chars).collect()
}
