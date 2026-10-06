# Security Incident Runbook

TreeDX production incident response should start by preserving audit logs and
revoking affected credentials or policy grants.

Immediate checks:

- review `GET /api/v1/audit/events` with `audit:read`.
- rotate any remote credential IDs involved in Git operations.
- disable `TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED` if remote transport is suspect.
- disable `TREEDX_EXEC_BACKEND=external_worker` or rotate worker token/HMAC if
  worker transport is suspect.
- quarantine affected workspaces through policy revocation and verify
  `workspace.quarantined` audit events.

Public TreeDX responses and audit payloads must not contain raw credentials,
local filesystem paths, hidden refs, hidden paths, snippets, stdout/stderr, or
binary payloads.

## Token Compromise

1. Revoke affected grants with policy refresh.
2. Rotate verifier or JWKS keys if token signing material may be affected.
3. Check audit events for `auth.verified`, `auth.rejected`, and policy changes.
4. Quarantine workspaces owned by affected actors.
5. Confirm `/api/v1/ready` is ready after config changes.

## Remote Credential Exposure

1. Disable `TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED`.
2. Rotate the operator-managed credential behind the affected credential ID.
3. Review `git.push.*`, `git.fetch.*`, and mirror audit events.
4. Confirm audit payloads contain sanitized remote URL and refspec counts only.
5. Re-enable transport only after `scripts/verification/security-check.sh` succeeds.

## Path Traversal Or Hidden Data Report

1. Preserve request IDs and audit events.
2. Disable write operations for affected grants if exposure may continue.
3. Run boundary and leakage regression tests.
4. Add missing protected path or scope reduction coverage before release.
5. Notify operators if unauthorized snippets, paths, refs, or counts were exposed.

## Sandbox Escape Suspicion

1. Disable external worker or container sandbox backend.
2. Rotate worker tokens and HMAC secrets.
3. Inspect exec audit events for backend, mode, status, and byte counts.
4. Do not rely on stdout/stderr in audit logs; collect backend logs from the worker environment.
5. Re-enable only after sandbox tests and release gate pass.

## Malicious Repository Or Artifact

1. Mark affected repository unavailable in the control plane.
2. Revoke artifact export capability for affected actors.
3. Verify artifact checksums and snapshot manifests.
4. Delete unsafe artifacts through artifact lifecycle APIs.
5. Rebuild trusted artifacts from a verified commit.

## Storage Corruption

1. Stop write traffic.
2. Enter read-only recovery mode.
3. Run storage check and backup verification.
4. Restore only from a verified backup and only with explicit restore acknowledgement.
5. Preserve audit logs and pre-restore backups.

## Dependency Disclosure

1. Run `scripts/verification/security-check.sh`.
2. Patch vulnerable dependencies where possible.
3. If temporary acceptance is required, document it in `docs/security/accepted-vulnerabilities.md` with owner and expiration.
4. Rerun the release gate before deploying.
