# Blob And Artifact Lifecycle

Blob APIs support binary-safe JSON transport, raw byte transport, resumable
multipart upload sessions, and artifact lifecycle metadata.

Multipart upload endpoints:

- `POST /api/v1/workspaces/:workspace_id/blobs/uploads`
- `PUT /api/v1/workspaces/:workspace_id/blobs/uploads/:upload_id/parts/:part_number`
- `POST /api/v1/workspaces/:workspace_id/blobs/uploads/:upload_id/complete`
- `DELETE /api/v1/workspaces/:workspace_id/blobs/uploads/:upload_id`

Artifact lifecycle endpoints:

- `GET /api/v1/repos/:repo_id/artifacts`
- `GET /api/v1/repos/:repo_id/artifacts/:artifact_id`
- `DELETE /api/v1/repos/:repo_id/artifacts/:artifact_id`
- `POST /api/v1/admin/artifacts/cleanup`

Multipart completion commits through the existing workspace blob path, so
workspace revocation, path authorization, protected-path checks, content hash
validation, and public hygiene rules remain centralized.
