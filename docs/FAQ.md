# Common use cases and FAQ

**English** · [Tiếng Việt](FAQ.vi.md)

Quick answers to "how do I do X" and "why does Y happen". Each entry answers briefly, then
links to the detailed docs. Hit a new problem? Add an entry using the
[template at the end](#adding-an-entry).

- [Common use cases](#common-use-cases)
  - Installing: [UC-1](#uc-1-install-the-pipeline-into-a-project) · [UC-2](#uc-2-upgrade-the-toolkit)
  - Giving work and building: [UC-3](#uc-3-give-the-agent-a-task) · [UC-4](#uc-4-work-through-the-backlog) · [UC-5](#uc-5-build-automatically-on-github-actions)
  - When things change: [UC-6](#uc-6-change-the-requirements-mid-way) · [UC-7](#uc-7-cancel-a-task) · [UC-8](#uc-8-block-a-pr-from-merging)
  - When the agent gets stuck: [UC-9](#uc-9-fix-a-red-agent-pr) · [UC-10](#uc-10-take-over-after-needs-human)
  - Other: [UC-11](#uc-11-have-the-agent-review-a-human-pr) · [UC-12](#uc-12-run-a-sandboxed-agent-session-on-your-machine) · [UC-13](#uc-13-run-an-agent-session-in-claude-cloud) · [UC-14](#uc-14-release-a-version) · [UC-15](#uc-15-track-costs)
- [Frequently asked questions](#frequently-asked-questions)
  - [General](#general) · [Installation and configuration](#installation-and-configuration) ·
    [Operation](#operation) · [Troubleshooting](#troubleshooting) · [Security and cost](#security-and-cost)
- [Adding an entry](#adding-an-entry)

---

## Common use cases

### UC-1. Install the pipeline into a project

1. Once for all projects: get a Claude token and create the GitHub App →
   [GETTING-STARTED §4–5](GETTING-STARTED.md#4-get-your-claude-credentials).
2. From the project's clone (on the default branch):

   ```bash
   curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.sh | bash
   ```

3. Check the lint/test/coverage commands the script filled in ([ADD-TO-PROJECT §3](ADD-TO-PROJECT.md#3-adapt-the-workflows-to-your-stack)),
   fill in `CLAUDE.md` ([§4](ADD-TO-PROJECT.md#4-write-claudemd)), then open a small issue
   to try the whole loop ([§8](ADD-TO-PROJECT.md#8-commit-and-verify)).

The repo already has a `ci.yml` or issue templates: the script keeps your files and reports
them → [§2.3](ADD-TO-PROJECT.md#23-repo-with-existing-files).

### UC-2. Upgrade the toolkit

- Pipeline logic (reusable workflows, plugin) updates itself through the `@v0` tag; nothing
  to do.
- Files copied into the project: run `upgrade.sh` (preview with `--dry-run`), read the
  result table, resolve files marked `!`, then commit yourself →
  [ADD-TO-PROJECT §10.2](ADD-TO-PROJECT.md#102-upgrade-command).

### UC-3. Give the agent a task

1. Open an issue from the template (Goal / Constraints / Acceptance criteria). The more
   concrete the acceptance criteria, the fewer questions the agent asks.
2. Triage labels it; if information is missing it asks back (up to 5 rounds) — answer in a
   comment.
3. Once the issue has `ready-for-plan`, in Claude Code on the project (your machine or the
   web): `/pipeline:build N` (or say "build issue N"). Confirm the push when asked.
4. CI + the reviewer run on the PR; the merge gate squash-merges it into `develop` when green.

### UC-4. Work through the backlog

`/pipeline:build` with no argument: collects ready issues and red agent PRs, ranks them (red
PRs first, then P0→P3, bugs, smaller size, older), proposes an order and builds the ones you
approve one after another → [GETTING-STARTED §7](GETTING-STARTED.md#7-use-the-plugin-by-hand-optional).

### UC-5. Build automatically on GitHub Actions

```bash
gh variable set AGENT_AUTO_BUILD --body true
```

Issues with `risk` other than `high` and `size` ≤ `auto-implement-max-size` (default M) are
built on Actions right after triage; red PRs are sent back to the agent (up to 3 times). To
build just one issue on Actions: add the `agent:implement` label →
[ADD-TO-PROJECT §3.4](ADD-TO-PROJECT.md#34-other-common-tweaks).

### UC-6. Change the requirements mid-way

Edit the **issue body** (not a comment). Triage runs again and the round count restarts at
0. An open agent PR for the issue gets `needs-human`: close the PR, delete the branch, and
build again once the issue is back to `ready-for-plan` →
[ARCHITECTURE](ARCHITECTURE.md#changing-requirements-and-cancelling).

### UC-7. Cancel a task

Close the issue (and the PR if there is one). A running build neither pushes nor opens a PR;
the merge gate does not merge a PR whose issue is closed.

### UC-8. Block a PR from merging

Add `do-not-merge` or `risk:high` to the PR. The merge gate returns `blocked`.

### UC-9. Fix a red agent PR

The merge gate comments the command on the PR: run `/pipeline:build pr P` in Claude Code.
With `AGENT_AUTO_BUILD=true` this runs on Actions by itself up to 3 times, then stops with
`needs-human` (circuit breaker).

### UC-10. Take over after `needs-human`

1. Find the reason: the bot's comment, the run's Step Summary, or the `transcript-*`
   artifact.
2. Issue: clarify it, remove `needs-human`, then `/pipeline:build N`.
3. PR: fix and push yourself (or `/pipeline:build pr P`), remove the label; the merge gate
   reruns when CI finishes.

### UC-11. Have the agent review a human PR

Add the `agent` label to the PR. **Note:** the PR then becomes eligible for the merge gate
to merge it when green; also add `do-not-merge` if you only want the review.

### UC-12. Run a sandboxed agent session on your machine

`scripts/agent-session.sh run`: decrypts `.env.age`, pulls files from storage, runs Claude
in a sandbox (no push, network only to GitHub + registries). When it exits, `publish` shows
you the commits before pushing and opening the PR →
[AGENT-SESSION §4](AGENT-SESSION.md#4-a-session-on-your-machine).

### UC-13. Run an agent session in Claude cloud

Create a dedicated key with `scripts/agent-session.sh cloud-key claude-cloud`, set
`AGE_SECRET_KEY` in the environment, and put **no** storage credential in it →
[AGENT-SESSION §5](AGENT-SESSION.md#5-a-session-in-claude-cloud).

### UC-14. Release a version

Open a `develop` → `main` PR and merge it yourself. release-please opens a release PR;
merging that → tag, CHANGELOG, GitHub Release → [ADD-TO-PROJECT §9.4](ADD-TO-PROJECT.md#94-release).

### UC-15. Track costs

The `pipeline-usage` issue (from *Agent Usage Report*, weekly or run by hand) sums Actions
minutes and Claude cost; each run also writes its cost to the Step Summary. Set thresholds
with `minutes-budget` and `cost-budget-usd` in `agent-usage-report.yml`.

---

## Frequently asked questions

### General

#### Do I need a paid GitHub plan?

No. It runs on GitHub Free, private repos included. The merge gate replaces branch
protection (which Free + private lacks).

#### Claude API key or OAuth token?

Either. `claude setup-token` gives an OAuth token if you have a Pro/Max plan (capped by the
plan's quota); an API key is billed per token, so set a spend limit in the Console →
[GETTING-STARTED §4](GETTING-STARTED.md#4-get-your-claude-credentials).

#### Why doesn't the agent build right after triage?

That's the default: you decide when to build (`/pipeline:build N`), so the agent runs with
your full harness and you can watch it. For automatic builds: [UC-5](#uc-5-build-automatically-on-github-actions).

#### What about `size:L`/`XL` or `risk:high` issues?

They are never built or merged automatically. You can still build them by hand with
`/pipeline:build N`; `risk:high` PRs must be merged by hand.

#### What does `needs-human` mean?

"A person's turn": every failure path (out of rounds, circuit breaker, conflict, failed
smoke test…) stops at this label, and every agent skips issues/PRs carrying it. See
[UC-10](#uc-10-take-over-after-needs-human).

#### My stack isn't Node/Python/Go?

Install with `--stack none`: all commands are left empty for you to fill in the
`edit for your stack` blocks → [ADD-TO-PROJECT §3](ADD-TO-PROJECT.md#3-adapt-the-workflows-to-your-stack).

### Installation and configuration

#### Is the GitHub App required?

No, but strongly recommended. Events created by `GITHUB_TOKEN` don't trigger other
workflows, so without an App the toolkit dispatches CI separately and checks don't show on
the PR → [ARCHITECTURE](ARCHITECTURE.md#github-pitfalls-already-handled).

#### Why make `develop` the default branch?

`workflow_run`, `schedule` and `workflow_dispatch` only read workflows from the default
branch. Keeping `main` as default works too, but you must remember to sync workflows to
`main` → [ADD-TO-PROJECT §7](ADD-TO-PROJECT.md#7-choose-the-default-branch).

#### I edited a caller workflow — will upgrading lose it?

No, `upgrade.sh` does a 3-way merge based on `.github/agent-toolkit.lock`. To avoid
conflicts, only change values in the `edit for your stack` blocks and `with:`; for extra
steps write your own workflow → [ADD-TO-PROJECT §10.3](ADD-TO-PROJECT.md#103-how-the-script-keeps-your-edits).

#### Does upgrading overwrite `CLAUDE.md`?

No. It is generated once and belongs to the project.

#### Is it safe to re-run the installer?

Yes. Existing files are kept (unless `--force`), labels are updated, and existing secrets
are only replaced if you agree.

#### Does it work on Windows?

The installer runs from PowerShell (`install.ps1`). The sandbox of
`agent-session.sh run` needs WSL2, since the Claude Code sandbox doesn't run on native
Windows.

### Operation

#### Triage doesn't respond to my answers?

Comment from a human account (bot comments are ignored), and the issue must still be
`awaiting-clarification`. Otherwise add `needs-triage` again.

#### The PR from a cloud session isn't on branch `agent/issue-N`?

Expected: the cloud's GitHub proxy only allows pushing to the session's own branch. Review
and the merge gate go by the `agent` label and `Closes #N`, not the branch name.

#### The issue stays open after merging?

`Closes #N` only works when merging into the default branch, so the merge gate closes the
issue itself. If it's still open: check the merge gate log and that the PR has `Closes #N`,
then close it by hand.

#### Where can I see what the agent did?

*Actions → run → Summary* (decisions, cost, turns) and the `transcript-*` artifact (Claude's
full conversation) → [GETTING-STARTED §8.3](GETTING-STARTED.md#83-see-what-the-agent-did).

### Troubleshooting

Full table: [ADD-TO-PROJECT §12](ADD-TO-PROJECT.md#12-troubleshooting). The most common ones:

| Symptom | Check first |
|---|---|
| No workflow runs when opening an issue | Callers are on the default branch; Actions is enabled |
| `Agent Merge Gate` never runs | The file is on the default branch; the CI workflow is named exactly `CI` |
| `GitHub Actions is not permitted to create or approve pull requests` | Enable that permission in *Settings → Actions → General* |
| The *Mint GitHub App token* step fails | The App is installed on the repo; App ID; private key has its BEGIN/END lines |
| Claude authentication error / `401` | Regenerate the token (`claude setup-token`) and reset the secret |
| The agent is denied a command | Add it to `extra-allowed-tools` in both `agent-implement.yml` and the `fix` job |
| `coverage-command must print the percentage on its last line` | The last stdout line must be a number; send other output to `>&2` |

### Security and cost

#### Can the agent leak secrets or push bad code?

Agents on Actions never hold a write token: commits leave the job as a `git bundle` and are
checked by another job before pushing; there is no WebFetch/WebSearch; issues from outsiders
don't start builds automatically → [SECURITY](SECURITY.md#model-the-lethal-trifecta). In a
session on your machine the agent can read `.env` (tests need it), so keep only dev/test
credentials there.

#### How much does one issue cost?

Typically a few dozen Actions minutes (triage 1–3 min/round, build 5–45 min, review 2–15
min) plus the Claude cost shown in the Step Summary. `timeout-minutes`/`max-turns` stop
runaway runs → [GETTING-STARTED §9](GETTING-STARTED.md#9-costs-and-limits).

---

## Adding an entry

- **Use case** ("how do I do X"): add `### UC-<next number>. <task>` to the right group and
  to the contents at the top.
- **Question** ("why Y", "can I Z"): add `#### <question>?` to the right group. For an error
  with a clear symptom, add a row to the [Troubleshooting](#troubleshooting) table (and to
  [ADD-TO-PROJECT §12](ADD-TO-PROJECT.md#12-troubleshooting) if it belongs there for good).
- Answer briefly (2–5 lines), then link to the detailed section instead of copying it.
- Never renumber existing UCs (they may be linked); mark a dropped one "removed".
- Update the Vietnamese [FAQ.vi.md](FAQ.vi.md) too, with the same UC numbers.

Template:

```markdown
### UC-16. <Task>

<1–3 steps or commands> → [<doc> §<section>](<file>.md#<anchor>).

#### <Question>?

<Short answer: what to do / why.> → [<doc>](<file>.md#<anchor>).
```
