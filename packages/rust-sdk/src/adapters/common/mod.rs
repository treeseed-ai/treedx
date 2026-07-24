use std::collections::BTreeMap;
use std::sync::Arc;

use bytes::Bytes;
use serde_json::Value;
use url::form_urlencoded::byte_serialize;

use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod, TreeDxRequest};

pub fn segment(value: &str) -> String {
    byte_serialize(value.as_bytes()).collect()
}

pub async fn json_request(
    transport: &Arc<dyn Transport>,
    method: TreeDxHttpMethod,
    path: impl Into<String>,
    body: Option<Value>,
    query: Option<BTreeMap<String, String>>,
) -> TreeDxResult<Value> {
    let mut request = TreeDxRequest::new(method, path);
    request.body = body;
    request.query = query.unwrap_or_default();
    Ok(transport.request(request).await?.data)
}

pub async fn binary_request(
    transport: &Arc<dyn Transport>,
    method: TreeDxHttpMethod,
    path: impl Into<String>,
    body: Bytes,
    query: Option<BTreeMap<String, String>>,
) -> TreeDxResult<Value> {
    let mut request = TreeDxRequest::new(method, path);
    request.binary_body = Some(body);
    request.query = query.unwrap_or_default();
    Ok(transport.request(request).await?.data)
}
