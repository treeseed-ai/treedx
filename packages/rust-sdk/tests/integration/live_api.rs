use treedx_sdk::{TreeDxClient, TreeDxConfig};

#[tokio::test]
async fn live_health_is_optional() {
    let Ok(base_url) = std::env::var("TREEDX_BASE_URL") else {
        eprintln!("TreeDX integration not configured: TREEDX_BASE_URL is absent");
        return;
    };

    let client = TreeDxClient::new(TreeDxConfig {
        base_url,
        token: std::env::var("TREEDX_TOKEN").ok(),
        ..Default::default()
    });
    client.health().await.unwrap();
}
