from __future__ import annotations

from typing import Any

from .common import json_request, segment
from treedb_sdk.transport import Transport


class GraphAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def refresh(self, repo_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/graph/refresh", body)

    def query(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/graph/query", body)

    def refresh_job(self, repo_id: str, job_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/graph/refresh-jobs/{segment(job_id)}")

    def node(self, repo_id: str, node_id: str, query: Any | None = None) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/graph/nodes/{segment(node_id)}", query=query)

    def related(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/graph/related", body)

    def subgraph(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/graph/subgraph", body)

    def search_files(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/graph/search-files", body)

    def search_sections(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/graph/search-sections", body)

    def search_entities(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/graph/search-entities", body)
