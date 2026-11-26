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

LANGFUSE_SEED_DB=1 "$ROOT/.enact/scripts/prepare-dbs.sh"

WORKER_LOG="/tmp/langfuse-api-worker-$$.log"
WEB_LOG="/tmp/langfuse-api-web-$$.log"
WORKER_PID=""
WEB_PID=""

cleanup() {
  local rc=$?
  if [ -n "$WEB_PID" ]; then
    kill "$WEB_PID" 2>/dev/null || true
    wait "$WEB_PID" 2>/dev/null || true
  fi
  if [ -n "$WORKER_PID" ]; then
    kill "$WORKER_PID" 2>/dev/null || true
    wait "$WORKER_PID" 2>/dev/null || true
  fi
  rm -f "$WORKER_LOG" "$WEB_LOG"
  exit "$rc"
}
trap cleanup EXIT INT TERM

(
  cd "$ROOT/worker"
  exec pnpm exec dotenv -e ../.env -- node dist/index.js
) >"$WORKER_LOG" 2>&1 &
WORKER_PID=$!

(
  cd "$ROOT/web"
  exec pnpm exec dotenv -e ../.env -- env NEXT_MANUAL_SIG_HANDLE=true next start -H 127.0.0.1 -p 3000
) >"$WEB_LOG" 2>&1 &
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
