# TreeDB Security Model

TreeDB protects repository, workspace, graph, search, blob, artifact, federation, and storage operations with explicit identity, capability, path, ref, and operational boundaries. Public surfaces must not expose raw credentials, raw tokens, authorization headers, credential-bearing URLs, local filesystem paths, hidden refs, hidden paths, unauthorized snippets, stdout/stderr, binary payloads, or request bodies.

## Threats And Controls

| Threat | Attack path | Existing mitigation | Release-gate check | Residual risk | Operational response |
| --- | --- | --- | --- | --- | --- |
| Token forgery | Submit forged bearer token | JWT verifier, algorithm allowlist, issuer and audience checks | Auth verifier tests and security contract tests | Verifier misconfiguration | Rotate verifier keys, revoke grants, inspect audit events |
| Issuer or audience mismatch | Reuse token from another system | Required `iss` and `aud` validation | Auth verifier tests | Incorrect deployment env | Fix config and restart after readiness is healthy |
| Token expiration bypass | Use expired token | Expiration check maps to `token_expired` | Auth verifier tests | Clock drift | Set clock skew policy and monitor auth failures |
| JWKS rotation failure | Present token signed by stale/unknown key | JWKS cache refresh and fail-closed behavior | JWKS cache tests | Provider outage | Use cached valid keys only within grace, rotate safely |
| Path traversal | Request `../`, encoded traversal, or absolute path | Repository-relative path normalization and traversal rejection | Security boundary tests | Parser bug | Disable writes, preserve audit logs, patch path policy |
| Protected path access | Read or write `.env`, `.ssh`, `.git`, private keys | Protected path policy and explicit override checks | Security boundary tests | Missing protected pattern | Add pattern and publish compatibility note |
| Hidden data leakage | Unauthorized repo/path/snippet/count appears in response | Capability reduction before query/search/graph execution | Leakage and federation security tests | New route omits reduction | Block route in release gate and fix controller |
| Malicious Git repository | Crafted refs, remotes, hooks, or paths | Explicit refspec validation, sanitized remote URLs, no shell fallback for native path | Git remote tests | Git implementation vulnerability | Disable external transport and rotate credentials |
| Malicious file contents | Binary or text content abuses parsers | Blob byte limits, UTF-8 checks for text APIs, binary-safe blob APIs | Blob and artifact tests | Parser vulnerability | Disable artifact export for affected repo |
| Binary payload abuse | Oversized uploads or artifacts | Blob and multipart limits, content hashes, retention | Blob and artifact lifecycle tests | Storage pressure | Run artifact cleanup and backup checks |
| Malicious patches | Patch attempts to write outside scope | Path normalization and workspace path authorization | Security boundary tests | Patch parser bug | Quarantine workspace and revoke grants |
| Command injection | Exec command escapes intended backend | Backend abstraction, direct backend disabled in production by default, sandbox policy | Exec sandbox tests | Backend bug | Disable exec backend and inspect audit events |
| Environment leakage | Exec inherits secrets | Clean env allowlist, audit excludes output | Exec sandbox tests | Worker implementation bug | Rotate secrets and disable worker |
| Network egress | Exec reaches external network | Sandbox network defaults to none | Exec sandbox tests | Container runtime bug | Disable exec and rotate credentials |
| Storage corruption | Tampered `.tdb` record or backup | Checksums, recovery checks, verified backups | Storage security tests | Disk or filesystem failure | Enter recovery mode, verify backup, restore only after approval |
| Artifact tampering | Artifact bytes or metadata changed | Checksums and logical artifact IDs | Artifact security tests | External storage tamper | Rebuild snapshot and compare checksum |
| Remote credential leakage | Credentials in URL, logs, audit, or metrics | Credential IDs only, URL sanitizer, scrubber, strict logs | Git remote and observability tests | Operator command leak | Disable external transport and rotate credentials |
| Cross-tenant access | Token or grant crosses tenant boundary | Principal tenant and policy scope resolution | Policy and federation tests | Bad grant | Revoke grant and quarantine affected workspaces |
| Dependency vulnerability | Vulnerable crate or container dependency | `cargo audit`, Syft, Trivy | `scripts/security-check.sh` | Accepted temporary advisory | Document in accepted vulnerabilities with expiration |
| Container vulnerability | Runtime image has high/critical issue | Trivy image scan | `scripts/security-check.sh` | Base image emergency | Patch image and rerun release gate |
| SBOM and license risk | Unknown package inventory | Syft SBOM generation and license docs | `scripts/security-check.sh` | Transitive changes | Review generated SBOM before release |

## Release Boundary

Release readiness is gated by `scripts/release-gate.sh`. The gate runs the unified test suites, OpenAPI contract checks, storage recovery checks, strict dependency scans, SBOM generation, container image scan, and optional live contracts when credentials are configured.

Security scanner availability is mandatory for release readiness. Missing scanner tools fail the gate.
