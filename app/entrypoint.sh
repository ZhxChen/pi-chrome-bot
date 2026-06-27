#!/usr/bin/env bash
# entrypoint.sh — wraps ttyd (which runs omp) so we can sanity-check the
# environment and print useful diagnostics before handing off.
#
# Exits nonzero with a clear message on misconfiguration; otherwise execs
# the command passed in (the CMD from the Dockerfile).

set -euo pipefail

# 1) Sanity: omp binary is present.
if ! command -v omp >/dev/null 2>&1; then
  echo "entrypoint: \`omp\` binary missing from PATH" >&2
  exit 127
fi

# 2) Sanity: ttyd binary is present.
if ! command -v ttyd >/dev/null 2>&1; then
  echo "entrypoint: \`ttyd\` binary missing from PATH" >&2
  exit 127
fi

# 3) Seed omp context files from the baked-in omp-config/ directory.
#    /opt/omp-config is COPYed into the image at build time (see Dockerfile).
#    We copy *.md into ~/.omp/agent/ on every boot so the files are always
#    current even after a persistent volume wipe. To update these files, edit
#    app/omp-config/*.md and rebuild the image (make build).
OMP_AGENT_DIR="${HOME}/.omp/agent"
OMP_CONFIG_SRC="/opt/omp-config"
if [ -d "$OMP_CONFIG_SRC" ]; then
  mkdir -p "$OMP_AGENT_DIR"
  for src in "$OMP_CONFIG_SRC"/*.md; do
    [ -e "$src" ] || continue
    dest="$OMP_AGENT_DIR/$(basename "$src")"
    cp "$src" "$dest"
    echo "entrypoint: refreshed $(basename "$src")"
  done
fi

# 4) If a CDP target is configured, surface it in the log so users know which
#    chrome the agent will talk to. The LLM passes it via the browser tool's
#    `app.cdp_url` argument on each call.
if [ -n "${PI_DEFAULT_BROWSER_CDP:-}" ]; then
  echo "entrypoint: agent should target Chrome CDP at ${PI_DEFAULT_BROWSER_CDP}"
fi

# 5) Brief version banner — useful for `docker compose logs app` debugging.
echo "entrypoint: omp    $(omp --version 2>&1 | head -1 || true)"
echo "entrypoint: ttyd   $(ttyd --version 2>&1 | head -1 || true)"

# 6) Provider credentials are NOT injected via environment variables in this
#    stack. omp's ~/.omp/agent/ directory (including agent.db, which holds
#    /login credentials) is persisted by the ./data/app:/root volume, so a
#    single /login in the TUI survives restarts. Built-in providers (e.g.
#    xiaomi-token-plan-cn) become available once authenticated.
if ! [ -f "${HOME}/.omp/agent/agent.db" ]; then
  echo "entrypoint: no stored credentials yet — run /login in the TUI to authenticate a provider"
fi

exec "$@"
