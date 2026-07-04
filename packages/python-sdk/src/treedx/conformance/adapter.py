from __future__ import annotations

from dataclasses import dataclass
import os
from typing import Literal

from treedx.client import TreeDxClient


@dataclass(frozen=True)
class TreeDxConformanceScenario:
    id: str
    capability_id: str
    title: str
    required: bool
    endpoint_refs: list[str]
    steps: list[dict[str, str]]
    assertions: list[str]


@dataclass(frozen=True)
class TreeDxConformanceResult:
    scenario_id: str
    status: Literal["passed", "failed", "not_configured"]
    message: str | None = None


class TreeDxConformanceAdapter:
    def __init__(self, client: TreeDxClient, server_configured: bool = False) -> None:
        self.client = client
        self.server_configured = server_configured

    def run_scenario(self, scenario: TreeDxConformanceScenario) -> TreeDxConformanceResult:
        if not self.server_configured:
            return TreeDxConformanceResult(
                scenario_id=scenario.id,
                status="not_configured",
                message="TreeDX conformance server is not configured.",
            )
        path_params = {
            "repo_id": os.environ.get("TREEDX_CONFORMANCE_REPO_ID", "repo_conformance"),
            "workspace_id": os.environ.get("TREEDX_CONFORMANCE_WORKSPACE_ID", "workspace_conformance"),
            "node_id": os.environ.get("TREEDX_CONFORMANCE_NODE_ID", "node_conformance"),
            "job_id": os.environ.get("TREEDX_CONFORMANCE_JOB_ID", "job_conformance"),
            "snapshot_id": os.environ.get("TREEDX_CONFORMANCE_SNAPSHOT_ID", "snapshot_conformance"),
            "artifact_id": os.environ.get("TREEDX_CONFORMANCE_ARTIFACT_ID", "artifact_conformance"),
            "mirror_id": os.environ.get("TREEDX_CONFORMANCE_MIRROR_ID", "mirror_conformance"),
            "migration_id": os.environ.get("TREEDX_CONFORMANCE_MIGRATION_ID", "migration_conformance"),
            "upload_id": os.environ.get("TREEDX_CONFORMANCE_UPLOAD_ID", "upload_conformance"),
            "part_number": os.environ.get("TREEDX_CONFORMANCE_PART_NUMBER", "1"),
        }
        try:
            for endpoint_ref in scenario.endpoint_refs:
                method, path = endpoint_ref.split(" ", 1)
                self.client.operation(
                    method,
                    path,
                    path_params=path_params,
                    body=None if method in {"GET", "DELETE"} else {"planOnly": True},
                )
            return TreeDxConformanceResult(scenario_id=scenario.id, status="passed")
        except Exception as error:
            return TreeDxConformanceResult(
                scenario_id=scenario.id,
                status="failed",
                message=str(error),
            )
