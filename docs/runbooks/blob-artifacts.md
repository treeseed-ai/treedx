# Blob Upload And Artifact Lifecycle Runbook

Use raw blob upload/download for ordinary binary transfer. Use multipart upload
for larger files or retryable clients.

Multipart flow:

1. Create an upload session.
2. Upload contiguous numbered parts starting at `1`.
3. Complete the upload with optional expected content hash.
4. Abort abandoned sessions when no longer needed.

Artifact lifecycle:

- list: `GET /api/v1/repos/:repo_id/artifacts`
- show: `GET /api/v1/repos/:repo_id/artifacts/:artifact_id`
- delete: `DELETE /api/v1/repos/:repo_id/artifacts/:artifact_id`
- cleanup: `POST /api/v1/admin/artifacts/cleanup`

Artifact responses expose logical artifact IDs, byte length, checksum, and
`treedx://artifact/...` URI metadata only.
