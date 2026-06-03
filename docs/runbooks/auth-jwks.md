# TreeDB Auth And JWKS Runbook

Connected auth requires a verifier configuration and fails closed when required
settings are missing.

Common checks:

```bash
curl "$TREEDB_URL/api/v1/auth/mode"
curl -H "authorization: Bearer $TOKEN" "$TREEDB_URL/api/v1/auth/whoami"
```

When auth provider health checking is enabled with
`TREEDB_HEALTH_CHECK_AUTH_PROVIDER=true`, inspect:

```bash
curl -H "authorization: Bearer $TOKEN" "$TREEDB_URL/api/v1/admin/health/deep"
```

Do not place raw tokens, JWKS URLs with credentials, private keys, or shared
secrets in public requests, logs, metrics, or audit payloads.
