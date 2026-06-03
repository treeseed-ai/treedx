# Release Gate Runbook

Run the release gate from the repository root:

```bash
./scripts/release-gate.sh
```

The gate is complete only when the command exits successfully.

## Checklist

- Production auth uses connected mode with a configured verifier.
- JWKS verifier configuration is valid and key rotation tests pass.
- Policy revocation and workspace quarantine tests pass.
- Protected paths are blocked by default.
- Sandbox backend is production-safe and direct execution is disabled unless explicitly allowed.
- Remote Git credentials use credential IDs only.
- Storage lock, recovery, backup, migration, and restore checks pass.
- Backup verification returns logical backup URIs only.
- Readiness, deep health, metrics, and JSON log tests pass.
- Logs, metrics, audit payloads, and public responses are scrubbed.
- OpenAPI and generated SDK types are synchronized.
- `cargo audit` passes.
- `npm audit --audit-level=high` passes.
- Syft writes `target/treedb-sbom.spdx.json`.
- Trivy reports no high or critical image findings.
- Live SDK contract reports not configured or passes.
- Live federation check reports not configured or passes.

## Scanner Policy

The security scanner gate is strict. Missing `cargo-audit`, `syft`, `trivy`, `docker`, `cargo`, or `npm` fails the release gate. Accepted vulnerability records, when needed, live in `docs/security/accepted-vulnerabilities.md` and must include package or image, advisory ID, severity, reason, mitigation, owner, and expiration date.

## Optional Live Checks

Live checks are environment-backed operational checks. When credentials are absent they report not configured and exit successfully. They are not test skips and do not reduce local or CI test coverage.
