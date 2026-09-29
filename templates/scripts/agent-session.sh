#!/usr/bin/env bash
# Run Claude Code on this project with secrets and untracked files kept out of its reach.
#
#   scripts/agent-session.sh init              one-time per machine: age key, .age-recipients,
#                                              .agent-session.conf, .gitignore entries
#   scripts/agent-session.sh cloud-key [label] new age key for a Claude cloud environment; prints
#                                              the secret once (paste it as AGE_SECRET_KEY)
#   scripts/agent-session.sh encrypt           SECRET_FILES (.env) → <file>.age; commit the .age files
#   scripts/agent-session.sh decrypt [--force] [--if-key]
#                                              <file>.age → <file>, key from $AGE_SECRET_KEY or the key file
#   scripts/agent-session.sh pull              PULL_REMOTE → .agent-local/in/ (rclone)
#   scripts/agent-session.sh run [--no-pull] [-- <claude args>]
#                                              decrypt + pull, run Claude in a strict sandbox, then offer
#                                              `publish` and `save`
#   scripts/agent-session.sh publish [--yes] [--trust-changes]
#                                              push each branch /pipeline:build left in .agent-local/pr/
#                                              and open (or comment on) its PR
#   scripts/agent-session.sh save [--yes] [--trust-changes]
#                                              .agent-local/out/ → PUSH_REMOTE/<stamp>/ after checks
#   scripts/agent-session.sh settings          print the sandbox settings `run` passes to Claude
#
# Storage (rclone) and age credentials are only used by this script, outside Claude: `run`
# strips them from Claude's environment, denies reading them, and its sandbox cannot reach
# any host outside the allowlist, storage hosts included. Only a person runs `publish` and
# `save`.
# Guide: https://github.com/kokoroou/agent-toolkit/blob/main/docs/AGENT-SESSION.md
set -euo pipefail

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die() { echo "agent-session: $*" >&2; exit 1; }
note() { echo "agent-session: $*" >&2; }

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "run inside the project's git checkout"
cd "$root"

conf_file=.agent-session.conf
key_dir="${XDG_CONFIG_HOME:-$HOME/.config}/agent-session"
key_file="${AGENT_SESSION_KEY_FILE:-$key_dir/age.key}"
# Outside the project, so the sandboxed agent (write access: project + temp only) cannot
# rewrite the checksums `save` trusts.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/agent-session/$(printf '%s' "$root" | git hash-object --stdin | cut -c1-16)"
trusted_files=".agent-session.conf .age-recipients scripts/agent-session.sh .claude/settings.json"

