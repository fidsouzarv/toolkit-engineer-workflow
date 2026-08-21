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
| Record the run as video | `qa-browser record start <path>` … `record stop` |
| Full traffic capture | `qa-browser network har start` … `har stop <path>.har` |
| Responsive check | `qa-browser set viewport 390 844` |
| Dark mode check | `qa-browser set media dark` |
| Stub a flaky third party | `qa-browser network route "**/analytics/**" --abort` |

`a11y` and `vitals` are opt-in: run them only when the test plan asks for accessibility or
performance evidence, and report them as their own stories.
