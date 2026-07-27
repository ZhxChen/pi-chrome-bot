# Deployment tools

This deployment provides two native tools beyond the builtins:

- `agent_browser` (from `pi-agent-browser-native`) — drives the one shared,
  user-visible Chromium.
- `schedule_prompt` (from `pi-schedule-prompt`) — schedules future prompts for
  reminders, deferred work, and recurring checks.

Each tool's built-in guidance is the source of truth for its parameters. The
constraints below are deployment-specific and override generic defaults.

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

# Prompt scheduling constraints

Use `schedule_prompt` when the user asks to be reminded, to defer work, or to
run something repeatedly ("every 5 minutes", "in 30 minutes", "each morning").
Do not emulate scheduling with `sleep`, background shell loops, `at`, or
`cron` — those outlive nothing useful here and are invisible to the user.

Cron expressions have **six** fields; the first is seconds. `0 * * * * *` is
every minute. A five-field expression is rejected.

Prefer the simplest form that fits: `+30m` for one-shots (`type: "once"`),
`10m` for repeats (`type: "interval"`), six-field cron only for wall-clock
times. Container timezone is set by `TZ` in Compose (`Asia/Shanghai` by
default), so cron hours are local to that, not UTC.

## Jobs only fire while a session is live

Nothing is queued. A job fires only while the Pi session that owns it is still
running inside the pi-web server process, and the pi-web session wrapper
destroys an idle session after about 10 minutes with no agent activity.
Practical consequences:

- An interval under ~10 minutes keeps itself alive: each firing is activity,
  which resets the idle timer.
- A daily-at-09:00 cron or a `+4h` reminder will usually **not** survive to its
  fire time on its own. Say so when the user asks for one — offer a short
  interval instead, or tell them the session must stay active.
- Restarting the `pi` container drops all live sessions. Jobs stay on disk in
  `<cwd>/.pi/schedule-prompts.json` but are bound to the old session id and
  will not fire again until re-created (or their `session` field is removed by
  the user via `/schedule-prompt → Jobs → s`).

Confirm the schedule you actually created — name, next run, and whether it
repeats — instead of implying an unattended daemon.

## Working directory

Jobs live in the session's working directory (`<cwd>/.pi/schedule-prompts.json`).
pi-web's default cwd is dated (`~/pi-cwd-YYYYMMDD`), so a job created today is
not visible from tomorrow's default directory. If the user wants schedules they
can find again, create them in a stable project directory and tell them which
one holds the job file.

## Inline vs subagent jobs

Without `model`, the scheduled prompt is injected into the current chat: it has
this session's context and full toolset, including `agent_browser`. This is the
default and usually the right one.

With `model` set, the job runs in a fresh in-process session with no context and
**no extensions** — `agent_browser` is not available there. If a recurring
browser check should run as a subagent, pass
`extensions: ["agent-browser"]` so the browser tool loads, and keep the
per-run prompt self-contained (state the URL and the CDP attachment
requirement, since the subagent does not inherit this conversation).

Leave `notify` off unless the user wants the main agent to react to every run;
a notifying job that fires every few minutes interrupts the chat each time.

## Scheduled browser work shares the user's screen

A scheduled job that drives Chromium takes over the browser the user is
watching. Keep such jobs short, and do not navigate away from whatever page is
open unless the job's purpose requires it. Never schedule a job that closes the
browser, clears the profile, or signs the user out.

## Other limits

- A scheduled prompt cannot create more scheduled prompts; the tool blocks it
  to prevent loops. Set up all follow-up jobs from a normal turn.
- Job names must be unique in a directory. Reuse `action: "update"` or remove
  the old job rather than inventing a near-duplicate name.
- Before adding a job, `action: "list"` if there is any chance a similar one
  already exists; before promising a change, confirm the job id you targeted.
- Scheduled prompts execute unattended with real tools and the user's
  credentials. Do not schedule anything destructive (deletes, force pushes,
  deploys) without the user asking for exactly that.
