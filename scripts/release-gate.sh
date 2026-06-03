#!/usr/bin/env bash
set -euo pipefail

./scripts/test-all.sh
./scripts/security-check.sh
./scripts/sdk-live-contract.sh
./scripts/federation-live-check.sh
