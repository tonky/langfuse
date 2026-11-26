#!/usr/bin/env bash
set -euo pipefail

if [ -n "${ENACT_COLLECT_ONLY:-}" ]; then
  exec "$ENACT_EXE" helper vitest --config vitest.server.config.mts \
    --arg=--project --arg=server \
    --arg=--project --arg=server-isolated \
    --arg=--project --arg=server-shared-source \
    --arg=--project --arg=e2e-server \
    "$@"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# `media.servertest.ts` asserts `DATABASE_URL.includes("localhost:5432")`.
if [ -n "${DATABASE_URL:-}" ]; then
  export DATABASE_URL="${DATABASE_URL//127.0.0.1/localhost}"
fi

LANGFUSE_SEED_DB=1 "$ROOT/.enact/scripts/prepare-dbs.sh"
psql "$DATABASE_URL" -qc "UPDATE projects SET name = 'Seed Project' WHERE id = '7a88fb47-b4e2-43b8-a06c-a5ce950dc53a';"

WORKER_LOG="/tmp/langfuse-api-worker-$$.log"
WEB_LOG="/tmp/langfuse-api-web-$$.log"
WORKER_PID=""
WEB_PID=""

kill_tree() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
}

kill_tree_force() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  local rc=$?
  kill_tree "$WEB_PID"
  kill_tree "$WORKER_PID"
  sleep 1
  kill_tree_force "$WEB_PID"
  kill_tree_force "$WORKER_PID"
  rm -f "$WORKER_LOG" "$WEB_LOG"
  exit "$rc"
}
trap cleanup EXIT INT TERM

setsid bash -c 'cd "$1/worker" && exec pnpm exec dotenv -e ../.env -- node dist/index.js' _ "$ROOT" </dev/null >"$WORKER_LOG" 2>&1 &
WORKER_PID=$!

setsid bash -c 'cd "$1/web" && exec pnpm exec dotenv -e ../.env -- env NEXT_MANUAL_SIG_HANDLE=true next start -H 127.0.0.1 -p 3000' _ "$ROOT" </dev/null >"$WEB_LOG" 2>&1 &
WEB_PID=$!

wait_health() {
  local name="$1"
  local url="$2"
  local log="$3"
  local pid="$4"
  local i
  for i in $(seq 1 90); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$name exited early before becoming healthy" >&2
      tail -n 100 "$log" >&2 || true
      return 1
    fi
    sleep 1
  done
  echo "$name did not become healthy at $url within 90s" >&2
  tail -n 100 "$log" >&2 || true
  return 1
}

wait_health "worker" "http://127.0.0.1:3030/api/health" "$WORKER_LOG" "$WORKER_PID"
wait_health "web" "http://127.0.0.1:3000/api/public/health" "$WEB_LOG" "$WEB_PID"

"$ENACT_EXE" helper vitest --config vitest.server.config.mts \
  --arg=--project --arg=server \
  --arg=--project --arg=server-isolated \
  --arg=--project --arg=server-shared-source \
  --arg=--project --arg=e2e-server \
  "$@"
