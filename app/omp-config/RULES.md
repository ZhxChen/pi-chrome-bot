# Browser automation rules for the pi-chrome-bot stack.
#
# This file is mounted into the omp container at ~/.omp/agent/RULES.md, where
# omp loads it as an always-apply sticky rule (see omp docs/context-files.md).
# Sticky rules are re-attached near the current turn, so these stay visible
# even after a long session pushes the opening context far up the transcript.
#
# The same content is also available (non-sticky) as a context file via
# AGENTS.md in this directory, which is mounted to ~/.omp/agent/AGENTS.md.

- When controlling the browser through omp's browser tool, you MUST pass
  `app.cdp_url: "http://chrome:9222"` so the call routes through the
  cdp-proxy sidecar. This is the only working endpoint on the compose
  network.
- Never use `ws://...` URLs for `app.cdp_url`. The CDP discovery endpoint
  must be HTTP (e.g. `http://chrome:9222`), not a DevTools WebSocket URL
  such as `ws://chrome:9222/devtools/browser/<id>`.
- Never connect directly to Chromium's internal loopback port `9221`
  (`http://chrome:9221`, `http://127.0.0.1:9221`). It is bound on loopback
  inside chrome's network namespace and is unreachable from the app
  container; use the `http://chrome:9222` proxy instead.
- The user watches the live Chromium desktop at `http://localhost:3000`
  (KasmVNC web desktop). Drive the same browser the user is looking at —
  do not spawn a separate headless browser.
