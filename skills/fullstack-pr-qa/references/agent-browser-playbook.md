# agent-browser Playbook for QA runs

The command loop and the traps, for driving a QA run with the `agent-browser` CLI. Every
command below is run through the wrapper so it lands in the run's session:

```
bash <skill-dir>/scripts/qa-browser.sh <report-dir> <args...>
```

`<skill-dir>` is this skill's own directory — SKILL.md carries it as the already-expanded
`${CLAUDE_SKILL_DIR}` value, so take it from there rather than hardcoding a path.
`<report-dir>` is the `REPORT_DIR` that `scaffold-qa.sh` printed. Shortened to
`qa-browser <args>` in the rest of this document.

## Load the CLI's own reference first

```
agent-browser skills get core --full
```

It ships with the installed binary, so it is always version-matched to what is on this
machine. Read it before improvising a flag; this playbook only covers what is specific to a
QA run. Specialized skills exist too: `agent-browser skills list` (electron, slack,
exploratory testing, cloud providers).

## The core loop, per user story

0. **Open the scenario's recording** — `qa-browser record start US-<n>-<slug>.webm`
   One video per scenario, never one for the run. Details and the context-reset trap in
   "Recording per scenario" below.
1. **Locate and read** — `qa-browser snapshot -i -c`
   Interactive elements only, compact: ~200-400 tokens instead of a DOM dump. It returns
   `@ref`s (`@e1`, `@e2`) **and** the rendered text, so it is also how you assert on exact
   copy: modal titles, button labels, toast text, empty-state messages.
2. **Act** — by ref when the element is stable, by semantics when it moves:
   ```
   qa-browser click @e3
   qa-browser fill @e2 "cliente@teste.com"
   qa-browser find role button click --name "Salvar"
   qa-browser find label "E-mail" fill "cliente@teste.com"
   qa-browser find text "Excluir" click --exact
   qa-browser press Enter
   qa-browser select @e7 "Últimos 30 dias"
   ```
3. **Wait on a condition, never on a guess**
   ```
   qa-browser wait --text "Pedido criado"
   qa-browser wait --url "**/dashboard"
   qa-browser wait --load networkidle
   qa-browser wait --fn "window.__APP_READY === true"
   ```
   `wait 2000` (raw ms) is a last resort and must not appear in a report as evidence of
   anything.
4. **Confirm the request** — the authoritative proof of a mutation:
   ```
   qa-browser network requests --filter /api/pedidos
   qa-browser network request <requestId>     # full detail incl. response body
   ```
5. **Catch what the UI swallowed**
   ```
   qa-browser console
   qa-browser errors
   ```
   A story that "looks right" while `errors` is non-empty is not a PASS without an explanation.
6. **Capture** — the screenshot dir is already set by `.qa-env`, so a bare filename lands in
   `screenshots/`:
   ```
   qa-browser screenshot 03-modal-confirmacao.png
   qa-browser screenshot --full 04-lista-completa.png
   qa-browser screenshot --annotate 05-mapa-refs.png
   ```
7. **Verify the capture** — re-read the saved PNG with the Read tool. A redirect between the
   snapshot and the screenshot saves the wrong page with no error at all.
8. **Close the recording** — `qa-browser record stop`, then `ls -l <report-dir>/recordings` to
   confirm the file exists and is non-empty. An unstopped recording is never written.

## Recording per scenario

The run produces `recordings/US-1-login.webm`, `recordings/US-2-filtro.webm`, one file per
scenario — **never a single video of the whole session**. A per-scenario file can be attached
to that story's verdict; a whole-run file forces a reviewer to scrub for the ten seconds that
matter and drags an unrelated failure into the evidence of a passing story.

```
qa-browser record start US-1-login.webm            # -> recordings/US-1-login.webm
#  ... the scenario ...
qa-browser record stop

qa-browser record restart US-2-filtro-status.webm  # stop + start, no gap between scenarios
```

The wrapper anchors a bare filename in the run's `recordings/` and appends `.webm` when the
extension is missing. agent-browser has no recordings-dir variable of its own, so a direct
`agent-browser record start US-1.webm` would drop the file in the shell's cwd.

### Recording needs `ffmpeg`, and says so late

agent-browser encodes through `ffmpeg`. Without it:

```
$ qa-browser record start US-1-home.webm
✓ Recording started: .../recordings/US-1-home.webm     # a lie, nothing is being written
$ qa-browser record stop
✗ ffmpeg not found or failed to execute. Install ffmpeg to enable recording.
$ ls recordings/                                        # empty
```

