#!/usr/bin/env bash
# scripts/smoke.sh — pi-web primary stack smoke test.
#
# Surfaces:
#   * HTTPS pi-web + embedded Selkies on :30141
#   * CDP from pi container
#   * binaries + AGENTS.md seed
#   * soft: agent-browser CDP attach forms

set -euo pipefail

WEBUI_PORT="${WEBUI_PORT:-30141}"
COMPOSE="${COMPOSE:-docker compose -f docker-compose.dev.yml}"
CDP_URL="http://127.0.0.1:9222"

pass=0
fail=0

check() {
  local label="$1" cmd="$2"
  printf '%-56s ' "$label"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "OK"; pass=$((pass+1))
  else
    echo "FAIL"; fail=$((fail+1))
  fi
}

check_soft() {
  local label="$1" cmd="$2"
  printf '%-56s ' "$label"
  if eval "$cmd" >/dev/null 2>&1; then
    echo "OK"; pass=$((pass+1))
  else
    echo "SKIP/FAIL (non-fatal)"
  fi
}

check "HTTPS pi-web responds on host :${WEBUI_PORT}" \
  "curl -fskS --max-time 8 https://localhost:${WEBUI_PORT}/"

check "same-origin Selkies responds under pi-web" \
  "curl -fskS --max-time 5 https://localhost:${WEBUI_PORT}/__pcb/vnc/"

check "chrome CDP reachable from pi container" \
  "${COMPOSE} exec -T pi curl -fsS --max-time 5 ${CDP_URL}/json/version"

check "pi binary in pi container" \
  "${COMPOSE} exec -T pi sh -c 'command -v pi >/dev/null 2>&1'"

check "pi-web binary in pi container" \
  "${COMPOSE} exec -T pi sh -c 'command -v pi-web >/dev/null 2>&1'"

check "agent-browser binary in pi container" \
  "${COMPOSE} exec -T pi sh -c 'command -v agent-browser >/dev/null 2>&1'"

check "AGENTS.md seeded under ~/.pi/agent" \
  "${COMPOSE} exec -T pi sh -c 'test -f /root/.pi/agent/AGENTS.md'"

check_soft "agent-browser --cdp http URL (preferred)" \
  "${COMPOSE} exec -T pi sh -c 'agent-browser --cdp ${CDP_URL} get url'"

check_soft "agent-browser connect http URL" \
  "${COMPOSE} exec -T pi sh -c 'agent-browser connect ${CDP_URL} >/dev/null && agent-browser get url'"

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
