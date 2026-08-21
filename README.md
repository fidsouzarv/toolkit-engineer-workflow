# Toolkit Engineer Workflow

A personal toolkit for AI-assisted software engineering using [Claude Code](https://claude.ai/code). It provides a structured workflow — from requirements to delivery — through slash commands, skills, agents, and document templates.

---

## Workflow Overview

```
Requirements → PRD → Tech Assessment → Task List → Execute → Code Review
```

Each step has a dedicated command, skill, or template to keep the process consistent and repeatable.

---

## Structure

```
toolkit-engineer-workflow/
├── agents/         # Subagents invoked automatically during commands
├── commands/       # Slash commands for Claude Code (/prompt-create-prd, etc.)
├── skills/         # Reusable skills for recurring workflows
└── templates/      # Markdown document templates
```

---

## Commands

Place files from `commands/` in `~/.claude/commands/` to use them as slash commands in Claude Code.

### `/prompt-create-prd`
Creates a Product Requirements Document (PRD) from a feature request.

- Asks clarifying questions before generating anything
- Follows the `template-prd.md` structure
- Saves output to `./tasks/prd-[feature-name]/prd.md`
- Model: `claude-opus-4-6`

### `/prompt-create-tech-assessment`
Creates a Tech Spec (Technical Assessment) from an existing PRD.

- Automatically invokes the `context-enricher` agent to fetch up-to-date library documentation via Context7
- Performs deep project analysis before writing
- Follows the `template-tech-assessment-clojure-en.md` structure
- Saves output to `./tasks/prd-[feature-name]/techspec.md`
- Model: `claude-opus-4-6`

### `/prompt-create-tasks`
Creates a detailed task list from a PRD + Tech Spec pair.

- Shows high-level tasks for approval before generating files
- Produces a `tasks.md` summary and individual `[num]_task.md` files
- Separates sequential dependencies from parallelizable tasks
- Saves to `./tasks/prd-[feature-name]/`
- Model: `claude-opus-4-6`

---

## Skills

Place directories from `skills/` in `~/.claude/skills/` to use them as skills in Claude Code.

### `execute-task-personal`
Executes a specific task from the task list, automatically parallelizing independent subtasks via sub-agents.

**Usage:** `execute-task-personal [PRD path] [TechSpec path] [Tasks path] [Task ID]`

- Reads PRD, Tech Spec, and task graph before starting
- Checks that all task dependencies are marked `completed`
- If 2+ subtasks are independent → launches parallel sub-agents via `Task` tool
- If fewer than 2 parallel subtasks → executes sequentially
- Marks the task as `completed` when done

### `requesting-code-review`
Dispatches a `code-reviewer` subagent to review code changes at a specific git range.

- Should be used after each task, major feature, or before merging
- Reviewer receives only the diff context — not your session history
- Issues are categorized as Critical, Important, or Minor
- Critical and Important issues must be fixed before proceeding

### `receiving-code-review`
Protocol for handling incoming code review feedback with technical rigor.

- Verify before implementing — never apply feedback blindly
- Ask for clarification on unclear items before implementing anything
- Push back with technical reasoning when a suggestion is wrong
- No performative agreement ("great point!", "you're absolutely right!")
- Fix items one at a time, test each

### `fullstack-pr-qa`
Runs manual browser QA of any web project against any environment and writes a screenshot-backed report.

**Usage:** `/fullstack-pr-qa [projeto] [plano] [auth] [ambiente]`

```
/fullstack-pr-qa ~/dev/minha-app ./docs/plano-checkout.md @minha-app-staging staging
/fullstack-pr-qa ~/dev/minha-app pr:42 env:QA_USER,QA_PASS localhost
```

- Four named positional arguments, declared in frontmatter and substituted into the skill body as `$projeto`, `$plano`, `$auth` and `$ambiente`; quote any value containing spaces
- Runs as `context: fork` with `background: false` — the coordinator passes the whole context through those four arguments, and the skill returns a self-contained verdict
- Project-agnostic: everything stack-specific comes from the four arguments or the project's own `qa.config.json`
- Drives a real Chrome through the [agent-browser](https://agent-browser.dev) CLI, in an isolated session per project + environment
- Credentials always resolve to an encrypted agent-browser auth vault profile — never a file, a log, or the report
- Captures accessibility snapshots, network status codes and screenshots as evidence for every user story
- Writes the report to `<project-root>/qa-analyze/<slug>/qa-results.md`
- Separates product defects (FAIL) from environment blockers (BLOCKED), so deploy lag never reads as a bug

**Requires:** `agent-browser` on `PATH` (`brew install agent-browser` or `npm i -g agent-browser`, then `agent-browser install`).

---

## Agents

Place files from `agents/` in `~/.claude/agents/` to make them available as subagents.

### `context-enricher`
A specialist subagent that fetches up-to-date documentation from Context7 before a tech assessment.

- Invoked automatically by `/prompt-create-tech-assessment` when tools need documentation context
- Resolves library IDs and fetches focused docs (max 3 calls per tool)
- Returns a structured `Documentation Context Report` to the main Claude instance
- Model: `claude-haiku-4-5`

---

## Templates

Place files from `templates/` in `~/.claude/templates/`. Commands reference these templates directly.

| File | Used by |
|------|---------|
| `template-prd.md` | `/prompt-create-prd` |
| `template-ta.md` | General tech assessment |
| `template-tech-assessment-clojure-en.md` | `/prompt-create-tech-assessment` |
| `template-task-list.md` | `/prompt-create-tasks` (tasks.md) |
| `template-task.md` | `/prompt-create-tasks` (individual task files) |

---

## Installation

Copy each folder to the corresponding Claude Code config directory:

```bash
cp -r agents/*    ~/.claude/agents/
cp -r commands/*  ~/.claude/commands/
cp -r skills/*    ~/.claude/skills/
cp -r templates/* ~/.claude/templates/
```

---

## Example End-to-End Flow

```
1. /prompt-create-prd "add authentication via OAuth"
   → Asks clarifying questions
   → Saves: tasks/prd-auth-oauth/prd.md

2. /prompt-create-tech-assessment tasks/prd-auth-oauth/prd.md
   → context-enricher fetches OAuth library docs
   → Saves: tasks/prd-auth-oauth/techspec.md

3. /prompt-create-tasks tasks/prd-auth-oauth/prd.md tasks/prd-auth-oauth/techspec.md
   → Shows high-level task list for approval
   → Saves: tasks/prd-auth-oauth/tasks.md + individual task files

4. execute-task-personal [prd] [techspec] [tasks] 1.0
   → Executes Task 1.0, parallelizing independent subtasks
   → Marks task as completed

5. /requesting-code-review
   → Dispatches code-reviewer subagent on the diff
   → Returns issues by severity

6. /receiving-code-review
   → Apply feedback with technical rigor
   → Push back if reviewer is wrong
```
