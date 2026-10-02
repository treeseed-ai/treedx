# TreeDX workspace guidance

## CRITICAL: complete automated test coverage

Every behavior, contract, state transition, failure path, and edge case must have automated unit, integration, and scene/guarantee-based acceptance coverage. This is mandatory for all projects, especially the capacity-provider and agent system. A behavior without all three layers is an unresolved delivery gap, not completed work.

- Unit tests must prove exact outputs, validation, invariants, and boundary conditions. Cover valid and invalid inputs, missing/empty/malformed values, authorization denial, stale or moved refs, and every named prohibited field.
- Integration tests must exercise the real owning components and their public boundaries: handlers, provider/kernel execution, APIs, persistence, tools, and downstream consumers. Mocks, string assertions, compilation, or call-order checks alone are not integration proof.
- Coded scenes and guarantees must prove production-shaped end-to-end outcomes: exact governed artifacts and read-back, independent verification, actual usage, exactly-once settlement, and durable teardown. Use the project's existing native acceptance harness and respect package ownership; do not put TreeSeed-specific policy into product-neutral packages.
- Cover duplicate and concurrent execution, idempotency, partial failure, interruption, retry, resume, cancellation, expiry, provider/tool/subprocess errors, unsafe commands, and cleanup without residue. Preserve failed observations; do not fabricate dispositions, usage, citations, receipts, or passing replays.
- For every defect, first add a focused regression that reproduces the failure, then add or strengthen the corresponding integration and scene/guarantee cases. Fix the earliest owning contract. Retain previously covered behavior and all historical failed evidence.
- Never weaken assertions, remove negative cases, narrow acceptance criteria, disable type checks, extend deadlines, increase allowances, or relabel failures as passes to get green results. An unexpected agent timeout is a fatal architecture defect: agents must check authoritative remaining time frequently, reserve verification/closeout time, and produce authorized continuation proposals for unfinished work before the original deadline.
- Delivery requires passing evidence at all three layers on the exact candidate. Missing environments, credentials, skipped tests, or blocked layers remain explicitly unproven. Component passes, suite totals, line coverage, and process completion never substitute for full semantic acceptance.
- Before EVERY acceptance run (scene or guarantee), run ALL automated unit and integration tests for every participating project on the exact candidate. Focused regressions are additional checks, not substitutes for the complete suites. Failed, skipped, missing, empty, or inconclusive prerequisite coverage blocks acceptance; never launch a live campaign first and discover prerequisite failures afterward. Run the complete suites once per participating project per acceptance invocation, before any scene begins; do not reuse a previous invocation's passing receipt or omit tests to save time. Preserve exact command, candidate, run, and result evidence in the existing Issue and Actions artifacts.
- Keep the behavior-to-unit/integration/scene mapping and exact command, commit, run, and artifact evidence in the existing Issue body and Actions artifacts. Reproduce failures with cheap focused tests before another expensive activation or full campaign; batch known fixes, inspect failed jobs, and reuse only unchanged immutable evidence. No duplicate campaigns or new coverage side channels.

## Agent configuration and handler ownership

When this project defines or consumes agents, agent identity, task instructions, prompts, capabilities, permissions, parameters, and activity profiles must be governed YAML configuration. Adding or renaming an agent using existing handlers must not require provider, guest, kernel, or scheduler code changes. Do not hardcode named-role configuration in shared runtime code; shared rules must apply to any configured agent.

Task-specific executable code belongs in the configured handler. Reuse existing class-based handlers and exact profile bindings; new coded functionality may require a pinned handler, but not a parallel dispatch path or duplicated policy. Test arbitrary YAML-defined agents, renamed identities, handler selection, changed prompts/parameters, denied permissions, and unknown/duplicate handlers through unit, real integration, and coded acceptance cases.

Preserve TreeDX as the canonical knowledge, Git mirror, index, and workspace service. Keep credentials opaque and bounded, and fail closed on moved refs or incomplete synchronization.

## Required implementation languages

TreeDX uses Elixir for its API and service orchestration and Rust for native storage, Git, graph, and search components. These are required project languages, not exceptions that need repeated approval. Implement fixes and regression tests in the owning language; do not move existing engines into TypeScript or introduce a duplicate runtime to satisfy another repository's language guidance. TypeScript remains appropriate for the existing TypeScript SDK and its tooling; JavaScript is generated output there. Preserve independent builds and the language-specific formatting and test gates.

## Branch and deployment boundary

`main` is the only production branch and maps only to the `production` deployment environment. `staging` is the only development-integration branch and maps only to the `staging` deployment environment. Short-lived pull-request branches may validate without deploying, but they must never define another deployment environment. Do not create or use `development`, `preview`, `stable`, or any other GitHub deployment environment; preview deployments are prohibited. Release tags may promote an exact reviewed `staging` commit to `production` without creating another branch or environment. Artifact channel names must never become GitHub deployment environments.

## Project library

Use `trsd library show treedx` and `status` before querying `treeseed-ai/treedx-library`. Read root-level paths at an exact commit. Author only through governed library workspaces and reviews. Never recreate `src/content` or edit `.treeseed/data` directly.
