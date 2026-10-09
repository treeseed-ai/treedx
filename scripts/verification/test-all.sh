#!/usr/bin/env bash
set -euo pipefail

if [[ "${TREESEED_NATIVE_REPORT_FD:-}" != "3" ]]; then
  exec node ./scripts/verification/reporting/command.ts suite -- bash "$0"
fi

./scripts/verification/test-treedx-fast.sh
./scripts/verification/openapi-check.sh
./scripts/verification/storage-recovery-check.sh
./scripts/verification/test-sdk-packages.sh
(cd release && npm ci --ignore-scripts)
node ./scripts/verification/reporting/command.ts node -- node --test release/publication.test.mjs release/custody.test.mjs
node packages/ts-sdk/node_modules/typescript/bin/tsc -p scripts/verification/reporting/tsconfig.json
node ./scripts/verification/reporting/command.ts node -- node --test tests/reporting/*.test.ts
