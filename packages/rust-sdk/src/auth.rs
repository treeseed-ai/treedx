use std::sync::Arc;

use async_trait::async_trait;

use crate::config::TreeDxConfig;
use crate::error::TreeDxResult;

#[async_trait]
pub trait AuthProvider: Send + Sync {
    async fn get_token(&self) -> TreeDxResult<String>;
}

#[derive(Clone, Debug)]
pub struct StaticBearerTokenAuthProvider {
    token: String,
}

impl StaticBearerTokenAuthProvider {
    pub fn new(token: impl Into<String>) -> Self {
        Self {
            token: token.into(),
        }
    }
}

#[async_trait]
impl AuthProvider for StaticBearerTokenAuthProvider {
    async fn get_token(&self) -> TreeDxResult<String> {
        Ok(self.token.clone())
    }
}

pub fn create_auth_provider(token: Option<String>) -> Option<Arc<dyn AuthProvider>> {
    token.map(|token| Arc::new(StaticBearerTokenAuthProvider::new(token)) as Arc<dyn AuthProvider>)
}

pub async fn resolve_authorization_header(
    config: &TreeDxConfig,
) -> TreeDxResult<Option<(String, String)>> {
    let provider = match &config.auth_provider {
        Some(provider) => Some(provider.clone()),
        None => create_auth_provider(config.token.clone()),
    };

    match provider {
        Some(provider) => Ok(Some((
            "Authorization".to_string(),
            format!("Bearer {}", provider.get_token().await?),
        ))),
        None => Ok(None),
    }
}
