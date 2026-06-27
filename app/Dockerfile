# syntax=docker/dockerfile:1
###############################################################################
# pi-chrome-bot/app
#
# Installs omp from npm (@oh-my-pi/pi-coding-agent). @oh-my-pi/pi-natives is a
# dependency of the coding-agent; it declares per-platform optionalDependencies
# (@oh-my-pi/pi-natives-linux-x64 / -linux-arm64 / ...) that ship a prebuilt
# .node N-API addon — so no Rust toolchain and no native compile.
# First build is ~1-2 min (downloads omp + prebuilt natives + ~240 deps).
#
# Adds:
#   - ttyd binary — serves omp's TUI over HTTP/WebSocket on :7681
#   - entrypoint.sh — sanity checks + startup diagnostics
#
# omp provider credentials are NOT baked in or env-injected. The user runs
# /login in the TUI once; omp persists them to ~/.omp/agent/agent.db under the
# ./data/app:/root volume and survives restarts. AGENTS.md / RULES.md are
# COPYed to /opt/omp-config and seeded into ~/.omp/agent/ by entrypoint.sh on
# each boot.
#
# Update omp: bump OMP_VERSION and rebuild, or `docker compose exec app omp update`.
###############################################################################

FROM debian:bookworm-slim

ARG BUN_VERSION
ARG OMP_VERSION
ARG TTYD_VERSION

# Mirror the upstream pi-base layout: bun lives under /opt/bun and global bins
# (omp) land in /opt/bun/bin. PATH also carries /usr/local/bin (ttyd) and the
# system path (tini, git, ...).
ENV BUN_INSTALL=/opt/bun \
    PATH=/opt/bun/bin:/usr/local/bin:/usr/bin:/bin

# Runtime deps. libssl3 is the TLS lib the prebuilt .node may link (debian-slim
# doesn't ship it). omp's tools use git (repo ops), sqlite3 (inspect agent.db),
# openssh-client (git over SSH), ca-certificates (TLS), curl (smoke test),
# unzip, and tini (PID 1).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git ca-certificates libssl3 sqlite3 openssh-client curl unzip tini \
    && rm -rf /var/lib/apt/lists/*

# Bun runtime — omp's coding-agent CLI is TypeScript executed via bun.
# The official install script honors a pre-set BUN_INSTALL, so bun lands in
# /opt/bun (matching the layout above) rather than the default ~/.bun.
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
    && bun --version

# omp from npm. bun's global bin creates an `omp` shim that runs the CLI via
# bun. @oh-my-pi/pi-natives pulls the matching prebuilt platform optional dep
# (a .node N-API addon) — no Rust compile. `omp --version` is a load-time
# smoke check: it forces the natives addon to dlopen, so a missing system
# lib or arch mismatch fails the build here instead of at runtime.
#
# Transient integrity/extraction failures happen when reaching
# registry.npmjs.org over a flaky link (common in mainland China). Two defenses:
#   1. NPM_REGISTRY — optional mirror written to bunfig.toml. From China:
#        --build-arg NPM_REGISTRY=https://registry.npmmirror.com
#   2. Retry loop — bun caches resolved packages, so later attempts are cheaper.
ARG NPM_REGISTRY=""
# Install omp, then (in the SAME RUN layer) strip the speech-input chain so the
# removed files never enter a lower image layer (a separate rm RUN would leave
# the 813 MB install layer intact and shrink nothing). omp loads speech via
# dynamic import() inside try/catch, so removal only disables the TUI "talk
# instead of type" feature — core CLI, /login, and every tool (incl. browser)
# are unaffected. Verified: omp --version + browser tool work post-strip.
# The speech chain is removed unconditionally: this stack runs omp under ttyd,
# which only tunnels terminal I/O (no audio), and the container has no mic
# device or recorder binary — so omp's mic→text input cannot work here anyway.
# (The functional code lives inside omp's bundled cli.js as a lazy module and
# can't be removed; only its npm deps are stripped.)
RUN if [ -n "$NPM_REGISTRY" ]; then \
      printf '[install]\nregistry = "%s"\n' "$NPM_REGISTRY" > "$HOME/.bunfig.toml"; \
    fi \
    && for i in 1 2 3 4 5; do \
      if bun install -g @oh-my-pi/pi-coding-agent@${OMP_VERSION}; then break; fi; \
      echo "omp install attempt $i of 5 failed, retrying in 5s..."; \
      [ "$i" -ge 5 ] && exit 1; \
      sleep 5; \
    done \
    && rm -rf \
      /opt/bun/install/global/node_modules/onnxruntime-node \
      /opt/bun/install/global/node_modules/onnxruntime-web \
      /opt/bun/install/global/node_modules/onnxruntime-common \
      /opt/bun/install/global/node_modules/@huggingface/transformers \
      /opt/bun/install/global/node_modules/sherpa-onnx-node \
      /opt/bun/install/global/node_modules/sherpa-onnx-linux-* \
    && rm -rf /opt/bun/install/cache \
    && omp --version

# ttyd — serves the omp TUI over HTTP/WebSocket on :7681.
RUN ARCH=$(uname -m) \
    && case "$ARCH" in \
         aarch64) TTYD_ARCH=aarch64 ;; \
         x86_64)  TTYD_ARCH=x86_64  ;; \
         *) echo "unsupported arch: $ARCH" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" \
         -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd \
    && ttyd --version

# Bake AGENTS.md / RULES.md into the image; entrypoint.sh seeds ~/.omp/agent/
# from /opt/omp-config on each boot so the files survive a volume wipe.
COPY omp-config/ /opt/omp-config/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 7681

# tini as PID 1 for proper signal handling; entrypoint runs diagnostics then
# execs the CMD (ttyd --writable omp).
ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/entrypoint.sh"]
CMD ["ttyd","--writable","omp"]
