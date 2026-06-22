use std::collections::BTreeSet;
use std::process::Command;

use treedx::generated::openapi_types::TREEDX_OPENAPI_OPERATIONS;

fn endpoint_strings_from_sdk_spec() -> BTreeSet<String> {
    let text = std::fs::read_to_string("../sdk-spec/spec/endpoints.yaml").unwrap();
    text.lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            if trimmed.starts_with("- ") && trimmed.contains("/api/v1/") {
                Some(trimmed.trim_start_matches("- ").to_string())
            } else {
                None
            }
        })
        .collect()
}

#[test]
fn generated_openapi_metadata_is_fresh() {
    let output = Command::new("node")
        .arg("scripts/check_treedx_generated_types.ts")
        .output()
        .expect("run generated metadata freshness check");
    assert!(
        output.status.success(),
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn generated_operations_include_declared_sdk_spec_endpoints() {
    let generated = TREEDX_OPENAPI_OPERATIONS
        .iter()
        .map(|operation| format!("{} {}", operation.method, operation.path))
        .collect::<BTreeSet<_>>();
    for endpoint in endpoint_strings_from_sdk_spec() {
        assert!(
            generated.contains(&endpoint),
            "missing generated endpoint {endpoint}"
        );
    }
}
