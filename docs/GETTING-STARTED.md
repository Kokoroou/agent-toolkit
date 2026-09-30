# Getting started with agent-toolkit (first-time users)

**English** · [Tiếng Việt](GETTING-STARTED.vi.md)

This guide is for **GitHub users trying agent-toolkit for the first time**: you want Claude
Code to triage issues, write code, open PRs, review and merge in your repos by itself.
You do **not** need to fork or modify the toolkit — just prepare your accounts once, then
add the pipeline to each project with [ADD-TO-PROJECT.md](ADD-TO-PROJECT.md).

> Maintaining the `kokoroou/agent-toolkit` repo itself? See [MAINTAINING.md](MAINTAINING.md).

**Summary — one-time tasks (~15 min):**

| # | Task | Required? | Section |
|---|---|---|---|
| 1 | Install `gh`, sign in with `gh auth login` | ✔ (the installer offers to do it) | [§3](#3-install-tools-on-your-machine) |
| 2 | Get a Claude token: `claude setup-token` (Pro/Max plan) **or** an API key | ✔ | [§4](#4-get-your-claude-credentials) |
| 3 | Create a GitHub App, note the App ID + `.pem` file, install the App on your repos | strongly recommended | [§5](#5-create-a-github-app-for-the-agent-strongly-recommended) |
| 4 | Classic PAT for GitHub Projects | optional | [§6](#6-pat-for-github-projects-optional) |
| 5 | Try it on a sandbox repo before a real project | recommended | [§8](#8-try-it-on-a-sandbox-repo) |

Then move on to [ADD-TO-PROJECT.md](ADD-TO-PROJECT.md) — usually a single command. Terms
(triage, merge gate, `needs-human`…): [README](../README.md#glossary).

Contents:

1. [What the pipeline does](#1-what-the-pipeline-does)
2. [Requirements](#2-requirements)
3. [Install tools on your machine](#3-install-tools-on-your-machine)
4. [Get your Claude credentials](#4-get-your-claude-credentials)
5. [Create a GitHub App for the agent](#5-create-a-github-app-for-the-agent-strongly-recommended)
6. [PAT for GitHub Projects](#6-pat-for-github-projects-optional)
7. [Use the plugin by hand](#7-use-the-plugin-by-hand-optional)
8. [Try it on a sandbox repo](#8-try-it-on-a-sandbox-repo)
9. [Costs and limits](#9-costs-and-limits)

---

## 1. What the pipeline does

```
issue ─▶ triage ─▶ (you: /pipeline:build) ─▶ planner ─▶ implementer ─▶ PR ─▶ CI + reviewer ─▶ merge gate ─▶ develop ─▶ (you) ─▶ main ─▶ release
```

- You open an issue from the template (Goal / Constraints / Acceptance criteria).
- **Triage** reads the issue, asks back for up to 5 rounds if information is missing or the
  intent is unclear, then labels it `type:*`, `priority:*`, `risk:*`, `size:*`.
- A clear issue gets `ready-for-plan` and a comment with the next step. You start the
  **build agent** when you want: `/pipeline:build N` in Claude Code on your machine or on
  the web. It creates branch `agent/issue-N`, plans, writes code + tests and, after you
  confirm, opens a PR into `develop`. (Optional: set the repository variable
  `AGENT_AUTO_BUILD=true` to build issues with `risk` other than `high` and `size` ≤ M on
  GitHub Actions automatically, or add the `agent:implement` label to one issue.)
- **CI** (lint, format, test, no coverage drop, Semgrep, Gitleaks) and the **reviewer
  agent** run on the PR.
- The **merge gate** squash-merges green PRs into `develop`; on a red PR it comments with
  `/pipeline:build pr P` for you to run (with `AGENT_AUTO_BUILD=true` it sends the PR back
  to the build agent on Actions instead, up to 3 times, then stops with `needs-human`).
- *Branch Sync* keeps a promotion PR `develop` → `main` open; you merge it after testing,
  release-please creates the version, CHANGELOG and GitHub Release, and `main` is merged
  back into `develop`. (Solo project? Pick github-flow: PRs go straight to `main` —
  [ADD-TO-PROJECT §7.1](ADD-TO-PROJECT.md#71-branch-model-gitlab-flow-or-github-flow).)

A project repo only keeps a few thin YAML files calling into the toolkit
(`uses: kokoroou/agent-toolkit/...@v0`), so all the logic is updated from one place.
Design details: [ARCHITECTURE.md](ARCHITECTURE.md).

## 2. Requirements

| You need | Notes |
|---|---|
| A GitHub account (Free plan is enough) | Project repos can be private. The toolkit replaces branch protection with its merge gate. |
| **Admin** rights on the project repo | To add secrets, edit Settings → Actions, create labels and branches. |
| An Anthropic account | An API key (pay per token) **or** a Claude Pro/Max plan (via an OAuth token). |
| GitHub Actions minutes | Private repos on Free get 2,000 min/month; each issue costs a few dozen minutes (see [§9](#9-costs-and-limits)). |
| A machine with `git` and GitHub CLI `gh` | Linux, macOS, WSL or Windows. The one-command installer ([ADD-TO-PROJECT](ADD-TO-PROJECT.md#one-command-install)) offers to install them if missing. |

## 3. Install tools on your machine

The one-command installer ([ADD-TO-PROJECT](ADD-TO-PROJECT.md#one-command-install)) checks
for `git` and `gh`, offers to install them and runs `gh auth login`; below is the manual way.

```bash
# GitHub CLI — used to create labels, the develop branch, secrets and settings
# macOS: brew install gh      Ubuntu/Debian: sudo apt install gh      Windows: winget install GitHub.cli
gh auth login            # choose GitHub.com → HTTPS → sign in with the browser
gh auth status           # check: you should see "Logged in to github.com" and the "repo" scope

# Claude Code CLI — needed for the OAuth token (§4) and the plugin for manual work (§7)
npm install -g @anthropic-ai/claude-code
claude --version
```

Optional, only if you want the CI-watching agent (ci-doctor):

```bash
gh extension install github/gh-aw
```

## 4. Get your Claude credentials

The agent workflows need **one of** these two secrets (you will add it to each project repo
later; for now just get the value):

| Secret | Where to get it | When to choose it |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Run `claude setup-token` on your machine, sign in with your Claude Pro/Max account, copy the printed token | You have a Claude plan: uses your plan's quota, no API billing. |
| `ANTHROPIC_API_KEY` | [Claude Console → API keys](https://platform.claude.com/settings/keys) → *Create Key* (the Console moved from `console.anthropic.com` to `platform.claude.com`; old links still redirect) | No Claude plan, or you want separate API billing. Set a *spend limit* in the Console. |

Keep the value somewhere safe (a password manager). Never commit it to a repo.

## 5. Create a GitHub App for the agent (strongly recommended)

**In short:** with an App, agent PRs show CI checks and everything runs as if a real person
pushed. Do it once, use it for every repo: [open the pre-filled link](#51-create-the-app) →
name it → *Create* → note the App ID + download a private key → *Install* on your repos.

**Why:** GitHub does not let events created with `GITHUB_TOKEN` (push, opening a PR,
labeling, merging) trigger other workflows. Without an App the toolkit still works through
`workflow_dispatch` workarounds, but:

- CI checks do not show directly on the PR like on a normal PR;
- post-merge CI/smoke has to be dispatched by the toolkit;
- release PRs do not run CI automatically.

With an App everything runs as when a real person pushes. One App can be shared by all
your repos.

### 5.1 Create the App

1. Open the [pre-filled App creation page](https://github.com/settings/apps/new?url=https://github.com/kokoroou/agent-toolkit&public=false&webhook_active=false&contents=write&pull_requests=write&issues=write&actions=write&workflows=write).
   It fills in the Homepage URL, unticks Webhook, selects the permissions from step 3 and
   *Only on this account*; you only need to pick a name and double-check the steps below.
   To go there manually: **avatar → Settings → Developer settings → GitHub Apps → New GitHub App**.
   For an organization, use `https://github.com/organizations/<ORG>/settings/apps/new`
   with the same query string after the `?`.
2. Fill in:
   - **GitHub App name**: a unique name, e.g. `kokoroou-agent`. It shows up as the author
     of commits/PRs (`kokoroou-agent[bot]`).
   - **Homepage URL**: any URL, e.g. `https://github.com/kokoroou/agent-toolkit`.
   - **Webhook**: untick *Active* (the toolkit does not use webhooks).
3. **Repository permissions** (leave the rest at *No access*):

   | Permission | Level | Used to |
   |---|---|---|
   | Contents | Read and write | push branch `agent/issue-N`, merge |
   | Pull requests | Read and write | open PRs, edit labels, merge |
   | Issues | Read and write | comment, label, close issues |
   | Actions | Read and write | dispatch workflows, read CI logs for the fix loop |
   | Workflows | Read and write | only if the agent may edit files in `.github/workflows/` |
   | Metadata | Read-only | required (selected automatically) |

4. **Where can this GitHub App be installed?** → *Only on this account*.
5. Click **Create GitHub App**.

### 5.2 Get the App ID and private key

1. On the new App's page, note the **App ID** (a number, under *About*). This is the value
   of the `AGENT_APP_ID` secret.
2. Scroll to **Private keys → Generate a private key**. The browser downloads a `.pem` file.
   **The whole file content** (including the `-----BEGIN ... KEY-----` and
   `-----END ... KEY-----` lines) is the value of the `AGENT_APP_PRIVATE_KEY` secret.

   ```bash
   cat ~/Downloads/kokoroou-agent.*.private-key.pem   # copy the whole output
   ```

3. Keep the `.pem` file somewhere safe or delete it once the secret is added; if it leaks,
   go back to the App page to delete the key and generate a new one.

### 5.3 Install the App on your repos

1. App page → **Install App** → choose your account → **Install**.
2. Choose *Only select repositories* and tick the project repos that will use the pipeline
   (you can add repos later under [Installed GitHub Apps](https://github.com/settings/installations) → *Configure*).

> App tokens are minted per run and only valid for the running repo, so the App **must be
> installed on every project repo** that has the `AGENT_APP_ID` secret. Otherwise the
> *Mint GitHub App token* step fails.

## 6. PAT for GitHub Projects (optional)

Only needed if you want triage to add issues to a GitHub Project (v2) and fill in
`Priority` and `Size`. Projects owned by a **personal account** accept neither
`GITHUB_TOKEN` nor App tokens, so you need a **classic** PAT:

1. Open the [pre-filled classic PAT page](https://github.com/settings/tokens/new?scopes=repo,project&description=agent-toolkit%20projects)
   (Note and scopes already filled), or go to
   **Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token → Generate new token (classic)**.
2. Double-check: Note `agent-toolkit projects`; Expiration as you like (remember to renew);
   scopes **`repo`** and **`project`**.
3. **Generate token** → copy it → it will be the `PROJECT_TOKEN` secret.

> **Do not use a fine-grained token.** If the page shows *Repository access* and
> *Permissions → Add permissions*, it is the fine-grained page. Those tokens cannot yet
> write to personal-account Projects, so triage would fail to add issues. The classic page
> only has a list of scope checkboxes (`repo`, `workflow`, `project`, ...).

## 7. Use the plugin by hand (optional)

The sub-agents and commands the pipeline uses also work in Claude Code on your machine:

```bash
claude plugin marketplace add kokoroou/agent-toolkit
claude plugin install pipeline@agent-toolkit
```

This installs the plugin on your machine only. Projects set up with the installer also
enable it in their `.claude/settings.json` (`extraKnownMarketplaces` + `enabledPlugins`),
so Claude Code offers to install it when you open the project, and cloud sessions on
claude.ai/code load it on their own
([AGENT-SESSION §5](AGENT-SESSION.md#5-a-session-in-claude-cloud)).

In Claude Code, from the project repo directory (`gh auth login` is needed so the commands
can read issues/PRs):

| Command | What it does |
|---|---|
| `/pipeline:build 42` | **Build issue #42 end to end**: branch, plan, implement, checks, then (after you confirm) push + PR with `Closes #42` and label `agent`. Or just ask "build issue 42" |
| `/pipeline:build` | No argument: collects ready issues and red agent PRs, drops blocked ones, ranks them (red PRs first, then priority P0→P3, bugs, smaller size, older), proposes an order and builds the ones you approve one after another. Or ask "what should we build next?" |
| `/pipeline:build pr 57` | Fix agent PR #57 from its failing CI log / review findings, then push |
| `/pipeline:triage-issue 42` | Score and classify issue #42, suggest clarifying questions |
| `/pipeline:plan-feature 42` | Plan issue #42 file by file, no code changes |
| `/pipeline:implement-issue 42` | Planner → implementer on the current branch, commit (no push; used by the Actions workflow) |
| `/pipeline:fix-pr 57 <log-file>` | Fix PR #57 from a CI log / review, commit (no push; used by the Actions workflow) |
| `/pipeline:review-pr 57` | Review PR #57 and return a verdict |

Update the plugin: `claude plugin marketplace update agent-toolkit`.

To run these commands in a sandbox, with an encrypted `.env` and storage for untracked
files: [AGENT-SESSION.md](AGENT-SESSION.md).

## 8. Try it on a sandbox repo

Before using it on a real project, try the whole loop on a small throwaway repo.

### 8.1 Create the sandbox

```bash
gh repo create agent-sandbox --private --clone && cd agent-sandbox
npm init -y
npm install --save-dev jest prettier eslint
mkdir -p src test
cat > src/slugify.js <<'EOF'
module.exports = (s) => s.toLowerCase().trim().replace(/\s+/g, "-");
EOF
cat > test/slugify.test.js <<'EOF'
const slugify = require("../src/slugify");
test("spaces become dashes", () => expect(slugify("Hello World")).toBe("hello-world"));
EOF
cat > eslint.config.js <<'EOF'
module.exports = [{ files: ["**/*.js"], languageOptions: { sourceType: "commonjs",
  globals: { require: "readonly", module: "writable", test: "readonly", expect: "readonly" } } }];
EOF
printf 'node_modules/\ncoverage/\n' > .gitignore
printf 'coverage/\n' > .prettierignore
npm pkg set scripts.test="jest" scripts.lint="eslint src" scripts.build="echo no build"
npx prettier --write . && npm run lint && npm test   # all three must pass before you start
git add -A && git commit -m "chore: initial sandbox" && git push -u origin HEAD
```

Bootstrap sets `smoke-command` to `npm run build` here: it only adds a smoke test
(`npx jest smoke`, a positional path pattern that works with Jest 29 and 30) when a file
such as `test/smoke.test.js` exists.

Then follow [ADD-TO-PROJECT.md](ADD-TO-PROJECT.md) with this repo (the default template is
already Node + Jest, so the commands need almost no changes).

### 8.2 Scenarios to try

| Scenario | How | Expected |
|---|---|---|
| Issue missing information | Open a *Feature* issue with only a vague Goal and Acceptance criteria "make it good" | Label `awaiting-clarification` + ≤3 questions per round (Socratic, 5 Whys, 5W1H, examples/counter-examples… depending on the gap). Reply with a comment → triage runs again |
| Not enough answers | Reply off-topic 5 times | Label `needs-human`, the pipeline stops |
| Changed requirements | Edit the body of an issue that is already `ready-for-plan` | Triage runs again, round count restarts at 0; the old agent PR (if any) gets `needs-human` |
| Cancel | Close the issue | A running build does not push/open a PR; an open PR is neither fixed nor merged |
| Clear issue, size S | "slugify strips Vietnamese diacritics", with 2–3 concrete acceptance criteria, then `/pipeline:build N` in Claude Code | `ready-for-plan` → PR `agent/issue-N` with `Closes #N` |
| Green PR + approving review | Wait for CI and *Agent Review* to finish | The merge gate squashes into `develop`, deletes the branch, closes the issue |
| Red PR | Push a commit that breaks a test onto the agent branch | Merge gate comments `/pipeline:build pr P`; run it → the fix is pushed. With `AGENT_AUTO_BUILD=true`: `fix` → the agent commits a fix; after 3 times → `needs-human` |
| High-risk PR | Add the `risk:high` label to an agent PR | The merge gate returns `blocked`, no merge |
| Smoke fails after merge | Set `smoke-command: "false"` in `agent-merge-gate.yml` | After the merge a `revert/pr-N` PR appears with `needs-human` |
| Release | Merge the promotion PR `develop` → `main` (merge commit) | release-please opens a release PR; merging it → tag + GitHub Release; Branch Sync merges it back into `develop` |

### 8.3 See what the agent did

- **Actions → run → Summary**: triage/gate decisions, Claude cost, turns, duration.
- The run's **Artifacts**: `transcript-*` is Claude's full conversation, download it to inspect.
- The `pipeline-usage` issue (from *Agent Usage Report*, weekly or run by hand): total
  Actions minutes and Claude cost.

## 9. Costs and limits

- **Actions minutes:** each issue typically includes triage (1–3 min/round), build (5–45
  min), CI, review (2–15 min) and the merge gate. `timeout-minutes`/`max-turns` in the
  caller workflows stop runaway runs. Track it with *Agent Usage Report*.
- **Claude:** the default model is `sonnet`. Each run's cost is in its Step Summary. With
  an API key, set a spend limit in the Console; with an OAuth token, runs are capped by
  your plan's quota.
- **Safety:** agents never hold a push token; every label/merge/push is done by workflow
  bash based on the JSON Claude returns. `risk:high` is never auto-built or auto-merged.
  Every failure path ends with `needs-human`. See [ARCHITECTURE.md](ARCHITECTURE.md).

**Next:** [add the pipeline to a project](ADD-TO-PROJECT.md).
