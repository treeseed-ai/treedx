# TreeDB API Compatibility Notes

## Current Contract

- TreeDB API path prefix: `/api/v1`
- SDK package subpaths: `@treeseed/sdk/treedb`, `/client`, `/types`, `/adapters`
- Generated type source: `docs/api/openapi.yaml`
- Public compatibility gate: `scripts/test-treedb-fast.sh`
- Error envelopes and error codes are stable public contract surfaces.
- Operational health and metrics routes are covered by the same OpenAPI and SDK
  generation contract.
