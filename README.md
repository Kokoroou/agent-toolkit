# agent-toolkit

**English** · [Tiếng Việt](README.vi.md)

**Let Claude Code handle your GitHub issues end to end: ask clarifying questions, write
code + tests, open a PR, review and merge it — you open issues, say when to build, and
approve releases.**

- Runs on **GitHub Free**, private repos included, using GitHub Actions.
- You decide when an issue is built: triage marks it ready, then you say
  `/pipeline:build 42` in Claude Code on your machine or on the web, where the agent has
  your full harness (tools, hooks, sandbox). Building on GitHub Actions is one repository
  variable away (`AGENT_AUTO_BUILD=true`).
- Shared by every project: a project repo only keeps a few thin YAML files that call into
  this toolkit, so upgrading one place updates every project.
- Safe by default: agents on GitHub Actions never hold a write token, pushes from your own
  sessions wait for your OK, high-risk work is never auto-merged,
  and every failure stops and waits for a person (the `needs-human` label).

```
issue ─▶ triage ─▶ (you: /pipeline:build) ─▶ planner ─▶ implementer ─▶ PR ─▶ CI + reviewer ─▶ merge gate ─▶ develop ─▶ (you) ─▶ main ─▶ release
            │                                                                │                │
            └─ asks back ≤5 rounds                                           └─ fix ──────────┴─ fail → needs-human / revert
```

