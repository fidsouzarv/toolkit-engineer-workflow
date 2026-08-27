---
name: fullstack-pr-qa
description: Runs manual browser QA of any web project against any environment, driven by the agent-browser CLI. Takes four arguments — project, test plan, credentials, environment — stops to ask for the base URL whenever the environment is remote (staging, homolog, production), authenticates only through the agent-browser credential vault, drives a real Chrome through an isolated session, and captures per-scenario screenshots plus a WebM recording per test scenario, with network evidence, into a report under <project-root>/qa-analyze/<slug>/. Use when validating a change, a pull request, or a written test plan end to end in a real browser on localhost, staging or production, or when reproducing a ticket's acceptance criteria on screen. Gatilhos em português — "faz o QA de", "valida no navegador", "testa na tela", "roda o plano de testes", "prova que funciona end-to-end". Don't use for unit or integration test authoring, backend-only changes with no UI, or load and security testing.
argument-hint: "[projeto] [plano] [auth] [ambiente]"
arguments: projeto plano auth ambiente
context: fork
agent: general-purpose
background: false
metadata:
  author: Filipe Costa
  driver: agent-browser CLI (https://agent-browser.dev)
---

# Browser QA run

Validate a web application end to end in a real browser and produce a screenshot-backed
report. Nothing here is tied to a repository, stack, framework, port or issue tracker.

**You are running as a forked subagent. You have no access to the conversation that invoked
you, and there is no user to ask.** Everything you need arrived in the four arguments below,
plus whatever the coordinator wrote into them. When something required is missing or
ambiguous, do not guess and do not improvise a value — stop and return a precise statement of
what you need. The coordinator will re-invoke you with it.

## Arguments

| Argument | Value received | Meaning |
|---|---|---|
| `\$projeto` | `$projeto` | Project root: absolute path, `~`-path, relative path, or a bare name. **All output goes to `$projeto/qa-analyze/<slug>/`** — never to the cwd, never to `/tmp`. |
| `\$plano` | `$plano` | Test plan: a readable file path, inline prose, `pr:<n>`, or `linear:<ID>`. |
| `\$auth` | `$auth` | Credentials. Empty or `auto` means **look the vault up**; `@<perfil>`, `env:<VAR_USER>,<VAR_PASS>`, `<user>:<senha>` and `none` are the explicit forms. See Gate B. |
| `\$ambiente` | `$ambiente` | Environment. Preferred form `<rotulo>=<url>` (`staging=https://staging.app`); also accepts a bare local label (`localhost`, `local`, `dev`) or a bare `http(s)://` URL. A remote **label** alone (`staging`, `prod`, `producao`…) does not resolve — see Gate A. |

The left column names the argument; the right column is what the coordinator actually passed.
An empty right-hand cell means that argument was not supplied.

A named argument the coordinator omitted expands to an **empty string**. Before anything else,
check `$projeto`, `$plano` and `$ambiente`. If any is empty, or `$projeto` does not resolve to a
directory, return immediately with the list of what is missing and the exact invocation that
would fix it. (`$auth` empty is not an error — it means "find it in the vault", Gate B.)

```
/fullstack-pr-qa <projeto> <plano> <auth> <ambiente>
```

Values with spaces must be quoted by the coordinator, since arguments are split shell-style.

## Bundled paths

Every helper and reference below lives under `${CLAUDE_SKILL_DIR}`, which expands to this
skill's own directory wherever it is installed. Use that variable literally in commands — do
not hardcode a path under `~/.claude`.

## Prerequisites

1. `agent-browser` on `PATH` (`agent-browser --version`). If missing, stop and return the
   install line: `brew install agent-browser` (or `npm i -g agent-browser`), then
   `agent-browser install`.
2. `agent-browser doctor` reports no `fail`.
3. **`ffmpeg`, for the scenario recordings** — run the preflight, which installs it when it is
   missing and can do so unattended:

   ```
   bash ${CLAUDE_SKILL_DIR}/scripts/ensure-ffmpeg.sh
   ```

   | Stdout | Exit | Meaning |
   |---|---|---|
   | `FFMPEG=<path>` | 0 | Already there. Continue. |
   | `FFMPEG_INSTALLED=<path>` | 0 | Installed just now — **say so in the report**, it changed the machine. |
   | `FFMPEG_MISSING=<reason>` | 4 | No unattended install possible (no Homebrew, needs `sudo`, install failed). |

   Do this at minute zero, never mid-run, because the failure mode is otherwise brutal:
   `record start` prints `✓ Recording started`, the whole scenario runs, and only `record stop`
   says `✗ ffmpeg not found`, having written **no file at all**. `agent-browser doctor` does not
   check it either — it reports `0 fail` on a machine where every recording will be lost.

   The first install pulls a large dependency tree and takes a few minutes; that is normal and
   happens once. On `FFMPEG_MISSING`, **do not stop the run** — recordings are one of three kinds
   of evidence, not the run itself. Continue on screenshots plus network evidence, start no
   recording you cannot encode, and return the reason with the platform's install line so the
   next run has video. `QA_NO_INSTALL=1` (or `--no-install`) skips the install and only reports,
   for a machine where the coordinator does not want packages touched.
4. Only when the plan comes from a tracker: `gh` authenticated (for `pr:<n>`) or the Linear
   MCP available (for `linear:<ID>`). If the reference cannot be read, stop and say so.

**Before driving the browser, load the CLI's own guide:** `agent-browser skills get core --full`.
It ships with the installed binary, so it is always version-matched. Then read
`${CLAUDE_SKILL_DIR}/references/agent-browser-playbook.md` for the QA-specific loop.

## Step 0: The two hard gates

Two things can never be inferred: **which host you are about to drive**, and **which account
you are about to log in as**. Getting either wrong means a QA report that describes a system
nobody asked you to touch. Both are checked before any browser starts.

You cannot ask the user directly — you are a fork. "Stop and ask" means: **return immediately
to the coordinator with the exact question**, and it puts the question to the user and
re-invokes you. So evaluate **both gates first and return them together in one message**.
Never stop twice for two questions you could have asked at once. A missing `ffmpeg` is *not* one
of these questions — the preflight installs it on its own and, failing that, only degrades the
evidence.

### Gate A — a remote environment must arrive with an explicit base URL

Classify `$ambiente`, case-insensitively:

| `$ambiente` | Verdict |
|---|---|
| `<rotulo>=<url>`, e.g. `staging=https://staging.app` | **Passes.** The preferred form: label and host, both explicit. |
| a bare `http://` / `https://` URL | **Passes.** That string *is* the base URL; the label is derived from the host. |
| `localhost`, `local`, `dev`, `development` | **Passes.** Resolved from `qa.config.json` or detection (Step 3). |
| `staging`, `stg`, `homolog`, `homologacao`, `hml`, `qa`, `uat`, `preprod` | **STOP — ask for the URL.** |
| `prod`, `producao`, `produção`, `production`, `live` | **STOP — ask for the URL**, and see the production rule below. |
| any other bare label | **STOP — ask for the URL.** |

A label names an intention, not a host. `staging` is a different machine in every project, and
inventing `https://staging.<project>.com` produces a run against something that may not be the
system under test — or worse, may be someone else's. **Never construct a host from a label, a
package name, a git remote, a `.env` file, or a previous run's report.**

This gate holds **even when `qa.config.json` defines a `baseUrl`** for that label: a config file
can be stale, and a wrong host on production is not a recoverable mistake. Read it anyway and
quote it as the proposed default, so the user only has to confirm:

```
BLOCKED — environment "staging" has no confirmed base URL.
qa.config.json proposes: https://staging.exemplo.com.br
Confirm that URL, or give the right one, and re-invoke:
  /fullstack-pr-qa <projeto> <plano> <auth> staging=https://<host-confirmado>
```

With no config entry, ask flatly, and list nothing but what you actually checked:

```
BLOCKED — environment "producao" has no base URL and I must not guess one.
No qa.config.json at <projeto>; no environments block to read.
Re-invoke with the full URL:
  /fullstack-pr-qa <projeto> <plano> <auth> producao=https://<host-de-producao>
```

**Ask for `<rotulo>=<url>`, not a bare URL.** The label is what names the vault profile
(`qa-<projeto>-<rotulo>`) and the browser session, so keeping it stable is what lets Gate B find
the credentials again next run. A bare URL works, but derives the label from the hostname, and
a future run addressed as `staging` would then look for a different profile and ask again.

Pass whatever arrived straight through to `scaffold-qa.sh` — it splits `<rotulo>=<url>` itself,
and enforces the same rule, refusing a remote label with no URL. A skipped gate therefore fails
loudly instead of silently defaulting to a guessed host.

**Production is read-only, and the URL alone does not change that.** A confirmed prod URL
authorizes *reading* prod. Every mutating story still needs its own explicit authorization in
the plan text — Step 2 item 6.

### Gate B — the login comes from the vault, or you ask for it

Never run a QA that needs a login without a login, and never invent, reuse-by-guess or
hardcode credentials. The order is always: **vault first, ask second, save always.**

```
bash ${CLAUDE_SKILL_DIR}/scripts/qa-auth.sh "$projeto" "$ambiente" "${auth:-auto}" [login-url]
```

With `$auth` empty or `auto`, the helper looks for the conventional profile
`qa-<projeto>-<ambiente>` and prints one of:

| Stdout | Exit | What you do |
|---|---|---|
| `AUTH_PROFILE=<name>` | 0 | Use it: `agent-browser auth login <name>`. Nothing to ask. |
| `AUTH_MISSING=<name>` plus `CANDIDATE=<name> <user> <url>` lines | 3 | **STOP — ask.** |
| `AUTH_PROFILE=none` | 0 | Only when the coordinator passed a literal `none`. |

On `AUTH_MISSING`, ask for one of two things, and quote the candidates the helper found so the
user can pick an existing profile instead of retyping a password:

```
BLOCKED — no vault profile for this project+environment (qa-minha-app-staging).
Profiles already saved for this project:
  @qa-minha-app-localhost           (e2e@minha-app.local)
  @qa-minha-app-localhost-atendente (atendente@minha-app.local)
Re-invoke with either:
  auth=@<perfil-existente>            reuses a saved profile
  auth=<usuario>:<senha>              saved once, then found automatically from here on
```

When the user answers with `usuario:senha`, `qa-auth.sh` **saves it into the vault** under
`qa-<projeto>-<ambiente>`, encrypted at rest (AES-256-GCM under `~/.agent-browser`), password
delivered over stdin so it never reaches `ps` or a log. That is the whole point of asking once:
**every later run of this project+environment finds the profile by itself and asks nothing.**
Saving needs the login URL — pass it as arg 4, built from the base URL confirmed in Gate A plus
`login.path` from `qa.config.json` (default `/login`).

`none` is an explicit opt-out for a genuinely public app, never a fallback when the vault came
up empty. If credentials fail at login time, stop and report which account and environment —
do not retry, lockout policies are real.

`${CLAUDE_SKILL_DIR}/references/sessions-and-credentials.md` covers the selector overrides and
what to do when the login is SSO/OAuth, 2FA or a magic link, which no vault profile can drive.

## Step 1: Resolve the project and read its QA config

1. Resolve `$projeto` to an absolute directory. If it does not exist, stop and return the
   offending value.
2. Read `$projeto/qa.config.json` if present — it carries the environments, the login form
   selectors and the dev-server command. Its schema is in
   `${CLAUDE_SKILL_DIR}/references/environments-and-gotchas.md`.
3. If it is absent, detect what you can (package manager, dev script, framework default port)
   and **state every inference in the report**. Do not write a `qa.config.json`; recommend one
   in the report's closing section instead — creating project files is the coordinator's call.
4. Read the project's own agent instructions (`CLAUDE.md`, `AGENTS.md`, `README.md`) for stack
   rules, required roles, and any "never do X locally" constraint.

## Step 2: Turn `$plano` into user stories

1. **File path** — read it and lift its scenarios verbatim; keep the author's numbering.
2. **`pr:<n>`** — `gh pr view <n> --json title,body,files,headRefName,baseRefName`, then read
   the changed code to extract the exact user-facing strings to assert on: route paths, modal
   copy, toast text, button and filter labels, and the role required to reach the screen.
3. **`linear:<ID>`** — read the issue via the Linear MCP and lift its acceptance criteria.
4. **Inline prose** — use it as written, split into discrete stories.
5. Narrow every story to what the running UI can exercise. Mark backend-only criteria (audit
   rows, queue side effects, invite-state rules) as **out of UI scope** and name the automated
   test that covers them. Never fake them through the browser.
6. **Mutating stories need explicit authorization.** You cannot ask for it. Treat a story as
   authorized only when the plan text, or the coordinator's prompt, says so — or when
   `$ambiente` is a local environment whose data is disposable. Otherwise skip it, mark it
   `BLOCKED (mutation not authorized)`, and list it in the report so the coordinator can
   re-invoke with authorization.

## Step 3: Bring the environment up

The base URL is already settled: a remote one was confirmed by the user in Gate A, a local one
comes from `qa.config.json` or detection. **Nothing here may invent a host.**

1. **Local**: start the dev server in the background with inline env overrides (never edit a
   committed env file), then wait for its ready line. Confirm the base URL answers before
   logging in.
2. **Remote**: nothing to start. Check what is actually deployed (build stamp, `/health`,
   container tag) before calling a missing feature a defect — the deployment may be behind the
   branch under test.
3. **Production stays read-only.** Refuse every mutating story against production unless the
   plan text explicitly authorizes that specific mutation. A confirmed URL is permission to
   look, not to write.
4. Read `${CLAUDE_SKILL_DIR}/references/environments-and-gotchas.md` before starting — it lists
   the traps that repeatedly masquerade as product defects.

## Step 4: Scaffold the report folder and the browser session

```
bash ${CLAUDE_SKILL_DIR}/scripts/scaffold-qa.sh "$projeto" "<titulo>" "$ambiente" <base-url>
```

It creates `$projeto/qa-analyze/<slug>/` with `screenshots/` **and `recordings/`**, seeds
`qa-results.md` from the template, derives a stable session id
(`agent-browser session id --scope git-root`), and writes `<slug>/.qa-env` holding the session
name, the restore key, both output dirs and the base URL. It prints `PROJECT_ROOT`, `SLUG`,
`ENV`, `BASE_URL`, `REPORT_DIR`, `REPORT`, `SHOTS`, `RECORDINGS`, `SESSION` and `QA_ENV`.

Arg 4 is mandatory for any non-local environment — the script re-enforces Gate A and dies
rather than scaffolding a run with no host.

Drive the browser **only** through the wrapper, which re-applies `.qa-env` on every call — the
Bash tool starts a fresh shell each time, so a bare `agent-browser` would silently land in the
`default` session, a different browser that is not logged in:

```
bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> open /login
bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> snapshot -i -c
bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> screenshot 01-login.png
```

Three rewrites the wrapper applies:

1. A leading `/path` on a navigation command is expanded against `BASE_URL`.
2. A bare screenshot filename is anchored in the run's `screenshots/` — a plain
   `agent-browser screenshot 01.png` would write to the shell's cwd and litter the project
   root, because `AGENT_BROWSER_SCREENSHOT_DIR` only applies when no path is given at all.
3. A bare `record start|restart` filename is anchored in `recordings/`, and a missing extension
   becomes `.webm`. agent-browser has no recordings-dir variable at all, so without this every
   scenario video would land in the cwd.

## Step 5: Log in with the vault profile

Gate B already resolved `AUTH_PROFILE`. Here you only use it — after the session exists
(Step 4), because a login needs a browser:

```
bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> auth login <AUTH_PROFILE>
```

Then prove the login actually took, instead of assuming it: `snapshot -c` must show the
post-login marker (`login.successText` / `login.successUrl` from `qa.config.json`), not the
form you just submitted. A restored-but-expired cookie renders a logged-in shell and only
401s on the first data call.

Record in the report the **account identity** (email or role) and the profile name. Never the
password, the token or the cookie. If `$auth` arrived as a bare `user:senha`, note once — with
no repetition of the value — that the password passed through the invocation text, that it is
now in the vault, and that from the next run on `auth=` can be left empty entirely.

## Step 6: Drive the browser and capture evidence

Follow `${CLAUDE_SKILL_DIR}/references/agent-browser-playbook.md`. Evidence is captured at two
levels: a **WebM recording per scenario** and **screenshots at the decisive moments**.

### One recording per scenario — never one for the whole run

**A single video covering the entire session is forbidden.** A 20-minute file in which US-4
happens somewhere in the middle is not evidence anybody can use: it cannot be attached to one
story's verdict, cannot be reviewed without scrubbing, and mixes an unrelated failure into the
proof of a passing story. One scenario, one file:

```
recordings/US-1-login.webm
recordings/US-2-filtro-por-status.webm
recordings/US-3-cancelar-pedido.webm
```

Open each scenario on its own recording and close it before the next one starts:

```
bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> record start US-1-login.webm
#   ... the scenario's steps ...
bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> record stop
```

Between two back-to-back scenarios, `record restart US-2-<nome>.webm` does the stop and the
start in one call and leaves no gap.

`✓ Recording started` **does not mean a file will exist.** The encode happens at `record stop`,
so a missing `ffmpeg` fails there and loses the whole scenario silently. That is why it is a
prerequisite, and why every `record stop` is followed by a real check on disk.

**`record start` resets the browser context.** Per `agent-browser record --help`, it *creates a
fresh browser context* and preserves only cookies and localStorage. Three consequences at every
scenario boundary, and all three are silent:

1. **Every `@ref` is dead.** Take a fresh `snapshot -i -c` after starting the recording, always.
2. **In-memory state is gone** — an access token an SPA holds only in JS does not survive.
   Confirm you are still logged in on the first snapshot of the scenario; if the app bounced to
   `/login`, log in again inside the recording (that is legitimate scenario setup) rather than
   reporting a false session defect.
3. **It navigates**, to the current URL or the one you pass. Start each scenario's recording at
   that scenario's entry point: `record start US-3-cancelar.webm <URL>`, or navigate first and
   let it re-open the current page.

A recording is not a substitute for the other evidence. It shows *how* the UI behaved; the
network status is what proves a mutation, and the screenshot is what a reader sees without
opening a player.

### Per scenario

1. `record start US-<n>-<slug>.webm` (or `record restart`), then `snapshot -i -c` — fresh refs,
   exact rendered copy, and confirmation that the login survived the context reset.
2. Assert the copy against the strings the plan (or the code) says must appear.
3. Act: `click @e3`, `fill @e2 "..."`, `find role button click --name "Salvar"`, `press Enter`.
4. `network requests --filter <path>` to confirm the call fired and its status; `console` and
   `errors` to catch a silent client-side failure the UI swallowed.
5. `screenshot <NN>-<meaning>.png` into the report's `screenshots/`.
6. **Re-read the saved PNG with the Read tool** to confirm it captured the intended state. A
   mid-flight redirect saves the wrong page with no error.
7. `record stop`, and confirm the file exists and is non-empty (`ls -l <REPORT_DIR>/recordings`).
   A recording that was never stopped is a truncated or missing file.

Batch independent steps with `batch --bail` to cut round trips — but never batch across the
`record start` boundary, since the refs in the batch were taken in the previous context. Never
`close` the session between stories: the daemon is what keeps the login alive.

A story that is skipped or BLOCKED gets no recording; say so in the report rather than leaving
a reader to wonder which file is missing and why.

## Step 7: Clean up

1. `record stop` if any recording is still running — an unstopped recording never gets written.
2. Reverse every state change (restore what was archived, delete what was created), through the
   UI when possible, and verify the reversal from the response body or a fresh snapshot.
3. Stop the background dev server.
4. Close the browser session persisting its state:
   `bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> close`. Record the session id in
   the report so a follow-up run reuses the same logged-in state via `--restore`.

## Step 8: Write the report

1. Fill `$projeto/qa-analyze/<slug>/qa-results.md` from
   `${CLAUDE_SKILL_DIR}/assets/qa-results.template.md`.
2. Every story gets Steps / Expected / Actual / Result with a **PASS, FAIL or BLOCKED** verdict
   plus its screenshot, **its own `recordings/US-<n>-*.webm`**, and its network evidence.
   Cite the recording by relative path on the story itself, not in a lump at the end.
3. Separate genuine product defects from environment-only observations. An environment blocker
   must never read as a code defect — it is BLOCKED, not FAIL.
4. State the final data state and confirm cleanup.
5. If the preflight installed `ffmpeg`, say so — a QA run that changed the machine reports it.
6. Record the run's environment: base URL **and how it was obtained** (confirmed by the user
   for a remote environment, or resolved from `qa.config.json` locally), branch and commit
   (`git -C "$projeto" rev-parse --short HEAD`), agent-browser version, session id, the vault
   profile and account identity, and the date.

