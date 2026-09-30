#!/usr/bin/env bash
# Switch a project between the two branch models of the agent pipeline.
#
#   curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/switch-branch-model.sh \
#     | bash -s -- <gitlab-flow|github-flow> [<path>] [options]
#
#   gitlab-flow  agent PRs → develop (integration, SWE testing) → promotion PR develop → main
#                (QA testing) → release from main; main is merged back into develop after a
#                release or hotfix (branch-sync.yml does both automatically).
#   github-flow  agent PRs → main (integration + testing) → release from main; no develop.
#
# Runs in <path> (default: current directory, a checkout of main) and:
#   1. checks the remote: to github-flow, develop must hold nothing main lacks (merge the
#      promotion PR first);
#   2. rewrites the toolkit files with scripts/upgrade.sh --branch-model (your own edits
#      are 3-way merged; the files are also brought up to the ref in the lock);
#   3. commits and pushes them to main;
#   4. github-flow: makes main the default branch, optionally deletes develop;
#      gitlab-flow: creates develop from main, optionally makes it the default branch.
# Every step is skipped when already done, so after a conflict you can resolve, commit,
# and run the same command again.
#
# Options:
#   --commit | --no-commit              commit + push the files (asked; --yes: commit)
#   --default-branch | --keep-default   make the model's default branch the repo default
#                                       (github-flow: main; gitlab-flow: develop) (asked; --yes: yes)
#   --delete-develop                    github-flow: delete develop on GitHub (asked; --yes: keep)
#   --main <branch>                     the release branch [main]
#   --dry-run                           show what would change; change nothing
#   --toolkit-dir <dir>                 use this toolkit clone (with history) instead of cloning
#   -y, --yes                           non-interactive
set -euo pipefail

usage() { sed -n '2,33p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

if [[ -t 1 ]]; then b=$'\e[1m' g=$'\e[32m' y=$'\e[33m' r=$'\e[31m' n=$'\e[0m'; else b="" g="" y="" r="" n=""; fi
step() { printf '\n%s==> %s%s\n' "$b" "$*" "$n"; }
ok()   { printf '  %s✔%s %s\n' "$g" "$n" "$*"; }
say()  { printf '  %s\n' "$*"; }
warn() { printf '  %s!%s %s\n' "$y" "$n" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$r" "$n" "$*" >&2; exit 1; }

tty=""
if [[ -t 0 ]]; then tty=/dev/stdin
elif { : </dev/tty; } 2>/dev/null; then tty=/dev/tty; fi
confirm() { # <question> <default y|n>; non-interactive → default
  local a
  if [[ "$interactive" != true ]]; then [[ "$2" == y ]]; return; fi
  printf '  %s%s%s %s: ' "$b" "$1" "$n" "$([[ "$2" == y ]] && echo '[Y/n]' || echo '[y/N]')" >&2
  IFS= read -r a <"$tty" || true
  a=$(printf '%s' "${a:-$2}" | tr '[:upper:]' '[:lower:]')
  [[ "$a" == y || "$a" == yes ]]
}

model="" target="." target_set=false commit="" default_branch_opt="" delete_develop=""
main="main" develop="develop" dry_run=false toolkit_dir="" interactive=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    gitlab-flow|github-flow) model="$1"; shift ;;
    --commit) commit=true; shift ;;
    --no-commit) commit=false; shift ;;
    --default-branch) default_branch_opt=true; shift ;;
    --keep-default) default_branch_opt=false; shift ;;
    --delete-develop) delete_develop=true; shift ;;
    --main) main="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --toolkit-dir) toolkit_dir="$2"; shift 2 ;;
    -y|--yes) interactive=false; shift ;;
    -h|--help) usage 0 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [[ "$target_set" == true ]] && die "only one <path> allowed"; target="$1" target_set=true; shift ;;
  esac
done
[[ -n "$model" ]] || { echo "error: give the branch model: gitlab-flow or github-flow" >&2; usage 1; }
[[ -z "$tty" ]] && interactive=false
command -v git >/dev/null || die "git is not installed"

