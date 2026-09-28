#!/usr/bin/env bash
# One-command setup of the agent pipeline in a project repository.
#
#   curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- [<path>] [options]      # Windows: scripts/install.ps1
#
# Runs in <path> (default: current directory, a clone of a GitHub repo) and:
#   1. checks git + gh (offers to install them) and the gh login;
#   2. copies the caller workflows/templates with the stack's commands (bootstrap.sh),
#      creates the labels and the develop branch;
#   3. sets the repository secrets; 4. sets Actions/merge/Dependabot settings;
#   5. commits and pushes to the default branch and develop, optionally makes develop
#      the default branch.
# Anything not given as an option or environment variable is asked for; secrets that
# already exist are kept unless you agree to replace them. --yes never asks (missing
# secrets are skipped). Answers can be remembered for the next project: plain values in
# AGENT_TOOLKIT_CONFIG (default ~/.config/agent-toolkit/install.env, KEY=value lines),
# tokens only in the OS credential store (macOS Keychain, Linux Secret Service via
# secret-tool, Windows DPAPI) — never in a plain file. AGENT_TOOLKIT_SECRET_STORE=none
# turns the credential store off.
#
# Options (environment variable in brackets):
#   --ref <ref>             toolkit version to pin                  [AGENT_TOOLKIT_REF, v0]
#   --stack <s>             auto|node|pnpm|yarn|python|go|none      [AGENT_TOOLKIT_STACK, auto]
#   --claude-auth <a>       oauth|api-key|skip                      [AGENT_TOOLKIT_CLAUDE_AUTH]
#                           values: [CLAUDE_CODE_OAUTH_TOKEN] / [ANTHROPIC_API_KEY]
#   --app-id <id>           GitHub App ID                           [AGENT_APP_ID]
#   --app-key <file>        App private key (.pem)                  [AGENT_APP_PRIVATE_KEY_FILE]
#                           or the key itself                       [AGENT_APP_PRIVATE_KEY]
#   --project-owner <o>     GitHub Project owner (optional)         [PROJECT_OWNER]
#   --project-number <n>    GitHub Project number (optional)        [PROJECT_NUMBER]
#                           needs a classic PAT                     [PROJECT_TOKEN]
#   --default-develop | --keep-default   make develop the default branch (recommended)
#   --commit | --no-commit  commit + push the files                 (asked; --yes: commit)
#   --skip-secrets, --skip-settings, --no-labels, --force (overwrite existing files)
#   --toolkit-dir <dir>     use a local toolkit checkout instead of cloning
#   -y, --yes               non-interactive
set -euo pipefail

