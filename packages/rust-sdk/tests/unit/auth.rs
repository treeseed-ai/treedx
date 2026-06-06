use treedx_sdk::auth::{AuthProvider, resolve_authorization_header};
use treedx_sdk::{StaticBearerTokenAuthProvider, TreeDxConfig};

#[tokio::test]
async fn static_bearer_token_provider_returns_token() {
    let provider = StaticBearerTokenAuthProvider::new("secret");
    assert_eq!(provider.get_token().await.unwrap(), "secret");
}

#[tokio::test]
async fn authorization_header_uses_bearer_scheme() {
    let config = TreeDxConfig {
        token: Some("secret".to_string()),
        ..Default::default()
    };
    assert_eq!(
        resolve_authorization_header(&config).await.unwrap(),
        Some(("Authorization".to_string(), "Bearer secret".to_string()))
    );
}