# ── config: .agent-session.conf, KEY=value, read as data (never sourced) ──────────
SECRET_FILES=".env"
PULL_REMOTE=""
PUSH_REMOTE=""
IN_DIR=".agent-local/in"
OUT_DIR=".agent-local/out"
MAX_SAVE_MB=200
ALLOWED_DOMAINS="github.com *.github.com *.githubusercontent.com registry.npmjs.org registry.yarnpkg.com pypi.org files.pythonhosted.org proxy.golang.org sum.golang.org index.crates.io static.crates.io"
EXTRA_ALLOWED_DOMAINS=""
DENIED_DOMAINS="*.backblazeb2.com *.backblaze.com *.googleapis.com drive.google.com *.googleusercontent.com *.r2.cloudflarestorage.com *.amazonaws.com *.dropboxapi.com content.dropboxapi.com *.box.com *.onedrive.com graph.microsoft.com"
ALLOW_WEBFETCH=false
EXCLUDED_COMMANDS=""
if [[ -f "$conf_file" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" == *=* ]] || die "$conf_file: not KEY=value: $line"
    k="${line%%=*}" v="${line#*=}"
    [[ "$v" =~ ^\"(.*)\"$ || "$v" =~ ^\'(.*)\'$ ]] && v="${BASH_REMATCH[1]}"
    case "$k" in
      SECRET_FILES|PULL_REMOTE|PUSH_REMOTE|IN_DIR|OUT_DIR|MAX_SAVE_MB|ALLOWED_DOMAINS|EXTRA_ALLOWED_DOMAINS|DENIED_DOMAINS|ALLOW_WEBFETCH|EXCLUDED_COMMANDS)
        printf -v "$k" '%s' "$v" ;;
      *) die "$conf_file: unknown key $k" ;;
    esac
  done <"$conf_file"
fi
[[ "$MAX_SAVE_MB" =~ ^[0-9]+$ ]] || die "MAX_SAVE_MB must be a number"
for d in "$IN_DIR" "$OUT_DIR"; do
  [[ "$d" != /* && "$d" != *..* && -n "$d" ]] || die "IN_DIR/OUT_DIR must be relative paths inside the project"
done

cleanup=()
trap 'rm -rf ${cleanup[@]+"${cleanup[@]}"}' EXIT
tmpfile() { local t; t=$(umask 077 && mktemp); cleanup+=("$t"); printf '%s' "$t"; }

need() { command -v "$1" >/dev/null || die "$1 is not installed ($2)"; }
confirm() { # <question>; --yes skips
  [[ "${assume_yes:-false}" == true ]] && return 0
  local a
  { exec 3</dev/tty; } 2>/dev/null || return 1 # no terminal: treat as "no"
  read -r -p "$1 [y/N] " a <&3 || a=""
  exec 3<&-
  [[ "$a" == y || "$a" == Y || "$a" == yes ]]
}
json_str() { local s="${1//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }
json_list() { # words → JSON array of strings
  local out="" w
  for w in "$@"; do out="${out:+$out, }$(json_str "$w")"; done
  printf '[%s]' "$out"
}

# ── age ──────────────────────────────────────────────────────────────────────────
with_identity() { # <cmd...>: runs cmd with $identity set to a key file; returns 3 if no key
  if [[ -n "${AGE_SECRET_KEY:-}" ]]; then
    identity=$(tmpfile) && printf '%s\n' "$AGE_SECRET_KEY" >"$identity"
  elif [[ -f "$key_file" ]]; then
    identity="$key_file"
  else
    return 3
  fi
  "$@"
}

do_decrypt() {
  local f plain tmp n=0
  for f in $SECRET_FILES; do
    [[ -f "$f.age" ]] || continue
    tmp=$(tmpfile)
    age -d -i "$identity" -o "$tmp" "$f.age" || { die "cannot decrypt $f.age with this key"; }
    plain="$f"
    if [[ -f "$plain" ]] && ! cmp -s "$tmp" "$plain" && [[ "$force" != true ]]; then
      note "kept $plain: it differs from $f.age (run 'encrypt' to update the .age, or 'decrypt --force')"
      continue
    fi
    mkdir -p "$(dirname "$plain")" && mv "$tmp" "$plain" && chmod 600 "$plain"
    n=$((n + 1))
  done
  note "decrypted $n file(s)"
}

cmd_decrypt() {
  force=false if_key=false
  while [[ $# -gt 0 ]]; do
    case "$1" in --force) force=true ;; --if-key) if_key=true ;; *) usage 1 ;; esac; shift
  done
  if ! command -v age >/dev/null; then
    [[ "$if_key" == true ]] && return 0
    die "age is not installed (https://github.com/FiloSottile/age#installation)"
  fi
  local rc=0
  with_identity do_decrypt || rc=$?
  if [[ "$rc" == 3 ]]; then
    [[ "$if_key" == true ]] && return 0
    die "no age key: set AGE_SECRET_KEY or run 'init' ($key_file)"
  fi
  return "$rc"
}

do_encrypt() {
  local f tmp n=0
  for f in $SECRET_FILES; do
    [[ -f "$f" ]] || { note "skip $f: not found"; continue; }
    # age output is randomised: only re-encrypt when the content changed, so git diffs stay quiet.
    if [[ -f "$f.age" && -n "${identity:-}" ]]; then
      tmp=$(tmpfile)
      if age -d -i "$identity" -o "$tmp" "$f.age" 2>/dev/null && cmp -s "$tmp" "$f"; then continue; fi
    fi
    age -e -a -R .age-recipients -o "$f.age.tmp" "$f" && mv "$f.age.tmp" "$f.age"
    echo "  encrypted $f → $f.age"; n=$((n + 1))
  done
  note "$n file(s) updated; commit the .age files and .age-recipients"
}

cmd_encrypt() {
  need age "https://github.com/FiloSottile/age#installation"
  [[ -s .age-recipients ]] || die ".age-recipients is missing: run 'init' first"
  check_trusted .age-recipients
  local rc=0
  identity=""
  with_identity do_encrypt || rc=$?
  [[ "$rc" == 3 ]] && { identity=""; do_encrypt; rc=0; }
  return "$rc"
}

add_recipient() { # <public key> <comment>
  grep -qxF "$1" .age-recipients 2>/dev/null && return 0
  printf '# %s\n%s\n' "$2" "$1" >>.age-recipients
}

gitignore_add() {
  if [[ -s .gitignore && -n "$(tail -c1 .gitignore)" ]]; then echo >>.gitignore; fi
  echo "$1" >>.gitignore; echo "  .gitignore += $1"
}
ensure_ignored() { # <path>: make git ignore it
  git check-ignore -q "$1" 2>/dev/null || gitignore_add "/${1#/}"
}
ensure_tracked() { # <path>: undo a broader ignore rule such as `.env*`
  if git check-ignore -q "$1" 2>/dev/null; then gitignore_add "!/${1#/}"; fi
}

cmd_init() {
  need age-keygen "https://github.com/FiloSottile/age#installation"
  if [[ -f "$key_file" ]]; then
    echo "Using existing key $key_file"
  else
    mkdir -p "$(dirname "$key_file")" && chmod 700 "$(dirname "$key_file")"
    (umask 077 && age-keygen -o "$key_file" 2>/dev/null)
    echo "Created key $key_file (back it up in your password manager)"
  fi
  add_recipient "$(age-keygen -y "$key_file")" "$(id -un)@$(hostname -s 2>/dev/null || hostname) $(date +%F)"
  if [[ ! -f "$conf_file" ]]; then
    cat >"$conf_file" <<'EOF'
# agent-session config (scripts/agent-session.sh). KEY=value, read as data; values are words
# separated by spaces. Committed: every change is visible in review.

# Files encrypted into the repo as <file>.age.
SECRET_FILES=.env

# rclone remotes (from `rclone config`) for files that are not committed. Leave empty to skip.
#   PULL_REMOTE  read-only key; copied into IN_DIR before a session, e.g. b2-pull:my-bucket/myapp/shared
#   PUSH_REMOTE  write-only key; `save` uploads OUT_DIR to PUSH_REMOTE/<stamp>/, e.g. b2-push:my-bucket/myapp/sessions
PULL_REMOTE=
PUSH_REMOTE=
IN_DIR=.agent-local/in
OUT_DIR=.agent-local/out
MAX_SAVE_MB=200

# Hosts sandboxed commands may reach during `run`, in addition to the defaults (GitHub and
# the npm, PyPI, Go and crates registries). Never add your storage hosts here.
EXTRA_ALLOWED_DOMAINS=
# Let Claude's WebFetch tool open web pages during `run` (false = denied).
ALLOW_WEBFETCH=false
# Comma-separated commands that run OUTSIDE the sandbox (no network limit). Keep it empty
# unless a tool cannot work sandboxed, e.g. on macOS: EXCLUDED_COMMANDS=gh issue view *, gh pr view *
EXCLUDED_COMMANDS=
EOF
    echo "Created $conf_file"
  fi
  local f
  for f in $SECRET_FILES; do ensure_ignored "$f"; ensure_tracked "$f.age"; done
  ensure_ignored ".agent-local/"
  cat <<EOF

Next:
  1. Put your secrets in: $SECRET_FILES
  2. scripts/agent-session.sh encrypt
  3. git add .age-recipients $conf_file .gitignore $(for f in $SECRET_FILES; do printf '%s.age ' "$f"; done)&& git commit
  Other machines: run 'init' there, commit the new line in .age-recipients, then run
  'encrypt' here. Claude cloud: 'cloud-key'.
EOF
}

cmd_cloud_key() {
  need age-keygen "https://github.com/FiloSottile/age#installation"
  local label="${1:-claude-cloud}" tmp secret pub
  tmp=$(tmpfile); rm -f "$tmp"
  (umask 077 && age-keygen -o "$tmp" 2>/dev/null)
  pub=$(age-keygen -y "$tmp"); secret=$(grep '^AGE-SECRET-KEY-' "$tmp")
  rm -f "$tmp"
  add_recipient "$pub" "$label $(date +%F)"
  cmd_encrypt_force
  cat <<EOF

Added recipient '$label' and re-encrypted. In claude.ai/code → environment → Edit →
Environment variables, add this line (shown once, not stored anywhere):

AGE_SECRET_KEY=$secret

Then commit .age-recipients and the .age files. To revoke: delete the two lines for
'$label' in .age-recipients, run 'encrypt', and rotate the secrets themselves (old
ciphertexts stay in git history).
EOF
}

cmd_encrypt_force() { # re-encrypt every file for the current recipient list
  local f
  for f in $SECRET_FILES; do
    if [[ ! -f "$f" && -f "$f.age" ]]; then die "$f is missing: run 'decrypt' first so it can be re-encrypted"; fi
    rm -f "$f.age"
  done
  identity=""
  do_encrypt
}

# ── trusted files: the agent must not have changed what `save`/`encrypt` rely on ─────
record_trusted() {
  mkdir -p "$state_dir"
  local f
  for f in $trusted_files; do
    printf '%s %s\n' "$f" "$( [[ -f "$f" ]] && git hash-object "$f" || echo missing)"
  done >"$state_dir/trusted"
}

check_trusted() { # [files...]; no-op when no `run` was recorded
  [[ -f "$state_dir/trusted" && "${trust_changes:-false}" != true ]] || return 0
  local f want have changed=""
  while read -r f want; do
    if [[ $# -gt 0 ]] && [[ " $* " != *" $f "* ]]; then continue; fi
    have=$( [[ -f "$f" ]] && git hash-object "$f" || echo missing)
    [[ "$have" == "$want" ]] || changed="$changed $f"
  done <"$state_dir/trusted"
  [[ -z "$changed" ]] && return 0
  die "changed since the last 'run' started:$changed
  The agent may have edited them. Review with 'git diff' / 'git log -p', then re-run with --trust-changes."
}

# ── storage ──────────────────────────────────────────────────────────────────────
cmd_pull() {
  [[ -n "$PULL_REMOTE" ]] || { note "PULL_REMOTE is empty: nothing to pull"; return 0; }
  need rclone "https://rclone.org/install/"
  mkdir -p "$IN_DIR"
  echo "Pulling $PULL_REMOTE → $IN_DIR"
  rclone copy "$PULL_REMOTE" "$IN_DIR" --links=false
}

cmd_save() {
  assume_yes=false trust_changes=false
  while [[ $# -gt 0 ]]; do
    case "$1" in --yes|-y) assume_yes=true ;; --trust-changes) trust_changes=true ;; *) usage 1 ;; esac; shift
  done
  [[ -n "$PUSH_REMOTE" ]] || die "PUSH_REMOTE is empty in $conf_file"
  need rclone "https://rclone.org/install/"
  check_trusted
  [[ -d "$OUT_DIR" ]] || { note "$OUT_DIR does not exist: nothing to save"; return 0; }
  local odd files kb stamp dest
  odd=$(find "$OUT_DIR" ! -type f ! -type d -print)
  [[ -z "$odd" ]] || die "only regular files can be saved; remove these first:
$odd"
  files=$(find "$OUT_DIR" -type f | sort)
  [[ -n "$files" ]] || { note "$OUT_DIR is empty: nothing to save"; return 0; }
  kb=$(du -sk "$OUT_DIR" | cut -f1)
  [[ "$kb" -le $((MAX_SAVE_MB * 1024)) ]] || die "$OUT_DIR is $((kb / 1024)) MB, over MAX_SAVE_MB=$MAX_SAVE_MB"
  if command -v gitleaks >/dev/null; then
    if gitleaks dir --help >/dev/null 2>&1; then
      gitleaks dir "$OUT_DIR" --no-banner --redact >&2 || die "gitleaks found secrets in $OUT_DIR; remove them first"
    else
      gitleaks detect --no-git --source "$OUT_DIR" --no-banner --redact >&2 || die "gitleaks found secrets in $OUT_DIR; remove them first"
    fi
  else
    note "gitleaks is not installed: files are NOT scanned for secrets (https://github.com/gitleaks/gitleaks)"
    [[ "$assume_yes" == true ]] && die "refusing --yes without gitleaks"
  fi
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-$(git rev-parse --abbrev-ref HEAD | tr '/' '-')"
  dest="${PUSH_REMOTE%/}/$stamp"
  echo "Files ($((kb)) KB):"; printf '%s\n' "$files" | sed 's/^/  /'
  echo "Destination: $dest"
  confirm "Upload?" || { note "not uploaded"; return 1; }
  # --no-check-dest: a write-only key cannot list or read the destination; the stamp is unique.
  rclone copy "$OUT_DIR" "$dest" --no-check-dest --links=false
  echo "Saved to $dest"
}

# ── publish: the push and PR the sandbox does not allow, done by a person ─────────
# /pipeline:build writes one file per branch to pr_dir when `git push` is blocked: KEY: value
# header lines (branch, issue or pr, base, title, labels), a `---` line, then the PR body
# (issue mode) or a fix summary for a PR comment (PR mode). pr_legacy: older single file.
pr_dir=.agent-local/pr
pr_legacy=.agent-local/pr.md
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }
pr_files() { # waiting publish files, oldest first
  local f
  # shellcheck disable=SC2012 # names are written by the skill; ls -tr for age order
  { [[ -d "$pr_dir" ]] && ls -tr "$pr_dir"/*.md 2>/dev/null; [[ -f "$pr_legacy" ]] && echo "$pr_legacy"; } \
    | while IFS= read -r f; do [[ -f "$f" ]] && printf '%s\n' "$f"; done
  return 0
}

cmd_publish() {
  assume_yes=false trust_changes=false
  while [[ $# -gt 0 ]]; do
    case "$1" in --yes|-y) assume_yes=true ;; --trust-changes) trust_changes=true ;; *) usage 1 ;; esac; shift
  done
  need gh "https://cli.github.com"
  check_trusted
  local files f n=0 failed=()
  files=$(pr_files)
  [[ -n "$files" ]] || die "nothing to publish in $pr_dir/ (/pipeline:build writes there when the sandbox blocks the push)"
  while IFS= read -r f; do
    echo; echo "── $f"
    # A subshell per file: one bad file (die) does not stop the others.
    if ( publish_one "$f" ) </dev/null; then n=$((n + 1)); else failed+=("$f"); fi
  done <<<"$files"
  echo; note "published $n; left ${#failed[@]}${failed[*]:+: ${failed[*]}}"
  [[ ${#failed[@]} -eq 0 ]]
}

publish_one() { # <file>
  local file="$1" issue="" pr="" base="" title="" extra="" branch="" line k v in_body=false body l labels=(agent)
  mkdir -p "$state_dir"; body="$state_dir/pr-body.md"; : >"$body"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$in_body" == true ]]; then printf '%s\n' "$line" >>"$body"; continue; fi
    [[ "$line" == --- ]] && { in_body=true; continue; }
    [[ "$line" == *:* ]] || continue
    k=$(trim "${line%%:*}") v=$(trim "${line#*:}")
    case "$k" in
      branch) branch="${v%%[[:space:]]*}" ;;
      issue) issue="${v%%[[:space:]]*}" ;;
      pr) pr="${v%%[[:space:]]*}" ;;
      base) base="${v%%[[:space:]]*}" ;;
      title) title="$v" ;;
      labels) extra="${v%%#*}" ;;
    esac
  done <"$file"
  [[ -z "$issue" || "$issue" =~ ^[0-9]+$ ]] || die "$file: issue must be a number"
  [[ -z "$pr" || "$pr" =~ ^[0-9]+$ ]] || die "$file: pr must be a number"
  [[ -n "$issue$pr" ]] || die "$file: needs an 'issue:' or a 'pr:' line"
  if [[ -z "$base" ]]; then
    if git rev-parse -q --verify refs/remotes/origin/develop >/dev/null; then base=develop
    else base=$(git symbolic-ref --short -q refs/remotes/origin/HEAD || echo origin/main); base="${base#origin/}"; fi
  fi
  git check-ref-format --branch "$base" >/dev/null 2>&1 || die "$file: bad base branch '$base'"
  for l in $extra; do # only labels that hold a PR back; never ones that would widen what merges
    case "$l" in needs-human|risk:high) labels+=("$l") ;; *) note "ignored label '$l'" ;; esac
  done

  [[ -n "$branch" ]] || branch=$(git symbolic-ref --short -q HEAD) || die "$file: needs a 'branch:' line"
  git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "$file: bad branch '$branch'"
  case "$branch" in "$base"|main|master|develop) die "refusing to publish '$branch'" ;; esac
  git rev-parse -q --verify "refs/heads/$branch" >/dev/null || die "no local branch '$branch'"
  if [[ "$branch" == "$(git symbolic-ref --short -q HEAD || true)" && -n "$(git status --porcelain)" ]]; then
    die "uncommitted changes on $branch: commit or discard them first"
  fi
  git fetch -q origin "$base" || die "cannot fetch origin/$base"
  local ref="refs/heads/$branch" commits workflows
  commits=$(git log --oneline "origin/$base..$ref")
  [[ -n "$commits" ]] || die "$branch has no commits on top of origin/$base"
  workflows=$(git diff --name-only "origin/$base...$ref" -- .github/workflows)

  echo "Branch:  $branch → $base"
  echo "Commits:"; printf '%s\n' "$commits" | sed 's/^/  /'
  git --no-pager diff --stat "origin/$base...$ref" | tail -n 25
  if [[ -n "$issue" ]]; then
    [[ -n "$title" ]] || die "$file: needs a 'title:' line"
    grep -qiE "(close[sd]?|fix(e[sd])?|resolve[sd]?) #$issue\\b" "$body" || printf '\nCloses #%s\n' "$issue" >>"$body"
    echo "PR:      $title  [${labels[*]}]  (Closes #$issue)"
  else
    echo "PR:      #$pr (push; the text below '---' becomes a comment)"
  fi
  if [[ -n "$workflows" ]]; then
    echo "WARNING: changes CI workflows — review them before pushing:"; printf '%s\n' "$workflows" | sed 's/^/  /'
  fi
  confirm "Push $branch${issue:+ and open the PR}?" || { note "not published"; return 1; }

  # --no-verify: hooks come from the checkout the agent wrote to; they must not run here.
  git push --no-verify origin "$ref:$ref"
  if [[ -n "$pr" ]]; then
    if [[ -s "$body" ]]; then gh pr comment "$pr" --body-file "$body" >/dev/null; fi
    echo "Pushed to PR #$pr"
  elif l=$(gh pr list --head "$branch" --state open --json url --jq '.[0].url // empty') && [[ -n "$l" ]]; then
    echo "Pushed; PR already open: $l"
  else
    local args=()
    for l in "${labels[@]}"; do
      gh label create "$l" --color "$( [[ "$l" == agent ]] && echo 0e8a16 || echo d93f0b )" >/dev/null 2>&1 || true
      args+=(--label "$l")
    done
    gh pr create --base "$base" --head "$branch" --title "$title" --body-file "$body" "${args[@]}"
  fi
  rm -f "$file" "$body"
}

# ── sandboxed Claude ─────────────────────────────────────────────────────────────
secret_env_names() { compgen -e | grep -E '^(AGE_|RCLONE_|AGENT_SESSION_|B2_APPLICATION_KEY)' || true; }

settings_json() {
  local allowed denied deny_rules cred_files cred_env n p protected
  # shellcheck disable=SC2086 # word lists by design
  allowed=$(json_list $ALLOWED_DOMAINS $EXTRA_ALLOWED_DOMAINS)
  # shellcheck disable=SC2086
  denied=$(json_list $DENIED_DOMAINS)
  local rc_dir="${XDG_CONFIG_HOME:-$HOME/.config}/rclone"
  cred_files=""
  for p in "$rc_dir" "$HOME/.rclone.conf" "$key_dir" "$(dirname "$key_file")" "$state_dir"; do
    cred_files="${cred_files:+$cred_files, }{\"path\": $(json_str "$p"), \"mode\": \"deny\"}"
  done
  cred_env=""
  for n in AGE_SECRET_KEY RCLONE_CONFIG_PASS $(secret_env_names); do
    cred_env="${cred_env:+$cred_env, }{\"name\": $(json_str "$n"), \"mode\": \"deny\"}"
  done
  deny_rules=(
    "Bash(rclone:*)" "Bash(age:*)" "Bash(age-keygen:*)" "Bash(b2:*)" "Bash(scripts/agent-session.sh:*)"
    "Read(~/.config/rclone/**)" "Read(~/.config/agent-session/**)" "Read(~/.rclone.conf)"
    # Same line as the CI build agent: no pushing, no raw HTTP, and no gh command that
    # publishes something (gists, releases, comments, repos) with your GitHub login.
    "Bash(git push:*)" "Bash(git remote:*)" "Bash(git config:*)" "Bash(curl:*)" "Bash(wget:*)"
    "Bash(gh gist:*)" "Bash(gh api:*)" "Bash(gh release:*)" "Bash(gh repo:*)" "Bash(gh secret:*)"
    "Bash(gh variable:*)" "Bash(gh workflow:*)" "Bash(gh auth:*)" "Bash(gh issue create:*)"
    "Bash(gh issue comment:*)" "Bash(gh issue edit:*)" "Bash(gh pr create:*)" "Bash(gh pr comment:*)"
    "Bash(gh pr review:*)" "Bash(gh pr merge:*)"
  )
  local excluded=() e
  while IFS= read -r -d ',' e; do
    e="${e#"${e%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"
    [[ -n "$e" ]] && excluded+=("$e")
  done <<<"$EXCLUDED_COMMANDS,"
  protected=("$root/.git/hooks" "$root/.git/config")
  for p in $trusted_files; do deny_rules+=("Edit(/$root/$p)"); protected+=("$root/$p"); done
  [[ "$ALLOW_WEBFETCH" == true ]] || deny_rules+=("WebFetch")
  cat <<EOF
{
  "permissions": {
    "deny": $(json_list "${deny_rules[@]}")
  },
  "sandbox": {
    "enabled": true,
    "failIfUnavailable": true,
    "allowUnsandboxedCommands": false,
    "excludedCommands": $(json_list ${excluded[@]+"${excluded[@]}"}),
    "network": {
      "strictAllowlist": true,
      "allowedDomains": $allowed,
      "deniedDomains": $denied
    },
    "filesystem": {
      "denyWrite": $(json_list "${protected[@]}")
    },
    "credentials": {
      "files": [$cred_files],
      "envVars": [$cred_env]
    }
  }
}
EOF
}

cmd_run() {
  local pull=true
  while [[ $# -gt 0 ]]; do
    case "$1" in --no-pull) pull=false; shift ;; --) shift; break ;; *) break ;; esac
  done
  need claude "https://code.claude.com/docs/en/quickstart"
  mkdir -p "$state_dir" "$OUT_DIR"
  ensure_ignored ".agent-local/" >/dev/null
  record_trusted
  cmd_decrypt --if-key
  [[ "$pull" == true ]] && cmd_pull
  settings_json >"$state_dir/settings.json"
  local unset_args=() n rc=0
  for n in $(secret_env_names); do unset_args+=(-u "$n"); done
  echo "Starting Claude in the sandbox (settings: $state_dir/settings.json)."
  echo "Write untracked outputs to $OUT_DIR/; 'save' uploads them after the session."
  env ${unset_args[@]+"${unset_args[@]}"} claude --settings "$state_dir/settings.json" "$@" || rc=$?
  if [[ -n "$(pr_files)" ]]; then
    echo; echo "/pipeline:build left branches to publish:"; pr_files | sed 's/^/  /'
    ( cmd_publish ) || true
  fi
  if [[ -n "$PUSH_REMOTE" && -d "$OUT_DIR" && -n "$(find "$OUT_DIR" -type f -print -quit)" ]]; then
    echo; confirm "Save $OUT_DIR to $PUSH_REMOTE now?" && cmd_save
  fi
  return "$rc"
}

[[ $# -gt 0 ]] || usage 1
sub="$1"; shift
case "$sub" in
  init) cmd_init ;;
  cloud-key) cmd_cloud_key "$@" ;;
  encrypt) trust_changes=false; [[ "${1:-}" == --trust-changes ]] && trust_changes=true; cmd_encrypt ;;
  decrypt) cmd_decrypt "$@" ;;
  pull) cmd_pull ;;
  save) cmd_save "$@" ;;
  publish) cmd_publish "$@" ;;
  run) cmd_run "$@" ;;
  settings) settings_json ;;
  -h|--help|help) usage 0 ;;
  *) usage 1 ;;
esac