usage() { sed -n '2,34p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ── helpers ─────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then b=$'\e[1m' g=$'\e[32m' y=$'\e[33m' r=$'\e[31m' n=$'\e[0m'; else b="" g="" y="" r="" n=""; fi
step() { printf '\n%s==> %s%s\n' "$b" "$*" "$n"; }
ok()   { printf '  %s✔%s %s\n' "$g" "$n" "$*"; }
warn() { printf '  %s!%s %s\n' "$y" "$n" "$*" >&2; todo+=("$*"); }
die()  { printf '%serror:%s %s\n' "$r" "$n" "$*" >&2; exit 1; }
todo=()

# Prompts read from the terminal even when the script itself comes from `curl | bash`.
tty=""
if [[ -t 0 ]]; then tty=/dev/stdin
elif { : </dev/tty; } 2>/dev/null; then tty=/dev/tty; fi

ask() { # <var> <question> [default]  — plain answer
  local __v; printf '  %s%s%s%s: ' "$b" "$2" "$n" "${3:+ [$3]}" >&2
  IFS= read -r __v <"$tty" || true
  printf -v "$1" '%s' "${__v:-${3:-}}"
}
ask_secret() { # <var> <question>
  local __v; printf '  %s%s%s (hidden): ' "$b" "$2" "$n" >&2
  IFS= read -rs __v <"$tty" || true; echo >&2
  printf -v "$1" '%s' "$__v"
}
confirm() { # <question> <default y|n>; --yes → default
  local a
  if [[ "$interactive" != true ]]; then [[ "$2" == y ]]; return; fi
  ask a "$1 $([[ "$2" == y ]] && echo '[Y/n]' || echo '[y/N]')"
  a=$(printf '%s' "${a:-$2}" | tr '[:upper:]' '[:lower:]')
  [[ "$a" == y || "$a" == yes ]]
}

# ── remembered answers ──────────────────────────────────────────────────────────
config="${AGENT_TOOLKIT_CONFIG:-$HOME/.config/agent-toolkit/install.env}"
secret_keys="CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY PROJECT_TOKEN"
if [[ -f "$config" ]]; then
  if [[ -n "$(find "$config" \( -perm -020 -o -perm -002 \) 2>/dev/null)" ]]; then
    printf '  ! %s is writable by other users — ignored (chmod 600 it)\n' "$config" >&2
  else
    # KEY=value lines; only known, non-secret keys, never executed.
    while IFS='=' read -r k v; do
      v="${v%$'\r'}"; v="${v#\"}"; v="${v%\"}"
      case "$k" in
        AGENT_TOOLKIT_REF|AGENT_TOOLKIT_STACK|AGENT_TOOLKIT_CLAUDE_AUTH|AGENT_APP_ID|\
        AGENT_APP_PRIVATE_KEY_FILE|PROJECT_OWNER|PROJECT_NUMBER)
          [[ -z "${!k:-}" ]] && export "$k=$v" ;;
        CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY|PROJECT_TOKEN|AGENT_APP_PRIVATE_KEY)
          printf '  ! %s holds %s in plain text — ignored; delete that line (tokens go to the OS credential store)\n' \
            "$config" "$k" >&2 ;;
      esac
    done < <(grep -E '^[A-Z_]+=' "$config" || true)
  fi
fi

# OS credential store: store_backend prints keychain|secret-tool|dpapi, or nothing.
# Values always travel on stdin, never on a command line (visible in `ps`).
store_dir="$HOME/.config/agent-toolkit"
store_backend() {
  [[ "${AGENT_TOOLKIT_SECRET_STORE:-}" == none ]] && return 0
  case "$(uname -s)" in
    Darwin) command -v security >/dev/null && echo keychain ;;
    MINGW*|MSYS*|CYGWIN*) command -v powershell.exe >/dev/null && command -v cygpath >/dev/null && echo dpapi ;;
    *) [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v secret-tool >/dev/null && echo secret-tool ;;
  esac
  return 0
}
store_get() { # <name> → value on stdout (empty if absent)
  case "$(store_backend)" in
    keychain) security find-generic-password -s agent-toolkit -a "$1" -w 2>/dev/null ;;
    secret-tool) secret-tool lookup service agent-toolkit account "$1" 2>/dev/null ;;
    dpapi)
      [[ -f "$store_dir/$1.dpapi" ]] || return 0
      # DPAPI: only this Windows user on this machine can decrypt.
      # shellcheck disable=SC2016 # PowerShell code, not bash
      powershell.exe -NoProfile -NonInteractive -Command '
        $s = ConvertTo-SecureString ([Console]::In.ReadToEnd().Trim())
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))' \
        <"$store_dir/$1.dpapi" 2>/dev/null | tr -d '\r' ;;
  esac
  return 0
}
store_set() { # <name> <value>
  case "$(store_backend)" in
    keychain)
      # `security -i` reads its command from stdin; tokens are [A-Za-z0-9._~+/=-] only.
      [[ "$2" =~ ^[A-Za-z0-9._~+/=-]+$ ]] || return 1
      printf 'add-generic-password -U -s agent-toolkit -a %s -l agent-toolkit-%s -w %s\n' "$1" "$1" "$2" \
        | security -i >/dev/null ;;
    secret-tool)
      printf '%s' "$2" | secret-tool store --label="agent-toolkit $1" service agent-toolkit account "$1" ;;
    dpapi)
      mkdir -p "$store_dir"
      # shellcheck disable=SC2016 # PowerShell code, not bash
      printf '%s' "$2" | powershell.exe -NoProfile -NonInteractive -Command '
        ConvertTo-SecureString ([Console]::In.ReadToEnd()) -AsPlainText -Force | ConvertFrom-SecureString' \
        | tr -d '\r' >"$store_dir/$1.dpapi" ;;
    *) return 1 ;;
  esac
}
for k in $secret_keys; do
  if [[ -z "${!k:-}" ]]; then v=$(store_get "$k"); [[ -n "$v" ]] && export "$k=$v"; fi
