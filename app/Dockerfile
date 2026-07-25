# syntax=docker/dockerfile:1
###############################################################################
# pi-chrome-bot/pi (pi-web UI + native Pi + agent-browser)
#
# Key components:
#   - pi + pi-agent-browser-native (Pi package → agent_browser tool)
#   - agent-browser (global npm CLI and CDP engine)
#   - @agegr/pi-web (primary UX; standalone Next.js service via pi-web CLI)
#
# Global CLIs (pi, agent-browser, pi-web) install under NPM_CONFIG_PREFIX
# (/opt/npm-global). Compose mounts named volume `npm_global` there so
# `pi update --self` / `npm update -g` survive container recreates.
#
# Browser automation: CDP attach only → http://127.0.0.1:9222 (same netns
# direct connect — this container also runs nginx, terminating TLS on :8443
# for pi-web/Selkies; see network_mode: service:chrome).
###############################################################################

FROM debian:bookworm-slim

ARG NODE_VERSION=22.23.1
ARG PI_VERSION=0.82.0
ARG AGENT_BROWSER_VERSION=0.33.0
ARG PI_WEB_VERSION=0.8.0
ARG NPM_REGISTRY=""

ENV NODE_HOME=/opt/node \
    NPM_CONFIG_PREFIX=/opt/npm-global \
    PATH=/opt/npm-global/bin:/opt/node/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PI_SEED_DIR=/opt/pi-seed \
    NPM_CONFIG_UPDATE_NOTIFIER=false

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git nginx openssh-client openssl sqlite3 tini unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN ARCH=$(uname -m) \
    && case "$ARCH" in \
         x86_64)  NODE_ARCH=x64    ;; \
         aarch64) NODE_ARCH=arm64  ;; \
         *) echo "unsupported arch: $ARCH" >&2; exit 1 ;; \
       esac \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
         -o /tmp/node.tar.xz \
    && mkdir -p "$NODE_HOME" \
    && tar -xJf /tmp/node.tar.xz -C "$NODE_HOME" --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && node --version && npm --version

RUN if [ -n "$NPM_REGISTRY" ]; then \
      npm config set registry "$NPM_REGISTRY"; \
    fi

# Global CLIs → /opt/npm-global (volume-backed at runtime)
RUN mkdir -p "$NPM_CONFIG_PREFIX" \
    && for i in 1 2 3 4 5; do \
      if npm install -g --ignore-scripts \
           "@earendil-works/pi-coding-agent@${PI_VERSION}" \
           "agent-browser@${AGENT_BROWSER_VERSION}" \
           "@agegr/pi-web@${PI_WEB_VERSION}"; then \
        break; \
      fi; \
      echo "npm global install attempt $i of 5 failed, retrying in 5s..."; \
      [ "$i" -ge 5 ] && exit 1; \
      sleep 5; \
    done \
    && test -x "${NPM_CONFIG_PREFIX}/bin/pi" \
    && test -x "${NPM_CONFIG_PREFIX}/bin/agent-browser" \
    && test -x "${NPM_CONFIG_PREFIX}/bin/pi-web" \
    && pi --version \
    && agent-browser --version \
    # pi-web has no --version flag; it starts Next.js — only verify the binary
    # and that the published package includes prebuilt .next artifacts.
    && test -d "${NPM_CONFIG_PREFIX}/lib/node_modules/@agegr/pi-web/.next" \
    && npm cache clean --force

# Seed pi packages: only browser automation (pi-web is a standalone CLI, not a pi package)
RUN mkdir -p "${PI_SEED_DIR}/agent" \
    && PI_CODING_AGENT_DIR="${PI_SEED_DIR}/agent" \
         pi install "npm:pi-agent-browser-native" \
    && test -d "${PI_SEED_DIR}/agent/npm" \
    && test -f "${PI_SEED_DIR}/agent/settings.json" \
    && echo "seed tree:" \
    && find "${PI_SEED_DIR}/agent" -maxdepth 4 \( -type d -o -name 'package.json' -o -name 'settings.json' \) | head -80

COPY pi-config/ /opt/pi-config/
COPY ingress/nginx.conf.template ingress/widget.css ingress/widget.js.template /opt/pcb-ingress/
COPY scripts/ensure-tls-cert.sh /usr/local/bin/ensure-tls-cert.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY start-main.sh /usr/local/bin/start-main.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/start-main.sh /usr/local/bin/ensure-tls-cert.sh

# 8443 is this container's nginx TLS listener (pi-web/Selkies + widget).
# 30141/9222 are internal-only; the host port mapping actually
# lives on the `chrome` compose service, since pi runs with
# network_mode: service:chrome and shares its network namespace.
EXPOSE 8443

ENTRYPOINT ["/usr/bin/tini","--","/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/start-main.sh"]
