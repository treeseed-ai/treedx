#!/usr/bin/env bash
set -euo pipefail

./scripts/test-treedx-fast.sh
./scripts/mvp-smoke.sh
