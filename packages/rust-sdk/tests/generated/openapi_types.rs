use treedx_sdk::generated::openapi_types::{
    TREEDX_OPENAPI_OPERATION_COUNT, TREEDX_OPENAPI_OPERATIONS,
};

#[test]
fn generated_operation_count_matches_openapi_baseline() {
    assert_eq!(TREEDX_OPENAPI_OPERATION_COUNT, 113);
    assert_eq!(TREEDX_OPENAPI_OPERATIONS.len(), 113);
}
