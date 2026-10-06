use std::sync::Arc;

use async_trait::async_trait;
use treedx::auth::{AuthProvider, StaticBearerTokenAuthProvider};
use treedx::error::{TreeDxApiError, TreeDxResult};

#[async_trait]
trait Completion: Send + Sync {
    async fn complete(&self) -> usize {
        17
    }
}

struct DefaultCompletion;
#[async_trait]
impl Completion for DefaultCompletion {}

#[async_trait]
impl AuthProvider for DefaultCompletion {
    async fn get_token(&self) -> TreeDxResult<String> {
        Err(TreeDxApiError::network("provider refused"))
    }
}

fn require_send<T: Send>(value: T) -> T {
    value
}

#[tokio::test]
async fn default_trait_future_remains_object_safe_and_send() {
    let provider: Arc<dyn Completion> = Arc::new(DefaultCompletion);
    assert_eq!(require_send(provider.complete()).await, 17);
}

#[tokio::test]
async fn boxed_auth_provider_preserves_success_and_error() {
    let provider: Arc<dyn AuthProvider> = Arc::new(StaticBearerTokenAuthProvider::new("fixture"));
    assert_eq!(require_send(provider.get_token()).await.unwrap(), "fixture");
    let denied: Arc<dyn AuthProvider> = Arc::new(DefaultCompletion);
    let error = require_send(denied.get_token()).await.unwrap_err();
    assert_eq!(error.code, "network_error");
    assert_eq!(error.message, "provider refused");
}
