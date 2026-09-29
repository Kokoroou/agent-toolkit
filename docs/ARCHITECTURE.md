# Pipeline architecture

**English** · [Tiếng Việt](ARCHITECTURE.vi.md)

**Summary:** an issue is *triaged* (Claude only returns JSON, bash applies the labels) →
the *build agent* writes code in a job holding only a read token, and a separate job checks
the result before pushing and opening a PR → *CI* and the *reviewer* run in parallel → the
*merge gate* merges green PRs into `develop` or sends them back for a fix (up to 3 times) →
you merge `develop` → `main` to release. Every failure stops at the `needs-human` label.
Sections: [detailed flow](#overall-flow) · [changing requirements and cancelling](#changing-requirements-and-cancelling) ·
[design principles](#design-principles) · [GitHub pitfalls](#github-pitfalls-already-handled) ·
[labels](#labels).

## Overall flow

```
 Issue (template: Goal / Constraints / Acceptance criteria)  ── label needs-triage
   │
   ▼  agent-triage.yml ─ uses ─▶ triage.yml
   │     Claude (read-only) returns JSON {decision, score, type, priority, risk, size, questions…}
   │     the workflow applies labels / comments / GitHub Projects from that JSON
   │     ├─ clarify      → awaiting-clarification, ask ≤3 intent questions (up to max-rounds ≤ 5 rounds)
   │     ├─ needs-human  → stop
   │     ├─ reject       → comment / close if duplicate
   │     └─ ready        → ready-for-plan (+ Projects: Priority, Size)
   │                        comment: "Next: /pipeline:build N"
   ▼
 Build — default: you, in Claude Code (your machine, or on the web)
   │     /pipeline:build N (skill) → branch agent/issue-N → sub-agent planner → sub-agent
   │     implementer → checks → you confirm → push + PR "Closes #N" (label agent)
   │     local sandbox (agent-session.sh run) blocks the push → `publish` does it after you exit
   │
   │  or on GitHub Actions: label agent:implement, or automatically when the repository
   │  variable AGENT_AUTO_BUILD=true (risk≠high && size≤M → workflow_dispatch):
   │     agent-implement.yml ─ uses ─▶ implement.yml (mode=implement)
   │     /pipeline:implement-issue N with a read-only token; the publish job pushes + opens the PR
   ▼
 PR → develop ──┬─▶ ci.yml ─ uses ─▶ quality.yml   lint → format → test → coverage ≥ develop
                │                                   PR title · Gitleaks · Semgrep
                └─▶ agent-review.yml ─ uses ─▶ review.yml   sub-agent reviewer,
                                                commit status agent/review on the head SHA
   ▼  (workflow_run: completed of CI or Agent Review)
 agent-merge-gate.yml ─ uses ─▶ merge-gate.yml
   │   reads every check run + commit status of the head SHA via the Checks/Statuses API
   │   ├─ wait    → checks still running / agent/review missing
   │   ├─ blocked → needs-human, risk:high, do-not-merge, conflict, bad title
   │   ├─ fix-manual → comment once per head: "/pipeline:build pr P" (default)
   │   ├─ fix     → auto-fix (AGENT_AUTO_BUILD=true): implement.yml mode=fix (CI log + review
   │   │             findings); circuit breaker: ≥ max-fix-attempts → needs-human, stop
   │   └─ merged  → squash, delete branch, close issue
   │                 → smoke test on develop; failure → revert PR (needs-human)
   ▼
 develop ──(you review, merge by hand)──▶ main ─▶ release.yml (release-please: version,
                                                  CHANGELOG, tag, build, upload artifacts)
```

Guardrails run alongside: every Claude run's transcript is uploaded as an artifact
(`transcript-<agent>-<n>`), every agent job writes cost/turns/duration to its Step
Summary, and `usage-report.yml` updates a weekly issue summarizing Actions minutes +
Claude cost. `workflows/ci-doctor.md` (gh-aw) catches CI failures on `develop`/`main` and
turns them into `needs-triage` issues, feeding back into the start of the pipeline.

## Changing requirements and cancelling

- **Changing requirements = editing the issue.** Editing an issue in `needs-triage`,
  `awaiting-clarification` or `ready-for-plan` re-triggers triage. The round count only
  counts bot questions *after* the latest conclusion (ready / needs-human / reject), so
  each re-triage starts from 0.
- **Old PRs are never merged silently.** Re-triaging an issue that was `ready-for-plan`
  adds `needs-human` to its open agent PR. If the issue is edited while a build is running,
  the PR is opened as a draft + `needs-human`.
- **Cancelling = closing the issue.** Triage and build (`implement` and `fix`) skip closed
  issues; the `publish` step re-checks before pushing, so an in-flight build neither pushes
  nor opens a PR; the merge gate blocks PRs whose linked issue is closed and adds
  `needs-human`.

## Design principles

1. **Claude decides, the workflow executes.** Triage and review return JSON via
   `--json-schema`; labels, comments, merges and pushes are all done by deterministic
   bash. A prompt-injected issue can at worst pick the wrong label — like gh-aw's
   *safe-outputs* model.
2. **Agents never hold a write token (Lethal Trifecta).** The build agent runs in its own
   job with a *read-only* token; commits leave the job as a `git bundle`, and a `publish`
   job on a clean runner checks the bundle before pushing. No agent has
   WebFetch/WebSearch; issues from outsiders do not start builds automatically.
   Capability matrix: [SECURITY.md](SECURITY.md).
3. **State is tied to the SHA.** Review writes the commit status on the head SHA, the
   merge gate uses `--match-head-commit`, and fix mode skips if the PR has newer commits →
   nothing is ever merged or fixed based on stale results.
4. **Fail towards a human.** Every failure path (out of rounds, circuit breaker, conflict,
   smoke failure, no commits) ends with the `needs-human` label, and every agent workflow
   skips issues/PRs carrying it.
5. **All logic lives in the toolkit.** Project repos only hold thin caller YAML +
   `CLAUDE.md`, so updating the toolkit updates every project pinned to the moving `@v0`
   tag (or pin `@v0.1.0` for control).

## GitHub pitfalls already handled

| Pitfall | Consequence if ignored | How the toolkit handles it |
|---|---|---|
| Events created by `GITHUB_TOKEN` (push, PR, label, merge) **do not trigger other workflows** (except `workflow_dispatch`/`repository_dispatch`) | Agent PRs run no CI, merges run no smoke test, the `ready-for-plan` label does not start a build | Recommend a GitHub App (`AGENT_APP_ID`/`AGENT_APP_PRIVATE_KEY`). Without an App: triage *dispatches* agent-implement, implement/merge-gate *dispatch* `ci.yml`, and the smoke test runs inside the merge gate |
| Free + private repos have no branch protection / rulesets | Native auto-merge cannot gate on checks | `merge-gate.yml` checks the Checks + Statuses APIs itself, then `gh pr merge --match-head-commit` |
| `Closes #N` only closes the issue when merging into the **default branch** | Issues stay open after merging into `develop` | The merge gate closes the issue explicitly |
| `workflow_run`, `schedule`, `workflow_dispatch` only read workflows from the **default branch** | Callers placed on `develop` never run | Commit the callers to the default branch (see [ADD-TO-PROJECT §7](ADD-TO-PROJECT.md#7-choose-the-default-branch)) |
| `claude-code-action` rejects bot actors | Review/fix do not run on PRs created by the App | `allowed-bots` input (default `*`, suitable for private repos) |
| **User**-owned Projects v2 accept neither `GITHUB_TOKEN` nor GitHub Apps | Items cannot be added | `PROJECT_TOKEN` secret (classic PAT, scopes `project`, `repo`) |
| CodeQL needs Advanced Security on private repos | No SAST | Semgrep CLI (new findings vs base only) + Gitleaks + Dependabot |
| `gitleaks-action` needs a license for **organization** repos | Job fails | `GITLEAKS_LICENSE` secret (free registration), not needed for personal accounts |

## Why the main pipeline is not written in gh-aw

`gh-aw` compiles each Markdown workflow into a `.lock.yml` *in the target repo*
(`gh aw add` + `gh aw compile`), so it cannot be called via `uses: …@v1` as Phase 9
requires, and its safe-outputs model lacks the push/merge/circuit-breaker steps the build
loop needs. So:

- **The gated pipeline** (triage → build → review → merge → release): reusable workflows
  + `anthropics/claude-code-action@v1`, borrowing gh-aw's read-only + safe-outputs
  principles.
- **Observing, non-gating agents** (`workflows/ci-doctor.md`, and other workflows from
  `githubnext/agentics` if you like): use gh-aw, installed with
  `gh aw add kokoroou/agent-toolkit/ci-doctor`.

## Labels

| Group | Labels |
|---|---|
| Issue state | `needs-triage` → `awaiting-clarification` → `ready-for-plan`; `needs-human` |
| Control | `agent:implement` (added by a person to build on GitHub Actions), `agent` (PR created by the agent, eligible for auto-merge), `do-not-merge`, `revert` |
| Classification | `type:*`, `priority:P0..P3`, `risk:low/medium/high`, `size:XS..XL` |

`risk:high` is never auto-implemented or auto-merged.