done

target="." ref="${AGENT_TOOLKIT_REF:-v0}" stack="${AGENT_TOOLKIT_STACK:-auto}"
claude_auth="${AGENT_TOOLKIT_CLAUDE_AUTH:-}"
app_id="${AGENT_APP_ID:-}" app_key_file="${AGENT_APP_PRIVATE_KEY_FILE:-}"
project_owner="${PROJECT_OWNER:-}" project_number="${PROJECT_NUMBER:-}"
default_develop="" commit="" secrets=true settings=true labels=true force=false
toolkit_dir="" interactive=true target_set=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) ref="$2"; shift 2 ;;
    --stack) stack="$2"; shift 2 ;;
    --claude-auth) claude_auth="$2"; shift 2 ;;
    --app-id) app_id="$2"; shift 2 ;;
    --app-key) app_key_file="$2"; shift 2 ;;
    --project-owner) project_owner="$2"; shift 2 ;;
    --project-number) project_number="$2"; shift 2 ;;
    --default-develop) default_develop=true; shift ;;
    --keep-default) default_develop=false; shift ;;
    --commit) commit=true; shift ;;
    --no-commit) commit=false; shift ;;
    --skip-secrets) secrets=false; shift ;;
    --skip-settings) settings=false; shift ;;
    --no-labels) labels=false; shift ;;
    --force) force=true; shift ;;
    --toolkit-dir) toolkit_dir="$2"; shift 2 ;;
    -y|--yes) interactive=false; shift ;;
    -h|--help) usage 0 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [[ "$target_set" == true ]] && die "only one <path> allowed"; target="$1" target_set=true; shift ;;
  esac
done
[[ -z "$tty" ]] && interactive=false

# ── 1. tools ────────────────────────────────────────────────────────────────────
step "Checking tools"
install_pkg() { # <command> <brew> <apt> <dnf> <winget id> <url>
  local cmd="$1" how=""
  if command -v brew >/dev/null; then how="brew install $2"
  elif command -v winget.exe >/dev/null || command -v winget >/dev/null; then how="winget install --id $5 -e --accept-source-agreements --accept-package-agreements"
  elif command -v apt-get >/dev/null; then how="sudo apt-get install -y $3"
  elif command -v dnf >/dev/null; then how="sudo dnf install -y $4"
  fi
  [[ -n "$how" ]] || die "$cmd is not installed — install it from $6 and run again"
  confirm "$cmd is not installed. Run '$how'?" y || die "$cmd is required — install it from $6"
  $how || die "installing $cmd failed — install it from $6"
  hash -r
  command -v "$cmd" >/dev/null || die "$cmd installed but not on PATH — open a new terminal and run again"
}
command -v git >/dev/null || install_pkg git git git git Git.Git https://git-scm.com/downloads
command -v gh >/dev/null || install_pkg gh gh gh gh GitHub.cli https://cli.github.com
ok "git $(git --version | awk '{print $3}'), gh $(gh --version | awk 'NR==1{print $3}')"

if ! gh auth status >/dev/null 2>&1; then
  [[ "$interactive" == true ]] || die "gh is not logged in — run 'gh auth login' (or set GH_TOKEN) first"
  echo "  gh is not logged in; starting 'gh auth login'…"
  gh auth login -h github.com -p https -w <"$tty"