`agent-browser doctor` does **not** cover it and will report `0 fail` on a machine where every
recording is lost. The preflight `scripts/ensure-ffmpeg.sh` checks for it and installs it when
it can (SKILL.md Prerequisites) — run it before the first `record start`, and still check the
file on disk after every `record stop`.

### `record start` opens a fresh context — plan for it

`agent-browser record --help`: *"Creates a fresh browser context but preserves cookies and
localStorage."* Cookies and localStorage survive; nothing else does. At every scenario boundary:

| What happens | What you do |
|---|---|
| All `@ref`s from the previous context are dead | `snapshot -i -c` immediately after `record start`, always |
| In-memory state is dropped — an SPA access token held only in JS is gone | Check the first snapshot is not the login screen. If it is, log in inside the recording; that is scenario setup, not a defect |
| It navigates to the current URL, or to the one you pass | Start at the scenario's entry point: `record start US-3-cancelar.webm <URL>` |

Because of the reset, **never batch across a `record start`**: the refs in the batch were
resolved in the context that just went away.

### What a recording is and is not evidence of

The video shows *how* the UI behaved — the animation that never finished, the flash of an error
toast, the double submit. It does not replace the other two:

- **Network status proves the mutation** (`204` on delete, `201` on create).
- **The screenshot is what a reader sees** without opening a player.
- **The recording explains the sequence** when a verdict is contested.

Cite it per story, by relative path. Never cite a file you have not confirmed on disk, and never
imply a recording covers a scenario that was skipped or BLOCKED — those get none, and the report
says so.

## Batching

Independent steps in one round trip; each command is a JSON array:

```
qa-browser batch --bail \
  '["fill","@e1","cliente@teste.com"]' \
  '["fill","@e2","<senha>"]' \
  '["click","@e3"]' \
  '["wait","--url","**/dashboard"]'
```

`--bail` stops at the first error. Do **not** batch across a re-render: refs taken before the
batch are stale after the first step that repaints. Batch within a stable screen only.

Plain `&&` chaining in one Bash call works too and is often clearer for a short sequence.

## Refs go stale

`@e1` is bound to the snapshot that produced it. Any re-render — a route change, a list
refresh, a modal opening — invalidates it. The fix is a fresh `snapshot`, never a retry of the
old ref. For elements that move between renders, prefer `find role|label|text|testid`, which
re-resolves at call time.

## SPA navigation

A full `open` is a real page load: in-memory state (an access token held only in JS) is lost
and the app may bounce to the login screen. Inside an already-authenticated SPA, navigate
client-side instead:

```
qa-browser pushstate /pedidos/123
```

It auto-detects the Next.js router and falls back to `history.pushState` plus the navigation
events other frameworks listen to.

## Evidence hygiene

- Network status is the authoritative proof of a mutation (`204` on delete, `200` on restore);
  the screenshot is visual support, not the proof.
- Name screenshots by order and meaning: `01-login.png`, `02-lista-vazia.png`,
  `03-modal-confirmacao.png`. The number is the run order, so the report reads as a timeline.
- **Toasts auto-dismiss** in seconds and a capture usually misses them. The toast *text* is
  still in the `snapshot` output immediately after the action — cite that plus the network
  status. Never claim a toast screenshot that was not actually taken.
- Use `--full` when the evidence is below the fold.
- If a capture genuinely cannot be obtained, say so in the report and cite the alternative
  evidence. A mislabeled screenshot is worse than a missing one.

## Session hygiene during a run

- Never `close` between stories: the daemon holding the browser is what keeps the login alive.
- `agent-browser session list` shows the daemon is still up. The user-level config sets
  `idleTimeout: 2h`, so a long run with pauses survives.
- End the run with `qa-browser <report-dir> close` — with `AGENT_BROWSER_RESTORE` set by
  `.qa-env`, closing persists cookies and storage, so the next run against the same
  project+environment starts already logged in.

## Useful extras

| Need | Command |
|------|---------|
| Accessibility audit (axe-core) | `qa-browser a11y --json` |
| Core Web Vitals / hydration | `qa-browser vitals --json` |
| Visual regression | `qa-browser diff screenshot --baseline` |
| Full traffic capture | `qa-browser network har start` … `har stop <path>.har` |
| Responsive check | `qa-browser set viewport 390 844` |
| Dark mode check | `qa-browser set media dark` |
| Stub a flaky third party | `qa-browser network route "**/analytics/**" --abort` |

`a11y` and `vitals` are opt-in: run them only when the test plan asks for accessibility or
performance evidence, and report them as their own stories.
