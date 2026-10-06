from __future__ import annotations

from typing import Any, Mapping

from ..common import binary_request, json_request, segment
from treedx.binary import BinaryBody
from treedx.transport import Transport


class BlobsAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def read(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/blobs/read", body)

    def write(self, workspace_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/workspaces/{segment(workspace_id)}/blobs/write", body)

    def delete(self, workspace_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/workspaces/{segment(workspace_id)}/blobs/delete", body)

    def download(self, workspace_id: str, query: Mapping[str, str | int | float | bool | None] | None = None) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/workspaces/{segment(workspace_id)}/blobs/download", query=query)

    def upload(self, workspace_id: str, binary_body: BinaryBody, query: Mapping[str, str | int | float | bool | None] | None = None) -> Any:
        return binary_request(self.transport, "PUT", f"/api/v1/workspaces/{segment(workspace_id)}/blobs/upload", binary_body, query)

    def create_multipart_upload(self, workspace_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/workspaces/{segment(workspace_id)}/blobs/uploads", body)

    def upload_part(self, workspace_id: str, upload_id: str, part_number: int, binary_body: BinaryBody) -> Any:
        return binary_request(self.transport, "PUT", f"/api/v1/workspaces/{segment(workspace_id)}/blobs/uploads/{segment(upload_id)}/parts/{part_number}", binary_body)

    def complete_multipart_upload(self, workspace_id: str, upload_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/workspaces/{segment(workspace_id)}/blobs/uploads/{segment(upload_id)}/complete", body)

    def abort_multipart_upload(self, workspace_id: str, upload_id: str) -> Any:
        return json_request(self.transport, "DELETE", f"/api/v1/workspaces/{segment(workspace_id)}/blobs/uploads/{segment(upload_id)}")
