use crate::error::GraphError;
use crate::rank::{lexical_score, tokenize, PROVIDER_ID};
use crate::types::*;
use serde_json::json;
use std::collections::{BTreeMap, BTreeSet, VecDeque};

pub fn search_graph(
    index: GraphIndex,
    request: GraphSearchRequest,
) -> Result<Vec<GraphSearchResult>, GraphError> {
    let limit = limit(request.options.limit);
    let threshold = request.options.score_threshold.unwrap_or(0.0);
    let scope = request.scope.as_str();
    let mut results = index
        .nodes
        .iter()
        .filter(|node| scope_matches(node, scope))
        .filter(|node| type_matches(node, &request.options.node_types))
        .filter_map(|node| {
            let score = lexical_score(node, &request.query);
            (score > threshold).then(|| GraphSearchResult {
                node: node.clone(),
                score,
                reason: format!("lexical:{scope}"),
                highlights: tokenize(&request.query),
                context: json!({"path": node.path}),
            })
        })
        .collect::<Vec<_>>();
    sort_results(&mut results);
    results.truncate(limit);
    Ok(results)
}

pub fn get_node(index: &GraphIndex, node_id: &str) -> Option<GraphNode> {
    index.nodes.iter().find(|node| node.id == node_id).cloned()
}

pub fn query_graph(
    index: GraphIndex,
    request: GraphQueryRequest,
) -> Result<GraphQueryResult, GraphError> {
    let depth = depth(request.options.depth);
    let limit = limit(request.options.max_nodes.or(request.options.limit));
    let node_map = node_map(&index);
    let mut scores: BTreeMap<String, (f64, u32, Vec<String>)> = BTreeMap::new();
    let mut seed_ids = Vec::new();

    for seed in seed_node_ids(&index, &request) {
        if node_map.contains_key(&seed) {
            seed_ids.push(seed.clone());
            scores.insert(seed.clone(), (100.0, 0, vec!["seed".to_string()]));
            expand(&index, &seed, depth, &request, &mut scores);
        }
    }

    if let Some(query) = &request.query {
        let search = search_graph(
            index.clone(),
            GraphSearchRequest {
                query: query.clone(),
                scope: request.scope.clone().unwrap_or_else(|| "all".to_string()),
                options: request.options.clone(),
            },
        )?;
        for result in search {
            let entry = scores
                .entry(result.node.id.clone())
                .or_insert((0.0, 0, Vec::new()));
            entry.0 += result.score;
            entry.2.push("query".to_string());
            if !seed_ids.contains(&result.node.id) {
                seed_ids.push(result.node.id.clone());
            }
        }
    }

    let mut nodes = scores
        .into_iter()
        .filter_map(|(id, (score, depth, reasons))| {
            node_map.get(&id).cloned().map(|node| GraphQueryNodeResult {
                node,
                score,
                depth,
                reasons,
            })
        })
        .filter(|entry| where_matches(&entry.node, &request.where_filters))
        .filter(|entry| type_matches(&entry.node, &request.options.node_types))
        .collect::<Vec<_>>();
    nodes.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.node.id.cmp(&b.node.id))
    });
    nodes.truncate(limit);
    let included: BTreeSet<String> = nodes.iter().map(|entry| entry.node.id.clone()).collect();
    let edges = index
        .edges
        .into_iter()
        .filter(|edge| included.contains(&edge.source_id) && included.contains(&edge.target_id))
        .filter(|edge| {
            request.options.edge_types.is_empty()
                || request.options.edge_types.contains(&edge.edge_type)
        })
        .collect::<Vec<_>>();
    Ok(GraphQueryResult {
        seed_ids,
        nodes,
        edges,
        provider_id: PROVIDER_ID.to_string(),
        diagnostics: json!({"authorizedNodeCount": included.len()}),
    })
}

pub fn related_nodes(
    index: GraphIndex,
    seed_id: &str,
    mut request: GraphQueryRequest,
) -> Result<GraphQueryResult, GraphError> {
    request.seed_ids = vec![seed_id.to_string()];
    request.options.depth = Some(request.options.depth.unwrap_or(1));
    query_graph(index, request)
}

pub fn subgraph(
    index: GraphIndex,
    seed_ids: Vec<String>,
    mut request: GraphQueryRequest,
) -> Result<GraphQueryResult, GraphError> {
    request.seed_ids = seed_ids;
    query_graph(index, request)
}

