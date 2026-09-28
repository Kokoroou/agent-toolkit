#!/usr/bin/env bash
# Upgrade the agent pipeline files of a project repository to a newer toolkit version.
#
#   curl -fsSL https://raw.githubusercontent.com/kokoroou/agent-toolkit/main/scripts/upgrade.sh | bash
#   curl -fsSL .../upgrade.sh | bash -s -- [<path>] [--to <ref>] [--dry-run]
#   Windows: & ([scriptblock]::Create((irm .../scripts/install.ps1))) upgrade --to v1
#
# Rebuilds the files of the installed version (base) and of --to (new) with bootstrap.sh
# and the same --stack, then for every toolkit-managed file:
#   unchanged locally → replaced by the new version;   changed only locally → kept;
#   changed on both sides → 3-way merged (git merge-file), conflicts left as <<<<<<< markers.
# New template files are added, removed ones deleted if you never edited them. Files that
# existed before the install are project-owned and never touched; CLAUDE.md is yours after
# the first install. The installed version, stack and managed files come from
# .github/agent-toolkit.lock (bootstrap.sh writes it). Nothing is committed: review
# `git diff`, then commit to the default branch.
#
# Options:
#   --to <ref>          version to upgrade to: moving tag (v0, v1), vX.Y.Z, branch or SHA
#                       [default: the ref in the lock, i.e. the latest release of that major]
#   --from <ref>        installed version, for installs without a lock (guessed otherwise)
#   --stack <s>         stack used at install, for installs without a lock [default: detected]
#   --dry-run           print what would change, with diffs; write nothing
#   --no-labels         do not create/update the labels with gh
#   --allow-dirty       run with uncommitted changes in .github/ or CLAUDE.md
#   --toolkit-dir <dir> use this toolkit clone (needs the history of both versions)
set -euo pipefail

usage() { sed -n '2,26p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

if [[ -t 1 ]]; then b=$'\e[1m' g=$'\e[32m' y=$'\e[33m' r=$'\e[31m' n=$'\e[0m'; else b="" g="" y="" r="" n=""; fi
step() { printf '\n%s==> %s%s\n' "$b" "$*" "$n"; }
say()  { printf '  %s\n' "$*"; }
die()  { printf '%serror:%s %s\n' "$r" "$n" "$*" >&2; exit 1; }

target="." to="" from="" stack="" dry_run=false labels=true allow_dirty=false toolkit_dir="" target_set=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to) to="$2"; shift 2 ;;
    --from) from="$2"; shift 2 ;;
    --stack) stack="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --no-labels) labels=false; shift ;;
    --allow-dirty) allow_dirty=true; shift ;;
    --toolkit-dir) toolkit_dir="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) [[ "$target_set" == true ]] && die "only one <path> allowed"; target="$1" target_set=true; shift ;;
  esac
done
command -v git >/dev/null || die "git is not installed"

# ── project + install record ────────────────────────────────────────────────────
[[ -d "$target" ]] || die "$target is not a directory"
target=$(cd "$target" && pwd)
git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || die "$target is not a git checkout"
lock="$target/.github/agent-toolkit.lock"
lock_get() { sed -n "s/^$1=//p" "$lock" | head -n 1; }
has_lock=false old_ref="" old_commit="" old_version=""
if [[ -f "$lock" ]]; then
  has_lock=true
  old_ref=$(lock_get ref) old_commit=$(lock_get commit) old_version=$(lock_get version)
  [[ -n "$stack" ]] || stack=$(lock_get stack)
fi
uses_ref=$(grep -rhoE 'kokoroou/agent-toolkit/\.github/workflows/[a-z-]+\.yml@[A-Za-z0-9._/-]+' \
  "$target/.github/workflows" 2>/dev/null | head -n 1 | sed 's/.*@//' || true)
old_ref="${old_ref:-$uses_ref}"
[[ -n "$old_ref" ]] || die "no agent-toolkit workflows in $target/.github/workflows — install first (scripts/install.sh)"
to="${to:-$old_ref}"

if [[ "$dry_run" != true && "$allow_dirty" != true \
      && -n "$(git -C "$target" status --porcelain -- .github CLAUDE.md)" ]]; then
  die "uncommitted changes in .github/ or CLAUDE.md — commit or stash them first (or --allow-dirty)"
fi

# ── toolkit versions ────────────────────────────────────────────────────────────
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [[ -z "$toolkit_dir" ]]; then
  toolkit_dir="$tmp/toolkit"
  git -c core.autocrlf=false clone -q https://github.com/kokoroou/agent-toolkit "$toolkit_dir" \
    || die "cannot clone agent-toolkit"
fi
git -C "$toolkit_dir" rev-parse --git-dir >/dev/null 2>&1 || die "$toolkit_dir is not a git clone of agent-toolkit"