## Step 9: Return to the coordinator

Your final message is the result the coordinator receives — it is not read by a human directly,
so make it self-contained:

1. The overall verdict and a one-line result per story (PASS / FAIL / BLOCKED).
2. The absolute path to `qa-results.md`, the screenshot count and the recording count.
3. Anything that blocked you: a missing argument, an unconfirmed base URL (Gate A), a missing
   vault profile (Gate B), an unauthorized mutation, a credential that failed. Gate stops are
   the *first* thing you return, phrased as the question the coordinator should put to the
   user, with the exact re-invocation line.
4. Explicitly: whether data was mutated and whether it was reversed.

Do **not** commit `qa-analyze/`, comment on a PR, or edit a PR description. Publishing is a
separate opt-in action the coordinator triggers; when it does, read
`${CLAUDE_SKILL_DIR}/references/publish-artifacts.md` and use
`${CLAUDE_SKILL_DIR}/scripts/publish-qa-images.sh`.

## Error Handling

- **`agent-browser` not found** — stop and return the install line. Do not fall back to a
  browser MCP: the report format assumes this driver.
- **Element not found / stale `@ref`** — refs are invalidated by re-render. Take a fresh
  `snapshot` instead of retrying the old ref, and prefer `find role|label|text` for elements
  that move.
