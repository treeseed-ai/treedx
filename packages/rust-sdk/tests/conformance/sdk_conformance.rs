use std::fs;
use std::path::Path;

use serde::Deserialize;
use treedx_sdk::conformance::{
    TreeDxConformanceAdapter, TreeDxConformanceScenario, TreeDxConformanceStatus,
};
use treedx_sdk::{TreeDxClient, TreeDxConfig};

#[derive(Debug, Deserialize)]
struct ScenarioFile {
    scenarios: Vec<TreeDxConformanceScenario>,
}

fn load_scenarios() -> Vec<TreeDxConformanceScenario> {
    let dir = Path::new("../sdk-spec/conformance/scenarios");
    let mut scenarios = Vec::new();
    for entry in fs::read_dir(dir).unwrap() {
        let entry = entry.unwrap();
        if entry.path().extension().and_then(|value| value.to_str()) != Some("yaml") {
            continue;
        }
        let text = fs::read_to_string(entry.path()).unwrap();
        let file: ScenarioFile = serde_yaml::from_str(&text).unwrap();
        scenarios.extend(file.scenarios);
    }
    scenarios
}

#[tokio::test]
async fn conformance_scenarios_load_and_report_not_configured() {
    let scenarios = load_scenarios();
    assert!(!scenarios.is_empty());
    let client = TreeDxClient::new(TreeDxConfig {
        base_url: "http://localhost:4000".to_string(),
        ..Default::default()
    });
    let adapter = TreeDxConformanceAdapter::new(client);

    for scenario in scenarios {
        assert!(!scenario.id.is_empty());
        assert!(!scenario.capability_id.is_empty());
        let result = adapter.run_scenario(&scenario).await;
        assert_eq!(result.status, TreeDxConformanceStatus::NotConfigured);
    }
}
