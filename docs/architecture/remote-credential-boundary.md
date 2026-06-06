# Remote Credential Boundary

TreeDX remote Git APIs never accept raw credentials in request bodies or remote
URLs. Operators configure a credential provider and callers pass only a logical
`credentialId`.

Supported providers:

- `TREEDX_REMOTE_CREDENTIAL_PROVIDER=none`
- `TREEDX_REMOTE_CREDENTIAL_PROVIDER=env_file`
- `TREEDX_REMOTE_CREDENTIAL_PROVIDER=external_command`

Authenticated HTTPS and SSH transports use the constrained external transport
path only when `TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED=true`. SSH also requires
`TREEDX_GIT_SSH_ENABLED=true` and `TREEDX_GIT_SSH_KNOWN_HOSTS`.

Public responses and audit payloads include sanitized remote URL metadata,
backend, refspec count, dry-run flag, and status. They do not include
credential material, askpass paths, private key paths, stdout/stderr, hidden
refs, or local filesystem paths.
