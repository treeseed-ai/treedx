#!/usr/bin/env bash
set -euo pipefail

./scripts/verification/test-treedx-fast.sh
./scripts/verification/openapi-check.sh
./scripts/verification/storage-recovery-check.sh
