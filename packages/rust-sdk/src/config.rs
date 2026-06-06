use std::collections::BTreeMap;
use std::fmt;
use std::sync::Arc;
use std::time::Duration;

use crate::auth::AuthProvider;

#[derive(Clone, Default)]
pub struct TreeDxConfig {
    pub base_url: String,
    pub token: Option<String>,
    pub auth_provider: Option<Arc<dyn AuthProvider>>,
    pub default_headers: BTreeMap<String, String>,
    pub timeout: Option<Duration>,
}

impl fmt::Debug for TreeDxConfig {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("TreeDxConfig")
            .field("base_url", &self.base_url)
            .field("token", &self.token.as_ref().map(|_| "<redacted>"))
            .field(
                "auth_provider",
                &self.auth_provider.as_ref().map(|_| "<provider>"),
            )
            .field("default_headers", &self.default_headers)
            .field("timeout", &self.timeout)
            .finish()
    }
}
