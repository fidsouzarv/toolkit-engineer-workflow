# Environments, `qa.config.json`, and the traps that fake product defects

## `qa.config.json` (project root, optional but worth writing once)

Everything project-specific the skill needs, so a run reduces to four parameters. Place it at
`<projeto>/qa.config.json`. It is a plain config file for this skill — no tool reads it but
`fullstack-pr-qa`.

```json
{
  "reportDir": "qa-analyze",
  "environments": {
    "localhost": {
      "baseUrl": "http://localhost:3002",
      "start": "npm run dev",
      "cwd": "frontend",
      "readyText": "Ready in",
      "env": { "NEXT_PUBLIC_API_URL": "http://localhost:3003/api" }
    },
    "staging": {
      "baseUrl": "https://staging.exemplo.com.br",
      "readOnly": false
    },
    "prod": {
      "baseUrl": "https://app.exemplo.com.br",
      "readOnly": true
    }
  },
  "login": {
    "path": "/login",
    "usernameSelector": "#email",
    "passwordSelector": "#password",
    "submitSelector": "button[type=submit]",
    "successText": "Dashboard",
    "successUrl": "**/dashboard"
  },
  "notes": [
    "Datas do painel usam America/Sao_Paulo; o dia corrente e sempre parcial."
  ]
}
```

| Key | Meaning |
|-----|---------|
| `reportDir` | Folder under the project root for reports. Default `qa-analyze`. |
| `environments.<env>.baseUrl` | The URL **proposed** when the environment argument is that label. For a local environment it is used directly; for a remote one it is quoted back to the user for confirmation, never used unattended. |
| `environments.<env>.start` / `cwd` / `readyText` | How to bring a local server up, from which subdirectory, and the line that means "ready". Only for local environments. |
| `environments.<env>.env` | Inline env overrides for the start command. Never edit a committed `.env` instead. |
| `environments.<env>.readOnly` | `true` refuses mutating stories without explicit per-mutation authorization. Always `true` for prod — a confirmed URL grants reading, not writing. |
| `login.*` | Form selectors and the post-login success marker, reused by the auth vault and by `wait`. |
| `notes` | Free-text warnings the QA agent must read before interpreting results. |

Absent the file: detect what you can (package manager, dev script, framework default port),
run with those inferences, and **list every one of them in the report**. Do not write the file
during a QA run; creating project files is outside the run's scope. Recommend the stub in the
report instead.

## Bringing a local environment up

1. Start in the background with **inline** env overrides; never edit a committed env file:
   ```
   NEXT_PUBLIC_API_URL=http://localhost:3003/api npm run dev
   ```
2. Wait for the ready line before navigating. A screenshot of a connection-refused page is a
   wasted round trip and reads as a product defect in the report.
3. Confirm the base URL answers before logging in: `qa-browser <dir> open /` then `snapshot -c`.
4. Stop the server in Step 7, even when the run failed.

## Staging and prod

**The base URL must have been confirmed by the user before you get here** (SKILL.md, Gate A). A
label is not a host: `staging` is a different machine in every project, and `baseUrl` in
`qa.config.json` is a *proposal* to put in front of the user, not an authorization to drive. The
config file can be stale, and a QA run against the wrong deployment is at best wasted and at
worst a write to someone else's production.

Once confirmed, address the environment as `<rotulo>=<url>` (`staging=https://staging.app`):
the label keeps the vault profile and the browser session stable across runs, while the URL is
explicit every time. A bare URL also works but derives the label from the hostname.

Nothing to start; the environment is whatever was last deployed. Two consequences that decide
verdicts:

- The deployed build may be **behind the branch you are validating**. Check what is actually
  deployed (a build stamp, `/health`, the container tag) before calling a missing feature a
  defect.
- Data is shared and real. Prefer a disposable account, keep every round trip reversible, and
  confirm the reversal. On `prod`, mutations require explicit authorization for that specific
  action, in this conversation.

## The traps that repeatedly masquerade as product defects

Record each of these as an **environment note**, and mark the affected story **BLOCKED**, never
FAIL.

### 1. Cross-site auth cookie dropped on reload

A local frontend pointed at a remote API sets its refresh cookie on the API's host. A full page
reload from `localhost` sends it cross-site, the refresh 401s, and the app bounces to `/login`.
Intermittent, and it looks exactly like a broken session.
**Workaround:** log in once, then navigate client-side with `pushstate /rota` instead of `open`,
so the in-memory access token survives.

### 2. Inactivity auto-logout mid-run

Most apps log out after N minutes idle. The pauses between automation steps — including waiting
on the user — trip it, and the next screenshot silently captures the login page.
**Workaround:** raise the app's inactivity timeout for the run via an inline env override, and
re-read every PNG.

### 3. Deploy lag: a brand-new endpoint returns 404

Distinguish a **framework** route-not-found (body like `Cannot PATCH /api/...`, generic error
shape) from the **app's own** not-found (its error code, its message). Read the response body
with `network request <id>` before deciding. Undeployed backend ⇒ BLOCKED, not FAIL.

### 4. CORS rejects `localhost`

The remote API's allowlist may not include the local origin. The browser blocks the request
before it reaches the server; `console` shows the CORS message and `network requests` shows it
failed with no status. Environment, not code.

### 5. Wrong environment for the account

Users, roles and plans differ per environment. Credentials that work on staging may not exist
on localhost's seeded database. Confirm which environment the account belongs to before
retrying — lockout policies are real, and a blind retry can lock a shared test account.

### 6. Route gate stricter than the API

The screen may require a higher role than the endpoint it calls. Request credentials for the
role the **screen** needs, not the one the API accepts.

### 7. Timezone and partial-day data

Analytics screens frequently anchor on "yesterday" or on the last complete day. A number that
looks wrong is often the current day being partial. Read the project's own rules (`CLAUDE.md`,
`notes` in `qa.config.json`) before reporting a numeric discrepancy.

### 8. Stale restored session

`--restore` can reload a cookie whose server-side session already expired: the app renders
logged-in shell, then 401s on the first data call. Use `--restore-check-text` /
`--restore-check-url`, or clear the state and log in fresh.

### 9. A scenario recording that starts its own context

`record start` opens a fresh browser context (cookies and localStorage survive, in-memory state
does not). The first snapshot of a scenario can therefore land on the login screen even though
the session was healthy a second earlier, and every `@ref` from the previous scenario is dead.
Re-authenticate inside the recording and move on — it is the recorder's behaviour, **not** a
session defect, and it must never be reported as one.

## Environment note vs product defect

A story **FAILS** only when the running, deployed code behaves wrong. It is **BLOCKED** when
the environment prevented exercising it. Anything in the list above is a note in the report's
"Environment notes" section — never a defect attributed to the change under test.