resolve() { # <ref> → commit SHA in the toolkit clone
  local c
  for c in "refs/tags/$1" "refs/remotes/origin/$1" "$1"; do
    git -C "$toolkit_dir" rev-parse -q --verify "$c^{commit}" 2>/dev/null && return 0
  done
  return 1
}
extract() { # <sha> <dir> — toolkit files at <sha>
  mkdir -p "$2" && git -C "$toolkit_dir" archive "$1" | tar -x -C "$2"
}
markers="package.json pnpm-lock.yaml yarn.lock pyproject.toml setup.py requirements.txt go.mod"
gen() { # <toolkit files> <out dir> <ref> — bootstrap into a scratch repo, keep its files
  local a=("$2" --ref "$3" --no-labels) m
  mkdir -p "$2" && git -C "$2" init -q
  # The stack presets look at these files (python: pyproject.toml → pip install -e).
  for m in $markers; do if [[ -f "$target/$m" ]]; then : >"$2/$m"; fi; done
  if grep -q -- '--stack' "$1/scripts/bootstrap.sh"; then a+=(--stack "$stack"); fi
  AGENT_TOOLKIT_QUIET_NEXT_STEPS=1 bash "$1/scripts/bootstrap.sh" "${a[@]}" >/dev/null
  for m in $markers; do rm -f "$2/$m"; done
  rm -rf "$2/.git" "$2/.github/agent-toolkit.lock"
}
files_in() { (cd "$1" && find . -type f | sed 's#^\./##' | sort); }

new_sha=$(resolve "$to") || die "agent-toolkit has no ref '$to'"
extract "$new_sha" "$tmp/new-tk"
new_version=$(cat "$tmp/new-tk/version.txt" 2>/dev/null || true)
[[ -n "$stack" ]] || stack=$(bash "$tmp/new-tk/scripts/bootstrap.sh" "$target" --detect-stack)

base_sha="" base_label=""
if [[ -n "$from" ]]; then
  base_sha=$(resolve "$from") || die "agent-toolkit has no ref '$from'"; base_label="$from"
elif [[ -n "$old_commit" ]] && base_sha=$(resolve "$old_commit"); then
  base_label="${old_version:+v$old_version }(${old_commit:0:7})"
elif [[ -n "$old_version" ]] && base_sha=$(resolve "v$old_version"); then
  base_label="v$old_version"
else
  # Install without a record: pick the release whose files match the project best.
  best_n=0
  for t in $(git -C "$toolkit_dir" tag -l 'v*.*.*' --sort=-v:refname | head -n 15); do
    d="$tmp/guess-$t"
    if ! { extract "$t" "$d/tk" && gen "$d/tk" "$d/out" "$old_ref" 2>/dev/null; }; then continue; fi
    k=0
    while IFS= read -r f; do
      if [[ -f "$target/$f" ]] && tr -d '\r' <"$target/$f" | cmp -s - "$d/out/$f"; then k=$((k + 1)); fi
    done < <(files_in "$d/out")
    if (( k > best_n )); then best_n=$k base_sha=$(resolve "$t") base_label="$t (guessed: $k identical files)"; fi
  done
fi

step "Upgrading agent-toolkit in $target"
say "from: ${base_label:-unknown version (no .github/agent-toolkit.lock; use --from <ref>)}"
say "to:   $to${new_version:+ = v$new_version} (${new_sha:0:7})"
say "stack: $stack"
[[ -n "$base_sha" && "$base_sha" == "$new_sha" ]] && say "(same toolkit commit — only local drift is reported)"

gen "$tmp/new-tk" "$tmp/new" "$to"
mkdir -p "$tmp/base"
if [[ -n "$base_sha" ]]; then
  extract "$base_sha" "$tmp/base-tk"
  gen "$tmp/base-tk" "$tmp/base" "$old_ref"
fi

# ── merge file by file ──────────────────────────────────────────────────────────
is_managed() { # <file> [normalized project copy]
  if [[ "$has_lock" == true ]]; then grep -qxF "managed=$1" "$lock"; return; fi
  # No record: toolkit-owned if missing, untouched since install, or calling the toolkit.
  [[ ! -f "$target/$1" ]] || { [[ -f "$tmp/base/$1" ]] && cmp -s "$2" "$tmp/base/$1"; } \
    || grep -q 'kokoroou/agent-toolkit/' "$2"
}
put() { # <content file> <file> — write (or, with --dry-run, show the diff)
  if [[ "$dry_run" == true ]]; then
    diff -u --label "a/$2" --label "b/$2" "$pn" "$1" | sed 's/^/      /' || true
  else
    mkdir -p "$(dirname "$target/$2")" && cp "$1" "$target/$2"
  fi
}
row() { printf '  %s %-45s %s\n' "$1" "$2" "$3"; rows=$((rows + 1)); }