fi
ok "gh logged in as $(gh api user --jq .login)"

# ── 2. project repository ───────────────────────────────────────────────────────
step "Project repository"
[[ -d "$target" ]] || die "$target is not a directory"
target=$(cd "$target" && pwd)
git -C "$target" rev-parse --git-dir >/dev/null 2>&1 \
  || die "$target is not a git checkout — clone your GitHub repo and run this inside it"
repo=$(cd "$target" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) \
  || die "$target has no GitHub remote that gh can see (git remote -v)"
default_branch=$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name // ""')
[[ -n "$default_branch" ]] || die "$repo has no commits yet — push an initial commit first"
perm=$(gh repo view "$repo" --json viewerPermission --jq .viewerPermission)
[[ "$perm" == ADMIN ]] || warn "you are $perm on $repo, not ADMIN — secrets and settings will likely fail"
# Files are committed on the default branch, so stop before writing anything if the
# checkout is elsewhere — otherwise they would be left uncommitted on the wrong branch.
current=$(git -C "$target" symbolic-ref --short -q HEAD || echo "")
if [[ "$current" != "$default_branch" && "$commit" != false ]]; then
  die "$target is on '${current:-detached HEAD}', but the pipeline files are committed to the default branch '$default_branch'.
  Switch first (in that folder):  git switch $default_branch && git pull
  (or pass --no-commit to write the files here and commit them yourself)"
fi
ok "$repo (default branch: $default_branch) at $target"

# ── 3. toolkit files ────────────────────────────────────────────────────────────
step "Toolkit files (ref $ref)"
# Run from a toolkit checkout → use it; run via `curl | bash` → clone the toolkit at --ref.
if [[ -z "$toolkit_dir" && -f "${BASH_SOURCE[0]:-}" ]]; then
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$here/bootstrap.sh" && -d "$here/../templates" ]] && toolkit_dir="$here/.."
fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [[ -z "$toolkit_dir" ]]; then
  toolkit_dir="$tmp/agent-toolkit"
  git -c advice.detachedHead=false -c core.autocrlf=false clone -q --depth 1 --branch "$ref" \
      https://github.com/kokoroou/agent-toolkit "$toolkit_dir" 2>/dev/null \
    || { git -c core.autocrlf=false clone -q https://github.com/kokoroou/agent-toolkit "$toolkit_dir" \
         && git -C "$toolkit_dir" -c advice.detachedHead=false checkout -q "$ref"; } \
    || die "cannot fetch agent-toolkit at '$ref'"
fi
toolkit_dir=$(cd "$toolkit_dir" && pwd)

if [[ "$stack" == auto && "$interactive" == true ]] && grep -q -- '--stack' "$toolkit_dir/scripts/bootstrap.sh"; then
  detected=$(bash "$toolkit_dir/scripts/bootstrap.sh" "$target" --detect-stack)
  ask stack "Stack (node|pnpm|yarn|python|go|none)" "$detected"
fi

args=("$target" --ref "$ref")
if grep -q -- '--stack' "$toolkit_dir/scripts/bootstrap.sh"; then args+=(--stack "$stack")
elif [[ "$stack" != auto && "$stack" != node ]]; then warn "toolkit $ref has no stack presets — edit the \"edit for your stack\" blocks by hand"; fi
[[ "$force" == true ]] && args+=(--force)
[[ "$labels" == true ]] || args+=(--no-labels)
AGENT_TOOLKIT_QUIET_NEXT_STEPS=1 bash "$toolkit_dir/scripts/bootstrap.sh" "${args[@]}" | sed 's/^/  /'
[[ "$stack" == none ]] && warn "stack 'none': the workflows still use the Node defaults — edit the \"edit for your stack\" blocks"

