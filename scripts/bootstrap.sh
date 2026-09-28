#!/usr/bin/env bash
# Install the agent pipeline into a project repository.
#
#   scripts/bootstrap.sh <path-to-project-checkout> [--ref v1] [--force] [--no-labels]
#
# Copies the caller workflows, issue/PR templates, dependabot config and a CLAUDE.md
# skeleton; pins every `uses: kokoroou/agent-toolkit/...@main` to --ref; creates the
# label taxonomy and the develop branch with gh. Existing files are kept unless --force.
set -euo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

target="" ref="main" force=false labels=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) ref="$2"; shift 2 ;;
    --force) force=true; shift ;;
    --no-labels) labels=false; shift ;;
    -h|--help) usage 0 ;;
    *) if [[ -z "$target" ]]; then target="$1"; else usage 1; fi; shift ;;
  esac
done
[[ -n "$target" && -d "$target/.git" ]] || { echo "error: <path> must be a git checkout" >&2; usage 1; }

toolkit="$(cd "$(dirname "$0")/.." && pwd)"
src="$toolkit/templates"

copied=() skipped=()
while IFS= read -r -d '' f; do
  rel="${f#"$src"/}"
  [[ "$rel" == ".github/labels.json" ]] && continue
  dst="$target/$rel"
  if [[ -e "$dst" && "$force" != true ]]; then skipped+=("$rel"); continue; fi
  mkdir -p "$(dirname "$dst")"
  sed "s#\(kokoroou/agent-toolkit/\.github/workflows/[a-z-]*\.yml\)@main#\1@$ref#" "$f" >"$dst"
  copied+=("$rel")
done < <(find "$src" -type f -print0 | sort -z)

echo "Copied (${#copied[@]}):"; printf '  + %s\n' "${copied[@]}"
if [[ ${#skipped[@]} -gt 0 ]]; then
  echo "Kept existing (${#skipped[@]}, use --force to overwrite):"; printf '  = %s\n' "${skipped[@]}"
fi

if [[ "$labels" == true ]] && command -v gh >/dev/null; then
  repo=$(cd "$target" && gh repo view --json nameWithOwner --jq .nameWithOwner)
  echo "Creating labels in $repo"
  jq -c '.[]' "$src/.github/labels.json" | while read -r l; do
    gh label create "$(jq -r .name <<<"$l")" --repo "$repo" --force \
      --color "$(jq -r .color <<<"$l")" --description "$(jq -r .description <<<"$l")" >/dev/null
  done
  default=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)
  if ! gh api "repos/$repo/branches/develop" >/dev/null 2>&1; then
    sha=$(gh api "repos/$repo/git/ref/heads/$default" --jq .object.sha)
    gh api "repos/$repo/git/refs" -f ref=refs/heads/develop -f sha="$sha" >/dev/null
    echo "Created branch develop from $default"
  fi
fi

cat <<EOF

Next steps (see docs/ADD-TO-PROJECT.md in agent-toolkit):
  1. Edit the "edit for your stack" blocks in .github/workflows/*.yml and CLAUDE.md.
  2. Repository secrets:
       ANTHROPIC_API_KEY  (or CLAUDE_CODE_OAUTH_TOKEN)          required
       AGENT_APP_ID + AGENT_APP_PRIVATE_KEY                     recommended
       PROJECT_TOKEN                                            only for GitHub Projects
  3. Settings → Actions → General → Workflow permissions: "Read and write" and
     "Allow GitHub Actions to create and approve pull requests".
  4. Commit to the DEFAULT branch — workflow_run / schedule / dispatch only use
     workflow files from there.
EOF