# ── project ─────────────────────────────────────────────────────────────────────
[[ -d "$target" ]] || die "$target is not a directory"
target=$(cd "$target" && pwd)
git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || die "$target is not a git checkout"
lock="$target/.github/agent-toolkit.lock"
[[ -f "$lock" ]] || die "no .github/agent-toolkit.lock in $target — install the pipeline first (scripts/install.sh), or run scripts/upgrade.sh once"
current_model=$(sed -n 's/^branch-model=//p' "$lock" | head -n 1)
current_model="${current_model:-gitlab-flow}"

remote=false repo=""
if command -v gh >/dev/null && repo=$(cd "$target" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null); then
  remote=true
else
  warn "gh is not installed or cannot see the repo — only the files are switched; do the GitHub steps by hand"
fi

step "Switching $target: $current_model → $model"
git -C "$target" fetch -q origin 2>/dev/null || warn "git fetch failed — checks use the last fetched state"
m="origin/$main" d="origin/$develop"
git -C "$target" rev-parse -q --verify "$m" >/dev/null || die "origin has no branch '$main' (use --main <branch>)"
has_develop=false
git -C "$target" rev-parse -q --verify "$d" >/dev/null && has_develop=true

# <from> <into>: true if merging <from> into <into> would change <into>'s files (as branch-sync.yml).
brings_changes() {
  local t
  git -C "$target" merge-base --is-ancestor "$1" "$2" && return 1
  t=$(git -C "$target" merge-tree --write-tree "$2" "$1") || return 0
  [[ "${t%%$'\n'*}" != "$(git -C "$target" rev-parse "$2^{tree}")" ]]
}

# ── 1. remote precondition ──────────────────────────────────────────────────────
if [[ "$model" == github-flow && "$has_develop" == true ]] && brings_changes "$d" "$m"; then
  die "'$develop' has changes '$main' does not — merge the promotion PR ($develop → $main) first, so
  no work stays behind on $develop, then run this again"
fi

# ── 2. files ────────────────────────────────────────────────────────────────────
current=$(git -C "$target" symbolic-ref --short -q HEAD || echo "")
if [[ "$current_model" == "$model" ]]; then
  ok "files already use $model (.github/agent-toolkit.lock)"
else
  if [[ "$dry_run" != true && "$commit" != false && "$current" != "$main" ]]; then
    die "$target is on '${current:-detached HEAD}'; the pipeline files are committed to '$main'.
  Switch first:  git switch $main && git pull     (or pass --no-commit)"
  fi
  if [[ -z "$toolkit_dir" && -f "${BASH_SOURCE[0]:-}" ]]; then
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [[ -f "$here/upgrade.sh" ]] && git -C "$here/.." rev-parse --git-dir >/dev/null 2>&1 && toolkit_dir="$here/.."
  fi
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  if [[ -z "$toolkit_dir" ]]; then
    toolkit_dir="$tmp/toolkit"
    git -c core.autocrlf=false clone -q https://github.com/kokoroou/agent-toolkit "$toolkit_dir" \
      || die "cannot clone agent-toolkit"
  fi
  up=("$target" --toolkit-dir "$toolkit_dir" --branch-model "$model" --no-labels)
  [[ "$dry_run" == true ]] && up+=(--dry-run)
  AGENT_TOOLKIT_QUIET_NEXT_STEPS=1 bash "$toolkit_dir/scripts/upgrade.sh" "${up[@]}" \
    || die "upgrade.sh stopped — resolve the conflicts (grep -rn '^<<<<<<<' .github), commit, and run this again"
fi
if [[ "$dry_run" == true ]]; then
  step "Dry run — the GitHub side would:"
  if [[ "$model" == github-flow ]]; then
    say "- make '$main' the default branch"
    [[ "$has_develop" != true ]] || say "- offer to delete '$develop'"
  else
    [[ "$has_develop" == true ]] || say "- create '$develop' from '$main'"
    say "- offer to make '$develop' the default branch"
  fi
  exit 0
fi

