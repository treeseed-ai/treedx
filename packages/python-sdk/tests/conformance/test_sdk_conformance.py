from pathlib import Path

import yaml

from treedx_sdk import TreeDxClient
from treedx_sdk.conformance import TreeDxConformanceAdapter, TreeDxConformanceScenario
from treedx_sdk.transport import TreeDxRequest, TreeDxResponse


class MockTransport:
    def request(self, request: TreeDxRequest) -> TreeDxResponse[object]:
        return TreeDxResponse(status=200, headers={}, data={"ok": True})


def load_scenarios() -> list[dict[str, object]]:
    root = Path(__file__).resolve().parents[3]
    scenarios: list[dict[str, object]] = []
    for path in sorted((root / "sdk-spec" / "conformance" / "scenarios").glob("*.yaml")):
        data = yaml.safe_load(path.read_text(encoding="utf8"))
        scenarios.extend(data.get("scenarios") or [])
    return scenarios


def test_scenario_catalog_loads() -> None:
    scenarios = load_scenarios()
    assert scenarios
    assert all(scenario.get("id") for scenario in scenarios)
    assert all(scenario.get("capabilityId") for scenario in scenarios)


def test_conformance_adapter_reports_not_configured() -> None:
    raw = load_scenarios()[0]
    scenario = TreeDxConformanceScenario(
        id=str(raw["id"]),
        capability_id=str(raw["capabilityId"]),
        title=str(raw["title"]),
        required=bool(raw["required"]),
        endpoint_refs=list(raw["endpointRefs"]),  # type: ignore[arg-type]
        steps=list(raw["steps"]),  # type: ignore[arg-type]
        assertions=list(raw["assertions"]),  # type: ignore[arg-type]
    )
    client = TreeDxClient(base_url="http://treedx.test", transport=MockTransport())
    result = TreeDxConformanceAdapter(client).run_scenario(scenario)
    assert result.status == "not_configured"
