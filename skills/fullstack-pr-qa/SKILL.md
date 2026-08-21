---
name: fullstack-pr-qa
description: Runs manual browser QA of any web project against any environment, driven by the agent-browser CLI. Takes four parameters — project, test plan, credentials, environment — resolves the environment's base URL, drives a real Chrome through an isolated agent-browser session, captures screenshots plus network evidence, and writes a report under <project-root>/qa-analyze/<slug>/. Use when validating a change, a pull request, or a written test plan end to end in a real browser on localhost, staging or production, or when reproducing a ticket's acceptance criteria on screen. Gatilhos em português — "faz o QA de", "valida no navegador", "testa na tela", "roda o plano de testes", "prova que funciona end-to-end". Don't use for unit or integration test authoring, backend-only changes with no UI, or load and security testing.
metadata:
  author: Filipe Costa
  driver: agent-browser CLI (https://agent-browser.dev)
---

# Browser QA Procedure (project-agnostic)

Validate a web application end to end in a real browser and produce a screenshot-backed
report. Nothing here is tied to a single repository, stack, framework, port or issue
tracker: everything project-specific arrives as a parameter or is read from the project's
own `qa.config.json`.

## Invocation

```
/fullstack-pr-qa <projeto> <plano> <credenciais> <ambiente>
```

Named form (preferred — order-free, unambiguous):

```
/fullstack-pr-qa projeto=~/dev/minha-app plano=./docs/plano-checkout.md auth=@minha-app-staging env=staging
```

| # | Param | Accepts | Resolution |
|---|-------|---------|------------|
| `$1` | `projeto` | absolute path, `~`-path, relative path, or a bare name | Must resolve to a directory. A bare name is looked up under the current directory, then `~/dev/<name>`. **Everything the run writes goes to `<projeto>/qa-analyze/<slug>/`** — never to the cwd, never to `/tmp`. |
| `$2` | `plano` | a readable file path, inline prose, `pr:<n>`, or `linear:<ID>` | Becomes the numbered list of user stories. See Step 2. |
| `$3` | `auth` | `@<perfil>`, `<user>:<senha>`, `env:<VAR_USER>,<VAR_PASS>`, or `none` | Always ends as an **agent-browser auth vault profile**. See Step 3. |
| `$4` | `ambiente` | `localhost` \| `staging` \| `prod` \| an explicit `http(s)://` URL | Resolved to a base URL via `qa.config.json`, then detection, then asking. See Step 4. |

Missing parameters are asked for, one at a time, before any browser starts. Never guess a
base URL and never guess credentials.

## Bundled Path Rule

Resolve bundled paths relative to this skill directory: `~/.claude/skills/fullstack-pr-qa/`.
Expand that prefix when invoking a helper or reading a reference from any working directory.

## Prerequisites

1. `agent-browser` on `PATH` (`agent-browser --version`). If missing: `brew install agent-browser`
   or `npm i -g agent-browser`, then `agent-browser install` to fetch Chrome.
2. `agent-browser doctor` reports no `fail`. Run it once if anything behaves oddly.
3. Optional, only when the plan comes from a tracker: `gh` authenticated (for `pr:<n>`) or the
   Linear MCP connected (for `linear:<ID>`).

**Before driving the browser for the first time in a session, load the CLI's own guide:**
`agent-browser skills get core --full`. It ships with the installed binary, so it is always
version-matched — prefer it over any remembered flag. Then read
`~/.claude/skills/fullstack-pr-qa/references/agent-browser-playbook.md` for the QA-specific loop.

## Step 1: Resolve the project and read its QA config

1. Resolve `$1` to an absolute directory. Abort with the offending value if it does not exist.
2. Read `<projeto>/qa.config.json` if present — it carries the environments, the login form
   selectors and the dev-server command for that project. Its schema is documented in
   `references/environments-and-gotchas.md`.
3. If it is absent, do **not** create it silently. Detect what you can (package manager, dev
   script, dev port from the framework config), state your inferences, and offer to write a
   `qa.config.json` stub so the next run needs no detection. Writing it requires the user's OK.
4. Read the project's own agent instructions (`CLAUDE.md`, `AGENTS.md`, `README.md`) for stack
   rules, required roles, and any "never do X locally" constraint.

## Step 2: Turn `$2` into user stories

1. **File path** — read it and lift its scenarios verbatim; keep the author's numbering.
2. **`pr:<n>`** — `gh pr view <n> --json title,body,files,headRefName,baseRefName`, then read the
   changed code to extract the exact user-facing strings to assert on: route paths, modal copy,
   toast text, button and filter labels, and the role required to reach the screen.
3. **`linear:<ID>`** — read the issue via the Linear MCP and lift its acceptance criteria.
4. **Inline prose** — use it as written, split into discrete stories.
5. Narrow every story to what the running UI can actually exercise. Mark backend-only criteria
   (audit rows, queue side effects, invite-state rules) as **out of UI scope** and say which
   automated test covers them — do not fake them through the browser.
6. Show the numbered story list to the user before starting, along with which stories mutate
   data and how each mutation will be reversed. Get confirmation for the mutating ones.

## Step 3: Resolve credentials into a vault profile

Credentials always end up in the agent-browser auth vault (AES-256-GCM at
`~/.agent-browser`), never in the report, never in a project file, never echoed to a log.

```
bash ~/.claude/skills/fullstack-pr-qa/scripts/qa-auth.sh <projeto> <ambiente> "<$3>" [login-url]
```

The helper prints only `AUTH_PROFILE=<name>` on stdout. Read
`references/sessions-and-credentials.md` for the four input forms, the selector overrides, and
what to do when the login is SSO/OAuth and the vault cannot drive it.

If `$3` arrived as a bare `user:senha` on the command line, tell the user plainly — once — that
the password is now in the conversation transcript and that `@perfil` or `env:` avoids it next
time. Then continue; do not block on it.

## Step 4: Resolve the environment and bring it up

1. Map `$4` to a base URL through `qa.config.json` → explicit URL → ask. Never invent a host.
2. `localhost`: start the dev server in the background with inline env overrides (never edit a
   committed env file), then wait for its ready line. `staging` / `prod`: nothing to start.
3. **`prod` is read-only by default.** Refuse to execute a mutating story against production
   unless the user explicitly authorizes that specific mutation in this conversation.
4. Read `references/environments-and-gotchas.md` before starting the server — it lists the traps
   that repeatedly masquerade as product defects (cross-site auth cookies, inactivity logout,
   deploy lag, CORS on localhost).

## Step 5: Scaffold the report folder and the browser session

```
bash ~/.claude/skills/fullstack-pr-qa/scripts/scaffold-qa.sh <projeto> "<titulo>" <ambiente> <base-url>
```

It creates `<projeto>/qa-analyze/<slug>/screenshots/`, seeds `qa-results.md` from the template,
derives a stable session id (`agent-browser session id --scope git-root`), and writes
`<slug>/.qa-env` holding the session name, the restore key, the screenshot dir and the base URL.
It prints `PROJECT_ROOT`, `SLUG`, `ENV`, `BASE_URL`, `REPORT_DIR`, `REPORT`, `SHOTS`, `SESSION`
and `QA_ENV`. `REPORT_DIR` is the `<report-dir>` every `qa-browser.sh` call takes.

From then on, drive the browser **only** through the wrapper, which applies that `.qa-env` to
every call — the Bash tool does not keep environment between calls, so a bare `agent-browser`
would silently land in the wrong session:

```
bash ~/.claude/skills/fullstack-pr-qa/scripts/qa-browser.sh <REPORT_DIR> open /login
bash ~/.claude/skills/fullstack-pr-qa/scripts/qa-browser.sh <REPORT_DIR> snapshot -i -c
bash ~/.claude/skills/fullstack-pr-qa/scripts/qa-browser.sh <REPORT_DIR> screenshot 01-login.png
```

Two rewrites the wrapper applies: a leading `/path` on a navigation command is expanded against
`BASE_URL`, and a bare screenshot filename is anchored in the run's `screenshots/` folder — a
plain `agent-browser screenshot 01.png` would write to the shell's cwd and litter the project
root, because `AGENT_BROWSER_SCREENSHOT_DIR` only applies when no path is given at all.

## Step 6: Drive the browser and capture evidence

Follow `references/agent-browser-playbook.md`. Per user story:

1. `snapshot -i -c` to locate elements by `@ref` and read the exact rendered copy; assert it
   against the strings the plan (or the code) says must appear.
2. Act: `click @e3`, `fill @e2 "..."`, `find role button click --name "Salvar"`, `press Enter`.
3. `network requests --filter <path>` to confirm the call fired and its status; `console` and
   `errors` to catch a silent client-side failure the UI swallowed.
4. `screenshot <NN>-<meaning>.png` into the report's `screenshots/`.
5. **Re-read the saved PNG with the Read tool** to confirm it captured the intended state. A
   mid-flight redirect saves the wrong page without any error.

Batch independent steps with `batch --bail` to cut round trips. Never `close` the session
between stories — the daemon is what keeps the login alive.

## Step 7: Clean up

1. Reverse every state change (restore what was archived, delete what was created), through the
   UI when possible, and verify the reversal from the response body or a fresh snapshot.
2. Stop the background dev server.
3. Close the browser session persisting its state: `qa-browser.sh <report-dir> close`. Keep the
   session id in the report so a follow-up run reuses the same logged-in state via `--restore`.

## Step 8: Write the report

1. Fill `<projeto>/qa-analyze/<slug>/qa-results.md` from `assets/qa-results.template.md`.
2. Every story gets Steps / Expected / Actual / Result with a **PASS, FAIL or BLOCKED** verdict
   plus its screenshot and network evidence.
3. Separate genuine product defects from environment-only observations. An environment blocker
   must never read as a code defect — it is BLOCKED, not FAIL.
4. State the final data state and confirm cleanup.
5. Record the run's environment: base URL, branch and commit (`git -C <projeto> rev-parse --short HEAD`),
   agent-browser version, session id, and date.

## Step 9: Deliver

1. Report the verdict and per-story results. A failed or blocked story is stated plainly with
   its evidence — never smoothed over.
2. Do not commit `qa-analyze/`, comment on a PR, or edit a PR description without explicit
   confirmation. Add `qa-analyze/` to the project's `.gitignore` only if the user asks.
3. When the user does want the summary and screenshots in a **PR description**, read
   `references/publish-artifacts.md` and use `scripts/publish-qa-images.sh` to host the images
   by SHA so nothing is committed to the branch or the default branch.

## Error Handling

- **`agent-browser` not found** — stop and give the install line; do not fall back to a browser
  MCP silently, the whole report format assumes this driver.
- **Element not found / stale `@ref`** — refs are invalidated by re-render. Take a fresh
  `snapshot` instead of retrying the old ref, and prefer `find role|label|text` for elements
  that move.
- **Login does not stick after a reload** — a cross-site auth cookie is being dropped. Use
  client-side navigation (`pushstate /rota`) instead of a full `open`, and record it as an
  environment note. See gotcha 1 in the environments reference.
- **Session drops mid-run** — raise the app's inactivity timeout for the run, and confirm the
  daemon is alive with `agent-browser session list`; `idleTimeout` is 2h in the user config.
- **404 on a brand-new endpoint against staging** — distinguish a framework route-not-found
  from the app's own not-found by reading the response body. If the backend half is not
  deployed yet, the story is BLOCKED by environment, not FAIL.
- **A screenshot shows the wrong screen** — re-capture after fixing the cause, and re-read the
  earlier PNGs to audit them.
- **Credentials rejected** — confirm the account exists in *this* environment; do not retry
  blindly (lockout policies are real). Ask for the right account.

## Validation

- Every user story reached PASS, FAIL or BLOCKED with cited evidence.
- `<projeto>/qa-analyze/<slug>/qa-results.md` exists at the **project root**, and every image
  link resolves to a file in `screenshots/`.
- Every screenshot referenced was re-read and shows the state it claims.
- Mutated data was reversed and the dataset is clean; the dev server is stopped.
- No password appears anywhere under `qa-analyze/`:
  `grep -ri -e "senha" -e "password" <projeto>/qa-analyze/<slug>/` returns only field labels.