- **Login does not stick after a reload** — a cross-site auth cookie is being dropped. Use
  `pushstate /rota` instead of a full `open`, and record it as an environment note.
- **Session drops mid-run** — raise the app's inactivity timeout for the run, and confirm the
  daemon with `agent-browser session list`.
- **404 on a brand-new endpoint against staging** — distinguish a framework route-not-found
  from the app's own not-found by reading the response body. Undeployed backend ⇒ BLOCKED.
- **A screenshot shows the wrong screen** — re-capture after fixing the cause, and re-read the
  earlier PNGs to audit them.
- **Credentials rejected** — do not retry blindly; lockout policies are real. Stop and report
  which account, which vault profile and which environment failed.
- **Vault profile missing** (`AUTH_MISSING`, exit 3) — never fall back to `none` and never run
  the plan logged out. Stop, quote the `CANDIDATE=` profiles, ask for `@perfil` or
  `usuario:senha` (Gate B).
- **Environment label with no confirmed URL** — never construct a host. Stop, quote what
  `qa.config.json` proposes if anything, and ask (Gate A).
- **`✗ ffmpeg not found` on `record stop`** — the preflight was skipped and this scenario's
  video is already lost. Run `ensure-ffmpeg.sh` now: if it installs, recordings work from the
  next scenario on and only this one is missing. If it returns `FFMPEG_MISSING`, stop starting
  recordings that cannot be encoded, finish on screenshots plus network evidence, and mark the
  recordings unavailable in the report with the reason the preflight gave.
