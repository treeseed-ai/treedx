use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DslParseResult {
    pub ok: bool,
    pub query: Option<Value>,
    pub errors: Vec<String>,
}

pub fn parse_ctx_dsl(source: &str) -> DslParseResult {
    let tokens = tokenize(source);
    if tokens.is_empty() {
        return error("ctx query is empty.");
    }
    if tokens[0] != "ctx" {
        return error("ctx query must start with the `ctx` command.");
    }
    let Some(first_clause) = tokens
        .iter()
        .enumerate()
        .skip(1)
        .find(|(_, token)| clause(token))
        .map(|(idx, _)| idx)
    else {
        return build(&tokens[1..], &[]);
    };
    build(&tokens[1..first_clause], &tokens[first_clause..])
}

fn build(target: &[String], clauses: &[String]) -> DslParseResult {
    if target.is_empty() {
        return error("ctx query must include a target.");
    }
    let mut query = json!({
        "focus": "plan",
        "relations": ["related", "references"],
        "view": "brief",
        "options": {"depth": 1, "limit": 8, "maxNodes": 8},
        "seeds": [seed(&target.join(" "))]
    });
    let mut errors = Vec::new();
    let mut index = 0;
    while index < clauses.len() {
        let key = &clauses[index];
        let next = clauses[index + 1..]
            .iter()
            .position(|token| clause(token))
            .map(|pos| index + 1 + pos)
            .unwrap_or(clauses.len());
        let value = clauses[index + 1..next].join(" ");
        if value.is_empty() {
            errors.push(format!("Clause \"{key}\" requires a value."));
            index = next;
            continue;
        }
        match key.as_str() {
            "for" => query["focus"] = json!(value),
            "in" => {
                query["scopePaths"] = json!(value
                    .split('+')
                    .map(|part| part.trim())
                    .filter(|part| !part.is_empty())
                    .collect::<Vec<_>>())
            }
            "via" => {
                query["relations"] = json!(value
                    .split(',')
                    .map(|part| part.trim())
                    .filter(|part| !part.is_empty())
                    .collect::<Vec<_>>())
            }
            "depth" => set_option(&mut query, "depth", &value),
            "limit" => {
                set_option(&mut query, "limit", &value);
                set_option(&mut query, "maxNodes", &value);
                query["budget"]["maxNodes"] = json!(value.parse::<u32>().unwrap_or(8));
            }
            "budget" => query["budget"]["maxTokens"] = json!(value.parse::<u32>().unwrap_or(1800)),
            "as" => query["view"] = json!(value),
            "where" => query["where"] = parse_where(&value),
            _ => errors.push(format!("Unknown clause \"{key}\".")),
        }
        index = next;
    }
    DslParseResult {
        ok: errors.is_empty(),
        query: errors.is_empty().then_some(query),
        errors,
    }
}

fn seed(value: &str) -> Value {
    if let Some(value) = value.strip_prefix('@') {
        json!({"id": "seed:0", "kind": "id", "value": value})
    } else if value.starts_with('/') {
        json!({"id": "seed:0", "kind": "path", "value": value})
    } else if let Some(value) = value.strip_prefix('#') {
        json!({"id": "seed:0", "kind": "tag", "value": value})
    } else if let Some(value) = value.strip_prefix('%') {
        json!({"id": "seed:0", "kind": "type", "value": value})
    } else {
        json!({"id": "seed:0", "kind": "query", "value": value})
    }
}

fn parse_where(value: &str) -> Value {
    if let Some((field, expected)) = value.split_once('=') {
        json!([{"field": field.trim(), "op": "eq", "value": expected.trim()}])
    } else {
        json!([])
    }
}

fn set_option(query: &mut Value, key: &str, value: &str) {
    query["options"][key] = json!(value.parse::<u32>().unwrap_or(1));
}

fn clause(token: &str) -> bool {
    matches!(
        token,
        "for" | "in" | "via" | "depth" | "where" | "limit" | "budget" | "as"
    )
}

fn tokenize(source: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut quote = None;
    for ch in source.trim().chars() {
        if let Some(q) = quote {
            if ch == q {
                tokens.push(current.clone());
                current.clear();
                quote = None;
            } else {
                current.push(ch);
            }
        } else if ch == '"' || ch == '\'' {
            if !current.trim().is_empty() {
                tokens.push(current.trim().to_string());
                current.clear();
            }
            quote = Some(ch);
        } else if ch.is_whitespace() {
            if !current.trim().is_empty() {
                tokens.push(current.trim().to_string());
                current.clear();
            }
        } else {
            current.push(ch);
        }
    }
    if !current.trim().is_empty() {
        tokens.push(current.trim().to_string());
    }
    tokens
}

fn error(message: &str) -> DslParseResult {
    DslParseResult {
        ok: false,
        query: None,
        errors: vec![message.to_string()],
    }
}
