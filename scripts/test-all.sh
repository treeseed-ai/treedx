#!/usr/bin/env bash
set -euo pipefail

./scripts/test-treedb-fast.sh
./scripts/openapi-check.sh
./scripts/storage-recovery-check.sh
