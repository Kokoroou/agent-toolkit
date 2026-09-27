---
description: Review a pull request with the reviewer sub-agent, post inline comments for blocking findings, and return a verdict.
argument-hint: <pr-number>
---

Review pull request **#$1**.

1. Delegate to the **reviewer** sub-agent with the PR number.
2. For each blocking finding it reports, post one inline comment on the exact line with
   `mcp__github_inline_comment__create_inline_comment` (when that tool is available),
   including the failure scenario and suggested fix. Do not post style nits inline.
3. Return the structured output: `verdict` (`approve` / `request-changes` / `needs-human`),
   `summary` (≤ 5 sentences, lists blocking findings as `path:line — problem`), and
   `risk`. The workflow posts the summary and applies labels.
