#!/usr/bin/env bash
# scripts/smoke.sh — port-reachability smoke test.
#
# Checks that, after `make up`, the three user-visible surfaces respond:
#   * ttyd HTTP on :7681 (the omp TUI)
#   * chrome KasmVNC desktop on :3001 (watch the browser, HTTPS self-signed)
#   * chrome CDP endpoint, queried from inside the app container to verify the
#     compose-internal agent path.

set -euo pipefail

TTYD_PORT="${TTYD_PORT:-7681}"
CHROME_DESKTOP_PORT="${CHROME_DESKTOP_PORT:-3001}"

pass=0
fail=0

check() {
  local label="$1"
  local cmd="$2"
  printf '%-50s ' "$label"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "OK"
    pass=$((pass+1))
  else
    echo "FAIL"
    fail=$((fail+1))
  fi
}

check "ttyd responds on host :${TTYD_PORT}" \
  "curl -fsS --max-time 5 http://localhost:${TTYD_PORT}/"

check "chrome desktop responds on host :${CHROME_DESKTOP_PORT}" \
  "curl -fsSk --max-time 5 https://localhost:${CHROME_DESKTOP_PORT}/"

check "chrome CDP reachable from app container" \
  "docker compose -f docker-compose.dev.yml exec -T app curl -fsS --max-time 5 http://chrome:9222/json/version"

check "omp binary in app container" \
  "docker compose -f docker-compose.dev.yml exec -T app sh -c 'command -v omp >/dev/null 2>&1'"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
