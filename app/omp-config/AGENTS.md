# Browser automation context for the pi-chrome-bot stack.
#
# Mounted into the omp container at ~/.omp/agent/AGENTS.md and loaded as a
# context file at the start of every session. Hard requirements live in
# RULES.md (sticky, always-apply). Keep this file short — only what the
# agent must know to drive the browser correctly in this environment.

## Driving the browser

omp's browser tool uses `Puppeteer-core` over CDP. Attach to the
already-running Chromium instead of launching a new one:

```json
{ "app": { "cdp_url": "http://chrome:9222" } }
```

- `app.cdp_url` must be the HTTP CDP discovery endpoint, not a `ws://`
  DevTools URL — `normalizeConnectedCdpUrl()` rejects `ws://`.
- With `app.cdp_url` set you are attaching, not launching. Do not also pass
  `app.path`; that would spawn a second browser.
- `app.target` is a substring on url+title to pick a specific page among
  those Chromium exposes via discovery. Omit it for automatic selection.

The user watches the live desktop at `http://localhost:3000` — drive the
same browser they see, and they will observe your actions in real time.

## Troubleshooting

If `http://chrome:9222` is unreachable, do not try other ports — tell the
user to run `make logs` and check the `chrome` and `cdp-proxy` services.
