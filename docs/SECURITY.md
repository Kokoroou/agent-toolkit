# agent-toolkit security

**English** · [Tiếng Việt](SECURITY.vi.md)

_Reviewed: 2026-09 · scope: `.github/workflows/*`, `templates/`, `scripts/`, the `pipeline` plugin._

**Summary:**

- No agent simultaneously reads untrusted content, holds a write token and has an outbound
  channel: each agent has at least one leg cut **by configuration** ([matrix](#capability-matrix)).
- The build agent runs with a **read-only** token; its commits are checked in another job
  before being pushed.
- Issues from outsiders do not start builds automatically; agents have no WebFetch/WebSearch.
- 12/14 findings fixed, 2 kept on purpose ([table](#findings-and-status)).
  Remaining risk: the build agent still has network access to install dependencies ([details](#build-agent-3-jobs)).

## Model: the Lethal Trifecta

An LLM agent becomes dangerous when it has all three of these **at once**
([Simon Willison](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/)):

- **P — private data / privileges**: private source code, secrets, tokens with write access;
- **U — untrusted content**: issues, comments, PR diffs, CI logs — anyone who can write
  them can inject instructions into the prompt;
- **X — an outbound channel**: network calls, or actions with effects outside the job
  (push, comment, merge).

Prompt injection cannot be fully stopped by prompting, so the toolkit cuts at least one
leg of every agent **by configuration**, not by relying on the model "knowing to refuse".

### Capability matrix

| Agent | P: what the agent sees | U: what content it reads | X: how the agent affects the outside | Leg cut |
|---|---|---|---|---|
| Triage (`triage.yml`) | Repo (read), issue read token | Issue + comments (anyone can write on a public repo) | **None**: only returns schema-bound JSON; bash applies labels/comments. No arbitrary Bash, WebFetch, WebSearch | **X** |
| Review (`review.yml`) | Repo + PR (read) | PR diff, PR description | Only inline PR comments + a verdict JSON. Runs no code, no network | **X** (only an in-repo channel remains) |
| Build (`implement.yml`, job `agent`) | Repo (read), **read-only** token, Claude API key | Issues/PRs from **collaborators** (default), CI logs | Has network when running project commands (`npm run`…), but **no** write token; commits leave only via a bundle checked by `publish` | **U** (trusted authors) + **P** (no write token) |
| Merge gate, publish, revert | Write token | Structured data only | Merge, push | No LLM |

On a **private repo** everyone writing issues/comments is a collaborator, so these limits
change nothing in daily operation — they guard against public repos, compromised
collaborator accounts, or malicious content slipping in via dependencies/logs.

### Build agent: 3 jobs

```
prepare (write token, runs no project code)  → circuit breaker, branch, starting commit (SHA)
agent   (READ-ONLY token)                    → project setup + Claude → git bundle + JSON
publish (write token, clean runner)          → verify bundle → push → PR
```

`publish` treats everything from `agent` as untrusted data: the JSON must match the
schema, the bundle may only add commits on top of the exact SHA chosen by `prepare`, and
it may not modify `.github/workflows/` unless the caller sets `allow-workflow-changes: true`.
Anything the agent (or code it runs) writes on the runner — `.git/config`, hooks,
`$GITHUB_ENV`, `$GITHUB_PATH`, fake binaries — stays on the `agent` job's runner and never
reaches the push job.

**Residual risk (accepted):** the `agent` job still has network access (needed for
`npm ci` and the Claude API), so a hijacked agent could send *source code* out. The U leg
is reduced by `auto-implement-trusted-only`; keep `extra-allowed-tools` as narrow as
possible. Cutting the X leg entirely requires a self-hosted runner with an egress firewall
(allowing only `api.anthropic.com`, `github.com` and package registries).

## Findings and status

| # | Severity | Issue | Status |
|---|-----|--------|-----------|
| 1 | High | The build agent's Claude step had a write `GH_TOKEN`; `Bash(npm run:*)` + `Edit` = arbitrary code execution → token theft | **Fixed**: the `agent` job only has a read token |
| 2 | High | The push step ran after the agent could modify `.git/config`, hooks, `$GITHUB_ENV`, `$GITHUB_PATH` | **Fixed**: push happens in the `publish` job on a clean runner, from a verified bundle |
| 3 | High | Issues from outsiders (public repo) triaged `ready` started the build agent automatically | **Fixed**: `auto-implement-trusted-only` (default `true`) |
| 4 | High | The GitHub App token inherited **all** of the App's permissions | **Fixed**: each job requests exactly its `permission-*`; *Workflows* only with `allow-workflow-changes: true` |
| 5 | Medium | The smoke test ran freshly merged code in a job with a write token, reverting the PR on the same runner | **Fixed**: read-only `smoke` job, separate `revert` job |
| 6 | Medium | `quality.yml`: the project's lint/test commands received `GH_TOKEN` | **Fixed**: only the coverage comparison step gets the token |
| 7 | Medium | Actions pinned by tag; tags can be moved | **Fixed**: pinned by SHA with a version comment; Dependabot updates them |
| 8 | Medium | `self-test.yml` downloaded the actionlint script from the `main` branch | **Fixed**: downloaded from a release tag |
| 9 | Medium | `toolkit-release.yml` persisted credentials on checkout | **Fixed**: `persist-credentials: false`, push with an explicit token |
| 10 | Low | Templates used `secrets: inherit` | **Fixed**: each workflow gets exactly the secrets it needs |
| 11 | Low | Agents could use WebFetch/WebSearch as an outbound channel | **Fixed**: `--disallowedTools WebFetch,WebSearch` on every agent |
| 12 | Low | `allowed-bots: "*"` | Kept: suitable for private repos (agent PRs are created by a bot). Public repos should list specific bots |
| 13 | Low | `setup-command`/`smoke-command`… interpolated directly into `run:` (Semgrep `run-shell-injection`, zizmor `template-injection`) | **Fixed**: commands go through environment variables then `eval`, never interpolated into the script |
| 14 | — | `agent-merge-gate.yml` uses `workflow_run` | Accepted: skips fork PRs, checks the head SHA, never checks out PR code |

## Security tooling

| Tool | Where | What it checks |
|---------|-------|-------------|
| zizmor (blocks from *medium*) | `self-test.yml`, config `.github/zizmor.yml` | GitHub Actions vulnerabilities: template injection, excessive permissions, credential persistence, unpinned actions, actions with known vulnerabilities |
| Gitleaks | `quality.yml` (projects) + `self-test.yml` (toolkit) | Secrets leaked into git history |
| Semgrep `p/default` | same as above | Security bugs in code, only new findings vs the baseline |
| actionlint + shellcheck | `self-test.yml` | Workflow syntax, embedded scripts |
| Dependabot | `.github/dependabot.yml`, `templates/.github/dependabot.yml` | Action (including pinned SHAs) / library updates, CVE alerts |

## Behavior changes when upgrading

- The agent can only push changes under `.github/workflows/` when the caller sets
  `allow-workflow-changes: true` (in `agent-implement.yml` and the `fix` job of
  `agent-merge-gate.yml`); otherwise the run stops with the `needs-human` label.
- Issues opened by non-collaborators are not auto-implemented (private repos are
  unaffected). Disable with `auto-implement-trusted-only: false`.
- The caller templates pass secrets by name: `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`,
  `AGENT_APP_ID`, `AGENT_APP_PRIVATE_KEY`, `PROJECT_TOKEN` — the same names `install.sh`
  sets — and `GITLEAKS_LICENSE` (add it yourself for organization repos). Already-installed
  projects may keep `secrets: inherit`; both ways work.

## Node 24 on GitHub Actions

Every JavaScript action now uses its Node 24 release: `actions/checkout` v5, `setup-node`
v5, `upload-artifact` v6, `download-artifact` v7, `create-github-app-token` v3,
`release-please-action` v5, `gitleaks-action` v3 (`upload-artifact` v5 and
`download-artifact` v5/v6 are still Node 20). `anthropics/claude-code-action` is a
composite action that internally uses `oven-sh/setup-bun` v2.2.0 (Node 24). The default
smoke command uses `npm test -- smoke` because Jest 30 dropped the `--testPathPattern` flag.
