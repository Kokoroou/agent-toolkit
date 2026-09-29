# Agent sessions on your machine or in Claude cloud

**English** · [Tiếng Việt](AGENT-SESSION.vi.md)

This is the default way to build an issue: you run the `pipeline` plugin's
`/pipeline:build` skill yourself, on your machine or in a Claude Code cloud session, with
your full harness (tools, hooks, sandbox), and watch it work. (The GitHub Actions build
agent is the optional alternative, see ADD-TO-PROJECT §3.4.) `scripts/agent-session.sh` (copied into your project by the installer)
handles the two things such a session needs that must not end up in git:

- **Secrets** (`.env`): committed **encrypted** with [age](https://github.com/FiloSottile/age)
  as `.env.age`, decrypted at the start of each session.
- **Untracked files** (test data, logs, debug output): kept in external storage through
  [rclone](https://rclone.org) (Backblaze B2, Google Drive, or any other rclone backend),
  pulled before a session and saved after it.

Both are set up so the agent can't use them against anyone else. If it misreads a request
or is steered by a prompt injection, it has no credentials for the storage and no network
route to it.

- [1. How it fits together](#1-how-it-fits-together)
- [2. One-time setup](#2-one-time-setup)
- [3. Storage: Backblaze B2 or Google Drive](#3-storage-backblaze-b2-or-google-drive)
- [4. A session on your machine](#4-a-session-on-your-machine)
- [5. A session in Claude cloud](#5-a-session-in-claude-cloud)
- [6. What the sandbox guarantees, and what it doesn't](#6-what-the-sandbox-guarantees-and-what-it-doesnt)
- [7. Commands and config](#7-commands-and-config)

## 1. How it fits together

```
you (outside the sandbox)                  Claude (inside the sandbox)
─────────────────────────                  ───────────────────────────
decrypt .env.age → .env      ─┐
rclone pull → .agent-local/in ├─▶  reads .env, .agent-local/in/
                              │     writes code + commits, .agent-local/out/
                              │     network: GitHub + package registries only
                              │     no age key, no rclone config, no storage host
review diff, push, open PR   ◀┘
save: checks + confirm → rclone push (write-only key) → sessions/<time>-<branch>/
```

| What | Where it lives | Who can use it |
|---|---|---|
| `.env` | Plain text in the working tree, git-ignored | You and the agent (tests need it) |
| `.env.age` + `.age-recipients` | Committed | Anyone; only holders of a listed key can decrypt |
| age private key | `~/.config/agent-session/age.key` (local) · `AGE_SECRET_KEY` env var (cloud) | Only this script; locally the agent is denied it |
| rclone config (storage keys) | `~/.config/rclone/` on your machine only | Only this script, outside the sandbox. Never in the cloud |
| `.agent-local/in/`, `.agent-local/out/` | Working tree, git-ignored | The agent reads `in/` and writes `out/`; only you run `save` |

## 2. One-time setup

Install [age](https://github.com/FiloSottile/age#installation) (`brew install age`,
`apt install age`, `winget install FiloSottile.age`), plus [rclone](https://rclone.org/install/)
and [gitleaks](https://github.com/gitleaks/gitleaks#installing) if you'll use storage.
On Windows, use WSL2: the Claude Code sandbox doesn't run on native Windows.

The installer copies `scripts/agent-session.sh` and `.claude/settings.json` into your
project. If the project was installed before this feature existed, run
`scripts/upgrade.sh`. Then, from the project checkout:

```bash
scripts/agent-session.sh init       # age key, .age-recipients, .agent-session.conf, .gitignore
$EDITOR .env                        # your secrets
scripts/agent-session.sh encrypt    # → .env.age
git add .age-recipients .agent-session.conf .gitignore .env.age && git commit -m "chore: encrypted env"
```

Back up `~/.config/agent-session/age.key` in your password manager. Without it, `.env.age`
can't be decrypted.

**Another machine:** run `init` there and commit its new line in `.age-recipients`. Then,
on a machine that can already decrypt, run `encrypt` so the file is re-encrypted for the
new key.

**Changing a secret:** edit `.env`, run `encrypt`, then commit `.env.age`. `encrypt` leaves
`.env.age` untouched when the content hasn't changed, so diffs stay quiet.

## 3. Storage: Backblaze B2 or Google Drive

The script works with any rclone remote. It uses two remotes, and the configuration keeps
them as separate keys, so each key has only the rights it needs:

- `PULL_REMOTE`: read-only, for the files a session starts with.
- `PUSH_REMOTE`: write-only if the backend allows it, for what a session produces.

### Backblaze B2 (recommended: keys can be limited per folder and per right)

Free tier: 10 GB of storage and a free daily download allowance
([pricing](https://www.backblaze.com/cloud-storage/pricing)).

1. Create a **private** bucket, e.g. `my-agent-data`. Lifecycle setting: *Keep all versions*
   (the default), so an overwrite is never a loss.
2. **App Keys → Add a New Application Key**, twice:

   | Key | Bucket | File name prefix | Access |
   |---|---|---|---|
   | `myapp-pull` | `my-agent-data` | `myapp/shared/` | **Read Only** |
   | `myapp-push` | `my-agent-data` | `myapp/sessions/` | **Write Only** |

   Neither key needs *Allow List All Bucket Names*. Neither key can create sharing links:
   B2's `shareFiles` right isn't part of Read Only or Write Only.
3. Add them to rclone:

   ```bash
   rclone config create b2-pull b2 account <keyID-pull> key <applicationKey-pull>
   rclone config create b2-push b2 account <keyID-push> key <applicationKey-push>
   ```

4. In `.agent-session.conf`:

   ```
   PULL_REMOTE=b2-pull:my-agent-data/myapp/shared
   PUSH_REMOTE=b2-push:my-agent-data/myapp/sessions
   ```

### Google Drive (works, with weaker key scoping)

Free: 15 GB, shared with Gmail and Photos. rclone
[supports Drive](https://rclone.org/drive/). The difference from B2 is that a Drive token
**can't be limited to one folder or to read-only/write-only**. It grants what its OAuth
scope grants, and the account can create public sharing links. The safeguards here
therefore rest entirely on the agent never reaching the token: it stays in your local
rclone config, the sandbox denies reading it and blocks `*.googleapis.com`, and it's never
put in a cloud environment.

1. Create a folder, e.g. `agent-data/myapp`, and copy its ID from the URL.
2. Create the remote with the narrowest scope that works for you:

   ```bash
   # drive.file: rclone only sees files rclone itself created, so everything goes through rclone
   rclone config create gdrive drive scope drive.file root_folder_id <folder-id>
   ```

   Use `scope drive` instead if you want to drop files into the folder from the Drive web
   UI and pull them. `root_folder_id` then only sets the starting folder; it isn't a
   permission boundary.
3. For extra protection at rest, wrap it in an encrypted remote with
   [`rclone crypt`](https://rclone.org/crypt/). The files are then unreadable in Drive
   itself.
4. In `.agent-session.conf`:

   ```
   PULL_REMOTE=gdrive:shared
   PUSH_REMOTE=gdrive:sessions
   ```

Other rclone backends, such as Cloudflare R2, S3 or OneDrive, plug in the same way. If you
add a backend whose hosts aren't in `DENIED_DOMAINS` (see §7), add them there.

## 4. A session on your machine

Requires Claude Code v2.1.219 or later. On Linux/WSL2 you also need `bubblewrap` and
`socat` (`sudo apt install bubblewrap socat`); on macOS nothing extra is needed.

```bash
scripts/agent-session.sh run                         # interactive
scripts/agent-session.sh run -- --permission-mode auto
# inside Claude: /pipeline:build 42   (or: "build issue 42"; a red PR: /pipeline:build pr 57)
#                /pipeline:build      (no argument: ranked list of what to build next)
```

The skill creates the `agent/issue-42` branch, plans, implements and runs the checks. The
sandbox denies `git push` and `gh pr create`, so it writes the PR title and body to
`.agent-local/pr/agent-issue-42.md` instead. In queue mode it goes on to the next item on
its own branch; the branches wait for you to publish them when you exit.

`run` does the following:

1. Records checksums of the files it trusts: `.agent-session.conf`, `.age-recipients`,
   `scripts/agent-session.sh` and `.claude/settings.json`. They're stored outside the
   project, where the sandbox can't write.
2. Decrypts `.env.age` and pulls `PULL_REMOTE` into `.agent-local/in/`.
3. Starts `claude --settings <generated file>`:
   - `AGE_*`, `RCLONE_*`, `B2_APPLICATION_KEY*` and `AGENT_SESSION_*` are removed from its
     environment.
   - The sandbox is mandatory (`failIfUnavailable`, no unsandboxed retry).
   - Network access follows a strict allowlist: GitHub plus the npm, PyPI, Go and crates
     registries. Storage hosts are also on the deny list.
   - Reads of the age key and the rclone config are denied.
   - Writes to `.git/hooks`, `.git/config` and the trusted files are denied.
   - `rclone`, `age`, `WebFetch`, `git push`, `curl`/`wget`, and the `gh` commands that
     publish something (gists, releases, comments, PR creation…) are denied.

   Run `scripts/agent-session.sh settings` to see the exact file.
4. When Claude exits and `.agent-local/pr/` has files, runs `publish`, one branch at a
   time: it refuses if a trusted file changed or the branch is dirty, shows the commits,
   the diff stat and any
   `.github/workflows` change, then after you confirm pushes the branch (git hooks
   skipped) and opens the PR with `Closes #N` and the `agent` label — or, for a PR fix,
   pushes and comments the summary. You can also run `scripts/agent-session.sh publish`
   later.
5. When `.agent-local/out/` has files, asks whether to `save` them.

`save` refuses to upload when:

- a trusted file changed during the session. After reviewing, re-run with
  `--trust-changes`.
- `out/` contains anything other than regular files (symlinks, devices…), or is larger
  than `MAX_SAVE_MB`.
- `gitleaks` finds a secret in it.

Otherwise it lists the files and the destination and asks you to confirm. It uploads to a
new folder, `sessions/<UTC time>-<branch>/`.

To follow a local session from your phone, run `/remote-control` inside Claude.

**macOS:** `gh` can fail TLS verification under the Seatbelt sandbox. If it does, add
`EXCLUDED_COMMANDS=gh issue view *, gh pr view *` to `.agent-session.conf`. Only those two
read-only commands then run outside the sandbox.

## 5. A session in Claude cloud

A cloud session runs in a VM that Anthropic manages. The setup script, hooks, your
commands and the agent all share that VM, so anything you put in the environment, the
agent can read. The design is:

- Give it the **age key** (tests need the secrets anyway).
- Give it **no storage credential**, so nothing to upload with.

1. Create a key just for the cloud, so you can revoke it on its own:

   ```bash
   scripts/agent-session.sh cloud-key claude-cloud
   git add .age-recipients .env.age && git commit -m "chore: add cloud recipient" && git push
   ```

2. At claude.ai/code, open the environment menu in the session's title bar, choose **Edit**,
   then:
   - **Environment variables**: `AGE_SECRET_KEY=AGE-SECRET-KEY-1…` (the line `cloud-key`
     printed).
   - **Setup script**: `apt-get update && apt-get install -y age || true`.
   - **Network access**: see below.
3. Start a session on the repo. The project's `.claude/settings.json` has a `SessionStart`
   hook that runs `agent-session.sh decrypt --if-key`, so `.env` is there before the agent
   starts. The same hook does nothing in CI or on a machine without a key.
4. Say `/pipeline:build 42` (or "build issue 42"). The session can push itself, so after
   you confirm it pushes and opens the `agent` PR directly. The cloud's GitHub proxy only
   lets it push to the session's own branch, so the PR comes from that branch rather than
   `agent/issue-42`; review and the merge gate work the same (they go by the `agent`
   label and `Closes #42`). For `/pipeline:build pr 57` the session must be able to push
   to the PR's branch; if the push is refused, the skill stops and says so — fix that PR
   from your machine instead.

**Network access in the cloud.** The environment dialog offers four levels
([docs](https://code.claude.com/docs/en/cloud-environments#access-levels)):

| Level | Outbound connections |
|---|---|
| None | Nothing through the session's network |
| **Trusted** (default) | A fixed allowlist: package registries, GitHub, cloud SDKs |
| Full | Any domain |
| **Custom** | One domain per line (a leading `*.` matches subdomains); optionally also the Trusted list |

Some traffic bypasses the level you choose:

- GitHub, through a separate proxy that allows `git push` only to the session's branch.
- MCP connectors you enable.
- Hosts of the environment's **API credentials** (Pro/Max).
- The Anthropic API.

The Trusted list includes `*.googleapis.com`, `*.amazonaws.com` and
`*.r2.cloudflarestorage.com`, so a Trusted session **can reach Google Drive, S3 and R2 by
network**. That's fine here only because the environment holds no storage credential.
Keep it that way:

- Don't put rclone config, B2/Drive keys, or any storage token in environment variables.
- Don't add storage hosts as **API credentials**. The proxy would attach the key for the
  agent, which is exactly the "storage as a tool" this design avoids.
- Don't enable a Google Drive MCP connector on sessions that do implementation work.
- For the tightest setup, choose **Custom**, leave "Also include default list" unchecked,
  and list only the registries the project needs, e.g. `registry.npmjs.org`.

**Outputs in the cloud** stay on the VM and disappear when it's reclaimed. Ask Claude to
send you the file (the Claude app lets you view and download it). To archive it, download
it and run `scripts/agent-session.sh save` on your machine: saving always goes through a
person.

## 6. What the sandbox guarantees, and what it doesn't

**Locally:**

- Enforced by the OS sandbox for every command the agent runs and its child processes:
  - no connection to hosts outside the allowlist;
  - no reading the age key or rclone config;
  - no writing git hooks or the trusted files.
- Enforced by this script:
  - storage credentials never enter Claude's environment;
  - uploads only by a person, after checks, with a write-only key where the backend allows
    one.

**Residual risks:**

- **GitHub is reachable.** An agent could put data into a commit or PR text. Review the
  diff before you push. `/pipeline:build` asks before it pushes, and under `run` it cannot
  push at all: `publish` shows you the commits first.
- **Code the agent writes runs later, outside the sandbox**, when you run tests, git hooks
  from tools like husky, or build scripts yourself. Review it first, as you would any PR.
- **The agent can read `.env`** (tests need it). Put only development/test credentials
  there, never production ones.
- **In the cloud the agent can read `AGE_SECRET_KEY`.** It decrypts only what's already in
  `.env`, so the key adds no access. Revoke it with `cloud-key`'s instructions if the
  environment is shared or leaked.
- Removing a recipient doesn't un-encrypt old commits. **Rotate the secrets** when a key is
  lost.

## 7. Commands and config

| Command | What it does |
|---|---|
| `init` | Creates the age key (once per machine), adds it to `.age-recipients`, writes `.agent-session.conf`, updates `.gitignore` |
| `cloud-key [label]` | New key for a cloud environment: adds the recipient, re-encrypts, prints the secret once |
| `encrypt [--trust-changes]` | `SECRET_FILES` → `<file>.age` (ASCII-armored; skipped when unchanged) |
| `decrypt [--force] [--if-key]` | `<file>.age` → `<file>`. Keeps a local file that differs unless `--force`. `--if-key` does nothing when no key or no `age` is available |
| `pull` | `PULL_REMOTE` → `IN_DIR` |
| `run [--no-pull] [-- <claude args>]` | decrypt + pull + sandboxed Claude + offer to publish and save |
| `publish [--yes] [--trust-changes]` | For each file in `.agent-local/pr/` (written by `/pipeline:build`): pushes its branch and opens the PR, or for a PR fix pushes and comments. Asks before each; a file that fails stays for the next run |
| `save [--yes] [--trust-changes]` | Checks, then uploads `OUT_DIR` to `PUSH_REMOTE/<stamp>/`. `--yes` requires gitleaks |
| `settings` | Prints the generated sandbox settings |

`.agent-session.conf` is committed and read as data. Unknown keys are an error. A value can
be a list of words separated by spaces.

| Key | Default | Meaning |
|---|---|---|
| `SECRET_FILES` | `.env` | Files kept encrypted as `<file>.age` |
| `PULL_REMOTE` / `PUSH_REMOTE` | empty | rclone `remote:path`; empty = skip |
| `IN_DIR` / `OUT_DIR` | `.agent-local/in` / `.agent-local/out` | Relative to the project root, git-ignored |
| `MAX_SAVE_MB` | `200` | `save` refuses anything larger |
| `ALLOWED_DOMAINS` | GitHub + npm/yarn, PyPI, Go, crates registries | The sandbox allowlist during `run` |
| `EXTRA_ALLOWED_DOMAINS` | empty | Added to the allowlist, e.g. `registry.example.com` |
| `DENIED_DOMAINS` | B2, Google APIs/Drive, R2, S3, Dropbox, Box, OneDrive | Always blocked, even when an allowlist entry would match |
| `ALLOW_WEBFETCH` | `false` | Let Claude's WebFetch tool open web pages during `run` |
| `EXCLUDED_COMMANDS` | empty | Comma-separated commands that run **outside** the sandbox. Leave empty unless a tool can't work sandboxed |

Environment variables: `AGE_SECRET_KEY` (key content, used first), `AGENT_SESSION_KEY_FILE`
(key path, default `~/.config/agent-session/age.key`).
