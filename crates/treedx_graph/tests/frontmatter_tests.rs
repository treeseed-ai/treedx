use serde_json::json;
use treedx_graph::parse::parse_document;
use treedx_graph::{build_graph_index, GraphDocumentInput, GraphIndexInput};

#[test]
fn parses_structured_yaml_frontmatter() {
    let parsed = parse_document("\u{feff}---\r\ntitle: Guide\r\ntags: [security, teams]\r\ncover:\r\n  image: /guide.png\r\nrelations:\r\n  - id: page.child\r\n    weight: 2\r\nsummary: >-\r\n  A connected\r\n  guide.\r\n---\r\n# Guide\r\n");

    assert_eq!(parsed.frontmatter["tags"], json!(["security", "teams"]));
    assert_eq!(parsed.frontmatter["cover"]["image"], "/guide.png");
    assert_eq!(parsed.frontmatter["relations"][0]["weight"], 2);
    assert_eq!(parsed.frontmatter["summary"], "A connected guide.");
    assert_eq!(parsed.body, "# Guide\r\n");
    assert_eq!(parsed.frontmatter_error, None);
}

#[test]
fn reports_invalid_and_unterminated_frontmatter() {
    let invalid = parse_document("---\ntags: [broken\n---\nBody");
    assert!(invalid.frontmatter.as_object().unwrap().is_empty());
    assert!(invalid
        .frontmatter_error
        .as_deref()
        .unwrap()
        .contains("Invalid YAML"));
    assert_eq!(invalid.body, "---\ntags: [broken\n---\nBody");

    let unterminated = parse_document("---\ntitle: Missing close\nBody");
    assert!(unterminated.frontmatter_error.is_some());
}

#[test]
fn graph_preserves_frontmatter_and_reports_invalid_paths() {
    let index = build_graph_index(GraphIndexInput {
        repo_id: "repo".to_string(), ref_name: "main".to_string(), commit_sha: "abc".to_string(),
        graph_version: None, previous_manifest: None, previous_documents: vec![],
        documents: vec![
            GraphDocumentInput { path: "guide.md".to_string(), object_id: "one".to_string(), size: 1,
                content: "---\ntitle: Guide\nrelatedKnowledgeIds: [page.child]\ncontext:\n  nested: true\n---\n# Guide\n".to_string() },
            GraphDocumentInput { path: "broken.md".to_string(), object_id: "two".to_string(), size: 1,
                content: "---\ntags: [broken\n---\nBody".to_string() },
        ],
    }).unwrap();

    let guide = index
        .documents
        .iter()
        .find(|document| document.path == "guide.md")
        .unwrap();
    assert_eq!(
        guide.frontmatter["relatedKnowledgeIds"],
        json!(["page.child"])
    );
    assert_eq!(guide.frontmatter["context"]["nested"], true);
    assert_eq!(
        index.diagnostics.invalid_frontmatter_paths,
        vec!["broken.md"]
    );
}
