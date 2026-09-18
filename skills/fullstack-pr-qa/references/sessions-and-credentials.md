# Sessions and credentials

How a QA run gets an isolated browser, a login that survives between runs, and a password
that never reaches the report.

## Sessions

An agent-browser **session** is one browser instance with its own cookies, storage, history
and auth state. Two sessions cannot see each other, so two QA runs — or a QA run and whatever
the user is doing in their own Chrome — never collide.

`scaffold-qa.sh` derives the name once, and it is **stable for a project + environment pair**:

```
agent-browser session id --scope git-root --prefix qa-<projeto>-<ambiente>
#  -> qa-minha-app-staging-0f76a4ad03fd
```

`--scope git-root` hashes the repository root, so a second worktree of the same repo gets its
own session (and `--scope cwd` is the fallback when the project is not a git repo). The name
is written to `<report-dir>/.qa-env` along with the restore key, the screenshot dir and the
base URL, because **agent hosts may start a fresh shell process for every call** — exported
variables do not survive. That is the whole reason `qa-browser.sh` exists: it re-sources
`.qa-env` on each invocation. A bare `agent-browser` call would run in the `default` session,
a different browser that is not logged in.

Session names accept only `[A-Za-z0-9_-]`. Never hand-write one; always take it from
`session id`.

Useful:

```
agent-browser session list            # which daemons are alive
agent-browser session info --json     # daemon + launch + restore diagnostics
agent-browser close --all             # kill every session (end of day / stuck daemon)
```

## Persisted login (`--restore`)

`.qa-env` sets `AGENT_BROWSER_RESTORE` to the session name, which turns on auto-save/restore
of cookies and localStorage. State is autosaved periodically (30s) and on `close`, into
`~/.agent-browser/sessions/`. The next run against the same project+environment opens already
authenticated.

Validate the restored state instead of trusting it — a restored-but-expired cookie looks like
a logged-in session until the first protected request 401s:

```
agent-browser --restore-check-url "**/dashboard" ...
agent-browser --restore-check-text "Sair" ...
```

If the check fails, agent-browser reports the restore as invalid and you log in again. When a
run ends with a logged-out browser, clear the stale state so the next run does not inherit it:

```
agent-browser state list
agent-browser state clear <session-name>
agent-browser state clean --older-than 7
```

Saved state contains live session tokens. It lives under `~/.agent-browser`, never inside the
project, and must never be copied into `qa-analyze/`.

## Credentials — the vault

**The vault is the only source of credentials, and it is always consulted first.** A run does
not accept a password it was not asked for, does not read one from a project file, and does not
silently proceed logged out. The cycle is: look the vault up → ask the user once if it is empty
→ save → never ask again for that project+environment.


`qa-auth.sh` normalizes the skill's `$3` into a vault profile. The vault is encrypted at rest
with AES-256-GCM under `~/.agent-browser`; the key is auto-generated on the first `auth save`.
To pin your own key (recommended on a shared machine), export it before the first save:

```
export AGENT_BROWSER_ENCRYPTION_KEY=$(openssl rand -hex 32)   # 64 hex chars, in ~/.zshrc
```

Rotating that key makes previously saved profiles and states unreadable — save it once.

### The input forms for `$3`

| Form | Behavior | When |
|------|----------|------|
| *(empty)* or `auto` | **The default.** Looks for `qa-<projeto>-<ambiente>` in the vault. Found ⇒ `AUTH_PROFILE=`. Absent ⇒ `AUTH_MISSING=` on stdout, the project's other profiles as `CANDIDATE=` lines, **exit 3**. Creates nothing. | Every run after the first. Nothing sensitive in the invocation at all. |
| `@perfil` | Reuses that exact profile. Verified with `auth show`; `AUTH_MISSING=` + exit 3 if absent. | Picking a specific role, or an environment whose profile does not follow the convention. |
| `env:QA_USER,QA_PASS` | Reads both from the environment, then **saves** the profile. | CI, or a shell that already exports them. |
| `user:senha` | **Saves** a new profile named `qa-<projeto>-<ambiente>`. Needs the login URL as arg 4. | The one-time answer to `AUTH_MISSING`. **The password lands in the transcript** — say so once, then continue. |
| `none` | No login step. | An explicitly public app. **Never** a fallback for an empty vault. |

### The discovery contract

`qa-auth.sh` never blocks, never prompts and never invents. It answers with a profile or with a
question for the caller to relay:

```
$ bash scripts/qa-auth.sh ~/dev/minha-app staging auto
AUTH_MISSING=qa-minha-app-staging
CANDIDATE=qa-minha-app-localhost e2e@minha-app.local http://localhost:3002/login
CANDIDATE=qa-minha-app-localhost-atendente atendente@minha-app.local http://localhost:3002/login
# exit 3
```

Exit 3 is the "ask the user" signal, and it is the *only* correct reaction to it. Running the
plan without a login produces a report full of login screens; falling back to `none` produces
the same thing while claiming it was intended.

The naming convention `qa-<projeto>-<ambiente>` is what makes the next run silent, so keep it:
save under the conventional name unless the user asked for a specific one. A second role for
the same environment gets a suffix — `qa-minha-app-staging-atendente` — and is addressed with
`@`, and it still shows up as a `CANDIDATE=` line for whoever asks later.

The password always reaches the vault over **stdin** (`--password-stdin`), so it never appears
in `ps` output, in shell history, or in a log line. `qa-auth.sh` prints exactly one line,
`AUTH_PROFILE=<name>`.

### Logging in

```
agent-browser auth login <perfil>
```

It waits for the form fields, fills them, and submits. When the app's login form is not
detected, pass the selectors — once at save time, or per login:

```
agent-browser auth save qa-app-staging --url https://staging.app/login \
  --username user@x.com --password-stdin \
  --username-selector "#email" --password-selector "#password" \
  --submit-selector "button[type=submit]"
```

Put those selectors in the project's `qa.config.json` (`login` block) so every future run picks
them up without asking.

Housekeeping: `agent-browser auth list` (names and URLs only), `auth show <n>` (metadata, never
the password), `auth delete <n>`.

### When the vault cannot drive the login

SSO/OAuth redirects, 2FA, magic links and captchas are not form fills. Two options:

1. **Drive it manually once, then persist.** Run the flow with `--headed` so the user can
   complete the challenge, then let `--restore` (or an explicit `agent-browser state save`)
   capture the authenticated state. Subsequent runs reuse it until it expires.
2. **Import from the user's own Chrome.** With Chrome running with
   `--remote-debugging-port=9222`:
   ```
   agent-browser --auto-connect state save ./auth.json
   agent-browser --state ./auth.json open https://app.example.com/dashboard
   ```
   Save the file outside the project and delete it after the run.

A third, narrower option for API-token apps: `--headers '{"Authorization":"Bearer …"}'`. The
token is then in a command line — treat it exactly like a password.

## Rules for the report

- No password, token, cookie value or state file ever goes into `qa-analyze/`.
- **A recording can leak what the report does not.** `recordings/*.webm` shows the screen as it
  was: a typed password is masked by the input, but a token in a URL, an API key on a settings
  screen, or another customer's data on a shared staging environment is captured in full. Watch
  what the scenario walks past, and delete or re-record a video that caught something the report
  would never have printed.
- Record the **account identity** (email or role) — that is legitimate QA evidence — and the
  vault profile name. Never the secret.
- Before delivering, verify:
  `grep -ri -e password -e senha -e bearer -e token <projeto>/qa-analyze/<slug>/`
  should return only field labels and header names, never a value.
