from __future__ import annotations

from dataclasses import dataclass
import os
from typing import Literal

from treedb_sdk.client import TreeDbClient


@dataclass(frozen=True)
class TreeDbConformanceScenario:
    id: str
    capability_id: str
    title: str
    required: bool
    endpoint_refs: list[str]
    steps: list[dict[str, str]]
    assertions: list[str]


@dataclass(frozen=True)
class TreeDbConformanceResult:
    scenario_id: str
    status: Literal["passed", "failed", "not_configured"]
    message: str | None = None


class TreeDbConformanceAdapter:
    def __init__(self, client: TreeDbClient, server_configured: bool = False) -> None:
        self.client = client
        self.server_configured = server_configured

    def run_scenario(self, scenario: TreeDbConformanceScenario) -> TreeDbConformanceResult:
        if not self.server_configured:
            return TreeDbConformanceResult(
                scenario_id=scenario.id,
                status="not_configured",
                message="TreeDB conformance server is not configured.",
            )
        path_params = {
            "repo_id": os.environ.get("TREEDB_CONFORMANCE_REPO_ID", "repo_conformance"),
            "workspace_id": os.environ.get("TREEDB_CONFORMANCE_WORKSPACE_ID", "workspace_conformance"),
            "node_id": os.environ.get("TREEDB_CONFORMANCE_NODE_ID", "node_conformance"),
            "job_id": os.environ.get("TREEDB_CONFORMANCE_JOB_ID", "job_conformance"),
            "snapshot_id": os.environ.get("TREEDB_CONFORMANCE_SNAPSHOT_ID", "snapshot_conformance"),
            "artifact_id": os.environ.get("TREEDB_CONFORMANCE_ARTIFACT_ID", "artifact_conformance"),
            "mirror_id": os.environ.get("TREEDB_CONFORMANCE_MIRROR_ID", "mirror_conformance"),
            "migration_id": os.environ.get("TREEDB_CONFORMANCE_MIGRATION_ID", "migration_conformance"),
            "upload_id": os.environ.get("TREEDB_CONFORMANCE_UPLOAD_ID", "upload_conformance"),
            "part_number": os.environ.get("TREEDB_CONFORMANCE_PART_NUMBER", "1"),
        }
        try:
            for endpoint_ref in scenario.endpoint_refs:
                method, path = endpoint_ref.split(" ", 1)
                self.client.operation(
                    method,
                    path,
                    path_params=path_params,
                    body=None if method in {"GET", "DELETE"} else {"dryRun": True},
                )
            return TreeDbConformanceResult(scenario_id=scenario.id, status="passed")
        except Exception as error:
            return TreeDbConformanceResult(
                scenario_id=scenario.id,
                status="failed",
                message=str(error),
            )
