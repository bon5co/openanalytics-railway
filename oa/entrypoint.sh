#!/bin/bash
# Open Analytics on Railway: one entrypoint, branch per role (OA_ROLE).
set -euo pipefail
ROLE="${OA_ROLE:?OA_ROLE is baked into the image}"
log() { echo "[oa-$ROLE] $*"; }
KEYDIR=/tmp/oa-keys

# wait_tcp host port [seconds]: block until the peer accepts a connection. A template deploy starts every
# service at once, and a peer's private name does not resolve until that peer is up.
wait_tcp() {
  local host="$1" port="$2" limit="${3:-600}" waited=0
  until timeout 3 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null; do
    if [ "$waited" -ge "$limit" ]; then log "gave up waiting for ${host}:${port}" >&2; exit 1; fi
    if [ $((waited % 30)) -eq 0 ]; then log "waiting for ${host}:${port}"; fi
    sleep 3; waited=$((waited + 3))
  done
}

# Railway variables hold a bare hostname for project-scoped URLs; peers are dialled on the private name.
need() { local n; for n in "$@"; do [ -n "${!n:-}" ] || { log "required variable $n is empty" >&2; exit 1; }; done; }

# Run the upstream process, optionally behind the identity-stripping nginx. Exits non-zero if either dies.
run_node() {
  local app_port="$1" front="$2"; shift 2
  export PORT="$app_port"
  if [ "$front" = "1" ]; then
    sed -e "s|__LISTEN_PORT__|${OA_PUBLIC_PORT}|g" -e "s|__APP_PORT__|${app_port}|g" /opt/oa/nginx.conf > /tmp/oa-nginx.conf
    nginx -t -c /tmp/oa-nginx.conf >/dev/null
    sh -c 'exec node "$APP_MAIN"' &
    local app_pid=$!
    nginx -c /tmp/oa-nginx.conf -g 'daemon off;' &
    local ngx_pid=$!
    trap 'kill "$app_pid" "$ngx_pid" 2>/dev/null || true' TERM INT
    wait -n "$app_pid" "$ngx_pid" || true
    log "a process exited; stopping container" >&2
    kill "$app_pid" "$ngx_pid" 2>/dev/null || true
    wait || true
    exit 1
  fi
  exec sh -c 'exec node "$APP_MAIN"'
}

# Railway injects PORT (8080) and the Railway healthcheck dials it, so the public edge port is the injected one.
export OA_PUBLIC_PORT="${PORT:-8080}"
export NODE_ENV=production ENVIRONMENT=production LOG_LEVEL="${LOG_LEVEL:-info}"
# Literal settings live here, not in the template: a literal template variable publishes as a required blank field.
: "${PRODUCT_NAME:=Open Analytics}"
: "${QUERY_SIGNING_KEY_ID:=oa-railway-1}"
: "${CLICKHOUSE_DB:=analytics}"
: "${CLICKHOUSE_DATABASE:=analytics}"
: "${CLICKHOUSE_INGEST_USER:=oa_ingest}"
: "${CLICKHOUSE_READ_USER:=oa_read}"
: "${CLICKHOUSE_MAINTENANCE_USER:=oa_maintenance}"
: "${CLICKHOUSE_MIGRATION_USER:=oa_migration}"
: "${ANONYMOUS_IDENTITY_KEY_VERSION:=1}"
: "${AUTH_PASSWORD_SIGNIN:=enabled}"
: "${AUTH_COOKIE_SAMESITE:=none}"
: "${EMAIL_FROM:=Open Analytics <analytics@localhost>}"
export PRODUCT_NAME QUERY_SIGNING_KEY_ID CLICKHOUSE_DB CLICKHOUSE_DATABASE CLICKHOUSE_INGEST_USER CLICKHOUSE_READ_USER \
  CLICKHOUSE_MAINTENANCE_USER CLICKHOUSE_MIGRATION_USER ANONYMOUS_IDENTITY_KEY_VERSION AUTH_PASSWORD_SIGNIN AUTH_COOKIE_SAMESITE EMAIL_FROM
