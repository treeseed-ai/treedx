# TreeDX workspace guidance

Preserve TreeDX as the canonical knowledge, Git mirror, index, and workspace service. Keep credentials opaque and bounded, and fail closed on moved refs or incomplete synchronization.

## Branch and deployment boundary

`main` is the only production branch and maps only to the `production` deployment environment. `staging` is the only development-integration branch and maps only to the `staging` deployment environment. Short-lived pull-request branches may validate without deploying, but they must never define another deployment environment. Do not create or use `development`, `preview`, `stable`, or any other GitHub deployment environment; preview deployments are prohibited. Release tags may promote an exact reviewed `staging` commit to `production` without creating another branch or environment. Artifact channel names must never become GitHub deployment environments.

## Project library

Use `trsd library show treedx` and `status` before querying `treeseed-ai/treedx-library`. Read root-level paths at an exact commit. Author only through governed library workspaces and reviews. Never recreate `src/content` or edit `.treeseed/data` directly.
