#!/usr/bin/env bash
# entrypoint.sh — seed ~/.pi/agent + diagnostics, then exec CMD (start-main → pi-web).

set -euo pipefail

PI_SEED_DIR="${PI_SEED_DIR:-/opt/pi-seed}"
PI_CONFIG_SRC="${PI_CONFIG_SRC:-/opt/pi-config}"
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
CDP_URL="http://127.0.0.1:9222"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "entrypoint: \`$1\` binary missing from PATH" >&2
    exit 127
  fi
}

if [ -n "${NPM_CONFIG_PREFIX:-}" ]; then
  mkdir -p "${NPM_CONFIG_PREFIX}/bin"
  export PATH="${NPM_CONFIG_PREFIX}/bin:${PATH}"
  echo "entrypoint: npm global prefix ${NPM_CONFIG_PREFIX} (volume-backed CLIs)"
fi

need pi
need agent-browser
need pi-web

mkdir -p "$PI_AGENT_DIR"

if [ -d "$PI_CONFIG_SRC" ]; then
  for src in "$PI_CONFIG_SRC"/*; do
    [ -e "$src" ] || continue
    base="$(basename "$src")"
    dest="$PI_AGENT_DIR/$base"
    case "$base" in
      AGENTS.md|SYSTEM.md|APPEND_SYSTEM.md)
        cp "$src" "$dest"
        echo "entrypoint: refreshed $base"
        ;;
      settings.json) : ;;
      *)
        if [ ! -e "$dest" ]; then
          cp -a "$src" "$dest"
          echo "entrypoint: seeded $base"
        fi
        ;;
    esac
  done
fi

seed_settings="${PI_SEED_DIR}/agent/settings.json"
cfg_settings="${PI_CONFIG_SRC}/settings.json"
dest_settings="${PI_AGENT_DIR}/settings.json"

# Pi packages this deployment always provides (tools: agent_browser, schedule_prompt).
REQUIRED_PI_PACKAGES="pi-agent-browser-native pi-schedule-prompt"

# Ensure the required packages are listed without overriding user-selected versions.
sync_settings_packages() {
  local file="$1"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const required = process.argv[2].split(/\s+/).filter(Boolean);
    let s = {};
    try { s = JSON.parse(fs.readFileSync(path, "utf8")); } catch { s = {}; }
    if (!Array.isArray(s.packages)) s.packages = [];

    const srcOf = (p) => (typeof p === "string" ? p : (p && p.source) || "");

    const obsolete = ["pi-package-webui", "@firstpick/pi-package-webui"];
    const before = s.packages.length;
    s.packages = s.packages.filter((p) => !obsolete.some((name) => srcOf(p).includes(name)));
    if (s.packages.length !== before) {
      console.log("entrypoint: removed obsolete firstpick webui package entries from settings.json");
    }

    for (const name of required) {
      if (s.packages.some((p) => srcOf(p).includes(name))) {
        console.log(`entrypoint: keeping user-selected ${name} package entry`);
      } else {
        s.packages.push(`npm:${name}`);
        console.log(`entrypoint: added ${name} to settings.json packages[]`);
      }
    }

    fs.writeFileSync(path, JSON.stringify(s, null, 2) + "\n");
  ' "$file" "$REQUIRED_PI_PACKAGES"
}

if [ ! -f "$dest_settings" ]; then
  if [ -f "$seed_settings" ]; then
    cp "$seed_settings" "$dest_settings"
    echo "entrypoint: seeded settings.json from image seed"
  elif [ -f "$cfg_settings" ]; then
    cp "$cfg_settings" "$dest_settings"
    echo "entrypoint: seeded settings.json from /opt/pi-config"
  else
    printf '%s\n' "{}" > "$dest_settings"
    echo "entrypoint: created empty settings.json"
  fi
fi
sync_settings_packages "$dest_settings"

seed_npm="${PI_SEED_DIR}/agent/npm"
dest_npm="${PI_AGENT_DIR}/npm"
if [ -d "$seed_npm" ]; then
  mkdir -p "$dest_npm"
  for pkg_dir in "$seed_npm"/*; do
    [ -e "$pkg_dir" ] || continue
    name="$(basename "$pkg_dir")"
    if [ ! -e "${dest_npm}/${name}" ]; then
      cp -a "$pkg_dir" "${dest_npm}/${name}"
      echo "entrypoint: seeded npm package tree: ${name}"
    else
      echo "entrypoint: keeping existing npm package tree: ${name}"
    fi
  done
fi

pi_package_present() {
  local name="$1"
  find "$dest_npm" -type f -name 'package.json' 2>/dev/null \
    | xargs grep -l "\"name\"[[:space:]]*:[[:space:]]*\"${name}\"" >/dev/null 2>&1
}

# agent_browser ships its runtime as a bundled extension; accept either marker.
if find "$PI_AGENT_DIR" -type f -path '*/dist/extensions/agent-browser/index.js' 2>/dev/null | grep -q .; then
  browser_prebuilt=1
else
  browser_prebuilt=0
fi

for pkg in $REQUIRED_PI_PACKAGES; do
  if [ "$pkg" = "pi-agent-browser-native" ] && [ "$browser_prebuilt" -eq 1 ]; then
    continue
  fi
  if pi_package_present "$pkg"; then
    continue
  fi
  echo "entrypoint: installing missing ${pkg} (needs network)"
  PI_CODING_AGENT_DIR="$PI_AGENT_DIR" \
    pi install "npm:${pkg}" || \
    echo "entrypoint: WARNING: ${pkg} install failed" >&2
done

if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 3 "${CDP_URL}/json/version" >/dev/null 2>&1; then
    echo "entrypoint: CDP probe reached 127.0.0.1:9222"
  else
    echo "entrypoint: CDP probe failed on 127.0.0.1:9222 (chrome may still be starting)"
  fi
fi

echo "entrypoint: main UX     pi-web  https://<host>:30141/  (via nginx TLS in this container)"
echo "entrypoint: CDP target  ${CDP_URL}"
echo "entrypoint: agent tools agent_browser (pi-agent-browser-native), schedule_prompt (pi-schedule-prompt)"

echo "entrypoint: pi              $(pi --version 2>&1 | head -1 || true)"
# pi-web has no --version; print package.json version if present
if [ -f "${NPM_CONFIG_PREFIX:-/opt/npm-global}/lib/node_modules/@agegr/pi-web/package.json" ]; then
  echo "entrypoint: pi-web          $(node -p "require('${NPM_CONFIG_PREFIX:-/opt/npm-global}/lib/node_modules/@agegr/pi-web/package.json').version" 2>/dev/null || echo present)"
else
  echo "entrypoint: pi-web          $(command -v pi-web)"
fi
echo "entrypoint: agent-browser   $(agent-browser --version 2>&1 | head -1 || true)"
echo "entrypoint: node            $(node --version 2>&1 | head -1 || true)"

auth_hint=1
for candidate in \
  "${PI_AGENT_DIR}/auth.json" \
  "${HOME}/.pi/agent/auth.json" \
  "${HOME}/.pi/auth.json"
do
  if [ -f "$candidate" ]; then auth_hint=0; break; fi
done
if [ -d "${PI_AGENT_DIR}/sessions" ] && [ -n "$(ls -A "${PI_AGENT_DIR}/sessions" 2>/dev/null || true)" ]; then
  auth_hint=0
fi
if [ "$auth_hint" -eq 1 ]; then
  echo "entrypoint: no credentials yet — configure provider in pi-web (Models/Auth)"
fi

exec "$@"
