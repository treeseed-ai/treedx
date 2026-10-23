#!/bin/sh
set -eu

data_dir="${TREEDX_DATA_DIR:-/var/lib/treedx}"

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$data_dir"
  chown -R 65532:65532 "$data_dir"
  exec setpriv --reuid=65532 --regid=65532 --clear-groups "$0" "$@"
fi

if [ "${1:-}" = "/app/bin/treedx_store_recover" ]; then
  # The offline command takes this same lock itself before its read-only plan.
  exec "$@"
fi

exec flock --exclusive --nonblock --no-fork "$data_dir/.treedx.lock" "$@"
