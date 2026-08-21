---
name: fullstack-pr-qa
description: Runs manual browser QA of any web project against any environment, driven by the agent-browser CLI. Takes four arguments — project, test plan, credentials, environment — resolves the environment's base URL, drives a real Chrome through an isolated agent-browser session, captures screenshots plus network evidence, and writes a report under <project-root>/qa-analyze/<slug>/. Use when validating a change, a pull request, or a written test plan end to end in a real browser on localhost, staging or production, or when reproducing a ticket's acceptance criteria on screen. Gatilhos em português — "faz o QA de", "valida no navegador", "testa na tela", "roda o plano de testes", "prova que funciona end-to-end". Don't use for unit or integration test authoring, backend-only changes with no UI, or load and security testing.
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
| `\$auth` | `$auth` | Credentials: `@<perfil>`, `env:<VAR_USER>,<VAR_PASS>`, `<user>:<senha>`, or `none`. |
| `\$ambiente` | `$ambiente` | Environment: `localhost`, `staging`, `prod`, or an explicit `http(s)://` URL. |

The left column names the argument; the right column is what the coordinator actually passed.
An empty right-hand cell means that argument was not supplied.

A named argument the coordinator omitted expands to an **empty string**. Before anything else,
check all four. If any is empty, or `$projeto` does not resolve to a directory, return
immediately with the list of what is missing and the exact invocation that would fix it:

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
3. Only when the plan comes from a tracker: `gh` authenticated (for `pr:<n>`) or the Linear
   MCP available (for `linear:<ID>`). If the reference cannot be read, stop and say so.

**Before driving the browser, load the CLI's own guide:** `agent-browser skills get core --full`.
It ships with the installed binary, so it is always version-matched. Then read
`${CLAUDE_SKILL_DIR}/references/agent-browser-playbook.md` for the QA-specific loop.

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

## Step 3: Resolve credentials into a vault profile

Credentials always end up in the agent-browser auth vault (AES-256-GCM under
`~/.agent-browser`), never in the report, never in a project file, never echoed to a log.

```
bash ${CLAUDE_SKILL_DIR}/scripts/qa-auth.sh "$projeto" "$ambiente" "$auth" [login-url]
```

The helper prints only `AUTH_PROFILE=<name>` on stdout. Read
`${CLAUDE_SKILL_DIR}/references/sessions-and-credentials.md` for the four input forms, the
selector overrides, and what to do when the login is SSO/OAuth and the vault cannot drive it.

If `$auth` arrived as a bare `user:senha`, note in the report — once, without repeating the
value — that the password passed through the invocation text and that `@perfil` or `env:`
avoids that next time.

## Step 4: Resolve the environment

1. Map `$ambiente` to a base URL through `qa.config.json`, or use it directly when it is
   already a URL. **Never invent a host.** If it cannot be resolved, stop and return what you
   tried.
2. `localhost`: start the dev server in the background with inline env overrides (never edit a
   committed env file), then wait for its ready line. `staging` / `prod`: nothing to start.
3. **`prod` is read-only.** Refuse every mutating story against production unless the plan
   text explicitly authorizes that specific mutation.
4. Read `${CLAUDE_SKILL_DIR}/references/environments-and-gotchas.md` before starting the
   server — it lists the traps that repeatedly masquerade as product defects.

## Step 5: Scaffold the report folder and the browser session

```
bash ${CLAUDE_SKILL_DIR}/scripts/scaffold-qa.sh "$projeto" "<titulo>" "$ambiente" <base-url>
```

It creates `$projeto/qa-analyze/<slug>/screenshots/`, seeds `qa-results.md` from the template,
derives a stable session id (`agent-browser session id --scope git-root`), and writes
`<slug>/.qa-env` holding the session name, the restore key, the screenshot dir and the base
URL. It prints `PROJECT_ROOT`, `SLUG`, `ENV`, `BASE_URL`, `REPORT_DIR`, `REPORT`, `SHOTS`,
`SESSION` and `QA_ENV`.

Drive the browser **only** through the wrapper, which re-applies `.qa-env` on every call — the
Bash tool starts a fresh shell each time, so a bare `agent-browser` would silently land in the
`default` session, a different browser that is not logged in:

```
bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> open /login
bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> snapshot -i -c
bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> screenshot 01-login.png
```

Two rewrites the wrapper applies: a leading `/path` on a navigation command is expanded against
`BASE_URL`, and a bare screenshot filename is anchored in the run's `screenshots/` folder — a
plain `agent-browser screenshot 01.png` would write to the shell's cwd and litter the project
root, because `AGENT_BROWSER_SCREENSHOT_DIR` only applies when no path is given at all.

## Step 6: Drive the browser and capture evidence

Follow `${CLAUDE_SKILL_DIR}/references/agent-browser-playbook.md`. Per user story:

1. `snapshot -i -c` to locate elements by `@ref` and read the exact rendered copy; assert it
   against the strings the plan (or the code) says must appear.
2. Act: `click @e3`, `fill @e2 "..."`, `find role button click --name "Salvar"`, `press Enter`.
3. `network requests --filter <path>` to confirm the call fired and its status; `console` and
   `errors` to catch a silent client-side failure the UI swallowed.
4. `screenshot <NN>-<meaning>.png` into the report's `screenshots/`.
5. **Re-read the saved PNG with the Read tool** to confirm it captured the intended state. A
   mid-flight redirect saves the wrong page with no error.

Batch independent steps with `batch --bail` to cut round trips. Never `close` the session
between stories — the daemon is what keeps the login alive.

## Step 7: Clean up

1. Reverse every state change (restore what was archived, delete what was created), through the
   UI when possible, and verify the reversal from the response body or a fresh snapshot.
2. Stop the background dev server.
3. Close the browser session persisting its state:
   `bash ${CLAUDE_SKILL_DIR}/scripts/qa-browser.sh <REPORT_DIR> close`. Record the session id in
   the report so a follow-up run reuses the same logged-in state via `--restore`.

## Step 8: Write the report

1. Fill `$projeto/qa-analyze/<slug>/qa-results.md` from
   `${CLAUDE_SKILL_DIR}/assets/qa-results.template.md`.
2. Every story gets Steps / Expected / Actual / Result with a **PASS, FAIL or BLOCKED** verdict
   plus its screenshot and network evidence.
3. Separate genuine product defects from environment-only observations. An environment blocker
   must never read as a code defect — it is BLOCKED, not FAIL.
4. State the final data state and confirm cleanup.
5. Record the run's environment: base URL, branch and commit
   (`git -C "$projeto" rev-parse --short HEAD`), agent-browser version, session id, and date.

## Step 9: Return to the coordinator

Your final message is the result the coordinator receives — it is not read by a human directly,
so make it self-contained:

1. The overall verdict and a one-line result per story (PASS / FAIL / BLOCKED).
2. The absolute path to `qa-results.md` and the screenshot count.
3. Anything that blocked you: a missing argument, an unresolvable environment, an unauthorized
   mutation, a credential that failed.
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
  which account and environment failed.

## Validation

- Every user story reached PASS, FAIL or BLOCKED with cited evidence.
- `$projeto/qa-analyze/<slug>/qa-results.md` exists at the **project root**, and every image
  link resolves to a file in `screenshots/`.
- Every screenshot referenced was re-read and shows the state it claims.
- Mutated data was reversed; the dev server is stopped; the session was closed.
- No secret appears anywhere under `qa-analyze/`:
  `grep -ri -e senha -e password -e bearer -e token "$projeto/qa-analyze/<slug>/"` returns only
  field labels.