# ── 3. commit + push ────────────────────────────────────────────────────────────
files=(.github)
for f in .claude/settings.json scripts/agent-session.sh; do if [[ -e "$target/$f" ]]; then files+=("$f"); fi; done
if [[ -n "$(git -C "$target" status --porcelain -- "${files[@]}")" ]]; then
  if [[ -z "$commit" ]]; then
    confirm "Commit the changed files and push to '$main'?" y && commit=true || commit=false
  fi
  if [[ "$commit" == true ]]; then
    current=$(git -C "$target" symbolic-ref --short -q HEAD || echo "")
    [[ "$current" == "$main" ]] || die "not committed: the checkout is on '${current:-detached HEAD}', not '$main'"
    [[ "$(git -C "$target" rev-parse HEAD)" == "$(git -C "$target" rev-parse "$m")" ]] \
      || die "not committed: local '$main' differs from origin — pull/push first, then run this again"
    git -C "$target" add -- "${files[@]}"
    git -C "$target" commit -q -m "ci: switch the branch model to $model" -- "${files[@]}"
    git -C "$target" push -q origin "HEAD:$main" || die "push to $main failed"
    git -C "$target" fetch -q origin "$main" || true
    ok "pushed to $main"
  else
    warn "not committed: commit ${files[*]} to '$main' yourself, then run this again for the GitHub side"
    exit 0
  fi
fi

# ── 4. GitHub side ──────────────────────────────────────────────────────────────
if [[ "$remote" != true ]]; then
  if [[ "$model" == github-flow ]]; then say "Next: make '$main' the default branch; delete '$develop' when you no longer need it"
  else say "Next: create '$develop' from '$main' (git push origin $main:$develop); optionally make it the default branch"; fi
  exit 0
fi
default=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)
set_default() { # <branch>
  if [[ "$default" == "$1" ]]; then ok "default branch is '$1'"; return; fi
  if gh api -X PATCH "repos/$repo" -f default_branch="$1" >/dev/null; then ok "default branch is now '$1'"; default="$1"
  else warn "could not make '$1' the default branch (Settings → General → Default branch)"; fi
}

if [[ "$model" == github-flow ]]; then
  # workflow_run / schedule / dispatch read the workflow files of the default branch.
  if [[ "$default" != "$main" ]]; then
    if [[ -z "$default_branch_opt" ]]; then
      confirm "Make '$main' the default branch (needed: the callers live there now)?" y \
        && default_branch_opt=true || default_branch_opt=false
    fi
    if [[ "$default_branch_opt" == true ]]; then set_default "$main"
    else warn "'$default' is still the default branch: workflow_run/schedule triggers read its (old) files"; fi
  else ok "default branch is '$main'"; fi
  if [[ "$has_develop" == true ]]; then
    if [[ -z "$delete_develop" ]]; then
      confirm "Delete '$develop' on GitHub (it holds nothing '$main' lacks)?" n \
        && delete_develop=true || delete_develop=false
    fi
    if [[ "$delete_develop" == true && "$default" != "$develop" ]]; then
      if gh api -X DELETE "repos/$repo/git/refs/heads/$develop" >/dev/null; then ok "deleted '$develop'"
      else warn "could not delete '$develop'"; fi
    else
      warn "'$develop' is kept: open PRs into it and pushes to it are no longer part of the pipeline"
    fi
  fi
else
  if gh api "repos/$repo/branches/$develop" >/dev/null 2>&1; then
    ok "'$develop' exists — Branch Sync merges '$main' into it on the next push to either branch"
  else
    sha=$(git -C "$target" rev-parse "$m")
    if gh api "repos/$repo/git/refs" -f ref="refs/heads/$develop" -f sha="$sha" >/dev/null; then
      ok "created '$develop' from '$main'"
    else die "could not create '$develop'"; fi
  fi
  if [[ "$default" != "$develop" ]]; then
    if [[ -z "$default_branch_opt" ]]; then
      confirm "Make '$develop' the default branch (recommended, docs/ADD-TO-PROJECT.md §7)?" y \
        && default_branch_opt=true || default_branch_opt=false
    fi
    if [[ "$default_branch_opt" == true ]]; then set_default "$develop"
    else warn "keeping '$default' as default: merge workflow changes into it too (docs/ADD-TO-PROJECT.md §7)"; fi
  fi
fi

step "Done — $model"
if [[ "$model" == github-flow ]]; then
  say "Agent PRs now target '$main'; merging the release PR (release-please) publishes a version."
else
  say "Agent PRs now target '$develop'; Branch Sync opens the promotion PR $develop → $main and"
  say "merges '$main' back into '$develop' after each release."
fi
