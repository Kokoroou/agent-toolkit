# Add agent-toolkit to a project

**English** · [Tiếng Việt](ADD-TO-PROJECT.vi.md)

How to install the agent pipeline into **one project repo** (new or with existing code).

> First time using the toolkit? Do [GETTING-STARTED.md](GETTING-STARTED.md) first: get your
> Claude credentials and create the GitHub App (once for all projects).

**Shortest path (~10 min + agent run time):**

1. Run the [install command](#one-command-install) from your project's clone.
2. Check the lint/test/coverage commands the script filled in for your stack → [§3](#3-adapt-the-workflows-to-your-stack).
3. Fill in `CLAUDE.md` (commands, architecture, what not to touch) → [§4](#4-write-claudemd).
4. Open a small issue and watch it go through the whole loop → [§8](#8-commit-and-verify).

Sections 1–9 describe each step the installer performs, for doing it by hand or tuning
later. Sections 10–12 are for later: upgrades, day-to-day operation, troubleshooting.

Contents:

- [One-command install](#one-command-install)
0. [Checklist](#0-checklist)
1. [Prepare the repo](#1-prepare-the-repo)
2. [Run bootstrap](#2-run-bootstrap) *(manual install)*
3. [Adapt the workflows to your stack](#3-adapt-the-workflows-to-your-stack)
4. [Write `CLAUDE.md`](#4-write-claudemd)
5. [Add secrets](#5-add-secrets) *(manual install)*
6. [Configure repo Settings](#6-configure-repo-settings) *(manual install)*
7. [Choose the default branch](#7-choose-the-default-branch)
8. [Commit and verify](#8-commit-and-verify)
9. [Optional: Projects, Dependabot, ci-doctor, release](#9-optional)
10. [Pin and upgrade the toolkit version](#10-pin-and-upgrade-the-toolkit-version)
11. [Day-to-day operation](#11-day-to-day-operation)
12. [Troubleshooting](#12-troubleshooting)

---

## One-command install

Prerequisites: the repo exists on GitHub, has at least one commit, and you are an admin.
From your project's clone, run:

```bash
# Linux, macOS, WSL, Git Bash
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.sh | bash
```

```powershell
# Windows PowerShell
irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1 | iex
```

The script (`scripts/install.sh`; the Windows version installs Git for Windows and GitHub
CLI with `winget` if missing, then runs that same script under Git Bash) does, in order:

| Step | What it does | Matching section |
|---|---|---|
| 1 | Checks `git`, `gh` (offers to install if missing) and `gh auth login` | GETTING-STARTED §3 |
| 2 | Detects the stack (`package.json` + lockfile → node/pnpm/yarn, `pyproject.toml`/`requirements.txt` → python, `go.mod` → go) and the linter, formatter and test runner the project uses, copies the templates with the matching commands, creates labels and the `develop` branch | §2, §3 |
| 3 | Sets secrets: Claude token, App ID + private key, `PROJECT_TOKEN` | §5 |
| 4 | Enables *Workflow permissions* (read/write + create PRs), squash merge, delete branch after merge, Dependabot alerts | §6 |
| 5 | Commits `.github/` + `CLAUDE.md`, pushes to the default branch and `develop`, makes `develop` the default branch | §7, §8 |

It only asks for what is missing: the stack (Enter accepts the detected value), how to
sign in to Claude and the token (hidden input; the script can run `claude setup-token` for
you), the App ID and `.pem` path (it guesses the newest file in `~/Downloads`), and whether
to commit / change the default branch. Secrets already in the repo are kept unless you
agree to replace them.

Run it with the default branch checked out (after the first run that is usually
`develop`): on any other branch it stops before writing a file and tells you to switch, or
pass `--no-commit` to commit yourself. If the local branch differs from `origin` it skips
the commit and tells you what to do. At the end it prints the remaining
tasks — always including **fill in `CLAUDE.md`** (§4), **check the stack commands** (§3)
and **try a small issue** (§8). Re-running is safe: existing files are kept, labels are
updated.

Want to review or modify the script first? Clone the toolkit and run `scripts/install.sh`
(or `scripts/install.ps1`) from the clone; `--help` prints every option.

<details>
<summary><b>How the script remembers answers — later projects need almost no input</b></summary>

At the end of the first run the script offers to remember your answers:

| Kind | Stored in |
|---|---|
| Tokens (`CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, `PROJECT_TOKEN`) | The OS keychain, entry `agent-toolkit`: **macOS Keychain**; **Linux** Secret Service (GNOME Keyring/KWallet, via `secret-tool` — package `libsecret-tools`, needs a desktop session); **Windows** file `~/.config/agent-toolkit/<NAME>.dpapi` encrypted with DPAPI (only your Windows account on that machine can decrypt it). Without a keychain (e.g. headless servers, WSL) tokens are **not stored** and are asked again. |
| App ID, `.pem` path, `--ref`, project owner | `~/.config/agent-toolkit/install.env` (mode `600`, `KEY=value`, no secrets) |

From the second project on, the command above asks almost nothing. Other safeguards:

- Tokens are never written to plain files or passed on the command line (not visible via
  `ps`); the script feeds them to `gh secret set` and the keychain over stdin.
- `install.env` is read as data (never `source`d) and only accepts known keys; lines
  containing tokens are ignored with a warning; a file writable by other users is ignored
  entirely.
- The App private key is not copied — only the path to your `.pem` file is stored. Keep
  that file in a private directory (`chmod 600`), or delete it once every repo is set up.
- The keychain protects against leaks via backups, folder sync, accidental commits or
  other users on the machine, but **not** against malware running as your own account. For
  stricter handling, set `AGENT_TOOLKIT_SECRET_STORE=none` and fetch tokens from a password
  manager on each run, e.g.
  `CLAUDE_CODE_OAUTH_TOKEN=$(op read op://Private/claude/token) bash install.sh`
  (1Password; likewise `bw get password …`, `pass show …`).
- Delete stored tokens: macOS `security delete-generic-password -s agent-toolkit -a <NAME>`;
  Linux `secret-tool clear service agent-toolkit account <NAME>`; Windows delete the
  `.dpapi` file.
- The Claude token is only needed to set the repo secret; if it leaks, revoke it in the
  [Claude Console](https://platform.claude.com/settings/keys) (API key) or regenerate it
  with `claude setup-token`, then re-run the script to update it.

`AGENT_TOOLKIT_CONFIG` points to a different config file if needed.

</details>

<details>
<summary><b>Non-interactive runs (CI, your own scripts) and the option table</b></summary>

Pass values as options or environment variables and add `--yes`. Values passed this way
are always written, even if the secret already exists.

```bash
export CLAUDE_CODE_OAUTH_TOKEN=...          # or ANTHROPIC_API_KEY=...
export AGENT_APP_ID=123456 AGENT_APP_PRIVATE_KEY_FILE=~/keys/my-agent.pem
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.sh \
  | bash -s -- ~/code/my-project --stack python --yes
```

```powershell
$env:CLAUDE_CODE_OAUTH_TOKEN = '...'
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1))) --stack python --yes
```

| Option | Environment variable | Meaning |
|---|---|---|
| `<path>` | | Project repo (default: current directory) |
| `--ref <ref>` | `AGENT_TOOLKIT_REF` | Toolkit version to pin (default `v0`, see §10) |
| `--stack <s>` | `AGENT_TOOLKIT_STACK` | `auto` (default), `node`, `pnpm`, `yarn`, `python`, `go`, `none` (all commands left empty for you to fill in) |
| `--tools <k=v,...>` | `AGENT_TOOLKIT_TOOLS` | Override detected tools, e.g. `test=vitest,format=none` (§3) |
| `--claude-auth <a>` | `AGENT_TOOLKIT_CLAUDE_AUTH` | `oauth`, `api-key` or `skip` |
| | `CLAUDE_CODE_OAUTH_TOKEN` / `ANTHROPIC_API_KEY` | Claude secret value |
| `--app-id <id>` | `AGENT_APP_ID` | GitHub App ID |
| `--app-key <file>` | `AGENT_APP_PRIVATE_KEY_FILE` (or the content: `AGENT_APP_PRIVATE_KEY`) | `.pem` private key |
| `--project-owner`, `--project-number` | `PROJECT_OWNER`, `PROJECT_NUMBER`, `PROJECT_TOKEN` | GitHub Projects (§9.1) |
| `--default-develop` / `--keep-default` | | Change / keep the default branch (default: ask, `--yes` → change) |
| `--commit` / `--no-commit` | | Commit + push, or leave it to you (default: ask, `--yes` → commit) |
| `--skip-secrets`, `--skip-settings`, `--no-labels`, `--force` | | Skip each part; `--force` overwrites existing files (without it the installer lists them and asks — default: keep them) |
| `-y`, `--yes` | | Ask nothing; missing secrets are skipped and reported at the end |

</details>

## 0. Checklist

Items marked ⚙ are done automatically by the installer; for a manual install follow the
matching section.

- [ ] The repo has at least one commit; lint/test run locally (§1)
- [ ] ⚙ Files + labels + `develop` branch exist (§2)
- [ ] The `edit for your stack` blocks match the project in `ci.yml`, `agent-implement.yml`, `agent-merge-gate.yml` (§3)
- [ ] `CLAUDE.md` is filled in (§4)
- [ ] ⚙ Claude secret (+ App) added (§5)
- [ ] ⚙ Workflow permissions: *Read and write* + *Allow GitHub Actions to create and approve pull requests* (§6)
- [ ] ⚙ Caller workflows are on the **default branch** (§7)
- [ ] A small issue went through the whole loop (§8)

## 1. Prepare the repo

- The repo must exist on GitHub and be cloned locally. For a brand-new repo:

  ```bash
  gh repo create my-project --private --clone && cd my-project
  # scaffold the project, at least one passing test, then:
  git add -A && git commit -m "chore: initial commit" && git push -u origin HEAD
  ```

  Bootstrap creates `develop` from the default branch, so the repo needs at least one commit.
- The project should already have **lint**, **format check**, **test** and, if possible,
  **coverage** commands. The pipeline is only as safe as your test suite: the agent can
  only merge when CI is green.
- If the repo already has `.github/workflows/ci.yml`, `CLAUDE.md`, issue templates…:
  bootstrap **keeps** existing files (unless `--force`); you merge the content yourself
  (see §2.3).

## 2. Run bootstrap

> Used the [install command](#one-command-install)? Skip this section — except §2.3 if the
> repo already had `ci.yml`, `CLAUDE.md` or issue templates.

### 2.1 Command

```bash
git clone https://github.com/kokoroou/agent-toolkit /tmp/agent-toolkit
cd ~/code/my-project && gh auth status          # gh must be signed in, with repo admin rights
/tmp/agent-toolkit/scripts/bootstrap.sh ~/code/my-project --ref v0
```

`bootstrap.sh` only handles files + labels + `develop`; [`install.sh`](#one-command-install)
calls it and then continues with secrets, settings and the commit.

| Option | Meaning |
|---|---|
| `--stack <s>` | Pre-fill commands for a stack: `auto` (default, detected from repo files), `node`, `pnpm`, `yarn`, `python`, `go`, `none`. Values match the examples in §3.3. |
| `--tools <k=v,...>` | Override single detected tools, e.g. `--tools test=vitest,format=none` (keys in §3). `--detect-tools` prints what would be used and exits. |
| `--ref <ref>` | Pin every `uses: kokoroou/agent-toolkit/...@<ref>`. Recommended: `v0` (moving tag of the current 0.x release; `v1` once the toolkit reaches 1.0.0). `main` = always latest, sandbox only. Default: `main`. |
| `--force` | Overwrite existing files in the project repo. |
| `--no-labels` | Do not create labels / the `develop` branch (when `gh` is unavailable or they already exist). |

### 2.2 What bootstrap does

1. Copies from `templates/` into the project repo:

   | File | Role |
   |---|---|
   | `.github/workflows/ci.yml` | CI (named `CI`): lint, format, test, coverage, PR title, Semgrep, Gitleaks |
   | `.github/workflows/agent-triage.yml` | Triage issues on open/edit/comment, sweep every 6 hours |
   | `.github/workflows/agent-implement.yml` | Optional build agent on GitHub Actions; runs when `agent:implement` is added, or after triage when the repository variable `AGENT_AUTO_BUILD` is `true`. By default you build in Claude Code with `/pipeline:build N` |
   | `.github/workflows/agent-review.yml` | Review PRs labeled `agent` (named `Agent Review`) |
   | `.github/workflows/agent-merge-gate.yml` | Runs after `CI`/`Agent Review`: merge, ask for a fix (`/pipeline:build pr P`, or the Actions build agent with `AGENT_AUTO_BUILD=true`), or block |
   | `.github/workflows/release.yml` | release-please on push to `main` |
   | `.github/workflows/agent-usage-report.yml` | Weekly Actions minutes + Claude cost report |
   | `.github/ISSUE_TEMPLATE/{feature,bug,config}.yml` | Structured issue templates, blank issues disabled |
   | `.github/pull_request_template.md` | PR template |
   | `.github/dependabot.yml` | Dependency updates, PRs into `develop` |
   | `CLAUDE.md` | Project guidance skeleton for the agents |

2. Replaces `@main` in the `uses:` lines with `--ref`, and fills in the commands for the
   `--stack` and the detected tools (§3) in the `edit for your stack` blocks,
   `dependabot.yml`, `release.yml` and the *Commands* section of `CLAUDE.md`.
3. Creates ~24 labels (`needs-triage`, `agent`, `risk:high`, `size:M`…) — safe to re-run.
4. Creates the `develop` branch from the default branch if missing.
5. Writes `.github/agent-toolkit.lock` (toolkit version, stack, tools, list of files it manages)
   so `upgrade.sh` can upgrade later (§10).

### 2.3 Repo with existing files

Bootstrap prints a `Kept existing` list. Those files belong to the project: bootstrap and
`upgrade.sh` never overwrite them (§10.4). For each file:

- **Your own `ci.yml`**: you can keep your CI, but the workflow must be named **`CI`**
  (the merge gate and fix loop look it up by that name), have `workflow_dispatch:` and run
  on `pull_request` into `develop`. Or change `ci-workflow` / `workflows: [...]` in the
  callers to match your CI's name.
- **Existing `CLAUDE.md`**: add the *Commands*, *Architecture*, *Do not touch* sections
  from `/tmp/agent-toolkit/templates/CLAUDE.md`.
- **Your own issue templates**: fine to keep, but they must add the `needs-triage` label
  and should have Goal / Constraints / Acceptance criteria sections so triage scores well.

## 3. Adapt the workflows to your stack

Bootstrap/install fill in the commands from the `--stack` **and the tools the project
already uses**, read from its files. A tool the project does not have gets no command:
the value stays `""` and that CI step is skipped, and bootstrap prints a `!` line for it
(install lists them again at the end). Still review the `# ── edit for your stack ──`
blocks.

| Stack | Key | Detected from → value |
|---|---|---|
| node, pnpm, yarn | `lint` | `scripts.lint` → `script` (`npm run lint`); else `eslint` or `@biomejs/biome` in `package.json` → `eslint` / `biome`; else `none` |
| | `format` | `scripts["format:check"]` → `script`; `prettier` (dependency, `.prettierrc*`, `prettier.config.*`) → `prettier`; `@biomejs/biome` / `biome.json` → `biome`; else `none` |
| | `test` | `vitest` → `vitest`; `jest` → `jest`; else a real `scripts.test` → `script` (`npm test`); else `none` |
| | `coverage` | `yes` for Jest, or Vitest with `@vitest/coverage-v8`/`-istanbul`; else `no` (tests run via `test-command`, no coverage gate) |
| | `build`, `tsc` | `scripts.build`; `typescript` (adds `npx tsc` to the agent's allowed tools) |
| python | `lint` | `ruff` (in `pyproject.toml`/`requirements*.txt`/`setup.cfg`/`tox.ini`, or `ruff.toml`) → `ruff`; `flake8` / `.flake8` → `flake8`; else `none` |
| | `format` | `black` → `black`; else `ruff` if ruff lints; else `none` |
| | `test`, `coverage` | `pytest` / `pytest.ini` / `conftest.py` → `pytest`; `pytest-cov` → coverage `yes` |
| go | — | fixed: `go vet`, `gofmt`, `go test -cover` |
| none | — | every command empty |

A repo with no `package.json` / Python project file yet gets `npm run lint` + `npm test`
(node) or ruff + pytest (python). Override any key with `--tools`, e.g.
`--tools test=jest,format=none`; the result is recorded in the lock (`tools=`), so
`upgrade.sh` regenerates the same commands (§10.3).

### 3.1 `ci.yml`

| Input | Meaning |
|---|---|
| `setup-command` | Install dependencies (runs before every step) |
| `lint-command`, `format-check-command` | Empty = skip that step |
| `test-command` | Run tests. Leave empty if `coverage-command` already runs the tests (saves minutes) |
| `coverage-command` | **The last stdout line must contain the percentage** (e.g. `87.3` or `87.3%`; the last number on the line is used). Send all other output to stderr with `>&2`. Empty = no coverage gate |
| `coverage-tolerance` | How many percentage points coverage may drop vs `develop` (`"0"` = no drop allowed) |
| `enable-security`, `semgrep-config` | Semgrep (new findings vs base only) + Gitleaks |
| `enable-pr-title-check` | PR titles must follow Conventional Commits |

If you need a runtime setup step (setup-node/python/go), put it in `setup-command`; the
`ubuntu-latest` runner already has common versions of Node, Python, Go and Java.

### 3.2 `agent-implement.yml` and the `fix` job in `agent-merge-gate.yml`

These only run when builds happen on GitHub Actions (the `agent:implement` label, or
`AGENT_AUTO_BUILD=true`, see §3.4). Builds you start with `/pipeline:build` use your own
Claude Code session and the commands in `CLAUDE.md` instead.

| Input | Meaning |
|---|---|
| `setup-command` | Same as CI — so the agent can run tests |
| `extra-allowed-tools` | Shell commands the agent may run, as `Bash(<command>)` or `Bash(<prefix>:*)`. **A command missing here cannot be run by the agent** (it cannot test itself → PRs go red more often) |
| `model`, `max-turns`, `timeout-minutes` | Cost / time limits per run |
| `ci-dispatch-workflow`, `review-dispatch-workflow` | Only used **without** an App; leave as is unless you renamed the files |

The two places (`agent-implement.yml` and the `fix` job) must have the **same**
`setup-command` and `extra-allowed-tools`.

In the `gate` job of `agent-merge-gate.yml`:

| Input | Meaning |
|---|---|
| `smoke-command` | Runs on `develop` right after a merge; failure → automatic revert PR. Empty = skip |
| `required-statuses` | Default `agent/review` (the status written by the reviewer) |
| `required-checks` / `ignore-checks` | Check runs that are required / ignored |
| `block-labels` | Default `needs-human,risk:high,do-not-merge,wip` |
| `merge-method` | Default `squash` |

### 3.3 Examples per stack

**Python (pytest + ruff):**

```yaml
# ci.yml
setup-command: pip install -e ".[dev]"
lint-command: ruff check .
format-check-command: ruff format --check .
coverage-command: >-
  pytest --cov=src --cov-report=term >&2 &&
  coverage report --format=total
# agent-implement.yml + fix job
setup-command: pip install -e ".[dev]"
extra-allowed-tools: "Bash(pip install:*),Bash(pytest:*),Bash(ruff:*),Bash(python -m:*),Bash(mypy:*)"
# gate job
smoke-command: pytest -m smoke
```

**Go:**

```yaml
# ci.yml
setup-command: go mod download
lint-command: go vet ./...
format-check-command: test -z "$(gofmt -l .)"
coverage-command: >-
  go test -coverprofile=c.out ./... >&2 &&
  go tool cover -func=c.out | tail -1 | awk '{print $3}'   # "84.6%" is accepted too
# agent-implement.yml + fix job
setup-command: go mod download
extra-allowed-tools: "Bash(go build:*),Bash(go test:*),Bash(go vet:*),Bash(gofmt:*),Bash(go mod:*)"
# gate job
smoke-command: go build ./... && go test -run Smoke ./...
```

**Node with pnpm:**

```yaml
setup-command: corepack enable && pnpm install --frozen-lockfile
extra-allowed-tools: "Bash(pnpm install:*),Bash(pnpm run:*),Bash(pnpm test:*),Bash(pnpm exec:*)"
```

**Node + Vitest** (needs `@vitest/coverage-v8` for the coverage gate):

```yaml
# ci.yml
test-command: ""
coverage-command: >-
  npx vitest run --coverage --coverage.reporter=json-summary >&2 &&
  node -e "console.log(require('./coverage/coverage-summary.json').total.lines.pct)"
# gate job
smoke-command: npm run build && npx vitest run smoke
```

Check `coverage-command` locally before committing — the last line must be a number:

```bash
bash -c '<your coverage-command>' 2>/dev/null | tail -1   # e.g. 84.61
```

### 3.4 Other common tweaks

- **Where builds run.** By default nothing builds on its own: triage comments
  `/pipeline:build N` on ready issues and the merge gate comments `/pipeline:build pr P` on
  red agent PRs, and you run them in Claude Code (your machine or the web). To build on
  GitHub Actions automatically instead, set the repository variable
  `AGENT_AUTO_BUILD=true` (*Settings → Secrets and variables → Actions → Variables*, or
  `gh variable set AGENT_AUTO_BUILD --body true`): triage then dispatches
  `agent-implement.yml` and the merge gate runs the `fix` job. No file needs editing.
- `agent-triage.yml`: `max-rounds` (clarification rounds, 1–5, default 5),
  `auto-implement-max-size` (`XS|S|M|L`, with `AGENT_AUTO_BUILD=true`; larger issues wait
  for you).
- `agent-usage-report.yml`: `minutes-budget`, `cost-budget-usd` for your budget.
- An integration branch other than `develop`: change `base-branch`, `baseline-branch` and
  `branches:` in every caller to match.

## 4. Write `CLAUDE.md`

`CLAUDE.md` at the repo root is read by the planner, implementer and reviewer on every
run. It is the single most important place to make the agents do what you want. Keep it
short and specific:

- **Commands**: the exact install/lint/format/test/coverage/build commands — matching
  `extra-allowed-tools`, otherwise the agent tries commands it is not allowed to run.
- **Architecture**: 5–15 lines: which directory holds what, data flow, key abstractions.
  Point to files rather than describing them at length.
- **Conventions**: only what differs from the toolkit defaults (Conventional Commits,
  tests for every behavior change, no coverage drop). E.g. "use `Result<T>` instead of
  throwing", "new APIs need an OpenAPI spec in `docs/api/`".
- **Do not touch**: paths the agent must not modify (generated code, vendored code,
  applied migrations, `.github/workflows/`…).

## 5. Add secrets

> The installer already set the secrets. This section is for manual installs, rotating
> tokens, or adding `PROJECT_TOKEN` / `GITLEAKS_LICENSE` later.

**Repo → Settings → Secrets and variables → Actions → New repository secret**
(`https://github.com/<owner>/<repo>/settings/secrets/actions`), or with the CLI (from the
repo directory):

```bash
gh secret set CLAUDE_CODE_OAUTH_TOKEN          # paste the token, Enter, Ctrl-D — or ANTHROPIC_API_KEY
gh secret set AGENT_APP_ID --body 123456
gh secret set AGENT_APP_PRIVATE_KEY < ~/Downloads/kokoroou-agent.*.private-key.pem
gh secret set PROJECT_TOKEN                    # only when using Projects (§9.1)
gh secret list                                 # verify
```

| Secret | Required | Notes |
|---|---|---|
| `ANTHROPIC_API_KEY` *or* `CLAUDE_CODE_OAUTH_TOKEN` | ✔ | See [GETTING-STARTED §4](GETTING-STARTED.md#4-get-your-claude-credentials) |
| `AGENT_APP_ID`, `AGENT_APP_PRIVATE_KEY` | recommended | The App must be **installed on this repo** ([GETTING-STARTED §5.3](GETTING-STARTED.md#53-install-the-app-on-your-repos)) |
| `PROJECT_TOKEN` | when using Projects | classic PAT, scopes `project` + `repo` |
| `GITLEAKS_LICENSE` | organization repos only | free registration at gitleaks.io |

The caller workflows pass each secret by name (`${{ secrets.ANTHROPIC_API_KEY }}`…), so
the secret names must match the table (case-insensitive). In an organization you can set
these secrets at the org level and share them with several repos.

## 6. Configure repo Settings

> The installer already enabled items 1–3 below (unless you used `--skip-settings`). Read
> this to double-check when you hit permission errors.

1. **Settings → Actions → General**
   - *Actions permissions*: allow actions and reusable workflows (the default *Allow all
     actions* is fine; if restricted, add `kokoroou/agent-toolkit/*`, `anthropics/*`,
     `actions/*`, `googleapis/release-please-action@*`, `gitleaks/gitleaks-action@*`,
     `oven-sh/setup-bun@*` — the last one is called by `anthropics/claude-code-action`).
   - *Workflow permissions*: **Read and write permissions** and tick **Allow GitHub
     Actions to create and approve pull requests**. Without this the agent cannot open PRs
     and release-please cannot open release PRs.
2. **Settings → General → Pull Requests**: enable *Allow squash merging* (the merge gate
   squashes) and preferably *Automatically delete head branches*.
3. **Settings → Advanced Security** (in the sidebar; formerly *Code security*): enable
   *Dependabot alerts* and *Dependabot security updates* (free even for private repos; no
   GitHub Advanced Security purchase needed despite the page name).

Branch protection is not needed (and Free + private does not have it): the merge gate
checks checks and statuses itself.

## 7. Choose the default branch

`workflow_run` (merge gate), `schedule` (periodic triage sweep, usage report) and
`workflow_dispatch` only run **workflow files on the default branch**. Pick one:

| Option | What to do | Pros / cons |
|---|---|---|
| **A. `develop` as default** (recommended) | *Settings → General → Default branch* → `develop` | The callers live there; `Closes #N` closes issues automatically; `main` only receives manual release merges. Other people's PRs also target `develop` by default |
| **B. Keep `main` as default** | Commit the callers to `main`, and merge every workflow change into `main` | No habit change, but easy to forget to sync — workflows differing between `develop` and `main` cause confusing behavior |

## 8. Commit and verify

```bash
git switch <default-branch>
git add .github CLAUDE.md
git commit -m "ci: add agent-toolkit pipeline"
git push
git switch develop && git merge --ff-only <default-branch> && git push   # if using option B
```

Verify in order:

1. **Actions** tab: you see the `CI`, `Agent Triage`, `Agent Implement`, `Agent Review`,
   `Agent Merge Gate`, `Release`, `Agent Usage Report` workflows. None reports a syntax
   error (⚠ icon).
2. Run CI by hand: *Actions → CI → Run workflow* on `develop` → must be green. This run
   also records the coverage baseline for `develop`.
3. **Issues → New issue → Feature / change request** with a small, clear change, e.g.:
   - Goal: "Add a function `add(a, b)` that returns the sum of two numbers."
   - Constraints: "None"
   - Acceptance criteria: "- [ ] `add(2, 3)` returns 5  - [ ] has a unit test"
4. Watch: `Agent Triage` adds `ready-for-plan` → `Agent Implement` opens PR
   `agent/issue-N` → `CI` + `Agent Review` → `Agent Merge Gate` merges into `develop` and
   closes the issue. Usually takes 10–30 minutes.

If it gets stuck at any step, see [§12](#12-troubleshooting).

## 9. Optional

### 9.1 GitHub Projects

1. Create a Project (v2): *Profile → Projects → New project* (or in the org).
2. Add two **Single select** fields: `Priority` with options `P0`, `P1`, `P2`, `P3`;
   `Size` with options `XS`, `S`, `M`, `L`, `XL` (exact spelling).
3. Take the project number from the URL (`.../projects/3` → `3`).
4. In `agent-triage.yml`, uncomment and fill in:
   ```yaml
   project-owner: kokoroou
   project-number: "3"
   ```
5. Add the `PROJECT_TOKEN` secret ([GETTING-STARTED §6](GETTING-STARTED.md#6-pat-for-github-projects-optional)).

### 9.2 Dependabot

Edit `.github/dependabot.yml`: change `package-ecosystem: npm` to your ecosystem (`pip`,
`gomod`, `cargo`, `maven`, `gradle`, `composer`, `docker`…), adding blocks if you use
several. Dependabot PRs do not carry the `agent` label, so the merge gate leaves them for
you to merge; to have the agent review one, add the `agent` label to it.

### 9.3 ci-doctor (gh-aw)

An agent that watches CI failures on `develop`/`main` (which the PR fix loop cannot see)
and opens a `needs-triage` issue:

```bash
gh extension install github/gh-aw     # if not installed yet
gh aw add kokoroou/agent-toolkit/ci-doctor
gh aw compile                          # generates .github/workflows/ci-doctor.lock.yml
gh aw secrets set ANTHROPIC_API_KEY    # or follow gh aw's instructions for the claude engine
git add .github && git commit -m "ci: add ci-doctor" && git push
```

Commit both the `.md` and the `.lock.yml` files to the default branch.

### 9.4 Release

`release.yml` runs release-please on push to `main`:

- `release-type`: `node`, `python`, `go`, `rust`, `java`, `simple`… — decides which
  version files are updated.
- To attach build output to the GitHub Release: uncomment `setup-command`,
  `build-command`, `artifact-paths`.

Flow: merge `develop` → `main` (manual PR) → release-please opens a
"chore(main): release x.y.z" PR → review the CHANGELOG → merge → tag + GitHub Release.
Commits must follow Conventional Commits (`feat:` → minor, `fix:` → patch, `feat!:` →
major); CI already checks PR titles.
Entries with the same message in the same section (one change reaching `main` through
several commits) are merged into one line: `* msg ([30b8c69](…), [bf285b9](…))`.

## 10. Pin and upgrade the toolkit version

- `--ref v0` pins to the current major's **moving tag**: you get fixes and new features,
  but no breaking changes (before 1.0.0, breaking changes bump the minor, so `v0` can still
  change behavior — read the [CHANGELOG](../CHANGELOG.md) when updating).
- Tighter pinning: `--ref v0.1.0` or a commit SHA.
- The plugin (agents/commands) is installed from `toolkit-marketplace`, which defaults to
  the toolkit's default branch. To pin the plugin too, add this to the jobs calling
  `triage.yml`, `implement.yml`, `review.yml` (including the `fix` job):

  ```yaml
  with:
    toolkit-marketplace: https://github.com/kokoroou/agent-toolkit.git#v0
  ```

### 10.1 Two things to upgrade

| Thing | Where it lives | How to upgrade |
|---|---|---|
| Pipeline logic (reusable workflows, plugin) | In the toolkit, called via `uses: …@v0` | **Automatic** on the next run when the toolkit releases within the same major (`v0`). New major: `upgrade.sh --to v1` |
| Files copied into the project (caller workflows, issue/PR templates, `dependabot.yml`) | In the project repo | `upgrade.sh` — when the CHANGELOG says templates gained inputs/triggers/labels |

### 10.2 Upgrade command

From the project's clone, on the default branch, with no uncommitted changes in
`.github/`:

```bash
# preview, writes nothing
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/upgrade.sh | bash -s -- --dry-run
# apply: latest release of the pinned major (v0), or --to v1 / --to v0.3.0
curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/upgrade.sh | bash -s -- --to v1
git diff && git add .github && git commit -m "ci: upgrade agent-toolkit to v1"
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.ps1))) upgrade --to v1
```

The script does not commit; it prints a per-file table, the CHANGELOG from the installed
release to the new one, and updates labels (`--no-labels` to skip). It exits with code `1`
if conflicts remain.

### 10.3 How the script keeps your edits

`bootstrap.sh` (and `install.sh`) writes **`.github/agent-toolkit.lock`** — commit this
file, and do not edit it by hand beyond the `managed=` lines (§10.4):

```
version=0.1.0              # toolkit release that generated the files
ref=v0                     # the pinned --ref
commit=45c2ae5…            # exact toolkit commit
stack=python               # the --stack used
tools=lint=ruff,format=ruff,test=pytest,coverage=yes   # detected tools + --tools (§3)
managed=.github/workflows/ci.yml   # toolkit-managed file (one line per file)
```

When upgrading, the script regenerates the files of the **old release** (commit, stack
and tools from the lock) and of the **new release**, then compares three sides for each *managed*
file — like `git merge`:

| Your copy vs the old release | Toolkit changed the file? | Result |
|---|---|---|
| Unchanged | yes | `↑` replaced with the new version |
| Edited (e.g. `edit for your stack` blocks) | no | `=` kept as is |
| Edited | yes, elsewhere | `~` new version + your edits (`git merge-file`) |
| Edited | yes, **same lines** | `!` conflict: the file contains `<<<<<<< yours` … `>>>>>>> agent-toolkit v1`, resolve by hand |
| Missing (new toolkit file) | — | `+` added, recorded in `managed=` |
| You deleted it | — | not re-added |
| Toolkit removed the file | — | deleted if you did not edit it, otherwise kept and reported `!` |

For conflict-free upgrades: only change values in the `edit for your stack` blocks and the
`with:` inputs; for extra steps write your own workflow instead of editing a caller.

Changed tools (e.g. moved from Jest to Vitest)? `upgrade.sh --tools test=vitest` switches
the commands you never edited and records the new value. Locks written before tool
detection have no `tools=` line: the tools are detected from the project on the next
upgrade, so commands for tools the project does not use (e.g. `npx jest`) are replaced.

### 10.4 Files with the same name — who owns what

| Kind | Files | On upgrade |
|---|---|---|
| **Toolkit-managed** | files bootstrap copied (`managed=` lines in the lock) | 3-way merge as above |
| **Project-owned** | files that existed **before** installing (bootstrap reported `Kept existing`), e.g. your own `ci.yml` or issue templates | never written; if the matching template changes, the script reports `·` so you can merge by hand |
| **Generated once** | `CLAUDE.md` | never written; the script gives a comparison link if the template changes |

To hand a project-owned file over to the toolkit: delete it, re-run
`bootstrap.sh --ref <current ref>` (without `--force`), merge your custom parts back and
commit. To stop the toolkit managing a file: remove its `managed=` line from the lock.

### 10.5 Projects installed before the lock existed

The script detects it: it reads `@ref` from `uses:`, regenerates the files of each recent
release and picks the one matching the repo best (prints `guessed: N identical files`).
Only callers with `uses: kokoroou/agent-toolkit/…` and files still identical are treated
as toolkit-managed. To be sure, pass `--from v0.1.0` (and `--stack` if you chose a
different stack than detected). Files whose origin cannot be determined are kept, with the
new version placed next to them as `<file>.upstream` — merge by hand, then delete the
`.upstream` file. After the first upgrade the lock exists and later runs need no guessing.

## 11. Day-to-day operation

| You want to | Do |
|---|---|
| Give the agent work | Open an issue from a template; triage decides |
| Build a ready issue | In Claude Code on the project (your machine or the web): `/pipeline:build N`, or "build issue N". Confirm the push when asked |
| Work through the backlog | `/pipeline:build` with no argument: it ranks ready issues and red agent PRs, proposes an order, and builds what you approve one by one |
| Fix a red agent PR | `/pipeline:build pr P` (the merge gate comments it on the PR) |
| Build a size-L issue or one marked `needs-human` | Clarify the issue, remove `needs-human`, then `/pipeline:build N` (or add **`agent:implement`** to build on Actions) |
| Re-triage an issue | Add the `needs-triage` label or *Actions → Agent Triage → Run workflow* |
| Change the requirements | Edit the issue body (the issue is the source of truth, not comments). Issues in `needs-triage` / `awaiting-clarification` / `ready-for-plan` are re-triaged automatically, and the round count restarts at 0 if the previous triage had concluded. An open agent PR for the issue gets `needs-human` → close the PR, delete the branch, build it again (`/pipeline:build N` or `agent:implement`) once the issue is `ready-for-plan` again |
| Cancel, stop the work | Close the issue. Triage and build skip it; a running build does not push or open a PR; an open PR is not fixed, and the merge gate adds `needs-human` instead of merging. Close the PR too if there is one |
| Block an agent PR | Add `do-not-merge` (or `risk:high`) |
| Have the agent review a human PR | Add the `agent` label to the PR (the PR becomes eligible for auto-merge!) |
| Resume after `needs-human` on a PR | Fix and push yourself, remove the label; the merge gate reruns when CI finishes |
| See costs | The `pipeline-usage` issue, or each run's Step Summary |

## 12. Troubleshooting

| Symptom | Common cause | Fix |
|---|---|---|
| No workflow runs when opening an issue | Callers are not on the default branch; Actions disabled | §7; *Settings → Actions → General* |
| `Agent Merge Gate` never runs | File not on the default branch; the CI is not named `CI` | §7; §2.3 |
| The agent cannot open a PR: `GitHub Actions is not permitted to create or approve pull requests` | Missing permission from §6 | Enable *Allow GitHub Actions to create and approve pull requests* |
| The *Mint GitHub App token* step fails | App not installed on the repo, wrong App ID, private key missing the BEGIN/END lines | [GETTING-STARTED §5](GETTING-STARTED.md#5-create-a-github-app-for-the-agent-strongly-recommended), reset the secrets |
| Claude authentication error / `401` | Missing or wrong `ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`, expired OAuth token | Regenerate (`claude setup-token`), reset the secret |
| The agent PR has no CI checks (no App) | Expected: CI is dispatched separately, see the Actions tab | Use an App so checks show on the PR |
| CI says `coverage-command must print the percentage on its last line` | The last stdout line of `coverage-command` has no number | Send other output to `>&2` (§3.3) |
| The agent tries a denied command (`permission denied` / tool not allowed in the transcript) | Command missing from `extra-allowed-tools` | Add it to both `agent-implement.yml` and the `fix` job (Actions builds only) |
| A merged issue stays open | The merge gate did not reach the close step; the PR lacks `Closes #N` | Check the merge gate log; close it by hand |
| PR gets `needs-human` after 3 fixes | Circuit breaker | Read the `transcript-fix-*` transcript, fix by hand, run `/pipeline:build pr P`, or clarify the issue and build it again |
| Triage does not respond to your answers | Bot comments are ignored; the issue is no longer `awaiting-clarification` | Comment from a human account; add `needs-triage` again |

Still unclear: open the failed run → check the Step Summary and download the
`transcript-*` artifact.
