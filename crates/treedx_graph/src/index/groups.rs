use crate::ids::{edge_id, group_id};
use crate::types::{GraphDiagnostics, GraphEdge, GraphNode};
use serde_json::json;
use std::collections::{BTreeMap, BTreeSet, VecDeque};

#[derive(Debug, Clone)]
pub(super) struct GroupRelationship {
    pub(super) from: String,
    pub(super) to: String,
    pub(super) predicate: String,
    pub(super) propagates_membership: bool,
    pub(super) owner_file_id: String,
}

pub(super) fn apply_group_hierarchy(
    nodes: &mut [GraphNode],
    edges: &mut Vec<GraphEdge>,
    relationships: &[GroupRelationship],
    diagnostics: &mut GraphDiagnostics,
) {
    let mut parents: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for relationship in relationships {
        let from = group_id(&relationship.from);
        let to = group_id(&relationship.to);
        edges.push(GraphEdge {
            id: edge_id(
                &from,
                "GROUP_RELATION",
                &to,
                Some(&relationship.owner_file_id),
            ),
            edge_type: "GROUP_RELATION".to_string(),
            source_id: from.clone(),
            target_id: to.clone(),
            owner_file_id: Some(relationship.owner_file_id.clone()),
            data: json!({
                "predicate": relationship.predicate,
                "propagatesMembership": relationship.propagates_membership,
            }),
        });
        if relationship.propagates_membership {
            parents.entry(from).or_default().push(to);
        }
    }
    for values in parents.values_mut() {
        values.sort();
        values.dedup();
    }

    let direct_by_file = nodes
        .iter()
        .filter(|node| node.node_type == "File")
        .map(|node| (node.id.clone(), node.group_ids.clone()))
        .collect::<BTreeMap<_, _>>();
    for node in nodes.iter_mut() {
        let direct = if node.node_type == "File" {
            node.group_ids.clone()
        } else {
            node.owner_file_id
                .as_ref()
                .and_then(|owner| direct_by_file.get(owner))
                .cloned()
                .unwrap_or_default()
        };
        let mut effective = BTreeSet::new();
        for value in &direct {
            let origin = group_id(value);
            effective.insert(origin.clone());
            let mut queue = VecDeque::from([origin.clone()]);
            let mut visited = BTreeSet::from([origin.clone()]);
            while let Some(current) = queue.pop_front() {
                for parent in parents.get(&current).into_iter().flatten() {
                    if parent == &origin {
                        diagnostics.warnings.push(format!(
                            "Membership-propagating group cycle detected at {origin}."
                        ));
                        continue;
                    }
                    if visited.insert(parent.clone()) {
                        effective.insert(parent.clone());
                        queue.push_back(parent.clone());
                    }
                }
            }
        }
        node.effective_group_ids = effective.into_iter().collect();
    }

    let memberships = nodes
        .iter()
        .filter(|node| node.node_type == "File")
        .flat_map(|node| {
            let direct = node
                .group_ids
                .iter()
                .map(|value| group_id(value))
                .collect::<BTreeSet<_>>();
            node.effective_group_ids.iter().filter_map(move |value| {
                let target = group_id(value);
                (!direct.contains(&target)).then(|| (node.id.clone(), target))
            })
        })
        .collect::<Vec<_>>();
    for (source, target) in memberships {
        edges.push(GraphEdge {
            id: edge_id(&source, "EFFECTIVE_GROUP", &target, Some(&source)),
            edge_type: "EFFECTIVE_GROUP".to_string(),
            source_id: source.clone(),
            target_id: target,
            owner_file_id: Some(source),
            data: json!({"provenance": "inherited"}),
        });
    }
    diagnostics.warnings.sort();
    diagnostics.warnings.dedup();
}
