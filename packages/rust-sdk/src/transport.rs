use std::collections::BTreeMap;

use async_trait::async_trait;
use bytes::Bytes;
use reqwest::header::{CONTENT_TYPE, HeaderMap, HeaderName, HeaderValue};
use serde_json::Value;
use url::Url;

use crate::auth::resolve_authorization_header;
use crate::config::TreeDxConfig;
use crate::error::{TreeDxApiError, TreeDxResult};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TreeDxHttpMethod {
    Get,
    Post,
    Put,
    Patch,
    Delete,
}

impl TreeDxHttpMethod {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Get => "GET",
            Self::Post => "POST",
            Self::Put => "PUT",
            Self::Patch => "PATCH",
            Self::Delete => "DELETE",
        }
    }
}

#[derive(Clone, Debug)]
pub struct TreeDxRequest {
    pub method: TreeDxHttpMethod,
    pub path: String,
    pub query: BTreeMap<String, String>,
    pub headers: BTreeMap<String, String>,
    pub body: Option<Value>,
    pub binary_body: Option<Bytes>,
}

impl TreeDxRequest {
    pub fn new(method: TreeDxHttpMethod, path: impl Into<String>) -> Self {
        Self {
            method,
            path: path.into(),
            query: BTreeMap::new(),
            headers: BTreeMap::new(),
            body: None,
            binary_body: None,
        }
    }
}

#[derive(Clone, Debug)]
pub struct TreeDxResponse<T = Value> {
    pub status: u16,
    pub headers: BTreeMap<String, String>,
    pub data: T,
}

#[async_trait]
pub trait Transport: Send + Sync {
    async fn request(&self, request: TreeDxRequest) -> TreeDxResult<TreeDxResponse>;
}

#[derive(Clone, Debug)]
pub struct ReqwestTransport {
    config: TreeDxConfig,
    client: reqwest::Client,
}

impl ReqwestTransport {
    pub fn new(config: TreeDxConfig) -> Self {
        let mut builder = reqwest::Client::builder();
        if let Some(timeout) = config.timeout {
            builder = builder.timeout(timeout);
        }
        let client = builder.build().unwrap_or_else(|_| reqwest::Client::new());
        Self { config, client }
    }

    fn url_for(&self, request: &TreeDxRequest) -> TreeDxResult<Url> {
        let base = self.config.base_url.trim_end_matches('/');
        let path = if request.path.starts_with('/') {
            request.path.clone()
        } else {
            format!("/{}", request.path)
        };
        let mut url = Url::parse(&format!("{base}{path}"))
            .map_err(|error| TreeDxApiError::network(format!("invalid TreeDX URL: {error}")))?;
        if !request.query.is_empty() {
            let mut pairs = url.query_pairs_mut();
            for (key, value) in &request.query {
                pairs.append_pair(key, value);
            }
        }
        Ok(url)
    }

    fn headers_from(&self, request: &TreeDxRequest) -> TreeDxResult<HeaderMap> {
        let mut headers = HeaderMap::new();
        for (key, value) in self
            .config
            .default_headers
            .iter()
            .chain(request.headers.iter())
        {
            let name = HeaderName::from_bytes(key.as_bytes()).map_err(|error| {
                TreeDxApiError::network(format!("invalid header name: {error}"))
            })?;
            let value = HeaderValue::from_str(value).map_err(|error| {
                TreeDxApiError::network(format!("invalid header value: {error}"))
            })?;
            headers.insert(name, value);
        }
        Ok(headers)
    }
}

#[async_trait]
impl Transport for ReqwestTransport {
    async fn request(&self, request: TreeDxRequest) -> TreeDxResult<TreeDxResponse> {
        let url = self.url_for(&request)?;
        let method = match request.method {
            TreeDxHttpMethod::Get => reqwest::Method::GET,
            TreeDxHttpMethod::Post => reqwest::Method::POST,
            TreeDxHttpMethod::Put => reqwest::Method::PUT,
            TreeDxHttpMethod::Patch => reqwest::Method::PATCH,
            TreeDxHttpMethod::Delete => reqwest::Method::DELETE,
        };
        let mut builder = self
            .client
            .request(method, url)
            .headers(self.headers_from(&request)?);

        if let Some((name, value)) = resolve_authorization_header(&self.config).await? {
            builder = builder.header(name, value);
        }
        if let Some(binary_body) = request.binary_body {
            builder = builder.body(binary_body);
        } else if let Some(body) = request.body {
            builder = builder.json(&body);
        }

        let response = builder
            .send()
            .await
            .map_err(|error| TreeDxApiError::network(error.to_string()))?;
        let status = response.status().as_u16();
        let headers = response
            .headers()
            .iter()
            .filter_map(|(key, value)| {
                value
                    .to_str()
                    .ok()
                    .map(|value| (key.to_string(), value.to_string()))
            })
            .collect::<BTreeMap<_, _>>();
        let content_type = response
            .headers()
            .get(CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .unwrap_or("")
            .to_string();

        let data = if content_type.contains("application/json") {
            response
                .json::<Value>()
                .await
                .map_err(|error| TreeDxApiError::network(error.to_string()))?
        } else if content_type.starts_with("text/") {
            Value::String(
                response
                    .text()
                    .await
                    .map_err(|error| TreeDxApiError::network(error.to_string()))?,
            )
        } else {
            let _ = response
                .bytes()
                .await
                .map_err(|error| TreeDxApiError::network(error.to_string()))?;
            Value::Null
        };

        if !(200..300).contains(&status) {
            return Err(TreeDxApiError::from_response(status, data));
        }

        Ok(TreeDxResponse {
            status,
            headers,
            data,
        })
    }
}

#[cfg(test)]
mod url_contract {
    use super::*;

    #[test]
    fn empty_query_preserves_the_exact_endpoint() {
        let transport = ReqwestTransport::new(TreeDxConfig {
            base_url: "http://127.0.0.1:4000".to_string(),
            ..Default::default()
        });
        let request = TreeDxRequest::new(TreeDxHttpMethod::Get, "/api/v1/health");
        assert_eq!(
            transport.url_for(&request).unwrap().as_str(),
            "http://127.0.0.1:4000/api/v1/health"
        );
    }

    #[test]
    fn query_values_preserve_order_and_encoding() {
        let transport = ReqwestTransport::new(TreeDxConfig {
            base_url: "http://127.0.0.1:4000/".to_string(),
            ..Default::default()
        });
        let mut request = TreeDxRequest::new(TreeDxHttpMethod::Get, "api/v1/health");
        request.query.insert("a".to_string(), "a+b c&d".to_string());
        request.query.insert("z".to_string(), "1".to_string());
        assert_eq!(
            transport.url_for(&request).unwrap().as_str(),
            "http://127.0.0.1:4000/api/v1/health?a=a%2Bb+c%26d&z=1"
        );
    }

    #[test]
    fn invalid_base_remains_a_network_error() {
        let transport = ReqwestTransport::new(TreeDxConfig {
            base_url: "invalid".to_string(),
            ..Default::default()
        });
        let request = TreeDxRequest::new(TreeDxHttpMethod::Get, "/api/v1/health");
        let error = transport.url_for(&request).unwrap_err();
        assert_eq!(error.status, 0);
        assert_eq!(error.code, "network_error");
    }
}
