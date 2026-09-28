# Maintaining agent-toolkit

**English** · [Tiếng Việt](MAINTAINING.vi.md)

For **maintainers of the `kokoroou/agent-toolkit` repo**: one-time repo setup,
development process, testing changes, releasing versions and staying compatible with
projects in use.

> Just want to use the toolkit? See [GETTING-STARTED.md](GETTING-STARTED.md) and
> [ADD-TO-PROJECT.md](ADD-TO-PROJECT.md).

**Summary — 5 things to remember:**

1. Before pushing: `scripts/lint.sh` must pass ([§3](#3-development-environment)).
2. Commits/PR titles follow **Conventional Commits** — release-please computes versions from them ([§4](#4-change-process)).
3. Changing pipeline behavior → test on the sandbox repo before merging ([§5](#5-testing-on-the-sandbox-repo)).
4. Releasing = merging the release PR opened by release-please; never edit versions by hand ([§6](#6-releasing)).
5. Everything on `main` reaches `@v0` users immediately: renaming inputs/labels/commands is **breaking** ([§7](#7-compatibility-and-breaking-changes)).

Contents:

1. [Repo layout](#1-repo-layout)
2. [One-time repo setup](#2-one-time-repo-setup)
3. [Development environment](#3-development-environment)
4. [Change process](#4-change-process)
5. [Testing on the sandbox repo](#5-testing-on-the-sandbox-repo)
6. [Releasing](#6-releasing)
7. [Compatibility and breaking changes](#7-compatibility-and-breaking-changes)
8. [Recurring tasks](#8-recurring-tasks)
9. [Should the toolkit run the pipeline on itself?](#9-should-the-toolkit-run-the-pipeline-on-itself)

---

## 1. Repo layout

| Path | What it is | Used by |
|---|---|---|
| `.github/workflows/{triage,implement,review,quality,merge-gate,release,usage-report}.yml` | Reusable workflows (`on: workflow_call`) — all pipeline logic | Projects via `uses: …@v0` |
| `.github/workflows/self-test.yml` | The toolkit's CI | Toolkit |
| `.github/workflows/toolkit-release.yml` | Toolkit releases (calls `release.yml`) + moves the major tag | Toolkit |
| `.claude-plugin/marketplace.json`, `plugins/pipeline/` | Claude Code marketplace + plugin (agents, commands, skill) | Agent workflows install it via `toolkit-marketplace`; users install it by hand |
| `templates/` | Bootstrap files copied into projects (caller workflows, issue/PR templates, labels, `CLAUDE.md`) | `scripts/bootstrap.sh` |
| `workflows/ci-doctor.md` | gh-aw workflow | `gh aw add kokoroou/agent-toolkit/ci-doctor` |
| `scripts/install.sh`, `scripts/install.ps1` | One-command install: tools, bootstrap, secrets, settings, commit (the `.ps1` only installs git/gh, then runs `install.sh` under Git Bash) | Users, via `curl …/main/scripts/install.sh \| bash` |
| `scripts/bootstrap.sh`, `scripts/lint.sh` | Copy templates + `--stack` presets, labels, `develop`, write `.github/agent-toolkit.lock`; lint the toolkit | `install.sh` / users; CI + you |
| `scripts/upgrade.sh` | Upgrade the files copied into a project: regenerate the old (from the lock) and new releases with `bootstrap.sh`, 3-way merge | Users, via `curl …/main/scripts/upgrade.sh \| bash` |
| `release-please-config.json`, `.release-please-manifest.json`, `version.txt`, `CHANGELOG.md` | Release config and state | release-please |
| `docs/` | Documentation (English `*.md`, Vietnamese `*.vi.md`) | |

Important relationships to keep in mind when editing:

- Callers in `templates/.github/workflows/` must match the inputs/secrets of the
  corresponding reusable workflow — `scripts/lint.sh` cross-checks them with actionlint.
- The workflow names `CI` and `Agent Review` are referenced by `agent-merge-gate.yml`; the
  file names `ci.yml`, `agent-review.yml`, `agent-implement.yml` are dispatched when there
  is no App.
- Labels in `templates/.github/labels.json` are used by the reusable workflows by
  hard-coded name.
- The workflows install the plugin by the name `pipeline@agent-toolkit` and call
  `/pipeline:<command>` — renaming the plugin/commands is a breaking change.
- Docs exist in two languages: when you change a `docs/*.md` or `README.md`, update the
  matching `*.vi.md` too, and keep section numbers identical (scripts refer to them, e.g.
  "ADD-TO-PROJECT.md §7").

## 2. One-time repo setup

Already done for `kokoroou/agent-toolkit`; recorded here for moving/forking the repo.

1. **Visibility: public.** Callers in private repos can only call reusable workflows from
   public repos (or same-owner repos with special *Access* configuration), and
   `claude plugin marketplace add` / `plugin_marketplaces` can clone without a PAT. The
   toolkit contains no secrets or business logic — never commit anything like that here.
2. **[Settings → Actions → General](https://github.com/kokoroou/agent-toolkit/settings/actions) → Workflow permissions**: *Read and write permissions*
   and tick *Allow GitHub Actions to create and approve pull requests* — **before the first
   push to `main`**. Without it release-please can only create a `release-please--…`
   branch but cannot open the PR (`GitHub Actions is not permitted to create or approve
   pull requests`). After enabling it, re-run the failed `toolkit-release` run.
3. **[Settings → General](https://github.com/kokoroou/agent-toolkit/settings) → Pull Requests**: enable *Allow squash merging*; preferably disable
   merge commits so `main`'s history is a clean chain of Conventional Commits
   (release-please reads it).
4. **[Settings → Rules → Rulesets](https://github.com/kokoroou/agent-toolkit/settings/rules)** (available for public repos on Free): add a ruleset
   for `main` forbidding force-push and deletion. Be careful with *Require status checks*
   (`lint`): release PRs opened by `GITHUB_TOKEN` do **not** trigger `self-test`, so the
   check never appears and the PR gets stuck — then add yourself to the *Bypass list*
   (merge with admin rights) or configure the `AGENT_APP_ID`/`AGENT_APP_PRIVATE_KEY`
   secrets for the toolkit (`toolkit-release.yml` passes these two secrets to
   `release.yml`; release PRs opened by the App will run CI).
5. **Tags**: do not add rules blocking updates to `v*` tags — `toolkit-release.yml` must
   force-push the major tag (`v0`, `v1`…).

## 3. Development environment

```bash
git clone https://github.com/kokoroou/agent-toolkit && cd agent-toolkit
npm install -g @anthropic-ai/claude-code          # claude plugin validate
# actionlint: https://github.com/rhysd/actionlint (brew install actionlint / go install)
# shellcheck: brew install shellcheck / sudo apt install shellcheck
# jq:         brew install jq / sudo apt install jq
scripts/lint.sh
```

`scripts/lint.sh` checks:

1. Every JSON file is valid.
2. `claude plugin validate --strict` for the plugin and marketplace.
3. `actionlint` for `.github/workflows/*.yml` (with shellcheck for embedded scripts).
4. Caller templates: bootstrap with each `--stack` (node, pnpm, yarn, python, go), replace
   `kokoroou/agent-toolkit/...@ref` with local paths, then actionlint again — catches
   missing/wrong inputs or secrets between callers and reusable workflows, and YAML broken
   by presets.
5. `templates/.github/labels.json` keeps one label per line (bootstrap reads it with
   `sed`, so users need no `jq`).
6. `shellcheck scripts/*.sh`.

`self-test.yml` runs this exact script on every PR and push to `main`, plus a bootstrap
into a temporary repo to make sure no `@main` remains after pinning with `--ref`.

Try the plugin you are editing without publishing:

```bash
claude --plugin-dir ./plugins/pipeline      # inside any project repo
# or: claude plugin marketplace add ./ && claude plugin install pipeline@agent-toolkit
```

## 4. Change process

1. Branch off `main` (`feat/...`, `fix/...`).
2. Make the change; if you add/modify a reusable workflow input, update the callers in
   `templates/.github/workflows/` and the docs ([ADD-TO-PROJECT.md](ADD-TO-PROJECT.md)) too.
3. `scripts/lint.sh` passes locally.
4. Commit with **Conventional Commits** — release-please uses them to compute the version
   and write the CHANGELOG:

   | Prefix | Version impact (before 1.0.0) | Example |
   |---|---|---|
   | `fix:` | patch | `fix(merge-gate): ignore skipped checks` |
   | `feat:` | minor | `feat(triage): add max-rounds input` |
   | `feat!:` / `BREAKING CHANGE:` | minor (due to `bump-minor-pre-major`) | `feat(implement)!: rename setup input` |
   | `docs:`, `chore:`, `ci:`, `refactor:`, `test:` | no release on their own | |

   After 1.0.0: `fix` → patch, `feat` → minor, breaking → major.
5. Open a PR into `main`; squash-merge with the PR title as a well-formed commit message.
6. For pipeline behavior changes, test on the sandbox before merging (§5).

## 5. Testing on the sandbox repo

Lint does not catch workflow logic bugs. Keep a private repo `kokoroou/agent-sandbox`
(built as in [GETTING-STARTED §8](GETTING-STARTED.md#8-try-it-on-a-sandbox-repo)) and point
it at your development branch:

```bash
cd ~/code/agent-sandbox
sed -i 's#\(kokoroou/agent-toolkit/\.github/workflows/[a-z-]*\.yml\)@[A-Za-z0-9._/-]*#\1@feat/my-change#' \
  .github/workflows/*.yml
# if you changed the plugin: add to the triage/implement/review/fix jobs
#   toolkit-marketplace: https://github.com/kokoroou/agent-toolkit.git#feat/my-change
git commit -am "ci: test agent-toolkit feat/my-change" && git push
```

Run the scenarios from [GETTING-STARTED §8.2](GETTING-STARTED.md#82-scenarios-to-try) that
relate to your change. If you changed templates, re-run bootstrap with `--force` into a
clean clone of the sandbox. When done, point the sandbox back at `@main` (or `@v0`).

## 6. Releasing

Automated by `toolkit-release.yml` on every push to `main`:

1. release-please (through the reusable `release.yml` with `release-please-config.json`)
   opens or updates the **release PR** `chore(main): release X.Y.Z`, bumping the version in
   `version.txt`, `.release-please-manifest.json`,
   `plugins/pipeline/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (two
   places) and writing `CHANGELOG.md`.
2. You review the CHANGELOG in that PR and merge it.
3. release-please creates tag `vX.Y.Z` + a GitHub Release; the `major-tag` job
   force-pushes the moving tag `vX` (e.g. `v0`) to the same commit. Every project pinned to
   `@v0` gets the new release on its next run.

Notes:

- Only `feat:`, `fix:` or breaking commits create a release PR. Merging a PR with only
  `docs:`/`chore:`/`ci:`… still leaves the `toolkit-release` run green, logs
  `No user facing commits found … - skipping` and opens no PR — that is expected.
- The release PR always comes from the branch
  `release-please--branches--main--components--agent-toolkit` (reused for every version,
  force-pushed on new commits). release-please **hard-codes** this name; it cannot be
  configured, and release-please only recognizes a merged PR as a release when the source
  branch has its format. So **do not switch to git-flow style `release/X.Y.Z` branches**:
  merging a PR from such a branch creates no tag or GitHub Release. The version is in the
  PR title `chore(main): release X.Y.Z`.
- Only merge PRs opened by **github-actions** (label `autorelease: pending`, description
  generated by release-please). Do not open a PR from a `release-please--…` branch
  yourself: release-please will not recognize it and will not tag/release on merge.
- **Never edit by hand** the versions in the files above — release-please manages them.
- To force a specific version: an empty commit with a `Release-As: 1.0.0` footer
  (`git commit --allow-empty -m "chore: release 1.0.0" -m "Release-As: 1.0.0"`).
- Reaching **1.0.0** creates a new major tag `v1`; `v0` stays at the last 0.x release.
  Remember to update the `@v0` examples in the README and docs, and the recommended
  `--ref` in [ADD-TO-PROJECT.md](ADD-TO-PROJECT.md).
- Broken release (wrong tag): delete the GitHub Release + tag `vX.Y.Z`, set
  `.release-please-manifest.json` back to the previous version via a PR, then merge again.
  The major tag fixes itself at the next release, or move it by hand:
  `git tag -f v0 v0.1.0 && git push -f origin refs/tags/v0`.

## 7. Compatibility and breaking changes

Projects pin a moving tag, so **every change on `main` reaches users after release
without them doing anything**. Treat the following as breaking (needs `!` and upgrade
notes in the commit body):

- Renaming/removing inputs, outputs or secrets of a reusable workflow; changing a default
  in a way that changes behavior (e.g. `merge-method`, `block-labels`).
- Adding a `required: true` input.
- Renaming labels, the `agent/review` status, the `agent/issue-N` branch, hidden comment markers.
- Renaming the plugin, `/pipeline:*` commands, or the JSON schema the workflows read from Claude.
- Raising `permissions:` that callers must grant.

Not breaking: adding an optional input whose default keeps the old behavior, changing
prompts/agents without changing the output format, bug fixes.

`scripts/install.sh` / `install.ps1` are downloaded straight from `main` (not by tag),
while templates and `bootstrap.sh` are cloned at the user's `--ref` (default `v0`). So
`install.sh` on `main` must work with the `bootstrap.sh` of every tag still pinned: only
use a new bootstrap option after checking it exists (like how `--stack` is detected with
`grep`), and never rename published options/environment variables.

`scripts/upgrade.sh` also runs from `main`, and runs the `bootstrap.sh` of **both the old
and new releases** to generate files. So:

- Keep `bootstrap.sh <path> --ref <r> [--stack <s>] --no-labels` working, with
  `AGENT_TOOLKIT_QUIET_NEXT_STEPS=1`, in every version.
- The `.github/agent-toolkit.lock` format (`version=`, `ref=`, `commit=`, `stack=`,
  `managed=`) is a public interface: only add new keys, never change the meaning of
  existing ones.
- Changing templates is normal (users receive it via 3-way merge), but avoid editing lines
  users often customize (the `edit for your stack` blocks) to prevent conflicts;
  renaming/removing template files must be called out in the CHANGELOG.
- `lint.sh` has an upgrade test between two commits (local edit, upstream edit, conflict,
  new file) — run it after any change to `bootstrap.sh` or `upgrade.sh`.

The plugin is installed from `toolkit-marketplace` (default: the default branch, i.e.
`main`), **not** at the tag a project pins. So plugin changes must stay backward
compatible with the reusable workflows of every major tag still in use, or projects must
pin `#vX` for the marketplace.

## 8. Recurring tasks

- **Action updates**: `anthropics/claude-code-action`, `actions/*`,
  `googleapis/release-please-action`, `actions/create-github-app-token` — follow releases,
  bump versions, lint, test on the sandbox. Dependabot (`.github/dependabot.yml`, waiting 7
  days before adopting a new release) opens weekly PRs; you just review and merge them.
- **Default model**: the `model` inputs default to an alias (`sonnet`), so they follow new
  models automatically; check when Anthropic changes aliases.
- **ci-doctor**: compare with upstream `githubnext/agentics` when gh-aw changes significantly.
- **Docs**: when adding inputs/labels/workflows, update [ADD-TO-PROJECT.md](ADD-TO-PROJECT.md),
  [ARCHITECTURE.md](ARCHITECTURE.md), the README (plus their `*.vi.md` versions) and the
  final message of `bootstrap.sh`. New secrets or settings projects need go into
  `scripts/install.sh` too; new stack commands go into `preset()` in `bootstrap.sh` and the
  §3.3 examples of ADD-TO-PROJECT.

## 9. Should the toolkit run the pipeline on itself?

**Not the full automated pipeline.** Reasons:

| Problem | Details |
|---|---|
| **Public** repo | Anyone can open issues/comments → triage and builds spend Claude money + Actions minutes on strangers, and issue content is a prompt-injection surface. `allowed-bots: "*"` and the default configuration are designed for private repos. |
| Changes are mostly workflows | The agent would have to edit `.github/workflows/` → the App needs write *Workflows* permission. One wrongly auto-merged PR would, after the next release, spread to **every** project pinned to `@v0`. Toolkit risk is always `risk:high`, which is never auto-merged — automation gains nothing. |
| Different branch model | The toolkit releases straight from `main` (no `develop`), and has no executable tests/coverage: `quality.yml` could only gate on lint, not on workflow behavior. |
| Self-reference | The pipeline runs the toolkit's own code while the agent edits it; a bug in `merge-gate.yml` could block the very PR fixing it. |

Use instead:

- **The plugin by hand** (`/pipeline:plan-feature`, `/pipeline:review-pr`) to plan and
  self-review your PRs — no secrets or workflows needed.
- If you want some automation: only **`agent-review.yml`** (review when a *maintainer*
  adds the `agent` label, no merge gate) and possibly **`agent-triage.yml`** with
  `dispatch-on-ready` left empty (labels only, no builds). Both need a Claude secret in the
  repo; restrict the triage trigger to collaborators' issues before enabling it on a
  public repo.
- Real testing still happens on the sandbox repo (§5) — that is the safe place to
  "dogfood" the pipeline.
