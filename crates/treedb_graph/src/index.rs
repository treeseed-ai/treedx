use crate::ids::*;
use crate::parse::{
    extract_headings, extract_links, parse_document, section_ranges, string_array, string_field,
};
use crate::types::*;
use chrono::Utc;
use serde_json::json;
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

pub fn build_graph_index(input: GraphIndexInput) -> Result<GraphIndex, crate::GraphError> {
    let paths_hash = short_hash(
        &input
            .documents
            .iter()
            .map(|doc| doc.path.as_str())
            .collect::<Vec<_>>()
            .join("|"),
    );
    let version = input.graph_version.clone().unwrap_or_else(|| {
        graph_version(
            &input.repo_id,
            &input.ref_name,
            &input.commit_sha,
            &paths_hash,
        )
    });

    let mut documents = Vec::new();
    let mut nodes = Vec::new();
    let mut edges = Vec::new();
    let mut file_by_path = BTreeMap::new();
    let commit_node = GraphNode {
        id: commit_id(&input.commit_sha),
        node_type: "Reference".to_string(),
        entity_type: Some("Commit".to_string()),
        owner_file_id: None,
        path: None,
        slug: None,
        title: Some(input.commit_sha.clone()),
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
        data: json!({"commitSha": input.commit_sha}),
    };
    let ref_node = GraphNode {
        id: git_ref_id(&input.ref_name),
        node_type: "Reference".to_string(),
        entity_type: Some("GitRef".to_string()),
        owner_file_id: None,
        path: None,
        slug: None,
        title: Some(input.ref_name.clone()),
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
        data: json!({"ref": input.ref_name}),
    };
    nodes.push(commit_node);
    nodes.push(ref_node.clone());

    for doc_input in &input.documents {
        let parsed = parse_document(&doc_input.content);
        let body = parsed.body;
        let frontmatter = parsed.frontmatter;
        let file_id = file_id(&doc_input.path);
        file_by_path.insert(strip_extension(&doc_input.path), file_id.clone());
        file_by_path.insert(doc_input.path.clone(), file_id.clone());
        let title = string_field(&frontmatter, &["title", "name"])
            .unwrap_or_else(|| fallback_title(&doc_input.path));
        let tags = string_array(&frontmatter, "tags");
        let audience = string_array(&frontmatter, "audience");
        let series = string_field(&frontmatter, &["series"]);
        let status = string_field(&frontmatter, &["status"]);
        let domain = string_field(&frontmatter, &["domain"]);
        let updated_at = string_field(&frontmatter, &["updatedAt", "updated_at"]);
        let version_value = string_field(&frontmatter, &["version"]);
        let canonical = frontmatter
            .as_object()
            .and_then(|object| object.get("canonical"))
            .and_then(|value| value.as_bool());
        nodes.push(GraphNode {
            id: file_id.clone(),
            node_type: "File".to_string(),
            entity_type: None,
            owner_file_id: Some(file_id.clone()),
            path: Some(doc_input.path.clone()),
            slug: Some(strip_extension(&doc_input.path)),
            title: Some(title.clone()),
            heading: None,
            heading_path: None,
            level: None,
            text: Some(body.clone()),
            tags: tags.clone(),
            series: series.clone(),
            file_id: Some(file_id.clone()),
            status,
            canonical,
            version: version_value,
            domain,
            audience,
            updated_at,
            data: json!({
                "objectId": doc_input.object_id,
                "extension": Path::new(&doc_input.path).extension().and_then(|value| value.to_str()).map(|value| format!(".{value}")).unwrap_or_default(),
                "frontmatter": frontmatter,
                "ref": input.ref_name,
                "commitSha": input.commit_sha,
            }),
        });
        edges.push(edge(
            &file_id,
            "DEFINED_BY",
            &commit_id(&input.commit_sha),
            Some(&file_id),
        ));
        edges.push(edge(
            &git_ref_id(&input.ref_name),
            "DEFINES",
            &file_id,
            Some(&file_id),
        ));
        let dir = directory(&doc_input.path);
        let dir_id = directory_id(&dir);
        nodes.push(GraphNode {
            id: dir_id.clone(),
            node_type: "Reference".to_string(),
            entity_type: Some("Directory".to_string()),
            owner_file_id: None,
            path: None,
            slug: Some(dir.clone()),
            title: Some(dir.clone()),
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
            data: json!({"path": dir}),
        });
        edges.push(edge(&file_id, "BELONGS_TO", &dir_id, Some(&file_id)));
        for tag in &tags {
            let id = tag_id(tag);
            nodes.push(metadata_node(&id, "Tag", tag));
            edges.push(edge(&file_id, "HAS_TAG", &id, Some(&file_id)));
        }
        if let Some(series) = &series {
            let id = reference_id(&format!("series:{series}"));
            nodes.push(metadata_node(&id, "Series", series));
            edges.push(edge(&file_id, "IN_SERIES", &id, Some(&file_id)));
        }

        let headings = extract_headings(&body);
        let ranges = section_ranges(&body, &headings);
        let mut section_ids = Vec::new();
        if headings.is_empty() && !ranges.is_empty() {
            let sid = section_id(&file_id, "__intro", 0);
            section_ids.push(sid.clone());
            nodes.push(section_node(SectionSpec {
                id: &sid,
                file_id: &file_id,
                path: &doc_input.path,
                heading: None,
                heading_path: "__intro",
                level: 0,
                text: &body,
                start: 0,
                end: body.len(),
            }));
            edges.push(edge(&file_id, "HAS_SECTION", &sid, Some(&file_id)));
            edges.push(edge(&sid, "BELONGS_TO_FILE", &file_id, Some(&file_id)));
        } else {
            let mut stack: Vec<(u32, String)> = Vec::new();
            let mut ordinals: BTreeMap<String, usize> = BTreeMap::new();
            for (idx, heading) in headings.iter().enumerate() {
                while stack
                    .last()
                    .map(|(level, _)| *level >= heading.level)
                    .unwrap_or(false)
                {
                    stack.pop();
                }
                let heading_path = if let Some((_, parent)) = stack.last() {
                    format!("{parent}/{}", heading.slug)
                } else {
                    heading.slug.clone()
                };
                let ordinal = *ordinals.get(&heading_path).unwrap_or(&0);
                ordinals.insert(heading_path.clone(), ordinal + 1);
                let sid = section_id(&file_id, &heading_path, ordinal);
                let (start, end) = ranges[idx];
                let text = body[start..end].to_string();
                section_ids.push(sid.clone());
                nodes.push(section_node(SectionSpec {
                    id: &sid,
                    file_id: &file_id,
                    path: &doc_input.path,
                    heading: Some(&heading.text),
                    heading_path: &heading_path,
                    level: heading.level,
                    text: &text,
                    start,
                    end,
                }));
                edges.push(edge(&file_id, "HAS_SECTION", &sid, Some(&file_id)));
                edges.push(edge(&sid, "BELONGS_TO_FILE", &file_id, Some(&file_id)));
                if let Some((_, parent_id)) = stack.last() {
                    edges.push(edge(&sid, "PARENT_SECTION", parent_id, Some(&file_id)));
                    edges.push(edge(parent_id, "CHILD_SECTION", &sid, Some(&file_id)));
                }
                if let Some(previous) = section_ids.get(section_ids.len().saturating_sub(2)) {
                    edges.push(edge(previous, "NEXT_SECTION", &sid, Some(&file_id)));
                    edges.push(edge(&sid, "PREV_SECTION", previous, Some(&file_id)));
                }
                stack.push((heading.level, sid.clone()));
            }
        }
        documents.push(GraphDocument {
            path: doc_input.path.clone(),
            object_id: doc_input.object_id.clone(),
            size: doc_input.size,
            content_hash: format!(
                "blake3:{}",
                blake3::hash(doc_input.content.as_bytes()).to_hex()
            ),
            title,
            body: body.clone(),
            frontmatter,
            section_ids,
            link_targets: extract_links(&body)
                .into_iter()
                .map(|link| link.target)
                .collect(),
        });
    }

    let path_to_file = file_by_path;
    for doc in &documents {
        let file_id = file_id(&doc.path);
        for link in extract_links(&doc.body) {
            let target_path = resolve_link_path(&doc.path, &link.target);
            let target_id = target_path.as_ref().and_then(|path| {
                path_to_file
                    .get(path)
                    .cloned()
                    .or_else(|| path_to_file.get(&strip_extension(path)).cloned())
            });
            let target = if let Some(target_id) = target_id {
                target_id
            } else {
                let rid = reference_id(&link.target);
                nodes.push(GraphNode {
                    id: rid.clone(),
                    node_type: "Reference".to_string(),
                    entity_type: Some("Reference".to_string()),
                    owner_file_id: Some(file_id.clone()),
                    path: None,
                    slug: None,
                    title: Some(link.target.clone()),
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
                    data: json!({"target": link.target, "label": link.label, "resolved": false}),
                });
                rid
            };
            edges.push(edge(&file_id, "LINKS_TO", &target, Some(&file_id)));
        }
    }

    dedupe(&mut nodes, |node| node.id.clone());
    dedupe(&mut edges, |edge| edge.id.clone());
    let delta = compute_delta(input.previous_manifest.as_ref(), &documents);
    let metrics = GraphMetrics {
        total_files: documents.len() as u64,
        total_sections: nodes
            .iter()
            .filter(|node| node.node_type == "Section")
            .count() as u64,
        total_entities: nodes
            .iter()
            .filter(|node| !matches!(node.node_type.as_str(), "File" | "Section"))
            .count() as u64,
        total_edges: edges.len() as u64,
        skipped_binary_or_invalid_utf8: 0,
        unresolved_references: nodes
            .iter()
            .filter(|node| node.entity_type.as_deref() == Some("Reference"))
            .count() as u64,
        last_refresh_at: Some(Utc::now()),
    };
    let manifest = GraphManifest {
        schema_version: 1,
        graph_version: version,
        repo_id: input.repo_id,
        ref_name: input.ref_name,
        commit_sha: input.commit_sha,
        created_at: Utc::now(),
        paths_hash,
        node_count: nodes.len() as u64,
        edge_count: edges.len() as u64,
        document_count: documents.len() as u64,
        metrics: metrics.clone(),
        delta,
    };
    Ok(GraphIndex {
        manifest,
        documents,
        nodes,
        edges,
        metrics,
        diagnostics: GraphDiagnostics::default(),
    })
}

