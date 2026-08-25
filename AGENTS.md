# TreeDX workspace guidance

Preserve TreeDX as the canonical knowledge, Git mirror, index, and workspace service. Keep credentials opaque and bounded, and fail closed on moved refs or incomplete synchronization.

## Project library

Use `trsd library show treedx` and `status` before querying `treeseed-ai/treedx-library`. Read root-level paths at an exact commit. Author only through governed library workspaces and reviews. Never recreate `src/content` or edit `.treeseed/data` directly.
