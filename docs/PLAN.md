# Build-out plan — status

**English** · [Tiếng Việt](PLAN.vi.md)

> Historical document for maintainers: the original plan and what was done or done
> differently. To **use** the toolkit, read [GETTING-STARTED.md](GETTING-STARTED.md) instead.

Context: GitHub Free, private repos, Claude Code as sub-agents, GitHub Actions as CI,
fully automatic merge when CI passes. Shared toolkit: `kokoroou/agent-toolkit`.

Legend: ✅ in the repo · 👤 you need to do it on GitHub/your machine (cannot be automated) ·
🔀 done differently from the original plan, with a reason.

## Phase 0 — Foundations
- 👤 Make the `kokoroou/agent-toolkit` repo public → [MAINTAINING §2](MAINTAINING.md#2-one-time-repo-setup)
- 👤 `gh extension install github/gh-aw`
- ✅ Surveyed `githubnext/agentics`: `ci-doctor` was adapted into
  [`workflows/ci-doctor.md`](../workflows/ci-doctor.md) (claude engine, CI failure on
  develop/main → `needs-triage` issue). `issue-triage` and `pr-fix` served as references
  for `triage.yml` / `implement.yml mode=fix` (borrowing the read-only + safe-outputs model).
- 🔀 `verkyyi/github-agent-runner`: not surveyed in this session. The planner →
  implementer → reviewer roles stay as planned; the "spec" step lives in triage.
- ✅ `anthropics/claude-code-action@v1` is the base for calling Claude in every agent workflow.

## Phase 1 — Toolkit
- ✅ `.claude-plugin/marketplace.json` + `plugins/pipeline/`
  - 🔀 The plugin's `CLAUDE.md` → skill [`pipeline-conventions`](../plugins/pipeline/skills/pipeline-conventions/SKILL.md):
    Claude Code does **not** load a `CLAUDE.md` inside a plugin; the skill is preloaded into
    all 3 sub-agents (`skills:` frontmatter). Project-specific parts (test commands,
    architecture) live in [`templates/CLAUDE.md`](../templates/CLAUDE.md) at the project root.
  - ✅ `agents/`: `planner`, `implementer`, `reviewer` (planner/reviewer are read-only).
  - ✅ `commands/`: `/triage-issue`, `/plan-feature`, plus `/implement-issue`, `/fix-pr`, `/review-pr`.
- ✅ Reusable workflows: `triage.yml`, `merge-gate.yml`, `release.yml`, plus
  `implement.yml`, `review.yml`, `quality.yml`, `usage-report.yml`.
- ✅ Toolkit CI: `self-test.yml` (manifest, actionlint + shellcheck, caller templates
  cross-checked against the reusable workflows' inputs, trial bootstrap).
- 👤 Try it on a sandbox repo → [GETTING-STARTED §8](GETTING-STARTED.md#8-try-it-on-a-sandbox-repo)

## Phase 2 — Intake & triage
- ✅ Structured issue templates (Goal / Constraints / Acceptance criteria), feature + bug.
- ✅ Standard labels ([`templates/.github/labels.json`](../templates/.github/labels.json)), created by `bootstrap.sh`.
- ✅ `triage.yml`: runs on issue open/edit, on the `needs-triage` label, when the author
  replies to `awaiting-clarification`, and sweeps every 6 hours. Up to `max-rounds` (5)
  rounds of intent-clarifying questions, counted via hidden markers in the bot's comments,
  reset after each conclusion → beyond that, `needs-human`. Editing a `ready-for-plan`
  issue → re-triage; closing the issue → build/merge stop. Scores 0–5, assigns
  type/priority/risk/size.

## Phase 3 — GitHub Projects
- 👤 Create a Project v2 + fields `Priority`, `Size`; secret `PROJECT_TOKEN`.
- ✅ `ready` issues are added via `gh project item-add` and fields set via `gh project item-edit`.

## Phase 4 — Build sub-agent
- ✅ Each issue → branch `agent/issue-N`, ephemeral runner, `--max-turns`, restricted
  `--allowedTools` + `--disallowedTools` for push/reset/rebase/checkout.
- ✅ The plugin is installed before calling the agent — via claude-code-action's
  `plugin_marketplaces` / `plugins` inputs (equivalent to `claude plugin marketplace add`
  + `claude plugin install`).
- ✅ Concurrency group per issue/PR, never cancelling a running run.
- ✅ Circuit breaker: counts fix attempts on the PR; ≥ `max-fix-attempts` (3) →
  `needs-human`, stop. 🔀 Counts both CI failures and review change requests, not just CI.
- ✅ Starts automatically after triage when `risk≠high` and `size≤M`; a person can add `agent:implement`.

## Phase 5 — PR & CI
- ✅ PR created automatically with `Closes #N`, label `agent`; opened as draft if unfinished.
- ✅ `quality.yml`: lint → format → test → coverage (no drop vs `develop`, baseline stored
  as an artifact) → Conventional Commits PR title check.
- ✅ Security instead of CodeQL: Semgrep CLI (new findings only), Gitleaks action,
  👤 enable Dependabot alerts.
- ✅ `review.yml`: runs in parallel with CI, inline comments, writes the `agent/review` commit status.

## Phase 6 — Merge gate
- ✅ The caller triggers on `workflow_run: completed` of `CI` and `Agent Review`; checks
  every check run + commit status of the head SHA via the API.
- ✅ Pass → `gh pr merge --squash --delete-branch --match-head-commit`.
  🔀 Uses the GitHub App token when available (merging with `GITHUB_TOKEN` does not
  trigger post-merge workflows); without an App it still uses `GITHUB_TOKEN` as planned.
- ✅ Rollback: the smoke test runs inside merge-gate right after merging (not waiting for a
  push event, which may not fire), failure → revert PR + reopen the issue, `needs-human`.

## Phase 7 — Release
- 👤 Merge `develop` → `main` after review.
- ✅ `release.yml`: release-please (version, CHANGELOG, tag), build + upload artifacts.

## Phase 8 — Guardrails
- ✅ Transcript of every Claude run → artifact `transcript-*` (30 days).
- ✅ `timeout-minutes` on every job (triage 10, build 45, review 15, CI 20, gate 10).
- ✅ `usage-report.yml`: an issue summarizing Actions minutes (per workflow) + Claude cost
  (from transcripts), warning at 80% of budget; every agent job writes its cost to the
  Step Summary.

## Phase 9 — Rollout
- ✅ `scripts/bootstrap.sh <repo> --ref <tag>` copies callers + templates, creates labels, `develop`.
- ✅ Pinning by tag: `toolkit-release.yml` creates tag `vX.Y.Z` + the moving tag `vX`.