fn edge(source: &str, edge_type: &str, target: &str, owner: Option<&str>) -> GraphEdge {
    GraphEdge {
        id: edge_id(source, edge_type, target, owner),
        edge_type: edge_type.to_string(),
        source_id: source.to_string(),
        target_id: target.to_string(),
        owner_file_id: owner.map(ToString::to_string),
        data: json!({}),
    }
}

fn metadata_node(id: &str, entity_type: &str, title: &str) -> GraphNode {
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

struct SectionSpec<'a> {
    id: &'a str,
    file_id: &'a str,
    path: &'a str,
    heading: Option<&'a str>,
    heading_path: &'a str,
    level: u32,
    text: &'a str,
    start: usize,
    end: usize,
}

fn section_node(spec: SectionSpec<'_>) -> GraphNode {
    GraphNode {
        id: spec.id.to_string(),
        node_type: "Section".to_string(),
        entity_type: None,
        owner_file_id: Some(spec.file_id.to_string()),
        path: Some(spec.path.to_string()),
        slug: Some(format!(
            "{}#{}",
            strip_extension(spec.path),
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

fn fallback_title(path: &str) -> String {
    Path::new(path)
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or(path)
        .to_string()
}

fn strip_extension(path: &str) -> String {
    path.trim_end_matches(".md")
        .trim_end_matches(".mdx")
        .trim_end_matches(".txt")
        .to_string()
}

fn directory(path: &str) -> String {
    Path::new(path)
        .parent()
        .unwrap_or_else(|| Path::new(""))
        .to_string_lossy()
        .replace('\\', "/")
}

fn resolve_link_path(from: &str, target: &str) -> Option<String> {
    if target.starts_with("http://") || target.starts_with("https://") || target.starts_with('#') {
        return None;
    }
    let no_hash = target.split('#').next().unwrap_or(target);
    let base = Path::new(from).parent().unwrap_or_else(|| Path::new(""));
    let mut parts = Vec::new();
    for component in base.join(no_hash).components() {
        match component {
            std::path::Component::ParentDir => {
                parts.pop();
            }
            std::path::Component::Normal(value) => parts.push(value.to_string_lossy().to_string()),
            _ => {}
        }
    }
    Some(
        PathBuf::from_iter(parts)
            .to_string_lossy()
            .replace('\\', "/"),
    )
}

fn compute_delta(previous: Option<&GraphManifest>, docs: &[GraphDocument]) -> GraphDelta {
    let current: BTreeSet<String> = docs.iter().map(|doc| doc.path.clone()).collect();
    if previous.is_none() {
        return GraphDelta {
            added: current.into_iter().collect(),
            modified: Vec::new(),
            removed: Vec::new(),
        };
    }
    GraphDelta::default()
}

fn dedupe<T, F>(items: &mut Vec<T>, mut key: F)
where
    F: FnMut(&T) -> String,
{
    let mut seen = BTreeSet::new();
    items.retain(|item| seen.insert(key(item)));
}
