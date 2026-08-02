use crate::ids::normalize_id_value;
use regex::Regex;
use serde_json::{Map, Value};

#[derive(Debug, Clone)]
pub struct ParsedDocument {
    pub frontmatter: Value,
    pub body: String,
    pub frontmatter_error: Option<String>,
}

#[derive(Debug, Clone)]
pub struct Heading {
    pub text: String,
    pub slug: String,
    pub level: u32,
    pub start: usize,
    pub end: usize,
}

#[derive(Debug, Clone)]
pub struct Link {
    pub target: String,
    pub label: String,
    pub start: usize,
}

pub fn parse_document(content: &str) -> ParsedDocument {
    let source = content.strip_prefix('\u{feff}').unwrap_or(content);
    let opening_length = if source.starts_with("---\r\n") {
        5
    } else if source.starts_with("---\n") {
        4
    } else {
        return ParsedDocument {
            frontmatter: Value::Object(Map::new()),
            body: content.to_string(),
            frontmatter_error: None,
        };
    };
    let remainder = &source[opening_length..];
    let Some((yaml_end, body_start)) = frontmatter_boundary(remainder) else {
        return ParsedDocument {
            frontmatter: Value::Object(Map::new()),
            body: content.to_string(),
            frontmatter_error: Some(
                "Frontmatter opening delimiter has no closing delimiter.".to_string(),
            ),
        };
    };
    let yaml = &remainder[..yaml_end];
    match parse_yaml(yaml) {
        Ok(frontmatter) => ParsedDocument {
            frontmatter,
            body: remainder[body_start..].to_string(),
            frontmatter_error: None,
        },
        Err(error) => ParsedDocument {
            frontmatter: Value::Object(Map::new()),
            body: content.to_string(),
            frontmatter_error: Some(error),
        },
    }
}

fn frontmatter_boundary(source: &str) -> Option<(usize, usize)> {
    let mut offset = 0usize;
    for line in source.split_inclusive('\n') {
        let value = line.trim_end_matches(['\r', '\n']);
        if value == "---" {
            return Some((offset, offset + line.len()));
        }
        offset += line.len();
    }
    (source[offset..].trim_end_matches('\r') == "---").then_some((offset, source.len()))
}

fn parse_yaml(source: &str) -> Result<Value, String> {
    let yaml = serde_yaml::from_str::<serde_yaml::Value>(source)
        .map_err(|error| format!("Invalid YAML frontmatter: {error}"))?;
    if yaml.is_null() {
        return Ok(Value::Object(Map::new()));
    }
    if !yaml.is_mapping() {
        return Err("YAML frontmatter must contain a top-level mapping.".to_string());
    }
    serde_json::to_value(yaml)
        .map_err(|error| format!("YAML frontmatter is not JSON-compatible: {error}"))
}

pub fn extract_headings(body: &str) -> Vec<Heading> {
    let mut headings = Vec::new();
    let mut offset = 0usize;
    let heading_regex = Regex::new(r"^(#{1,6})\s+(.+)$").unwrap();
    for line in body.split_inclusive('\n') {
        let trimmed = line.trim_end_matches('\n');
        if let Some(captures) = heading_regex.captures(trimmed) {
            let text = captures.get(2).unwrap().as_str().trim().to_string();
            headings.push(Heading {
                slug: normalize_id_value(&text),
                text,
                level: captures.get(1).unwrap().as_str().len() as u32,
                start: offset,
                end: offset + trimmed.len(),
            });
        }
        offset += line.len();
    }
    headings
}

pub fn extract_links(body: &str) -> Vec<Link> {
    let mut links = Vec::new();
    let markdown = Regex::new(r"\[([^\]]+)\]\(([^)]+)\)").unwrap();
    for captures in markdown.captures_iter(body) {
        links.push(Link {
            label: captures.get(1).unwrap().as_str().to_string(),
            target: captures.get(2).unwrap().as_str().to_string(),
            start: captures.get(0).unwrap().start(),
        });
    }
    let mdx = Regex::new(r#"(?:import|export)\s+(?:[^'"]+?\s+from\s+)?['"]([^'"]+)['"]"#).unwrap();
    for captures in mdx.captures_iter(body) {
        links.push(Link {
            label: "import".to_string(),
            target: captures.get(1).unwrap().as_str().to_string(),
            start: captures.get(0).unwrap().start(),
        });
    }
    links
}

pub fn section_ranges(body: &str, headings: &[Heading]) -> Vec<(usize, usize)> {
    if headings.is_empty() {
        return if body.trim().is_empty() {
            Vec::new()
        } else {
            vec![(0, body.len())]
        };
    }
    headings
        .iter()
        .enumerate()
        .map(|(index, heading)| {
            let end = headings[index + 1..]
                .iter()
                .find(|candidate| candidate.level <= heading.level)
                .map(|candidate| candidate.start)
                .unwrap_or(body.len());
            (heading.start, end)
        })
        .collect()
}

pub fn string_field(frontmatter: &Value, keys: &[&str]) -> Option<String> {
    let object = frontmatter.as_object()?;
    keys.iter()
        .find_map(|key| {
            object
                .get(*key)
                .and_then(|value| value.as_str())
                .map(|value| value.trim().to_string())
        })
        .filter(|value| !value.is_empty())
}

pub fn string_array(frontmatter: &Value, key: &str) -> Vec<String> {
    let Some(value) = frontmatter.as_object().and_then(|object| object.get(key)) else {
        return Vec::new();
    };
    match value {
        Value::Array(entries) => entries
            .iter()
            .filter_map(|entry| entry.as_str().map(|value| value.trim().to_string()))
            .filter(|value| !value.is_empty())
            .collect(),
        Value::String(value) if !value.trim().is_empty() => vec![value.trim().to_string()],
        _ => Vec::new(),
    }
}