fn seed_node_ids(index: &GraphIndex, request: &GraphQueryRequest) -> Vec<String> {
    let mut ids = request.seed_ids.clone();
    for seed in &request.seeds {
        match seed.kind.as_str() {
            "id" => ids.push(seed.value.clone()),
            "path" => ids.extend(
                index
                    .nodes
                    .iter()
                    .filter(|node| node.path.as_deref() == Some(seed.value.trim_start_matches('/')))
                    .map(|node| node.id.clone()),
            ),
            "tag" => ids.extend(
                index
                    .nodes
                    .iter()
                    .filter(|node| {
                        node.tags
                            .iter()
                            .any(|tag| tag.eq_ignore_ascii_case(&seed.value))
                    })
                    .map(|node| node.id.clone()),
            ),
            "type" => ids.extend(
                index
                    .nodes
                    .iter()
                    .filter(|node| {
                        node.node_type.eq_ignore_ascii_case(&seed.value)
                            || node
                                .entity_type
                                .as_deref()
                                .unwrap_or("")
                                .eq_ignore_ascii_case(&seed.value)
                    })
                    .map(|node| node.id.clone()),
            ),
            "query" => {
                ids.extend(
                    index
                        .nodes
                        .iter()
                        .filter(|node| lexical_score(node, &seed.value) > 0.0)
                        .map(|node| node.id.clone()),
                );
            }
            _ => {}
        }
    }
    ids
}

fn expand(
    index: &GraphIndex,
    seed: &str,
    max_depth: usize,
    request: &GraphQueryRequest,
    scores: &mut BTreeMap<String, (f64, u32, Vec<String>)>,
) {
    let mut queue = VecDeque::from([(seed.to_string(), 0usize)]);
    let mut seen = BTreeSet::from([seed.to_string()]);
    while let Some((current, current_depth)) = queue.pop_front() {
        if current_depth >= max_depth {
            continue;
        }
        for edge in &index.edges {
            if !request.relations.is_empty()
                && !relation_allowed(&edge.edge_type, &request.relations)
            {
                continue;
            }
            let next = if edge.source_id == current {
                Some(edge.target_id.clone())
            } else if edge.target_id == current {
                Some(edge.source_id.clone())
            } else {
                None
            };
            if let Some(next) = next {
                if seen.insert(next.clone()) {
                    let depth = current_depth + 1;
                    let score = 100.0 / 2f64.powi(depth as i32);
                    scores.entry(next.clone()).or_insert((
                        score,
                        depth as u32,
                        vec![format!("edge:{}", edge.edge_type)],
                    ));
                    queue.push_back((next, depth));
                }
            }
        }
    }
}

fn relation_allowed(edge_type: &str, relations: &[String]) -> bool {
    relations.iter().any(|relation| match relation.as_str() {
        "related" => matches!(
            edge_type,
            "LINKS_TO" | "HAS_TAG" | "IN_SERIES" | "SAME_DIRECTORY"
        ),
        "references" => matches!(edge_type, "LINKS_TO" | "REFERENCES"),
        "parent" => edge_type == "PARENT_SECTION",
        "child" => edge_type == "CHILD_SECTION",
        "depends_on" => edge_type == "DEPENDS_ON",
        "implements" => edge_type == "IMPLEMENTS",
        "supersedes" => edge_type == "SUPERSEDES",
        _ => false,
    })
}

fn scope_matches(node: &GraphNode, scope: &str) -> bool {
    match scope {
        "files" => node.node_type == "File",
        "sections" => node.node_type == "Section",
        "entities" => !matches!(node.node_type.as_str(), "File" | "Section"),
        _ => true,
    }
}

fn type_matches(node: &GraphNode, node_types: &[String]) -> bool {
    node_types.is_empty() || node_types.contains(&node.node_type)
}

fn where_matches(node: &GraphNode, filters: &[GraphWhereFilter]) -> bool {
    filters.iter().all(|filter| {
        let values = match filter.field.as_str() {
            "type" => vec![node
                .entity_type
                .clone()
                .unwrap_or_else(|| node.node_type.clone())
                .to_lowercase()],
            "status" => vec![node.status.clone().unwrap_or_default().to_lowercase()],
            "audience" => node
                .audience
                .iter()
                .map(|value| value.to_lowercase())
                .collect(),
            "tag" => node.tags.iter().map(|value| value.to_lowercase()).collect(),
            "domain" => vec![node.domain.clone().unwrap_or_default().to_lowercase()],
            _ => Vec::new(),
        };
        let expected = match &filter.value {
            serde_json::Value::Array(items) => items
                .iter()
                .filter_map(|item| item.as_str().map(|value| value.to_lowercase()))
                .collect(),
            serde_json::Value::String(value) => vec![value.to_lowercase()],
            other => vec![other.to_string().to_lowercase()],
        };
        if filter.op == "in" {
            expected.iter().any(|value| values.contains(value))
        } else {
            expected.iter().all(|value| values.contains(value))
        }
    })
}

fn node_map(index: &GraphIndex) -> BTreeMap<String, GraphNode> {
    index
        .nodes
        .iter()
        .map(|node| (node.id.clone(), node.clone()))
        .collect()
}

fn sort_results(results: &mut [GraphSearchResult]) {
    results.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.node.id.cmp(&b.node.id))
    });
}

fn limit(value: Option<u32>) -> usize {
    value.unwrap_or(20).clamp(1, 50) as usize
}

fn depth(value: Option<u32>) -> usize {
    value.unwrap_or(1).clamp(0, 3) as usize
}
