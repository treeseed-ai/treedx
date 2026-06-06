use treedx_sdk::transport::{TreeDxHttpMethod, TreeDxRequest};

#[test]
fn request_defaults_are_empty() {
    let request = TreeDxRequest::new(TreeDxHttpMethod::Get, "/api/v1/health");
    assert_eq!(request.method.as_str(), "GET");
    assert_eq!(request.path, "/api/v1/health");
    assert!(request.query.is_empty());
}
