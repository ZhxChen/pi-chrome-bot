# pi-chrome-bot

A Docker Compose stack that pairs the **[oh-my-pi](https://github.com/can1357/oh-my-pi) (omp)** AI coding agent with a live **Chromium** browser. The agent controls Chrome via the Chrome DevTools Protocol (CDP) while you watch every action in real time through a browser-based desktop.

```
Browser tab A → http://<host>:7681    omp TUI (chat with the agent)
Browser tab B → https://<host>:3001  live Chromium desktop (self-signed HTTPS)
```

> Replace `<host>` with `localhost` if running locally, or with your server's IP / hostname for remote access.

## Quick deploy (pre-built image)

No need to clone the repository. Create a directory, download [`docker-compose.yml`](docker-compose.yml), and start:

```bash
# Create a working directory
mkdir pi-chrome-bot && cd pi-chrome-bot

# Download the compose file
curl -fsSL -O https://raw.githubusercontent.com/ZhxChen/pi-chrome-bot/main/docker-compose.yml

# Pull images and start all services
docker compose up -d
```

Then open `http://<host>:7681`, run `/login` inside the TUI to configure your LLM provider, and start chatting with the agent.

| URL | What you get |
|-----|--------------|
| `http://<host>:7681` | omp TUI (chat with the agent) |
| `https://<host>:3001` | Live Chromium desktop (HTTPS, self-signed; accept the cert warning on first visit) |

**Requirements:** Docker with Compose ≥ 2.23.0. The app image is pulled from `ghcr.io/zhxchen/pi-chrome-bot:latest`.

To update to the latest version:

```bash
docker compose pull && docker compose up -d
```

---

## Architecture

```
host
├─ :7681  ─►  app container
│              ├─ ttyd  (terminal over HTTP/WebSocket)
│              │   └─ tmux client → tmux server (session `webterm`)
│              │        └─ omp   (AI agent TUI)
│              │             └─ browser tool (Puppeteer-core, CDP)
│              │                    │
└─ :3001  ─►  chrome container (linuxserver/chromium)
               ├─ KasmVNC web desktop  (:3001, HTTPS)
               ├─ Chromium DevTools    (:9221 on [::1] only)  ◄──┐
               └─ cdp-proxy sidecar   (:9222 on 0.0.0.0)  ───────┘
                  nginx reverse-proxy with Host rewriting and
                  JSON body rewriting for Puppeteer compatibility
```

The `cdp-proxy` sidecar is necessary because Chromium 144+ forces DevTools to bind only on loopback (`[::1]:9221`) and validates the HTTP `Host` header. The proxy shares Chrome's network namespace, rewrites headers and response bodies, and re-exposes CDP at `0.0.0.0:9222` so the agent container can reach it.

omp runs inside a persistent tmux session (`webterm`) rather than as ttyd's direct child — closing the browser tab does **not** kill the agent. ttyd's child is just the tmux client; omp keeps running under the separate tmux server and the next browser connection re-attaches to the same session. Inside the TUI, `Ctrl-b c` opens a shell window and `Ctrl-b d` detaches (equivalent to closing the tab).

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) with Compose v2
- `make`

## Quick start

```bash
# 1. Build the app image (downloads omp from npm, ~1-2 min, image ~700 MB)
make build

# 2. Start all services
make up

# 3. Open the agent TUI in your browser
open http://<host>:7681

# 4. Open the live Chrome desktop in another tab (optional)
open https://<host>:3001
```

### First-time login

Provider credentials are **not** baked into the image. Run `/login` once inside the TUI to authenticate your LLM provider:

```
/login
```

omp saves the credentials to `./data/app` (a bind-mounted volume) and restores them automatically on restart. To change the active model, use `/model`.

## Usage

Once logged in, tell the agent what to do — it will control the Chromium browser you see at `https://<host>:3001`. Examples:

```
Search for "Docker multi-arch builds" on Google and summarise the top 3 results.
Go to github.com/can1357/oh-my-pi and tell me the latest release version.
```

The agent always attaches to the running browser; it does not launch a separate headless instance.

## Make targets

| Command | Description |
|---------|-------------|
| `make build` | Build the app image |
| `make up` | Start all services (`-d`) |
| `make down` | Stop all services |
| `make logs` | Tail logs from all services |
| `make ps` | Show running containers |
| `make shell` | Open a shell inside the app container |
| `make smoke` | Port-reachability smoke test (output in `tmp/smoke.log`) |
| `make clean` | Stop services, remove volumes, delete the app image |

## Configuration

All settings live in `docker-compose.dev.yml`. No `.env` file is required.

| Setting | Default | Where |
|---------|---------|-------|
| omp version | `16.3.0` | `build.args.OMP_VERSION` |
| Bun version | `1.3.14` | `build.args.BUN_VERSION` |
| ttyd version | `1.7.7` | `build.args.TTYD_VERSION` |
| npm mirror | _(none)_ | `build.args.NPM_REGISTRY` |
| Timezone | `Asia/Shanghai` | `environment.TZ` |
| Locale | `C.UTF-8` | `environment.LANG` / `LC_ALL` (also baked into the image) |

> The `C.UTF-8` locale is required, not cosmetic: omp's tmux session forwards Unicode box-drawing/icons (`╭ π ⬢ 📁`) to the browser only when the locale is UTF-8 — under a POSIX/C locale, tmux downgrades them to ACS escapes and they render as a row of `_`.

To use a custom npm registry (e.g., in mainland China):

```yaml
# docker-compose.dev.yml
build:
  args:
    NPM_REGISTRY: "https://registry.npmmirror.com"
```

### Updating omp

```bash
# Option A: bump OMP_VERSION in docker-compose.dev.yml, then rebuild.
# The `bun_global` named volume persists the old install across container
# recreates, so it must be dropped too — a plain `make build && make up`
# rebuilds the image but the running container keeps the old omp version.
make build
docker compose -f docker-compose.dev.yml stop app
docker compose -f docker-compose.dev.yml rm -f app
docker volume rm pi-chrome-bot_bun_global
make up

# Option B: update in the running container (persists via the bun_global volume)
docker compose exec app omp update
```

## Data persistence

| Volume | Path | Contents |
|--------|------|---------|
| `./data/app` | `/root` in app container | omp sessions, credentials (`agent.db`), settings |
| `./data/chrome` | `/config` in chrome container | Chromium profile, cookies, bookmarks |
| `bun_global` (named) | `/opt/bun/install/global` | Bun global packages (survives `omp update`) |

> **Note:** Deleting `data/app/` clears stored credentials — you will need to run `/login` again.


## License

[MIT](LICENSE)