if [[ -n "$project_owner" && -n "$project_number" ]]; then
  f="$target/.github/workflows/agent-triage.yml"
  if grep -q '# project-owner:' "$f"; then
    sed -i.bak -e "s|# project-owner: .*|project-owner: $project_owner|" \
               -e "s|# project-number: .*|project-number: \"$project_number\"|" "$f" && rm -f "$f.bak"
    ok "GitHub Project $project_owner/$project_number set in agent-triage.yml"
  fi
fi

# ── 4. secrets ──────────────────────────────────────────────────────────────────
# Values given as options/environment/config are always written. Otherwise an existing
# secret is kept (interactive runs are asked whether to replace it) and a missing one is
# asked for.
existing=" $(gh secret list --repo "$repo" --json name --jq '.[].name' 2>/dev/null | tr '\n' ' ') "
keep_existing() { # <name>... — true if one of them exists and should be kept
  local s
  for s in "$@"; do
    [[ "$existing" == *" $s "* ]] || continue
    if [[ "$interactive" == true ]] && confirm "$s already set in $repo. Replace it?" n; then return 1; fi
    ok "$s already set (kept)"; return 0
  done
  return 1
}
put_secret() { # <name> <value>
  printf '%s' "$2" | gh secret set "$1" --repo "$repo" >/dev/null || die "could not set secret $1"
  ok "$1 set"; existing+="$1 "
}

