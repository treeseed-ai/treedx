use crate::ids::normalize_id_value;
use regex::Regex;
use serde_json::{Map, Value};

#[derive(Debug, Clone)]
pub struct ParsedDocument {
    pub frontmatter: Value,
    pub body: String,
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
    if !content.starts_with("---\n") {
        return ParsedDocument {
            frontmatter: Value::Object(Map::new()),
            body: content.to_string(),
        };
    }
    let Some(index) = content[4..].find("\n---\n").map(|idx| idx + 4) else {
        return ParsedDocument {
            frontmatter: Value::Object(Map::new()),
            body: content.to_string(),
        };
    };
    let yaml = &content[4..index];
    let body = content[index + 5..].to_string();
    ParsedDocument {
        frontmatter: parse_simple_yaml(yaml),
        body,
    }
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

fn parse_simple_yaml(source: &str) -> Value {
    let mut object = Map::new();
    let mut current_array: Option<String> = None;
    for raw in source.lines() {
        let line = raw.trim_end();
        if line.trim().is_empty() {
            continue;
        }
        if let Some(key) = current_array.clone() {
            if let Some(item) = line.trim_start().strip_prefix("- ") {
                if let Some(Value::Array(values)) = object.get_mut(&key) {
                    values.push(Value::String(unquote(item.trim())));
                }
                continue;
            }
            current_array = None;
        }
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let key = key.trim().to_string();
        let value = value.trim();
        if value.is_empty() {
            object.insert(key.clone(), Value::Array(Vec::new()));
            current_array = Some(key);
        } else if value.eq_ignore_ascii_case("true") || value.eq_ignore_ascii_case("false") {
            object.insert(key, Value::Bool(value.eq_ignore_ascii_case("true")));
        } else if let Ok(number) = value.parse::<i64>() {
            object.insert(key, Value::Number(number.into()));
        } else {
            object.insert(key, Value::String(unquote(value)));
        }
    }
    Value::Object(object)
}

fn unquote(value: &str) -> String {
    value.trim_matches('"').trim_matches('\'').to_string()
}
