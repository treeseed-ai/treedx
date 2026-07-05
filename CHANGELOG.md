# Changelog

## [0.2.34] - 2026-07-05

### Fixed

- ci(ci): fix Docker Hub attestation verification (87a2b536f1e9)

### Infrastructure

- ci(source): harden container image release security (af1b3bd96934)

## [0.2.33] - 2026-07-05

### Changed

- Release metadata and deployment history updated.

## [0.2.32] - 2026-07-04

### Changed

- Release metadata and deployment history updated.

## [0.2.31] - 2026-07-04

### Changed

- Release metadata and deployment history updated.

## [0.2.30] - 2026-07-04

### Fixed

- fix(graph): satisfy release gate clippy (7a7435fcdf35)
- fix(ci): run release gate for graph crate changes (9c735eda6fc1)
- fix(graph): publish graph segments atomically (0ef060e01e27)

## [0.2.29] - 2026-07-04

### Fixed

- fix(sdk): restore Rust generated metadata checker entrypoint (a1c12b9d25a9)

### Infrastructure

- ci(release): restore TreeDX release gate (584296afc108)

## [0.2.28] - 2026-07-04

### Changed

- Release metadata and deployment history updated.

## [0.2.27] - 2026-07-04

### Changed

- Release metadata and deployment history updated.

## [0.2.26] - 2026-07-04

### Changed

- Release metadata and deployment history updated.

## [0.2.25] - 2026-07-04

### Changed

- Release metadata and deployment history updated.

## [0.2.24] - 2026-07-04

### Infrastructure

- docs: clean release changelog (3d52f6c01ed9)

## [0.2.23] - 2026-07-04

### Changed


## [0.2.22] - 2026-07-04

### Changed


## [0.2.21] - 2026-07-04

### Changed

- refactor: replace preview APIs with plan mode (5afc0f0de419)

## [0.2.20] - 2026-07-03

### Changed

- Release metadata and deployment history updated.

## [0.2.19] - 2026-07-03

### Changed

- Release metadata and deployment history updated.

## [0.2.18] - 2026-07-03

### Changed

- Release metadata and deployment history updated.

## [0.2.17] - 2026-07-03

### Changed

- Release metadata and deployment history updated.

## [0.2.16] - 2026-07-03

### Changed

- Release metadata and deployment history updated.

## [0.2.15] - 2026-07-03

### Changed

- Release metadata and deployment history updated.

## [0.2.14] - 2026-07-03

### Changed

- Release metadata and deployment history updated.

## [0.2.13] - 2026-07-03

### Changed

- Release metadata and deployment history updated.

## [0.2.12] - 2026-07-03

### Changed

- Release metadata and deployment history updated.

## [0.2.11] - 2026-07-02

### Changed

- Release metadata and deployment history updated.

## [0.2.10] - 2026-07-02

### Changed

- Release metadata and deployment history updated.

## [0.2.9] - 2026-07-02

### Changed

- Release metadata and deployment history updated.

## [0.2.8] - 2026-07-02

### Fixed

- fix(release): shrink Rust SDK crate package (eacaee8d26b2)

## [0.2.7] - 2026-07-02

### Fixed

- fix(release): keep Rust SDK build output untracked (424d8248b233)

## [0.2.6] - 2026-07-02

### Fixed

- fix(release): publish TreeDX SDK artifacts (276609ab14fd)

## [0.2.5] - 2026-07-02

### Fixed

- fix(release): declare dockerhub username variable (4d214b4b005e)

## [0.2.4] - 2026-07-02

### Fixed

- fix(release): publish plain semver tags (372518246667)

## [0.2.3] - 2026-07-02

### Tests

- test: clean treedx sdk verifier artifacts (6032881bafed)
- test: isolate audit event storage (59da210c4ca2)

## [0.2.2] - 2026-07-01

### Changed

- Release metadata and deployment history updated.

## [0.2.1] - 2026-07-01

### Changed

