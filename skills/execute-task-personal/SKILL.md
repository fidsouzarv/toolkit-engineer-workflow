---
name: prompt-execute-task-personal
description: Execute a task, automatically parallelizing independent subtasks via sub-agents.
argument-hint: "[PRD path] [TechSpec path] [Tasks path] [Task ID]"
model: claude-sonnet-4-6
context: fork
disable-model-invocation: true
---

You are an AI assistant responsible for executing a specific task in a software development project.

## File Locations

- PRD: `$1`
- Tech Spec: `$2`
- Tasks: `$3`
- Task ID to execute: `$4`
- Project Rules: @.claude/rules

---

## Steps to Execute

### 1. Pre-Task Setup

- Read the task file corresponding to `$4` inside the tasks folder
- Read the PRD at `$1`
- Read the Tech Spec at `$2`
- Read `$3` (tasks.md) to understand the full task graph
- Check dependencies: confirm all tasks that `$4` depends on are marked `completed`

### 2. Task Analysis

Analyze considering:

- Main objectives of the task
- How it fits into the project context
- Alignment with project rules and standards
- Possible approaches

### 3. Task Summary

```
Task ID: [ID]
Task Name: [Name]
PRD Context: [Key points from PRD relevant to this task]
Tech Spec Requirements: [Main technical requirements]
Dependencies: [Tasks this depends on]
Main Objectives: [Primary objectives]
Risks/Challenges: [Identified risks]
```

---

### 4. Parallel Execution Check

**Before starting implementation**, read all subtasks listed under `$4` in its task file.

Count how many subtasks have **no dependency on any sibling subtask** within this same task. Call this number `P`.

**Decision — you MUST follow this exactly:**

| Condition | Action                                                                     |
| --------- | -------------------------------------------------------------------------- |
| `P < 2`   | **DO NOT use the Task tool. Implement everything yourself, sequentially.** |
| `P >= 2`  | Launch exactly one sub-agent per parallel subtask using the Task tool.     |

<critical>
If P < 2: you are FORBIDDEN from using the Task tool. Execute all subtasks yourself in sequence.
Only use the Task tool when you have counted 2 or more subtasks that are explicitly independent from each other.
</critical>

#### When P >= 2 — Sub-agent prompt template

For each parallel subtask, launch a `Task` tool call with:

```
You are implementing subtask [SUBTASK_ID] - [SUBTASK_NAME] as part of task [PARENT_TASK_ID].

Context files:
- PRD: $1
- Tech Spec: $2
- Tasks: $3

Your scope is strictly: [SUBTASK_DESCRIPTION from task file]

Rules:
- Read prd.md and techspec.md before starting. If you skip this, your work is invalid.
- Implement only what is in your subtask scope. Do NOT touch other subtasks.
- Follow all project rules in @.claude/rules
- After completing your work, mark [SUBTASK_ID] as completed in the task file.
- Report back: what you did, files changed, and any blockers.
```

#### After all sub-agents finish:

- Collect results from each sub-agent
- Resolve any conflicts between files changed in parallel
- Run integration checks if needed
- Mark the parent task `$4` as `completed` in `$3`

---

### 5. Approach Plan (for sequential tasks or main-agent work)

```
1. [First step]
2. [Second step]
3. [Additional steps]
```

---

## Important Notes

- Always verify against PRD, tech spec, and task file
- Implement proper solutions **without workarounds**
- Follow all established project standards
- Sub-agents must be self-contained: pass all context explicitly, never assume shared state

## Implementation

After the summary and parallel check, **immediately begin implementation**.

**YOU MUST** start implementation right after the process above.

<critical>After completing ALL subtasks (parallel or sequential), mark task `$4` as `completed` in `$3`.</critical>
