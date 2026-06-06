# Release Gate Runbook

Run the release gate from the repository root:

```bash
./scripts/release-gate.sh
```

The gate is complete only when the command exits successfully.

## Scope

The root release gate verifies the TreeDX service repository and the generic
TreeDX SDK release set together: Elixir service tests, native Rust crates used
by the service, OpenAPI contract checks, security scanners, storage recovery,
smoke tests, container behavior, profile acceptance tests, `packages/sdk-spec`,
and the TypeScript, Python, Rust, and Elixir SDK packages.

The root release gate verifies only the TreeDX service repository. It is
path-filtered for service, native, storage, Docker, profile, and release-gate
files on pull requests and branch pushes. Git tag pushes run the release gate
without custom tag-diff filtering so release verification stays reliable.

The TypeScript, Python, Rust, and Elixir SDK packages are tested and packaged
inside this workflow so tagged SDK artifacts cannot be produced from a release
where the primary API service gate or required profile gates fail.

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
- Syft writes `target/treedx-sbom.spdx.json`.
- Trivy reports no high or critical findings for the production service image.
- The profiler image builds and receives an advisory vulnerability scan.
- Container smoke verification passes.
- Live federation check reports not configured or passes.
- Root workflow and scripts do not require `packages/ts-sdk`, npm, Node, or a
  `VERSION` file.

## Scanner Policy

The security scanner gate is strict for the production `treeseed/treedx`
service image. Missing `cargo-audit`, `syft`, `trivy`, `docker`, or `cargo`
fails the release gate. The Debian-based `treeseed/treedx-profiler` image is
also built, SBOMed, and scanned, but that scan is advisory because the image is
an operational profiling utility rather than the production API runtime.
Accepted vulnerability records, when needed, live in
`docs/security/accepted-vulnerabilities.md` and must include package or image,
advisory ID, severity, reason, mitigation, owner, and expiration date.

## Optional Live Checks

Live checks are environment-backed operational checks. When credentials are absent they report not configured and exit successfully. They are not test skips and do not reduce local or CI test coverage.

## Workflow Architecture

The GitHub workflow runs TreeDX verification independently on `linux/amd64` and
`linux/arm64` runner streams. Each stream runs the same release gate on native
hardware so architecture-specific Rust, native NIF, release, storage, container,
and SDK package issues are caught before publishing.

`SDK Spec` runs in parallel with service verification. The four language SDK
test jobs run on both `amd64` and `arm64` after `SDK Spec` passes, so no SDK
implementation test runs against an invalid shared spec. On release-path pushes,
Docker architecture image builds and SDK package artifact jobs both wait for all
language SDK tests and the required profile jobs. They then run in parallel.
Final Docker manifest publishing waits for both Docker architecture images and
all SDK package artifacts, keeping service and SDK release outputs synchronized.

The `TreeDX Release Gate` workflow preserves the release sequence:
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

Profile Compose starts API nodes from the stripped `treeseed/treedx` production
image target and runs profiling from the separate Debian-based
`treeseed/treedx-profiler` image. The service image does not contain profiler
tooling. Profile behavior is controlled with GitHub repository or environment
variables:

- `TREEDX_CI_PROFILE_MODE`, default `portfolio`
- `TREEDX_CI_PROFILE_DURATION`, default `10m`
- `TREEDX_CI_PROFILE_CONCURRENCY`, default `25`
- `TREEDX_CI_PROFILE_SIZE`
- `TREEDX_CI_PROFILE_FIXTURE`
- `TREEDX_CI_PROFILE_SCENARIO`
- `TREEDX_CI_PROFILE_LOAD_MODE`
- `TREEDX_CI_PROFILE_ITERATIONS`

Federation profile behavior is controlled separately:

- `TREEDX_CI_FEDERATION_PROFILE_ENABLED`, default `true` on release-path pushes
- `TREEDX_CI_FEDERATION_PROFILE_MODES`, default
  `mirror-federation,connected-library`