Two branch models, switchable at any time with `scripts/switch-branch-model.sh`
([ADD-TO-PROJECT §7.1](docs/ADD-TO-PROJECT.md#71-branch-model-gitlab-flow-or-github-flow)):
**gitlab-flow** (above: `develop` for the team's testing, an automatic promotion PR
`develop` → `main` for QA, `main` synced back into `develop` after each release) or
**github-flow** (agent PRs go straight to `main`, for a solo project). The toolkit ships
the shared CI/CD per language (lint, format, test, coverage, release-please); how your
project builds and deploys stays yours.

## Get started in 3 steps

1. **One-time setup** (~15 min): a Claude token + a GitHub App →
   [GETTING-STARTED §4–5](docs/GETTING-STARTED.md#4-get-your-claude-credentials).
2. **Install into a project** — from your project's clone, run:

   ```bash
   # Linux / macOS / WSL
   curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.sh | bash
   ```

   ```powershell
   # Windows
   irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1 | iex
   ```

   The script detects your stack, asks for the branch model, copies the workflows, creates
   labels (+ the `develop` branch for gitlab-flow), sets secrets, enables repo settings and
   commits; it only asks for what is missing.
3. **Fill in `CLAUDE.md`, then open a small issue** and watch the whole loop run →
   [ADD-TO-PROJECT §8](docs/ADD-TO-PROJECT.md#8-commit-and-verify).

## What to read next

| You want to | Read | Time |
|---|---|---|
| Understand what the pipeline does, prepare accounts, try it on a sandbox | [GETTING-STARTED.md](docs/GETTING-STARTED.md) | 10 min |
| Install into a project, adapt to your stack, upgrade, troubleshoot | [ADD-TO-PROJECT.md](docs/ADD-TO-PROJECT.md) | reference |
| Look up a common task or question ("how do I…", "why does…") | [FAQ.md](docs/FAQ.md) | reference |
| Understand the design, detailed flow, GitHub pitfalls | [ARCHITECTURE.md](docs/ARCHITECTURE.md) | 5 min |
| Assess the security risks | [SECURITY.md](docs/SECURITY.md) | 5 min |
| Run the agent yourself (machine / Claude cloud): encrypted secrets, storage, sandbox | [AGENT-SESSION.md](docs/AGENT-SESSION.md) | 10 min |
| Change or release the toolkit itself | [MAINTAINING.md](docs/MAINTAINING.md) | maintainers |
| History of the build-out and status of each item | [PLAN.md](docs/PLAN.md) | reference |

## Glossary

| Term | Meaning |
|---|---|
| **Triage** | An agent reads the issue, asks back if unclear, then labels type / priority / risk / size |
| **Build agent** | An agent that plans (*planner*) then writes code + tests (*implementer*) on branch `agent/issue-N` |
| **Reviewer** | An agent that reviews the PR, comments inline and records the verdict in the `agent/review` status |
| **Merge gate** | A workflow that replaces branch protection: green PR → squash-merge; red PR → sent back for a fix |
| **Circuit breaker** | Still red after 3 fixes → stop and add `needs-human` |
| **`needs-human`** | "A person's turn" label: every agent skips issues/PRs that carry it |
| **Caller workflow** | A thin YAML file in the project repo that calls a toolkit *reusable workflow* via `uses: …@v0` |
| **`@v0`** | A moving tag pointing at the latest 0.x release; projects get fixes without changing anything |

## Upgrading

Pipeline logic updates itself through the `@v0` tag. Files copied into your project are
upgraded with the command below (your edits are kept via a 3-way merge; details:
[ADD-TO-PROJECT §10](docs/ADD-TO-PROJECT.md#10-pin-and-upgrade-the-toolkit-version)):

```bash
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/upgrade.sh | bash -s -- --dry-run
```

## Using the plugin by hand

The pipeline's agents also work in Claude Code on your machine, no workflows or secrets
needed:

```bash
claude plugin marketplace add kokoroou/agent-toolkit
claude plugin install pipeline@agent-toolkit
# inside Claude Code: /pipeline:plan-feature 42
```

Command list: [GETTING-STARTED §7](docs/GETTING-STARTED.md#7-use-the-plugin-by-hand-optional).

**Building an issue** (the default way): in a Claude Code session on the project — on
your machine or on the web — run `/pipeline:build 42`, or just ask Claude to build issue
42. It branches, plans, implements, runs the checks, then pushes and opens the `agent` PR
that review and the merge gate pick up. `/pipeline:build pr 57` fixes a PR whose checks
failed. `/pipeline:build` with no argument ranks the ready issues and red PRs, proposes an
order, and builds the ones you approve one after another. For `.env` encrypted in the repo, untracked files on B2/Google Drive and a sandbox
that keeps the agent away from the storage: `scripts/agent-session.sh run` →
[AGENT-SESSION.md](docs/AGENT-SESSION.md).

## What's in this repo

<details>
<summary>Component table (for readers of the code)</summary>

| Path | What it is |
|---|---|
| [`plugins/pipeline/`](plugins/pipeline) | Claude Code plugin: sub-agents `planner` / `implementer` / `reviewer`, commands `/triage-issue` `/plan-feature` `/implement-issue` `/fix-pr` `/review-pr`, skills `build` (interactive build / fix) and `pipeline-conventions` |
| [`.github/workflows/triage.yml`](.github/workflows/triage.yml) | Clarify, score and label issues; add them to GitHub Projects |
| [`.github/workflows/implement.yml`](.github/workflows/implement.yml) | Build agent: branch `agent/issue-N`, commit, PR; fix mode + circuit breaker |
| [`.github/workflows/review.yml`](.github/workflows/review.yml) | Review PRs, inline comments, commit status `agent/review` |
| [`.github/workflows/quality.yml`](.github/workflows/quality.yml) | CI: lint → format → test → no coverage drop, PR title, Semgrep + Gitleaks |
| [`.github/workflows/merge-gate.yml`](.github/workflows/merge-gate.yml) | Home-made merge gate (replaces branch protection), smoke test + revert |
| [`.github/workflows/release.yml`](.github/workflows/release.yml) | release-please + build + upload artifacts |
| [`.github/workflows/branch-sync.yml`](.github/workflows/branch-sync.yml) | gitlab-flow: promotion PR `develop` → `main`, merge `main` back into `develop` |
| [`.github/workflows/usage-report.yml`](.github/workflows/usage-report.yml) | Actions minutes + Claude cost report |
| [`workflows/ci-doctor.md`](workflows/ci-doctor.md) | gh-aw workflow: CI failures on develop/main → issue |
| [`templates/`](templates) | Files copied into the project repo (caller workflows, issue templates, labels, `CLAUDE.md`) |
| [`scripts/install.sh`](scripts/install.sh), [`install.ps1`](scripts/install.ps1) | One-command install into a project repo (files, secrets, settings, commit) |
| [`scripts/upgrade.sh`](scripts/upgrade.sh) | Upgrade the copied files to a newer toolkit release, keeping your edits via 3-way merge |
| [`scripts/switch-branch-model.sh`](scripts/switch-branch-model.sh) | Switch a project between gitlab-flow and github-flow (files, default branch, `develop`) |
| [`scripts/bootstrap.sh`](scripts/bootstrap.sh) | The file copy + labels + `develop` (gitlab-flow) part that `install.sh` uses |
| [`templates/scripts/agent-session.sh`](templates/scripts/agent-session.sh) | Copied into projects: age-encrypted `.env`, rclone storage, sandboxed local Claude sessions ([AGENT-SESSION.md](docs/AGENT-SESSION.md)) |

A caller workflow in a project repo looks like this (full versions in
[`templates/.github/workflows/`](templates/.github/workflows)):

```yaml
jobs:
  triage:
    uses: kokoroou/agent-toolkit/.github/workflows/triage.yml@v0
    with:
      issue-number: ${{ github.event.issue.number }}
    secrets:
      anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
      claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

</details>

## Developing the toolkit

```bash
scripts/lint.sh   # needs claude, actionlint, shellcheck, jq
```

Use Conventional Commits; `toolkit-release.yml` publishes `vX.Y.Z` and moves the `vX` tag.
Details: [docs/MAINTAINING.md](docs/MAINTAINING.md).
