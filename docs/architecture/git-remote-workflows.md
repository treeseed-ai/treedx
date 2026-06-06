# Git Remote Workflows

TreeDX keeps Git remote operations generic and repository-scoped.

Push is implemented for local path and `file://` remotes without a shell
fallback. The Rust path validates repositories with `gix`, validates explicit
refspecs, copies loose objects for local remotes, and writes destination refs.

Authenticated HTTPS and SSH workflows use a constrained external Git transport
only when explicitly enabled. Public requests provide logical `credentialId`
values. Credential-bearing URLs are rejected, SSH requires configured
`known_hosts`, and the external transport runs with a scrubbed environment.

All remote URLs pass through the same public sanitizer before appearing in API
responses or audit payloads. Raw credentials, credential file paths, full
transport output, and unauthorized refs are not serialized.
