use serde_json::json;
use treedx_sdk::TreeDxApiError;

#[test]
fn response_error_preserves_payload_fields() {
    let payload = json!({ "error": { "code": "invalid_token", "message": "bad token", "details": { "why": "expired" } } });
    let error = TreeDxApiError::from_response(401, payload.clone());
    assert_eq!(error.status, 401);
    assert_eq!(error.code, "invalid_token");
    assert_eq!(error.message, "bad token");
    assert_eq!(error.details, Some(json!({ "why": "expired" })));
    assert_eq!(error.payload, Some(payload));
}

#[test]
fn network_error_uses_stable_contract() {
    let error = TreeDxApiError::network("offline");
    assert_eq!(error.status, 0);
    assert_eq!(error.code, "network_error");
}
