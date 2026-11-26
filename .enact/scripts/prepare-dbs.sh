#!/usr/bin/env bash
set -euo pipefail

if [ -n "${ENACT_COLLECT_ONLY:-}" ]; then
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PG_PORT="${ENVE_SERVICE_POSTGRES_PORT:?missing ENVE_SERVICE_POSTGRES_PORT}"
CH_PORT="${ENVE_SERVICE_CLICKHOUSE_PORT:?missing ENVE_SERVICE_CLICKHOUSE_PORT}"
S3_PORT="${ENVE_SERVICE_SEAWEEDFS_PORT:?missing ENVE_SERVICE_SEAWEEDFS_PORT}"

LOCK_DIR="/tmp/enact-prep-dbs-${PG_PORT}-${CH_PORT}-${S3_PORT}"

is_db_ready() {
  if [ "${LANGFUSE_SEED_DB:-0}" = "1" ]; then
    psql "$DATABASE_URL" -Atqc "SELECT 1 FROM projects WHERE id = '7a88fb47-b4e2-43b8-a06c-a5ce950dc53a' LIMIT 1" 2>/dev/null | grep -qx "1"
  else
    psql "$DATABASE_URL" -Atqc "SELECT to_regclass('public.datasets') IS NOT NULL" 2>/dev/null | grep -qx "t"
  fi
}

if is_db_ready; then
  exit 0
fi

while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  if is_db_ready; then
    exit 0
  fi
  sleep 0.2
done
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

if is_db_ready; then
  exit 0
fi

# Create SeaweedFS bucket in parallel with DB setup.
(
  for _ in $(seq 1 30); do
    if curl -fsS -o /dev/null "http://127.0.0.1:${S3_PORT}/" 2>/dev/null || curl -sS -o /dev/null "http://127.0.0.1:${S3_PORT}/langfuse" 2>/dev/null; then
      break
    fi
    sleep 0.5
  done
  curl -fsS -X PUT "http://127.0.0.1:${S3_PORT}/langfuse" >/dev/null || true
) &
S3_PID=$!

# Run ClickHouse migrations + dev-tables in parallel with Postgres migrate/seed!
(
  pnpm --filter @langfuse/shared run ch:up
  pnpm --filter @langfuse/shared run ch:dev-tables
) &
CH_PID=$!

export DIRECT_URL="${DIRECT_URL:-$DATABASE_URL}"
export SHADOW_DATABASE_URL="postgresql://postgres@127.0.0.1:${PG_PORT}/postgres_shadow"

TEMPLATE_DIR="$ROOT/.enact/state/db-template"
if [ "${LANGFUSE_SEED_DB:-0}" = "1" ]; then
  TEMPLATE_SQL="$TEMPLATE_DIR/pg-seeded.sql"
else
  TEMPLATE_SQL="$TEMPLATE_DIR/pg-migrated.sql"
fi

if [ -s "$TEMPLATE_SQL" ] && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$TEMPLATE_SQL" >/dev/null 2>&1; then
  :
else
  pnpm --filter @langfuse/shared exec prisma migrate deploy
  if [ "${LANGFUSE_SEED_DB:-0}" = "1" ]; then
    pnpm --filter @langfuse/shared run db:seed
  fi
  mkdir -p "$TEMPLATE_DIR"
  pg_dump "$DATABASE_URL" --no-owner --no-privileges --clean --if-exists > "$TEMPLATE_SQL.tmp" 2>/dev/null \
    && mv "$TEMPLATE_SQL.tmp" "$TEMPLATE_SQL" || rm -f "$TEMPLATE_SQL.tmp"
fi

wait "$CH_PID"
wait "$S3_PID"

if [ "${LANGFUSE_SEED_EXAMPLES:-0}" = "1" ]; then
  pnpm --filter @langfuse/shared run db:seed:examples
fi
