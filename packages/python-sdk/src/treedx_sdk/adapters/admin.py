from __future__ import annotations

from typing import Any

from .common import json_request
from treedx_sdk.transport import Transport


class AdminAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def deep_health(self) -> Any: return json_request(self.transport, "GET", "/api/v1/admin/health/deep")
    def storage_health(self) -> Any: return json_request(self.transport, "GET", "/api/v1/admin/storage/health")
    def storage_check(self, body: Any | None = None) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/storage/check", body)
    def storage_recover(self, body: Any | None = None) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/storage/recover", body)
    def storage_compact(self, body: Any | None = None) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/storage/compact", body)
    def storage_backup(self, body: Any | None = None) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/storage/backup", body)
    def storage_migrations(self) -> Any: return json_request(self.transport, "GET", "/api/v1/admin/storage/migrations")
    def storage_migration_plan(self, body: Any) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/storage/migrations/plan", body)
    def storage_migration_apply(self, body: Any) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/storage/migrations/apply", body)
    def storage_migration_rollback(self, body: Any) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/storage/migrations/rollback", body)
    def storage_restore_verify(self, body: Any) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/storage/restore/verify", body)
    def storage_restore(self, body: Any) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/storage/restore", body)
    def quarantined_workspaces(self) -> Any: return json_request(self.transport, "GET", "/api/v1/admin/workspaces/quarantined")
    def cleanup_artifacts(self, body: Any | None = None) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/artifacts/cleanup", body)
    def import_local_repo(self, body: Any) -> Any: return json_request(self.transport, "POST", "/api/v1/admin/repos/import-local", body)
