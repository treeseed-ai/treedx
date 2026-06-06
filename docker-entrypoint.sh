#!/bin/sh
set -eu

data_dir="${TREEDX_DATA_DIR:-/var/lib/treedx}"

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$data_dir"
  chown -R 65532:65532 "$data_dir"
  exec setpriv --reuid=65532 --regid=65532 --clear-groups "$@"
fi

exec "$@"
