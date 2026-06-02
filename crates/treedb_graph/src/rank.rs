use crate::types::*;

pub const PROVIDER_ID: &str = "treedb-graph-mvp";

pub fn lexical_score(node: &GraphNode, query: &str) -> f64 {
    let terms = tokenize(query);
    if terms.is_empty() {
        return 0.0;
    }
    terms.iter().map(|term| score_term(node, term)).sum()
}

pub fn tokenize(value: &str) -> Vec<String> {
    value
        .to_lowercase()
        .split(|ch: char| !ch.is_ascii_alphanumeric())
        .filter(|part| !part.is_empty())
        .map(ToString::to_string)
        .collect()
}

fn score_term(node: &GraphNode, term: &str) -> f64 {
    let mut score = 0.0;
    if contains(node.title.as_deref(), term) {
        score += 5.0;
    }
    if contains(node.heading.as_deref(), term) {
        score += 4.0;
    }
    if contains(node.path.as_deref(), term) {
        score += 3.0;
    }
    if node
        .tags
        .iter()
        .any(|tag| tag.to_lowercase().contains(term))
    {
        score += 4.0;
    }
    if let Some(text) = &node.text {
        score += text.to_lowercase().matches(term).count() as f64;
    }
    score
}

fn contains(value: Option<&str>, term: &str) -> bool {
    value
        .map(|value| value.to_lowercase().contains(term))
        .unwrap_or(false)
}
