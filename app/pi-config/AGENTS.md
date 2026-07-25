# Browser automation constraints

Use the native `agent_browser` tool for browser tasks. Its built-in guidance is
the source of truth for commands, snapshots, selectors, batching, artifacts,
and recovery behavior. Do not invoke the `agent-browser` CLI through shell.
When a task requires live website interaction, use this tool directly; do not
ask the user to open or connect the browser manually.

## Shared browser

This deployment provides one persistent Chromium instance. It is shared with
the user, and the user can watch actions in the embedded desktop.

- The only supported CDP endpoint is `http://127.0.0.1:9222`.
- Attach to that browser; never launch, install, or download another browser.
- Do not use `--auto-connect`, provider launches, raw DevTools WebSocket URLs,
  or a different CDP host or port.
- Do not use local-launch flags such as `--profile`, `--headed`,
  `--allowed-domains`, `--webgpu`, or `--executable-path`.
- The Chromium profile persists user cookies, logins, and browsing state. Do
  not clear its data, sign the user out, or close the browser unless the user
  explicitly requests that action.

## Required attachment

The first browser call in a Pi session must attach through CDP with a fresh
managed session:

```json
{
  "args": ["--cdp", "http://127.0.0.1:9222", "open", "<requested-url>"],
  "sessionMode": "fresh"
}
```

When the task refers to the page already visible in Chromium, attach without
navigating away from it:

```json
{
  "args": ["--cdp", "http://127.0.0.1:9222", "snapshot", "-i"],
  "sessionMode": "fresh"
}
```

After a successful attachment, use normal `agent_browser` calls without
repeating `--cdp`; the extension-managed session will continue to target the
shared browser.

If the managed session is closed, dead, or no longer attached to the visible
browser, repeat the CDP call above with `sessionMode: "fresh"`. Do not recover
by launching another browser or inventing another endpoint. If the endpoint
still fails, report that the shared Chromium/CDP service is unavailable.

Do not call browser-level `close`, `quit`, or `exit` as routine cleanup. The
browser is owned by the deployment and must remain available for later tasks.