- Release metadata and deployment history updated.

## [0.2.0] - 2026-07-01

### Added

- feat(api): fix Railway IaC-only reconciliation and TreeDX env names (ab9d1a228d83)
- feat(config): fix staging deploy env, image-backed Railway services, (9a8a8e48f038)
- feat(source): fix staging CI deploy workflow and TreeDX advisory (988b364d78bc)

### Changed

- docs(docs): implement model-aware agent content tools (91068de5f1ec)
- Close ecommerce architecture criteria (148e84a8ad61)
- docs(docs): Save reconciliation platform and live acceptance updates (c295f4de1d4f)
- Removing the now completed SDK plan. (336f2ac665ed)
- Cleaning up the OpenAPI specification so it is only defined in YAML. (3067958c4914)

### Fixed

- fix(release): add SDK package testing to release gates (0868f9bebddf)
- ci(ci): fix scoped project domains for staging Pages (9a5f972cc9c8)
- fix(api): fix Railway IaC-only reconciliation and TreeDX env names (220e4d95bfdb)
- ci(ci): fix Railway staging Dockerfile builds and persistent volumes (dc0f41b01d64)
- ci(ci): fix staging Railway source builds and volumes (8b6b203fcfa2)
- fix(api): fix staging Railway source builds and volumes (106595c7fbeb)
- test(tests): fix stage verification cleanup issues (4f9e517a682b)
- fix(api): clean agent assignment runtime and remove provider api (21919a0b66ca)
- ci(ci): promotion checkpoint after API and TreeDX CI fixes (28023f8853cb)
- fix(config): clean capacity runtime storage and hosting manifests (bc55073aac0e)
- ci(ci): fix action preflight failures (3ef095f28fae)
- build(api): fix local release graph rehearsal preflight (6d269458f7ec)
- fix(config): environment registry coverage and service credential (3cce1af1f9f5)
- ci(ci): Fix workflow checks for non Node packages (ee48763affba)
- fix: avoid provider cli install in image workflows (1a28b6a88886)
- fix: build treedx images on native runners (9137ef9f29d1)
- fix: honor runtime TreeDX data dir (27d5a80f4d2d)
- fix(docker): avoid remote Dockerfile frontend during release (61177430a1d1)
- fix(docker): refresh TreeDX runtime image for mounted volumes (9631da7d2971)
- fix(docker): initialize mounted TreeDX data volumes (53c481246b61)

### Infrastructure

- ci(ci): restore TreeDX release gate Beam setup (a8978c40318f)
- ci(ci): promotion checkpoint for TreeDX CI environment and hosted gate (fe3d25b28412)
- docs(docs): update workflow documentation (fd38bd2a4873)
- ci(ci): Add recursive submodule checkout to package workflows (0bab55f9058f)
- ci(ci): Complete unified reconciliation switch dev save closure (88ae5c602dcc)
- ci: bootstrap TreeDX security scan tools (9e6faebe201e)
- ci(ci): stage package submodule restructuring (e85d57d11427)
- docs(docs): stage package submodule restructuring (0838383d22c6)
- ci: use staging environment for TreeDX dev images (7b6b5407f140)
- chore: declare TreeDX Treeseed package metadata (fc7577ed0ad3)
- ci: use synced Docker Hub config for TreeDX images (feb311efc683)
- ci: run TreeDX dev images outside production environment (1e2669673cb2)
- ci: gate secondary artifacts on TreeDX image publish (f3f63afb337b)
- ci: add staging TreeDX development image workflow (693f9ef833ce)
- ci: decouple TreeDX image publish from profiling (1de7bafff500)
- chore(release): prepare TreeDX 0.1.3 (05434366f810)

### Tests

- ci(docs): checkpoint before verify action and local dev stack validation (125dd9a12e0f)
- chore(docs): migrate scripts to tsx and TypeScript (d0ef72cd56cb)
- docs(api): security tightening and demo workflow checkpoint (5e6f2cdc92f7)
