# Release Gate Runbook

Run the release gate from the repository root:

```bash
./scripts/release-gate.sh
```

The gate is complete only when the command exits successfully.

## Scope

The root release gate verifies the TreeDB service repository: Elixir service
tests, native Rust crates used by the service, OpenAPI contract checks, security
scanners, storage recovery, smoke tests, container behavior, and optional live
federation checks.

The root release gate does not own the full multi-language SDK toolchain. SDK
package verification is handled by the SDK workflows and local SDK package gate.

The root release gate verifies only the TreeDB service repository. It is
path-filtered for service, native, storage, Docker, profile, and release-gate
files on pull requests and branch pushes. Git tag pushes run the release gate
without custom tag-diff filtering so release verification stays reliable.

The TypeScript, Python, Rust, and Elixir SDK packages have independent
package-level release gates.

## Checklist

- Production auth uses connected mode with a configured verifier.
- JWKS verifier configuration is valid and key rotation tests pass.
- Policy revocation and workspace quarantine tests pass.
- Protected paths are blocked by default.
- Sandbox backend is production-safe and direct execution is disabled unless explicitly allowed.
- Remote Git credentials use credential IDs only.
- Storage lock, recovery, backup, migration, and restore checks pass.
- Backup verification returns logical backup URIs only.
- Readiness, deep health, metrics, and JSON log tests pass.
- Logs, metrics, audit payloads, and public responses are scrubbed.
- OpenAPI server contract checks pass.
- `cargo audit` passes.
- Syft writes `target/treedb-sbom.spdx.json`.
- Trivy reports no high or critical image findings.
- Container smoke verification passes.
- Live federation check reports not configured or passes.
- Root workflow and scripts do not require `packages/ts-sdk`, npm, Node, or a
  `VERSION` file.

## Scanner Policy

The security scanner gate is strict. Missing `cargo-audit`, `syft`, `trivy`,
`docker`, or `cargo` fails the release gate. Accepted vulnerability records,
when needed, live in `docs/security/accepted-vulnerabilities.md` and must
include package or image, advisory ID, severity, reason, mitigation, owner, and
expiration date.

## Optional Live Checks

Live checks are environment-backed operational checks. When credentials are absent they report not configured and exit successfully. They are not test skips and do not reduce local or CI test coverage.

## Workflow Architecture

The GitHub workflow runs TreeDB verification independently on `linux/amd64` and
`linux/arm64` runner streams. Each stream runs the same release gate on native
hardware so architecture-specific Rust, native NIF, release, storage, and
container issues are caught before publishing.

The `TreeDB Release Gate` workflow preserves the release sequence:
verification runs first, release-path profile jobs run after verification, and
publishing waits for the required profile streams. Profiles are broad
acceptance tests and can stop a release. The base profiler uses the production
profile Compose setup. Federation profiler jobs run both three-node
mirror-cluster and connected-library profiles. Performance profiles run by
default on `main`, `staging`, and tag pushes; Docker publishing waits for the
performance profile on publish-path pushes. The performance profile records the
target-RPS result in its reports, but missing the target RPS is not a release
failure by itself. The performance profile blocks release only for profiler
execution errors, service errors, assertion failures, or response validation
failures.

Profile behavior is controlled with GitHub repository or environment variables:

- `TREEDB_CI_PROFILE_MODE`, default `portfolio`
- `TREEDB_CI_PROFILE_DURATION`, default `10m`
- `TREEDB_CI_PROFILE_CONCURRENCY`, default `25`
- `TREEDB_CI_PROFILE_SIZE`
- `TREEDB_CI_PROFILE_FIXTURE`
- `TREEDB_CI_PROFILE_SCENARIO`
- `TREEDB_CI_PROFILE_LOAD_MODE`
- `TREEDB_CI_PROFILE_ITERATIONS`

Federation profile behavior is controlled separately:

- `TREEDB_CI_FEDERATION_PROFILE_ENABLED`, default `true` on release-path pushes
- `TREEDB_CI_FEDERATION_PROFILE_MODES`, default
  `mirror-federation,connected-library`
- `TREEDB_CI_FEDERATION_PROFILE_DURATION`, default `10m`
- `TREEDB_CI_FEDERATION_PROFILE_CONCURRENCY`, default `25`
- `TREEDB_CI_FEDERATION_PROFILE_SIZE`, default `small`

Duration means measured load after setup completes. Setup, image build, health
waits, fixture import, catalog convergence, and report finalization are recorded
separately and do not count toward the requested measured window.

The architecture image build runs only after the matching architecture has
completed verification and after required base and federation profiler streams
have succeeded. The final manifest is assembled only after both architecture
images are pushed.

## SDK Release Relationship

SDK-affecting changes should require these package-level GitHub checks:

- `SDK Spec Release Gate / SDK Spec Release Gate`
- `TypeScript SDK Release Gate / TypeScript SDK Release Gate`
- `Python SDK Release Gate / Python SDK Release Gate`
- `Rust SDK Release Gate / Rust SDK Release Gate`
- `Elixir SDK Release Gate / Elixir SDK Release Gate`

For a full release candidate, require both:

1. Root `TreeDB Release Gate`
2. Relevant SDK package release gates

Local SDK package verification is:

```bash
./scripts/test-sdk-packages.sh
```

SDK release gates build and upload package artifacts but do not publish to npm,
PyPI, crates.io, or Hex. Service release publishing remains gated by the root
verification and required profile streams.

## Docker Hub Publishing

The GitHub workflow publishes Docker images only after the release gate passes.

- Pushes to `main` publish `treeseed/treedb:latest`.
- Git tags publish `treeseed/treedb:<tag>`.
- Release tags must be semantic versions without a `v` prefix, such as
  `0.1.0` or `1.2.3-alpha.1`.
- Build metadata tags such as `1.2.3+build.5` are not used for Docker
  publishing because Docker tags cannot preserve `+` while keeping the image tag
  identical to the git tag.
- Existing Docker Hub version tags are not overwritten.
- Images are built as a multi-architecture manifest for `linux/amd64` and
  `linux/arm64`.
- Architecture images are built on native GitHub-hosted runners
  (`ubuntu-24.04` for `linux/amd64` and `ubuntu-24.04-arm` for `linux/arm64`)
  and then combined into the published manifest. The workflow does not use QEMU
  for release builds.
- Architecture-specific Docker Hub tags are named after the final manifest tag:
  `latest-amd64` and `latest-arm64` for `main`, or `<semver>-amd64` and
  `<semver>-arm64` for version tags. The manifest tag remains `latest` or the
  exact semantic-version git tag.
- BuildKit cache is enabled per architecture for Docker layers plus Cargo and
  Mix build caches.
- Architecture image builds attach BuildKit SBOM and max-mode provenance
  attestations at push time so Docker Hub supply-chain attestation checks can
  verify both software bill of materials and build provenance.
- The published runtime image omits optional shell Git tooling; deployments that
  enable authenticated external Git transport provide that tooling in a derived
  image or controlled worker environment.
- Publishing uses the GitHub `production` environment secrets
  `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.

There is no `VERSION` file. The git tag is the only source for a versioned
Docker image tag.
