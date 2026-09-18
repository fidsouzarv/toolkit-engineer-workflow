---
name: fullstack-pr-qa
description: Runs manual browser QA for any web project and environment with the agent-browser CLI, producing per-scenario screenshots, WebM recordings, network evidence, and a report. Use when validating a change, pull request, ticket, or test plan end to end in a real browser on localhost, staging, homologation, or production. Gatilhos em portugues — "faz o QA de", "valida no navegador", "testa na tela", "roda o plano de testes", "prova que funciona end-to-end". Do not use for unit-test authoring, backend-only changes without observable UI, load testing, or security testing.
metadata:
  author: Filipe Costa
  driver: agent-browser CLI (https://agent-browser.dev)
---

# Full-stack browser QA

Validate a web application in a real browser and write evidence under
`<project-root>/qa-analyze/<slug>/`. The workflow is project-, stack-, environment-, and
agent-host agnostic. Project-specific facts come from the request, `qa.config.json`, and the
project's own instructions.

## Inputs

| Input | Accepted values | Default |
|---|---|---|
| `project` | Directory path or project name | Current Git root |
| `plan` | File path, inline prose, `pr:<n>`, `linear:<ID>`, or `auto` | `auto` |
| `auth` | `auto`, `@<profile>`, `env:<USER_VAR>,<PASS_VAR>`, `<user>:<password>`, or `none` | `auto` |
| `environment` | `<label>=<url>`, bare URL, or a configured local label | None; always required |

Read these inputs from the invoking request, whether the host passes them as slash-command text,
a skill mention, or natural language. Apply the defaults above to omitted values. Values with
spaces must be quoted when the host parses arguments shell-style.

If `environment` is missing, stop before opening a browser. If `project` cannot resolve to a
directory, stop and identify the invalid value. When the execution context can ask the user,
ask directly. When running in an isolated worker or fork, return the exact blocking question to
the coordinator instead. Evaluate all known blockers together so the user is not asked twice.

## Skill root and bundled resources

Resolve `SKILL_ROOT` to the directory containing this loaded `SKILL.md`. Do not hardcode
`~/.claude`, `~/.agents`, `~/.codex`, or a repository checkout. A host-provided skill-directory
variable may be used only after confirming that it points to this directory.

All commands below use `$SKILL_ROOT`:

```bash
bash "$SKILL_ROOT/scripts/ensure-ffmpeg.sh"
bash "$SKILL_ROOT/scripts/qa-auth.sh" "$PROJECT_ROOT" "$ENVIRONMENT" "$AUTH" "$LOGIN_URL"
bash "$SKILL_ROOT/scripts/scaffold-qa.sh" "$PROJECT_ROOT" "$TITLE" "$ENVIRONMENT" "$BASE_URL"
bash "$SKILL_ROOT/scripts/qa-browser.sh" "$REPORT_DIR" <agent-browser arguments...>
```

## Preflight

1. Resolve the project and read its `AGENTS.md`, `CLAUDE.md`, and `README.md` when present.
2. Read `<project>/qa.config.json` when present. It may define local base URLs, server commands,
   login selectors, and project notes. Never create or edit it during a QA run.
3. Require `agent-browser` on `PATH` and run `agent-browser doctor`. If unavailable, stop with:
   `brew install agent-browser` (or `npm i -g agent-browser`), then `agent-browser install`.
4. Run the ffmpeg preflight at minute zero. Exit 0 enables recordings. Exit 4 is a soft failure:
   continue with screenshots and network evidence, start no recordings, and explain the missing
   dependency in the report. `QA_NO_INSTALL=1` disables unattended installation.
5. Load the version-matched CLI guide with `agent-browser skills get core --full`, then read
   `references/agent-browser-playbook.md`.

Do not substitute Chrome DevTools MCP, a browser MCP, Playwright, or another driver. The session,
vault, evidence, and report contracts in this skill depend on `agent-browser`.

## Resolve the test plan

Use an explicit plan exactly as supplied and preserve its scenario numbering. Otherwise, for
`auto`, derive the smallest useful set of user-visible scenarios in this order:

1. If the current branch has a pull request, inspect it with `gh pr view --json
   title,body,files,headRefName,baseRefName` and read the changed UI code.
2. Otherwise resolve the repository's default branch and inspect the merge-base diff through the
   current working tree, including committed, staged, and unstaged changes.
3. Extract exact routes, controls, visible copy, roles, and expected network calls from the code.
4. Include a happy path and a relevant negative or regression scenario when the change supports
   one. Do not manufacture a negative scenario with no relationship to the change.

For explicit sources:

- File path: read and use its scenarios.
- `pr:<n>`: inspect that PR and its changed code.
- `linear:<ID>`: read the issue through an available Linear integration.
- Inline prose: split it into discrete user-visible scenarios.

If no user-visible behavior or acceptance criterion can be established, stop and explain that
the change is not browser-testable instead of inventing assertions. Mark backend-only criteria
as out of UI scope and cite the automated test that covers them when one exists.

## Hard gates

### Environment and host

A remote host is never inferred from a label, package name, Git remote, `.env`, config default,
or previous report.

| Environment input | Result |
|---|---|
| `staging=https://staging.example.com` | Use the explicit label and URL |
| Bare `http://` or `https://` URL | Use it; derive the label from the host |
| `localhost`, `local`, `dev`, `development` | Resolve from `qa.config.json` or local detection |
| Any other bare label | Stop and ask for `<label>=<url>` |

When a remote bare label matches an entry in `qa.config.json`, quote that URL only as a proposed
value to confirm; never use it silently. Production is read-only by default. A URL confirms the
host, not permission to mutate it.

### Authentication

Resolve authentication before opening the browser:

```bash
bash "$SKILL_ROOT/scripts/qa-auth.sh" "$PROJECT_ROOT" "$ENVIRONMENT" "${AUTH:-auto}" "$LOGIN_URL"
```

- `AUTH_PROFILE=<name>`: use the saved profile.
- `AUTH_MISSING=<name>` with `CANDIDATE=` lines, exit 3: stop and ask for an existing profile or
  credentials to save.
- `AUTH_PROFILE=none`: valid only when the request explicitly supplied `none` for a public app.

Never invent credentials, read them from project files, retry rejected credentials, or silently
continue logged out. Passwords, cookies, tokens, and authorization headers must never appear in
the report.

### Mutation authorization

Every mutating scenario requires explicit authorization in the user's request or plan, including
on localhost. A local database is not assumed disposable. Without authorization, mark the
scenario `BLOCKED (mutation not authorized)` and do not execute it.

On production, authorization must name the specific mutation. General permission to run QA or a
confirmed production URL is insufficient. Always reverse authorized test data when reversal is
possible and verify the final state.

## Prepare the environment

1. Local environment: use the configured start command or detect the project's normal dev command.
   Do not edit committed environment files. If the app is already responding, do not restart it.
2. Remote environment: start nothing. Check deployment identity when possible before classifying a
   missing feature as a defect.
3. Read `references/environments-and-gotchas.md` before starting the app or drawing conclusions
   about environment-specific behavior.
4. Confirm the resolved base URL responds before authentication.

## Create the run

Scaffold the report and isolated browser session:

```bash
bash "$SKILL_ROOT/scripts/scaffold-qa.sh" "$PROJECT_ROOT" "$TITLE" "$ENVIRONMENT" "$BASE_URL"
```

Use the returned `REPORT_DIR` for every browser command. The wrapper restores the correct session,
base URL, screenshot directory, and recordings directory on every shell call:

```bash
bash "$SKILL_ROOT/scripts/qa-browser.sh" "$REPORT_DIR" open /login
bash "$SKILL_ROOT/scripts/qa-browser.sh" "$REPORT_DIR" snapshot -i -c
bash "$SKILL_ROOT/scripts/qa-browser.sh" "$REPORT_DIR" screenshot 01-login.png
```

Authenticate with the resolved vault profile, then prove the post-login marker or URL is present:

```bash
bash "$SKILL_ROOT/scripts/qa-browser.sh" "$REPORT_DIR" auth login "$AUTH_PROFILE"
```

Record only the profile name and account identity, never a secret.

## Execute each scenario

Each executed scenario gets its own recording, screenshots, and network evidence. Never create one
recording for the whole run.

1. Start `recordings/US-<n>-<slug>.webm` at the scenario entry point.
2. Take a fresh interactive snapshot after recording starts; recording creates a new context and
   invalidates old element references.
3. Confirm authentication survived. Re-authenticate inside the recording if required.
4. Assert the exact visible behavior, perform the user actions, and inspect the relevant request
   status plus browser console/errors.
5. Save a screenshot at the decisive state and inspect the saved PNG to confirm it proves the
   claimed result.
6. Stop the recording and verify the WebM exists and is non-empty.

Use `PASS`, `FAIL`, or `BLOCKED` per scenario. Environment and deployment blockers are `BLOCKED`,
not product failures. A blocked or skipped scenario gets no recording and must say why.

## Cleanup and report

1. Stop any active recording.
2. Reverse authorized mutations and verify the reversal.
3. Stop only a local server started by this run.
4. Close the browser session through `qa-browser.sh` so its restore state is persisted.
5. Fill `qa-results.md` from `assets/qa-results.template.md`.

The report must include:

- One section per scenario with Steps, Expected, Actual, verdict, screenshot, recording, and
  network evidence.
- Environment label, exact base URL and how it was obtained.
- Branch, commit, date, agent-browser version, session ID, vault profile, and account identity.
- Product defects separated from environment blockers.
- Stubbed dependencies and out-of-UI-scope criteria.
- Final data state and cleanup result.
- Any missing recording or degraded evidence, including the ffmpeg reason.

Before finishing, verify that every referenced file exists, every executed scenario has one
non-empty WebM unless recording was unavailable from preflight, and no secret exists under the
report directory.

Return the overall verdict, one line per scenario, the absolute report path, screenshot and
recording counts, blockers, and whether data was mutated and reversed. If execution is isolated,
make this response self-contained for its coordinator.

Do not commit `qa-analyze/`, comment on a PR, or edit a PR description unless the user separately
asks to publish. For publishing, read `references/publish-artifacts.md` and use
`scripts/publish-qa-images.sh`.

## Failure handling

- Missing `agent-browser`: stop with the install command; do not switch drivers.
- Stale element reference: take a new snapshot; do not retry the old reference.
- Credentials rejected: stop after the first failure and identify the profile and environment.
- Remote label without URL: ask for `<label>=<url>`; never construct a host.
- New endpoint returns 404 remotely: inspect the response and deployment identity before deciding
  whether it is a defect or an undeployed change.
- Recording fails after start: preserve screenshot and network evidence, explain the missing video,
  and rerun only that scenario if the encoder becomes available.
