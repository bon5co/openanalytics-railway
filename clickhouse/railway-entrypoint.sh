#!/bin/bash
# Railway mounts the volume root-owned and with a lost+found directory that ClickHouse would read as a database.
set -eo pipefail
DATA_DIR=/var/lib/clickhouse
if [ -d "$DATA_DIR" ]; then
  rm -rf "$DATA_DIR/lost+found" || true
  [ "$(id -u)" = "0" ] && chown -R clickhouse:clickhouse "$DATA_DIR" || true
fi
# A sentinel user config left by a previous run would be re-rendered by the upstream entrypoint; nothing to clean.
exec bash /usr/local/bin/oa-entrypoint.sh "$@"
