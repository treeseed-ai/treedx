from __future__ import annotations

from typing import Any

from ..common import json_request, segment
from treedx.transport import Transport


class FederationAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def plan(self, body: Any) -> Any:
        return json_request(self.transport, "POST", "/api/v1/federation/query/plan", body)

    def search(self, body: Any) -> Any:
        return json_request(self.transport, "POST", "/api/v1/search", body)

    def query(self, body: Any) -> Any:
        return json_request(self.transport, "POST", "/api/v1/query", body)

    def context_build(self, body: Any) -> Any:
        return json_request(self.transport, "POST", "/api/v1/context/build", body)

    def graph_query(self, body: Any) -> Any:
        return json_request(self.transport, "POST", "/api/v1/graph/query", body)

    def catalog(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/federation/catalog")

    def push_catalog(self, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", "/api/v1/federation/catalog/push", body)

    def sync_catalog(self, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", "/api/v1/federation/catalog/sync", body)

    def peers(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/federation/peers")

    def peer(self, node_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/federation/peers/{segment(node_id)}")

    def register_node(self, body: Any) -> Any:
        return json_request(self.transport, "POST", "/api/v1/federation/nodes/register", body)

    def trust_peer(self, node_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/federation/peers/{segment(node_id)}/trust", body)

    def revoke_peer(self, node_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/federation/peers/{segment(node_id)}/revoke", body)

    def routes(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/federation/routes")