- **Recording file missing or 0 bytes** — the recording was not stopped, or the scenario ended
  in an error before `record stop`. Re-run that scenario alone; if it still fails, report the
  story with its screenshot and network evidence and state plainly that the video is missing.
  Never cite a recording you did not verify on disk.
- **Refs all fail right after `record start`** — expected: it opens a fresh context. Take a new
  snapshot; do not retry the old refs, and do not report it as a product defect.

## Validation

- A remote environment ran against a URL the **user** confirmed, never one you built from a
  label.
- The login came from a vault profile — reused or saved this run. No password, in any form,
  appears in the report.
- Every user story reached PASS, FAIL or BLOCKED with cited evidence.
- `$projeto/qa-analyze/<slug>/qa-results.md` exists at the **project root**, and every image
  link resolves to a file in `screenshots/`.
- Every screenshot referenced was re-read and shows the state it claims.
- **`recordings/` holds one non-empty `.webm` per executed scenario and no whole-run video.**
  `ls -l <REPORT_DIR>/recordings` must show as many files as there are non-blocked stories, each
  named for its story; any story without one is explained in the report.
- Mutated data was reversed; every recording was stopped; the dev server is stopped; the
  session was closed.
- No secret appears anywhere under `qa-analyze/`:
  `grep -ri -e senha -e password -e bearer -e token "$projeto/qa-analyze/<slug>/"` returns only
  field labels.
