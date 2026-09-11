# TreeDX workspace guidance

Preserve TreeDX as the canonical knowledge, Git mirror, index, and workspace service. Keep credentials opaque and bounded, and fail closed on moved refs or incomplete synchronization.

## Required implementation languages

TreeDX uses Elixir for its API and service orchestration and Rust for native storage, Git, graph, and search components. These are required project languages, not exceptions that need repeated approval. Implement fixes and regression tests in the owning language; do not move existing engines into TypeScript or introduce a duplicate runtime to satisfy another repository's language guidance. TypeScript remains appropriate for the existing TypeScript SDK and its tooling; JavaScript is generated output there. Preserve independent builds and the language-specific formatting and test gates.

## Branch and deployment boundary

`main` is the only production branch and maps only to the `production` deployment environment. `staging` is the only development-integration branch and maps only to the `staging` deployment environment. Short-lived pull-request branches may validate without deploying, but they must never define another deployment environment. Do not create or use `development`, `preview`, `stable`, or any other GitHub deployment environment; preview deployments are prohibited. Release tags may promote an exact reviewed `staging` commit to `production` without creating another branch or environment. Artifact channel names must never become GitHub deployment environments.

## Project library

Use `trsd library show treedx` and `status` before querying `treeseed-ai/treedx-library`. Read root-level paths at an exact commit. Author only through governed library workspaces and reviews. Never recreate `src/content` or edit `.treeseed/data` directly.