conflicts=0 attention=0 rows=0
: >"$tmp/managed"
pn="$tmp/project"
compare="https://github.com/kokoroou/agent-toolkit/compare/${base_sha:0:12}...${new_sha:0:12}"
while IFS= read -r f; do
  P="$target/$f" B="$tmp/base/$f" N="$tmp/new/$f"
  if [[ -f "$P" ]]; then tr -d '\r' <"$P" >"$pn"; else : >"$pn"; fi

  if [[ "$f" == CLAUDE.md ]]; then
    if [[ -f "$B" && -f "$N" ]] && ! cmp -s "$B" "$N"; then
      row "·" "$f" "yours, not touched — the template changed: $compare"
    fi
    continue
  fi
  if [[ -f "$P" ]] && ! is_managed "$f" "$pn"; then
    if [[ -f "$N" ]] && ! cmp -s "$pn" "$N" && { [[ ! -f "$B" ]] || ! cmp -s "$B" "$N"; }; then
      row "·" "$f" "project-owned, not touched (the template changed — merge by hand if needed)"
    fi
    continue
  fi

  if [[ ! -f "$N" ]]; then                       # removed from the toolkit
    [[ -f "$P" ]] || continue
    if [[ -f "$B" ]] && cmp -s "$pn" "$B"; then
      row "${r}-${n}" "$f" "removed (no longer part of the toolkit)"
      [[ "$dry_run" == true ]] || rm -f "$P"
    else
      row "${y}!${n}" "$f" "no longer part of the toolkit — kept because you edited it; delete it if unused"
      attention=$((attention + 1))
    fi
    continue
  fi
  if [[ ! -f "$P" ]]; then
    if [[ -f "$B" ]]; then row "·" "$f" "deleted locally — not re-added"
    else row "${g}+${n}" "$f" "added"; put "$N" "$f"; echo "managed=$f" >>"$tmp/managed"; fi
    continue
  fi
  echo "managed=$f" >>"$tmp/managed"

  if cmp -s "$pn" "$N"; then
    continue                                     # already up to date
  elif [[ -f "$B" ]] && cmp -s "$pn" "$B"; then
    row "${g}↑${n}" "$f" "updated"; put "$N" "$f"
  elif [[ -f "$B" ]] && cmp -s "$B" "$N"; then
    row "=" "$f" "kept your edits (no upstream change)"
  elif [[ -f "$B" ]]; then
    rc=0
    git merge-file -p -L "yours" -L "base ${base_label%% *}" -L "agent-toolkit $to" \
      "$pn" "$B" "$N" >"$tmp/merged" || rc=$?
    if [[ $rc -eq 0 ]]; then
      row "${g}~${n}" "$f" "updated, your edits merged in"
    elif [[ $rc -lt 128 ]]; then
      row "${r}!${n}" "$f" "CONFLICT ($rc) — resolve the <<<<<<< markers"
      conflicts=$((conflicts + 1))
    else
      die "git merge-file failed on $f"
    fi
    put "$tmp/merged" "$f"
  else
    row "${y}!${n}" "$f" "differs and the installed version is unknown — compare with $f.upstream"
    [[ "$dry_run" == true ]] || cp "$N" "$P.upstream"
    attention=$((attention + 1))
  fi
done < <({ files_in "$tmp/base"; files_in "$tmp/new"; } | sort -u)
[[ $rows -gt 0 ]] || say "all toolkit files already match $to"

# ── record + labels ─────────────────────────────────────────────────────────────
if [[ "$dry_run" == true ]]; then
  step "Dry run — nothing written"
  exit 0
fi
{
  echo "# Written by agent-toolkit (scripts/bootstrap.sh, scripts/upgrade.sh). Do not edit:"
  echo "# scripts/upgrade.sh regenerates the files of this commit + stack to merge your edits."
  echo "version=$new_version"
  echo "ref=$to"
  echo "commit=$new_sha"
  echo "stack=$stack"
  sort -u "$tmp/managed"
} >"$lock"

if [[ "$labels" == true ]] && command -v gh >/dev/null \
   && repo=$(cd "$target" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null); then
  sed -n 's/.*"name": *"\([^"]*\)", *"color": *"\([^"]*\)", *"description": *"\([^"]*\)".*/\1\t\2\t\3/p' \
    "$tmp/new-tk/templates/.github/labels.json" | while IFS=$'\t' read -r name color desc; do
    gh label create "$name" --repo "$repo" --force --color "$color" --description "$desc" >/dev/null || true
  done
  say "labels of $repo updated"
fi

# ── summary ─────────────────────────────────────────────────────────────────────
step "Done"
if [[ -n "$old_version" && -n "$new_version" && "$old_version" != "$new_version" ]]; then
  say "Changes since v$old_version (CHANGELOG.md):"
  awk -v v="$old_version" 'NR > 1 && $0 ~ "^## \\[?" v "[] (]" { exit } NR > 1 && NF { print "    " $0 }' \
    "$tmp/new-tk/CHANGELOG.md" 2>/dev/null | head -n 60 || true
fi
say "Next:"
if [[ $conflicts -gt 0 ]]; then
  say "  - resolve the conflicts: grep -rn '^<<<<<<<' .github"
fi
if [[ $attention -gt 0 ]]; then say "  - check the files marked ! above (merge any *.upstream copy by hand, then delete it)"; fi
say "  - review: git diff"
say "  - commit to the DEFAULT branch (workflow_run/schedule/dispatch read it from there):"
say "      git add .github && git commit -m \"ci: upgrade agent-toolkit to $to${new_version:+ (v$new_version)}\""
[[ $conflicts -eq 0 ]] || exit 1
