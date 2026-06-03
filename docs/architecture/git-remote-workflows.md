# Git Remote Workflows

TreeDB Stage 3 keeps Git remote operations generic and repository-scoped.

Push is implemented for local path and `file://` remotes without a shell
fallback. The Rust path validates repositories with `gix`, validates explicit
refspecs, copies loose objects for local remotes, and writes destination refs.
HTTP(S) dry-run can validate request shape, but HTTP(S) non-dry-run returns
`unsupported_transport` until authenticated push transport lands.

All remote URLs pass through the same public sanitizer before appearing in API
responses or audit payloads. Credential-bearing URLs are rejected.