# Peers publish their private names through project-scoped variables set in the template.
case "$ROLE" in
  migrate)
    need POSTGRES_MIGRATION_URL CLICKHOUSE_URL CLICKHOUSE_MIGRATION_PASSWORD
    pg_host="$(printf '%s' "$POSTGRES_MIGRATION_URL" | sed -E 's|^[a-z]+://[^@]*@([^:/]+).*|\1|')"
    ch_host="$(printf '%s' "$CLICKHOUSE_URL" | sed -E 's|^[a-z]+://([^:/]+).*|\1|')"
    wait_tcp "$pg_host" 5432
    wait_tcp "$ch_host" 8123
    cd /repo
    log "postgres migrations"
    node packages/postgres/dist/cli.js
    log "clickhouse migrations"
    node packages/clickhouse/dist/cli.js
    node packages/clickhouse/dist/cli.js backfill-15m --if-needed || log "backfill-15m failed; retried on next start" >&2
    node packages/clickhouse/dist/cli.js backfill-15m --sessions --if-needed || log "backfill-15m --sessions failed; retried on next start" >&2
    node apps/worker/dist/revenue/seed-15m-reroll.js --if-needed || log "seed-15m-reroll failed; retried on next start" >&2
    log "ready on ${OA_PUBLIC_PORT}"
    exec node -e "require('http').createServer((q,r)=>{r.end('ok')}).listen(+process.env.OA_PUBLIC_PORT)"
    ;;
  web) ;;
  *)
    need OA_MIGRATE_HOST
    wait_tcp "$OA_MIGRATE_HOST" "${OA_MIGRATE_PORT:-8080}"
    ;;
esac

cd /repo
case "$ROLE" in
  api)
    need OA_QUERY_SEED OA_REALTIME_SEED OA_KEYRING_SEED ADMIN_EMAIL ADMIN_PASSWORD
    node /opt/oa/keys.mjs "$KEYDIR" query-private realtime-private keyring
    export QUERY_SIGNING_PRIVATE_KEY_FILE="$KEYDIR/query.private.pem" REALTIME_TOKEN_SIGNING_KEY_FILE="$KEYDIR/realtime.private.pem" OA_CREDENTIAL_KEYRING_FILE="$KEYDIR/credential-keyring.json"
    # Claim the instance before the api listens: the first-run screen offers the first account to whoever asks first.
    log "admin bootstrap"
    node scripts/create-admin.mjs --email "$ADMIN_EMAIL" >/tmp/create-admin.log 2>&1 || true
    sed -E 's/(password[^:]*:[[:space:]]*).*/\1<redacted>/I' /tmp/create-admin.log | tail -12
    run_node 8082 1
    ;;
  gateway)
    need OA_QUERY_SEED
    node /opt/oa/keys.mjs "$KEYDIR" query-public
    export QUERY_SIGNING_PUBLIC_KEY_FILE="$KEYDIR/query.public.pem"
    run_node "${OA_PUBLIC_PORT}" 0
    ;;
  realtime)
    need OA_REALTIME_SEED
    node /opt/oa/keys.mjs "$KEYDIR" realtime-public
    export REALTIME_TOKEN_VERIFY_KEY_FILE="$KEYDIR/realtime.public.pem"
    run_node 8084 1
    ;;
  collector)
    run_node 8083 1
    ;;
  worker)
    need OA_KEYRING_SEED
    node /opt/oa/keys.mjs "$KEYDIR" keyring
    export OA_CREDENTIAL_KEYRING_FILE="$KEYDIR/credential-keyring.json"
    run_node "${OA_PUBLIC_PORT}" 0
    ;;
  web)
    # A project-scoped URL reference is a bare host that stays empty while the referenced service does not exist yet (the generate
    # project builds web before api). The upstream entrypoint refuses "https://", so boot on a placeholder; a real deploy always resolves.
    for v in NEXT_PUBLIC_API_URL NEXT_PUBLIC_REALTIME_URL NEXT_PUBLIC_COLLECTOR_URL; do
      case "${!v:-}" in "https://"|"http://") log "$v has no host yet; using a placeholder until the referenced service exists" >&2; export "$v=https://pending.invalid" ;; esac
    done
    export PORT="${OA_PUBLIC_PORT}"
    exec sh /repo/apps/web/docker-entrypoint.sh
    ;;
  *)
    log "unknown role" >&2; exit 1 ;;
esac