if [[ "$secrets" == true ]]; then
  step "Secrets"
  # Claude credentials: one of the two is enough.
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then put_secret CLAUDE_CODE_OAUTH_TOKEN "$CLAUDE_CODE_OAUTH_TOKEN"
  elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then put_secret ANTHROPIC_API_KEY "$ANTHROPIC_API_KEY"
  elif [[ "$claude_auth" == skip ]] || keep_existing CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY; then :
  else
    if [[ -z "$claude_auth" && "$interactive" == true ]]; then
      echo "  Claude credentials for the agents:"
      echo "    1) CLAUDE_CODE_OAUTH_TOKEN — Claude Pro/Max plan (from 'claude setup-token')"
      echo "    2) ANTHROPIC_API_KEY       — API key from https://platform.claude.com/settings/keys"
      echo "    3) skip"
      ask a "Choose" 1
      case "$a" in 1) claude_auth=oauth ;; 2) claude_auth=api-key ;; *) claude_auth=skip ;; esac
    fi
    v=""
    if [[ "$interactive" == true && "$claude_auth" == oauth ]]; then
      if command -v claude >/dev/null && confirm "Run 'claude setup-token' now to create a token?" y; then
        claude setup-token <"$tty" || true
      fi
      ask_secret v "Paste CLAUDE_CODE_OAUTH_TOKEN"
      [[ -n "$v" ]] && put_secret CLAUDE_CODE_OAUTH_TOKEN "$v" && CLAUDE_CODE_OAUTH_TOKEN="$v"
    elif [[ "$interactive" == true && "$claude_auth" == api-key ]]; then
      ask_secret v "Paste ANTHROPIC_API_KEY"
      [[ -n "$v" ]] && put_secret ANTHROPIC_API_KEY "$v" && ANTHROPIC_API_KEY="$v"
    fi
    [[ -n "$v" ]] || warn "no Claude credentials — set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in $repo"
  fi

  # GitHub App (recommended; one App serves all your repos).
  key="${AGENT_APP_PRIVATE_KEY:-}"
  if [[ -z "$app_id" ]] && keep_existing AGENT_APP_ID; then :
  else
    if [[ -z "$app_id" && "$interactive" == true ]]; then
      echo "  GitHub App for the agent (recommended, see docs/GETTING-STARTED.md §5). Leave empty to skip."
      ask app_id "App ID"
    fi
    if [[ -n "$app_id" && -z "$key" ]]; then
      if [[ -z "$app_key_file" && "$interactive" == true ]]; then
        # shellcheck disable=SC2012 # newest download first; names have no newlines
        guess=$(ls -t "$HOME"/Downloads/*.private-key.pem 2>/dev/null | head -1 || true)
        ask app_key_file "Path to the App private key (.pem)" "$guess"
      fi
      app_key_file="${app_key_file/#\~/$HOME}"
      [[ -n "$app_key_file" && -f "$app_key_file" ]] && key=$(cat "$app_key_file")
    fi
    if [[ -n "$app_id" && "$key" == *"PRIVATE KEY-----"* ]]; then
      put_secret AGENT_APP_ID "$app_id"
      put_secret AGENT_APP_PRIVATE_KEY "$key"
      AGENT_APP_ID="$app_id" AGENT_APP_PRIVATE_KEY_FILE="$app_key_file"
      warn "make sure the GitHub App is installed on $repo: https://github.com/settings/installations"
    elif [[ -n "$app_id" ]]; then
      warn "App ID given but no valid private key (.pem) — AGENT_APP_ID / AGENT_APP_PRIVATE_KEY not set"
    else
      warn "no GitHub App — the pipeline still works, with the limits in docs/GETTING-STARTED.md §5"
    fi
  fi

  if [[ -n "$project_number" ]]; then
    if [[ -n "${PROJECT_TOKEN:-}" ]]; then put_secret PROJECT_TOKEN "$PROJECT_TOKEN"
    elif ! keep_existing PROJECT_TOKEN; then
      v=""
      [[ "$interactive" == true ]] && ask_secret v "Classic PAT with repo+project scopes for PROJECT_TOKEN (empty to skip)"
      if [[ -n "$v" ]]; then put_secret PROJECT_TOKEN "$v"; PROJECT_TOKEN="$v"
      else warn "PROJECT_TOKEN not set — triage cannot update the GitHub Project"; fi
    fi
  fi
fi

# ── 5. repository settings ──────────────────────────────────────────────────────
if [[ "$settings" == true ]]; then
  step "Repository settings"
  if gh api -X PUT "repos/$repo/actions/permissions/workflow" \
       -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true >/dev/null; then
    ok "Actions: read/write token, may create and approve PRs"
  else warn "could not set Settings → Actions → Workflow permissions (do it by hand)"; fi
  allowed=$(gh api "repos/$repo/actions/permissions" --jq '"\(.enabled) \(.allowed_actions // "all")"' 2>/dev/null || echo "? ?")
  [[ "$allowed" == "true all" ]] \
    || warn "Actions are restricted ($allowed) — allow kokoroou/agent-toolkit/*, anthropics/*, actions/*, googleapis/release-please-action@*, gitleaks/gitleaks-action@*, oven-sh/setup-bun@*"
  if gh api -X PATCH "repos/$repo" -F allow_squash_merge=true -F delete_branch_on_merge=true >/dev/null; then
    ok "squash merge on, delete head branches on merge"
  else warn "could not enable squash merge"; fi
  if gh api -X PUT "repos/$repo/vulnerability-alerts" >/dev/null 2>&1 \
     && gh api -X PUT "repos/$repo/automated-security-fixes" >/dev/null 2>&1; then
    ok "Dependabot alerts + security updates on"
  else warn "could not enable Dependabot alerts (Settings → Advanced Security)"; fi
fi

# ── 6. commit + push ────────────────────────────────────────────────────────────
step "Commit"
files=(.github CLAUDE.md)
if [[ -z "$(git -C "$target" status --porcelain -- "${files[@]}")" ]]; then
  ok "nothing to commit"; commit=none
fi
if [[ -z "$commit" ]]; then
  targets="'$default_branch'"; [[ "$default_branch" != develop ]] && targets+=" and 'develop'"
  confirm "Commit the pipeline files and push to $targets?" y && commit=true || commit=false
fi
if [[ "$commit" == true ]]; then
  current=$(git -C "$target" symbolic-ref --short -q HEAD || echo "")
  git -C "$target" fetch -q origin "$default_branch" || true
  if [[ "$current" != "$default_branch" ]]; then
    warn "not committed: checkout is on '${current:-detached HEAD}', not '$default_branch'"
  elif [[ "$(git -C "$target" rev-parse HEAD)" != "$(git -C "$target" rev-parse "origin/$default_branch" 2>/dev/null)" ]]; then
    warn "not committed: local '$default_branch' differs from origin — pull/push first, then commit .github and CLAUDE.md"
  else
    git -C "$target" add -- "${files[@]}"
    git -C "$target" commit -q -m "ci: add agent-toolkit pipeline" -- "${files[@]}"
    git -C "$target" push -q origin "HEAD:$default_branch" || die "push to $default_branch failed"
    ok "pushed to $default_branch"
    if [[ "$default_branch" == develop ]]; then :
    elif git -C "$target" push -q origin "HEAD:develop" 2>/dev/null; then ok "pushed to develop"
    else warn "develop has diverged from $default_branch — merge $default_branch into develop by hand"; fi
  fi
elif [[ "$commit" == false ]]; then
  warn "commit .github and CLAUDE.md to '$default_branch' (and develop) yourself"
fi

if [[ "$default_branch" != develop && "$settings" == true ]]; then
  if [[ -z "$default_develop" ]]; then
    confirm "Make 'develop' the default branch (recommended, docs/ADD-TO-PROJECT.md §7)?" y \
      && default_develop=true || default_develop=false
  fi
  if [[ "$default_develop" == true ]]; then
    if gh api "repos/$repo/contents/.github/workflows/agent-merge-gate.yml?ref=develop" >/dev/null 2>&1; then
      if gh api -X PATCH "repos/$repo" -f default_branch=develop >/dev/null; then
        ok "default branch is now develop"
      else warn "could not change the default branch"; fi
    else
      warn "default branch not changed: develop does not have the pipeline files yet"
    fi
  else
    warn "keeping '$default_branch' as default: merge workflow changes into it too (docs/ADD-TO-PROJECT.md §7)"
  fi
fi

# ── 7. remember answers ─────────────────────────────────────────────────────────
# Plain values → config file; tokens → OS credential store (or nowhere).
backend=$(store_backend)
unsaved=""
for k in $secret_keys; do [[ -n "${!k:-}" && -z "$(store_get "$k")" ]] && unsaved+="$k "; done
if [[ "$interactive" == true && ( -n "$unsaved" || ( ! -f "$config" && -n "${AGENT_APP_ID:-}" ) ) ]]; then
  if [[ -n "$backend" ]]; then where="tokens → $backend, other values → $config"
  else where="$config; no OS credential store found, so tokens are NOT saved"; fi
  if confirm "Remember these answers for your next project ($where)?" n; then
    mkdir -p "$(dirname "$config")"
    ( umask 077
      for k in AGENT_TOOLKIT_REF AGENT_APP_ID AGENT_APP_PRIVATE_KEY_FILE PROJECT_OWNER; do
        [[ "$k" == AGENT_TOOLKIT_REF ]] && v="$ref" || v="${!k:-}"
        if [[ -n "$v" ]]; then printf '%s=%s\n' "$k" "$v"; fi
      done >"$config" )
    chmod 600 "$config" 2>/dev/null || true
    ok "saved $config"
    for k in $unsaved; do
      if [[ -n "$backend" ]] && store_set "$k" "${!k}"; then ok "$k saved in $backend"
      else warn "$k not saved — it will be asked again (or pass it as an environment variable)"; fi
    done
  fi
fi

# ── summary ─────────────────────────────────────────────────────────────────────
step "Done"
echo "  Actions: https://github.com/$repo/actions"
echo "  Still to do:"
echo "    - fill in Architecture / Conventions / Do not touch in CLAUDE.md, check the stack commands"
echo "    - open a small Feature issue to try the whole loop (docs/ADD-TO-PROJECT.md §8)"
if [[ ${#todo[@]} -gt 0 ]]; then printf '    - %s\n' "${todo[@]}"; fi