- `TREEDX_CI_FEDERATION_PROFILE_DURATION`, default `10m`
- `TREEDX_CI_FEDERATION_PROFILE_CONCURRENCY`, default `25`
- `TREEDX_CI_FEDERATION_PROFILE_SIZE`, default `small`

Duration means measured load after setup completes. Setup, image build, health
waits, fixture import, catalog convergence, and report finalization are recorded
separately and do not count toward the requested measured window.

The architecture image build runs only after the matching architecture has
completed verification and after required base, federation, and performance
profiler streams have succeeded. The final service and profiler manifests are
assembled only after both architecture images for both image families are
pushed.

## SDK Release Relationship

SDK-affecting changes are handled by the integrated `TreeDX Release Gate`.
Relevant GitHub checks are:

- `TreeDX Release Gate / SDK Spec`
- `TreeDX Release Gate / TypeScript SDK Test (amd64)`
- `TreeDX Release Gate / TypeScript SDK Test (arm64)`
- `TreeDX Release Gate / Python SDK Test (amd64)`
- `TreeDX Release Gate / Python SDK Test (arm64)`
- `TreeDX Release Gate / Rust SDK Test (amd64)`
- `TreeDX Release Gate / Rust SDK Test (arm64)`
- `TreeDX Release Gate / Elixir SDK Test (amd64)`
- `TreeDX Release Gate / Elixir SDK Test (arm64)`

For release-path pushes, package artifact jobs also run after profile gates:

- `TreeDX Release Gate / Package TypeScript SDK`
- `TreeDX Release Gate / Package Python SDK`
- `TreeDX Release Gate / Package Rust SDK`
- `TreeDX Release Gate / Package Elixir SDK`

Local SDK package verification is:

```bash
./scripts/test-sdk-packages.sh
```

The integrated release gate builds and uploads SDK package artifacts but does
not publish to npm, PyPI, crates.io, or Hex. Service Docker manifest publishing
waits for SDK package artifacts on release-path pushes.

## Docker Hub Publishing

The GitHub workflow publishes Docker images only after the release gate passes.

- Pushes to `main` publish `treeseed/treedx:latest` and
  `treeseed/treedx-profiler:latest`.
- Git tags publish `treeseed/treedx:<tag>` and
  `treeseed/treedx-profiler:<tag>`.
- Release tags must be semantic versions without a `v` prefix, such as
  `0.1.0` or `1.2.3-alpha.1`.
- Build metadata tags such as `1.2.3+build.5` are not used for Docker
  publishing because Docker tags cannot preserve `+` while keeping the image tag
  identical to the git tag.
- Existing Docker Hub version tags are not overwritten for either image.
- Images are built as a multi-architecture manifest for `linux/amd64` and
  `linux/arm64`.
- Architecture images are built on native GitHub-hosted runners
  (`ubuntu-24.04` for `linux/amd64` and `ubuntu-24.04-arm` for `linux/arm64`)
  and then combined into the published manifest. The workflow does not use QEMU
  for release builds.
- Architecture-specific Docker Hub tags are named after the final manifest tag
  for each image: `latest-amd64` and `latest-arm64` for `main`, or
  `<semver>-amd64` and `<semver>-arm64` for version tags. The manifest tags
  remain `latest` or the exact semantic-version git tag.
- BuildKit cache is enabled per architecture for Docker layers plus Cargo and
  Mix build caches.
- Architecture image builds attach BuildKit SBOM and max-mode provenance
  attestations at push time so Docker Hub supply-chain attestation checks can
  verify both software bill of materials and build provenance.
- The published service runtime image is distroless and omits package-manager,
  shell, Git, curl, and profiler tooling. The published profiler image is a
  separate Debian-based utility image and is not used as the API service
  runtime.
- Publishing uses the GitHub `production` environment secrets
  `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.

There is no `VERSION` file. The git tag is the only source for a versioned
Docker image tag.
