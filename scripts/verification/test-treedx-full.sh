#!/usr/bin/env bash
set -euo pipefail

./scripts/verification/test-treedx-fast.sh
./scripts/acceptance/mvp-smoke.sh
