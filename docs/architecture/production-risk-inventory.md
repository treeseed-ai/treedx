# TreeDB Production Risk Inventory

Status: Stage 0 baseline  
Source: `PLAN` risk register

| Risk | Impact | Owner area | Target stage | Current mitigation | Required implementation item | Verification test |
|---|---|---|---|---|---|---|
| JWKS/control-plane auth is under-specified | Production auth weakness | API auth | Stage 1 | HS256 connected auth exists for MVP | Add verifier abstraction, JWKS/OIDC verifier, fail-closed boot config | `apps/api/test/treedb/auth_verifier_test.exs` |
| Direct exec sandbox leaks host data | Critical security issue | API exec/runtime | Stage 3 | Capability-gated MVP exec | Add production sandbox backend and isolation controls | Stage 3 sandbox escape/resource tests |
| Federation leaks hidden data through ranking/counts | Cross-tenant data leak | Federation/query/graph | Stage 4 | Planner-only federation reduces scope | Execute only authorized segments before ranking/serialization | `apps/api/test/treedb_web/leakage_regression_test.exs` and Stage 4 fixtures |
| Storage corruption loses metadata | Data loss | Rust store/native API | Stage 1 and Stage 3 | Append-only `.tdb` records and checksums | Add data-dir lock, diagnostic check, recovery mode, later compaction/backup | `crates/treedb_store/tests/recovery_tests.rs`, `lock_tests.rs` |
| Binary files cannot move through no-clone APIs | SDK users fall back to local clones or leak binary data through text responses | API files/store/SDK | Stage 2 | Git blob reads and snapshot artifacts are byte-safe internally | Add repository/workspace blob APIs, base64 JSON writes, raw upload/download, content hash checks, and binary diff placeholders | `apps/api/test/treedb_web/blob_controller_test.exs`, `crates/treedb_store/tests/workspace_blob_tests.rs`, `packages/ts-sdk/test/utils/treedb-blobs.test.ts` |
| SDK remote mode breaks local SDK ergonomics | Adoption blocker | TypeScript SDK | Stage 5 | Local mode remains default and TreeDB is opt-in | Keep exports stable and add local-vs-remote parity tests | `packages/ts-sdk/test/utils/treedb-*.test.ts` |
| API/server and SDK type drift | Runtime failures | API contract/SDK | Stage 0 and Stage 5 | Hand-maintained OpenAPI and SDK types | Add route inventory, export drift tests, later schema validation | `treedb-sdk-exports.test.ts`, future OpenAPI drift check |
| Git push leaks credentials | Secret exposure | Git/mirror/audit | Stage 3 | Push not implemented in MVP | Add credential provider boundary and URL sanitizer | Stage 3 credential scrubber tests |
| Policy revocation does not affect active workspaces | Unauthorized access persists | Policy/workspaces | Stage 1 | Workspace snapshots effective scope only | Add policy hash/version and workspace quarantine | `apps/api/test/treedb_web/workspace_revocation_test.exs` |
| Product semantics creep into TreeDB | Architecture degradation | API/storage/SDK boundary | All stages | Docs state TreeDB is repository scoped | Keep TreeSeed model/product concepts in SDK/core/control plane | Architecture review and API/schema grep |
| Shell Git fallback becomes default | Reliability/security drift | Git integration | Stage 3 | Rust/gix preferred in plan | Audit every fallback and prefer Rust implementations | Stage 3 Git workflow tests |
