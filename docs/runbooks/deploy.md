# TreeDB Deploy Runbook

1. Configure required runtime variables:
   - `TREEDB_DATA_DIR`
   - `TREEDB_AUTH_MODE`
   - connected auth verifier variables when using connected auth
   - storage and exec backend variables appropriate for the environment
2. Start the service.
3. Probe liveness:

```bash
curl "$TREEDB_URL/api/v1/health"
```

4. Gate traffic on readiness:

```bash
curl "$TREEDB_URL/api/v1/ready"
```

5. Configure metrics scraping:

```text
GET /metrics
```

6. Confirm production logs are JSON and do not contain raw secrets or local
   filesystem paths.
