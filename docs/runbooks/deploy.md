# TreeDB Deploy Runbook

TreeDB production images are published to Docker Hub as `treeseed/treedb`.

- `treeseed/treedb:latest` is published from verified `main` branch updates.
- `treeseed/treedb:<semver>` is published from verified semantic-version git
  tags, for example `0.1.0` or `1.2.3-alpha.1`.
- Published tags are multi-architecture images for `linux/amd64` and
  `linux/arm64`.
- Versioned Docker tags come directly from git tags. There is no separate
  version file. Tags with build metadata such as `1.2.3+build.5` are not used
  because Docker tags cannot preserve `+` while keeping the image tag identical
  to the git tag.

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
