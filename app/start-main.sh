#!/usr/bin/env bash
# start-main.sh — primary process supervisor for the pi container.
#
# Runs two long-lived processes: nginx (TLS ingress for pi-web/VNC, same
# netns as chrome) and pi-web (main UX; holds agent sessions server-side).
# Both are critical — if either exits, the whole container exits so compose
# can restart it.
#
# Closing the browser does not kill sessions (pi-web process keeps them).
# Stopping the container ends live sessions; ~/.pi JSONL can still be resumed.

set -euo pipefail

# pi-web must remain loopback-only; nginx is the sole public ingress.
WEBUI_HOST="127.0.0.1"
WEBUI_PORT="${PI_WEB_PORT:-${PI_WEBUI_PORT:-30141}}"
CERT_DIR="${TLS_CERT_DIR:-/etc/nginx/certs}"
INGRESS_DIR="${PCB_INGRESS_DIR:-/opt/pcb-ingress}"

validate_port() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

if ! validate_port "$WEBUI_PORT"; then
  echo "start-main: PI_WEB_PORT must be an integer from 1 to 65535" >&2
  exit 2
fi

# Extra args for pi-web (space-separated). Example: PI_WEB_EXTRA_ARGS="--no-open"
EXTRA=()
if [ -n "${PI_WEB_EXTRA_ARGS:-${PI_WEBUI_EXTRA_ARGS:-}}" ]; then
  # shellcheck disable=SC2206
  EXTRA=( ${PI_WEB_EXTRA_ARGS:-${PI_WEBUI_EXTRA_ARGS}} )
fi

# Never auto-open a browser inside the container (no display).
export PI_WEB_NO_OPEN=1

NGINX_PID="" PIWEB_PID=""

cleanup() {
  for p in "$PIWEB_PID" "$NGINX_PID"; do
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
      kill "$p" 2>/dev/null || true
      wait "$p" 2>/dev/null || true
    fi
  done
}
# Do NOT trap EXIT: bash runs EXIT before `exec`, which would kill children on handoff.
trap cleanup INT TERM

echo "start-main: ensuring TLS certificate in ${CERT_DIR}"
TLS_CERT_DIR="$CERT_DIR" /usr/local/bin/ensure-tls-cert.sh

sed \
  -e "s/__PI_WEB_PORT__/${WEBUI_PORT}/g" \
  "${INGRESS_DIR}/nginx.conf.template" > /etc/nginx/nginx.conf
mkdir -p /etc/nginx/templates
cp "${INGRESS_DIR}/widget.css" /etc/nginx/templates/widget.css
cp "${INGRESS_DIR}/widget.js.template" /etc/nginx/templates/widget.js

nginx -t
echo "start-main: starting nginx (TLS ingress on :8443)"
nginx -g 'daemon off;' &
NGINX_PID=$!
echo "start-main: nginx pid=${NGINX_PID}"

echo "start-main: starting pi-web on ${WEBUI_HOST}:${WEBUI_PORT}"
echo "start-main: open https://<host>:30141/  (main UX — @agegr/pi-web, via nginx TLS)"

# Pass --hostname/--port explicitly (do not rely on env HOSTNAME — Docker sets it
# to the container id, which would break bind-all-interfaces).
pi-web \
  --hostname "${WEBUI_HOST}" \
  --port "${WEBUI_PORT}" \
  --no-open \
  ${EXTRA[@]+"${EXTRA[@]}"} &
PIWEB_PID=$!
echo "start-main: pi-web pid=${PIWEB_PID}"

# nginx and pi-web are both critical: if either exits, tear everything down
# so compose (restart: unless-stopped) rebuilds the container.
wait -n "$NGINX_PID" "$PIWEB_PID"
echo "start-main: a critical process (nginx or pi-web) exited; shutting down" >&2
cleanup
exit 1
