use std::fs;

use treedx_graph::{
    build_graph_index, parse_ctx_dsl, query_graph, read_graph_segments, read_latest_graph_manifest,
    search_graph, write_graph_segments, GraphDocumentInput, GraphIndexInput, GraphQueryOptions,
    GraphQueryRequest, GraphSearchRequest,
};

fn sample_index() -> treedx_graph::GraphIndex {
    build_graph_index(GraphIndexInput {
        repo_id: "repo_test".to_string(),
        ref_name: "refs/heads/main".to_string(),
        commit_sha: "0123456789012345678901234567890123456789".to_string(),
        graph_version: None,
        previous_manifest: None,
        documents: vec![
            GraphDocumentInput {
                path: "docs/readme.md".to_string(),
                object_id: "blob1".to_string(),
                size: 0,
                content: r#"---
title: Release Notes
status: published
tags:
  - release
series: Handbook
---
# Overview

Release provenance links to [Guide](guide.md).

## Details

More release text.
"#
                .to_string(),
            },
            GraphDocumentInput {
                path: "docs/guide.md".to_string(),
                object_id: "blob2".to_string(),
                size: 0,
                content: "# Guide\n\nimport Widget from './widget'\n\nA guide page.".to_string(),
            },
        ],
    })
    .expect("graph builds")
}

#[test]
fn builds_generic_graph_nodes_and_edges() {
    let index = sample_index();

    assert_eq!(index.manifest.repo_id, "repo_test");
    assert_eq!(index.metrics.total_files, 2);
    assert!(index
        .nodes
        .iter()
        .any(|node| node.node_type == "File" && node.path.as_deref() == Some("docs/readme.md")));
    assert!(index
        .nodes
        .iter()
        .any(|node| node.node_type == "Section" && node.heading.as_deref() == Some("Overview")));
    assert!(index
        .nodes
        .iter()
        .any(|node| node.node_type == "Tag" && node.title.as_deref() == Some("release")));
    assert!(index
        .edges
        .iter()
        .any(|edge| edge.edge_type == "HAS_SECTION"));
    assert!(index.edges.iter().any(|edge| edge.edge_type == "LINKS_TO"));
    assert!(index.edges.iter().any(|edge| edge.edge_type == "IN_SERIES"));
    assert!(index
        .edges
        .iter()
        .any(|edge| edge.edge_type == "DEFINED_BY"));
}

#[test]
fn ranks_and_queries_deterministically() {
    let index = sample_index();
    let results = search_graph(
        index.clone(),
        GraphSearchRequest {
            query: "release overview".to_string(),
            scope: "sections".to_string(),
            options: GraphQueryOptions {
                limit: Some(10),
                ..Default::default()
            },
        },
    )
    .expect("search works");

    assert_eq!(results[0].node.heading.as_deref(), Some("Overview"));
    assert!(results[0].score > 0.0);

    let seed = index
        .nodes
        .iter()
        .find(|node| node.path.as_deref() == Some("docs/readme.md") && node.node_type == "File")
        .unwrap()
        .id
        .clone();
    let query = query_graph(
        index,
        GraphQueryRequest {
            seed_ids: vec![seed],
            relations: vec!["references".to_string()],
            options: GraphQueryOptions {
                depth: Some(1),
                max_nodes: Some(10),
                ..Default::default()
            },
            ..Default::default()
        },
    )
    .expect("query works");

    assert!(query.nodes.iter().any(|entry| entry.depth == 0));
    assert!(query
        .nodes
        .iter()
        .any(|entry| entry.node.path.as_deref() == Some("docs/guide.md")));
}

#[test]
fn writes_reads_and_verifies_segments() {
    let index = sample_index();
    let root = std::env::temp_dir().join(format!("treedx-graph-test-{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);

    let manifest = write_graph_segments(&root, &index).expect("segments write");
    let latest =
        read_latest_graph_manifest(&root, "repo_test", "refs/heads/main").expect("latest reads");
    assert_eq!(latest.unwrap().graph_version, manifest.graph_version);

    let reread =
        read_graph_segments(&root, "repo_test", &manifest.graph_version).expect("segments read");
    assert_eq!(reread.nodes.len(), index.nodes.len());

    let nodes_path = root
        .join("graph/repos/repo_test")
        .join(&manifest.graph_version)
        .join("nodes.tdb");
    let mut contents = fs::read_to_string(&nodes_path).unwrap();
    contents = contents.replacen("blake3:", "blake3:bad", 1);
    fs::write(&nodes_path, contents).unwrap();

    let error = read_graph_segments(&root, "repo_test", &manifest.graph_version).unwrap_err();
    assert!(error.to_string().contains("checksum"));
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn repeated_segment_publish_reuses_valid_graph_version() {
    let index = sample_index();
    let root =
        std::env::temp_dir().join(format!("treedx-graph-repeat-test-{}", std::process::id()));
    let _ = fs::remove_dir_all(&root);

    let first = write_graph_segments(&root, &index).expect("initial segments write");
    let second = write_graph_segments(&root, &index).expect("repeat segments write");

    assert_eq!(second.graph_version, first.graph_version);
    let reread =
        read_graph_segments(&root, "repo_test", &first.graph_version).expect("segments read");
    assert_eq!(reread.nodes.len(), index.nodes.len());

    let segment_root = root
        .join("graph/repos/repo_test")
        .join(&first.graph_version);
    let temp_files = fs::read_dir(&segment_root)
        .unwrap()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_name().to_string_lossy().ends_with(".tmp"))
        .count();
    assert_eq!(temp_files, 0);
    let _ = fs::remove_dir_all(&root);
}

#[test]
fn parses_ctx_dsl_subset() {
    let parsed = parse_ctx_dsl(
        "ctx \"release provenance\" for research in /docs via references depth 1 limit 8 budget 1200 as brief",
    );
    assert!(parsed.ok);
    let query = parsed.query.unwrap();
    assert_eq!(query["focus"], "research");
    assert_eq!(query["relations"][0], "references");
    assert_eq!(query["budget"]["maxTokens"], 1200);

    let invalid = parse_ctx_dsl("search release");
    assert!(!invalid.ok);
    assert!(invalid.query.is_none());
}
