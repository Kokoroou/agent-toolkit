---
description: Produce a file-level implementation plan for an issue using the planner sub-agent, without changing code.
argument-hint: <issue-number>
allowed-tools: Read, Grep, Glob, Task, Bash(gh issue view:*), Bash(git log:*), Bash(git diff:*), Bash(git ls-files:*)
---

Use the **planner** sub-agent to plan issue **#$1**. Return its Markdown plan verbatim.
Do not edit any file. If the planner reports blocking open questions, say so first.
