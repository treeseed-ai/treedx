from __future__ import annotations

from typing import Any

from .common import json_request, segment
from treedx_sdk.transport import Transport


class ArtifactsAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def export(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/artifacts/export", body)

    def list(self, repo_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/artifacts")

    def get(self, repo_id: str, artifact_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/artifacts/{segment(artifact_id)}")

    def delete(self, repo_id: str, artifact_id: str) -> Any:
        return json_request(self.transport, "DELETE", f"/api/v1/repos/{segment(repo_id)}/artifacts/{segment(artifact_id)}")
