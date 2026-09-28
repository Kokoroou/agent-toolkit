#!/usr/bin/env bash
# Install the agent pipeline into a project repository.
#
#   scripts/bootstrap.sh <path-to-project-checkout> [--ref v0] [--stack auto] [--force] [--no-labels]
#
# Copies the caller workflows, issue/PR templates, dependabot config and a CLAUDE.md
# skeleton; pins every `uses: kokoroou/agent-toolkit/...@main` to --ref; fills in the
# stack-specific commands (--stack auto|node|pnpm|yarn|python|go|none; auto detects from
# the project's files); creates the label taxonomy and the develop branch with gh.
# Existing files are kept unless --force. Records the toolkit version, --stack and the
# copied files in .github/agent-toolkit.lock for scripts/upgrade.sh. For the full
# one-command setup (tools, secrets, repo settings, commit) use scripts/install.sh.
set -euo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

target="" ref="main" stack="auto" force=false labels=true detect_only=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) ref="$2"; shift 2 ;;
    --stack) stack="$2"; shift 2 ;;
    --force) force=true; shift ;;
    --no-labels) labels=false; shift ;;
    --detect-stack) detect_only=true; shift ;; # print the detected stack and exit
    -h|--help) usage 0 ;;
    *) if [[ -z "$target" ]]; then target="$1"; else usage 1; fi; shift ;;
  esac
done
[[ -n "$target" && -e "$target/.git" ]] || { echo "error: <path> must be a git checkout" >&2; usage 1; }

toolkit="$(cd "$(dirname "$0")/.." && pwd)"
src="$toolkit/templates"

# ── stack presets ───────────────────────────────────────────────────────────────
# The templates default to Node + npm + Jest + Prettier + ESLint. A preset rewrites
# single lines: <file> TAB <line prefix> TAB <new value>. The key is the prefix up to its
# first ":"; a folded (">-") value keeps its style and its continuation lines are dropped.
detect_stack() {
  if [[ -f "$target/package.json" ]]; then
    if [[ -f "$target/pnpm-lock.yaml" ]]; then echo pnpm
    elif [[ -f "$target/yarn.lock" ]]; then echo yarn
    else echo node; fi
  elif [[ -f "$target/pyproject.toml" || -f "$target/setup.py" || -f "$target/requirements.txt" ]]; then echo python
  elif [[ -f "$target/go.mod" ]]; then echo go
  else echo node; fi
}

preset() {
  local ci=.github/workflows/ci.yml impl=.github/workflows/agent-implement.yml
  local gate=.github/workflows/agent-merge-gate.yml dep=.github/dependabot.yml
  local rel=.github/workflows/release.yml md=CLAUDE.md
  local setup lint fmt fmtw cov test tools smoke build eco rtype
  case "$1" in
    node|none) return 0 ;;
    pnpm|yarn)
      local pm="$1" x jest_cov
      if [[ "$pm" == pnpm ]]; then setup="corepack enable && pnpm install --frozen-lockfile" x="pnpm exec"
      else setup="corepack enable && yarn install --frozen-lockfile" x="yarn"; fi
      jest_cov="$x jest --coverage"
      lint="$pm run lint"; fmt="$x prettier --check ."; fmtw="$x prettier --write ."
      cov="$jest_cov --coverageReporters=json-summary >&2 && node -e \"console.log(require('./coverage/coverage-summary.json').total.lines.pct)\""
      test="$pm test"; build="$pm run build"
      tools="\"Bash(corepack enable),Bash($pm install:*),Bash($pm run:*),Bash($pm test:*),Bash($x:*)\""
      smoke="$pm run build && $pm test -- smoke"
      eco=npm rtype=node
      printf '%s\t%s\t%s\n' "$md" "- Coverage:" "\`$jest_cov\`" ;;
    python)
      if [[ -f "$target/pyproject.toml" || -f "$target/setup.py" ]]; then setup="pip install -e \".[dev]\""
      else setup="pip install -r requirements.txt"; fi
      lint="ruff check ."; fmt="ruff format --check ."; fmtw="ruff format ."
      cov="pytest --cov --cov-report=term >&2 && coverage report --format=total"
      test="pytest"; build="python -m build"
      tools="\"Bash(pip install:*),Bash(pytest:*),Bash(ruff:*),Bash(python -m:*),Bash(mypy:*),Bash(coverage:*)\""
      smoke="pytest -m smoke"
      eco=pip rtype=python
      printf '%s\t%s\t%s\n' "$md" "- Coverage:" "\`pytest --cov\`" ;;
    go)
      setup="go mod download"
      lint="go vet ./..."; fmt="test -z \"\$(gofmt -l .)\""; fmtw="gofmt -w ."
      cov="go test -coverprofile=c.out ./... >&2 && go tool cover -func=c.out | tail -1 | awk '{print \$3}'"
      test="go test ./..."; build="go build ./..."
      tools="\"Bash(go build:*),Bash(go test:*),Bash(go vet:*),Bash(gofmt:*),Bash(go mod:*),Bash(go tool cover:*)\""
      smoke="go build ./... && go test -run Smoke ./..."
      eco=gomod rtype=go
      printf '%s\t%s\t%s\n' "$md" "- Coverage:" "\`go test -cover ./...\`" ;;
    *) echo "error: unknown --stack '$1' (auto|node|pnpm|yarn|python|go|none)" >&2; exit 1 ;;
  esac
  printf '%s\t%s\t%s\n' \
    "$ci" "setup-command:" "$setup" \
    "$ci" "lint-command:" "$lint" \
    "$ci" "format-check-command:" "$fmt" \
    "$ci" "coverage-command:" "$cov" \
    "$impl" "setup-command:" "$setup" \
    "$impl" "extra-allowed-tools:" "$tools" \
    "$gate" "setup-command:" "$setup" \
    "$gate" "extra-allowed-tools:" "$tools" \
    "$gate" "smoke-command:" "$smoke" \
    "$dep" "- package-ecosystem: npm" "$eco" \
    "$rel" "release-type:" "$rtype" \
    "$md" "- Install:" "\`$setup\`" \
    "$md" "- Lint:" "\`$lint\`" \
    "$md" "- Format:" "\`$fmtw\` (check: \`$fmt\`)" \
    "$md" "- Test:" "\`$test\`" \
    "$md" "- Build:" "\`$build\`"
}

apply_preset() { # <rules-file> <relative path> <file>
  awk -F'\t' -v rel="$2" '
    FILENAME == ARGV[1] { if ($1 == rel) { n++; pre[n] = $2; val[n] = $3 } next }
    {
      if (skip) {
        match($0, /^ */)
        if ($0 !~ /^[[:space:]]*$/ && RLENGTH > ind) next
        skip = 0
      }
      match($0, /^ */); ind = RLENGTH; body = substr($0, ind + 1); pad = substr($0, 1, ind)
      for (i = 1; i <= n; i++) {
        if (substr(body, 1, length(pre[i])) != pre[i]) continue
        key = substr(pre[i], 1, index(pre[i], ":"))
        rest = substr(body, length(key) + 1); sub(/^[ \t]+/, "", rest)
        if (rest ~ /^>-/) { print pad key " >-"; print pad "  " val[i]; skip = 1 }
        else print pad key " " val[i]
        next
      }
      print
    }' "$1" "$3" >"$3.tmp" && mv "$3.tmp" "$3"
}

if [[ "$detect_only" == true ]]; then detect_stack; exit 0; fi
[[ "$stack" == auto ]] && stack=$(detect_stack)
rules=$(mktemp); trap 'rm -f "$rules"' EXIT
preset "$stack" >"$rules"
echo "Stack: $stack"

# ── copy templates ──────────────────────────────────────────────────────────────
copied=() skipped=()
while IFS= read -r -d '' f; do
  rel="${f#"$src"/}"
  [[ "$rel" == ".github/labels.json" ]] && continue
  dst="$target/$rel"
  if [[ -e "$dst" && "$force" != true ]]; then skipped+=("$rel"); continue; fi
  mkdir -p "$(dirname "$dst")"
  sed "s#\(kokoroou/agent-toolkit/\.github/workflows/[a-z-]*\.yml\)@main#\1@$ref#" "$f" >"$dst"
  apply_preset "$rules" "$rel" "$dst"
  copied+=("$rel")
done < <(find "$src" -type f -print0 | sort -z)

echo "Copied (${#copied[@]}):"
if [[ ${#copied[@]} -gt 0 ]]; then printf '  + %s\n' "${copied[@]}"; fi
if [[ ${#skipped[@]} -gt 0 ]]; then
  echo "Kept existing (${#skipped[@]}, use --force to overwrite):"; printf '  = %s\n' "${skipped[@]}"
fi

# ── install record ──────────────────────────────────────────────────────────────
# .github/agent-toolkit.lock tells scripts/upgrade.sh which toolkit commit and --stack
# produced the files, so it can regenerate them and 3-way merge local edits. managed=
# lists the files the toolkit owns: the ones copied here, minus CLAUDE.md (yours after
# the first install). Kept existing files stay project-owned. Re-running without --force
# only adds newly copied files to an existing record.
lock="$target/.github/agent-toolkit.lock"
{
  if [[ -f "$lock" && "$force" != true ]]; then
    cat "$lock"
  else
    echo "# Written by agent-toolkit (scripts/bootstrap.sh, scripts/upgrade.sh). Do not edit:"
    echo "# scripts/upgrade.sh regenerates the files of this commit + stack to merge your edits."
    echo "version=$(cat "$toolkit/version.txt" 2>/dev/null || true)"
    echo "ref=$ref"
    commit=""
    if [[ "$(git -C "$toolkit" rev-parse --show-toplevel 2>/dev/null)" == "$(cd "$toolkit" && pwd -P)" ]]; then
      commit=$(git -C "$toolkit" rev-parse -q --verify HEAD || true)
    fi
    echo "commit=$commit"
    echo "stack=$stack"
  fi
  for f in ${copied[@]+"${copied[@]}"}; do [[ "$f" == CLAUDE.md ]] || echo "managed=$f"; done
} | awk '!/^managed=/ || !seen[$0]++' >"$lock.tmp" && mv "$lock.tmp" "$lock"

# ── labels + develop branch ─────────────────────────────────────────────────────
# labels.json keeps one {"name", "color", "description"} object per line (checked by
# scripts/lint.sh), so it is read with sed and needs no jq.
if [[ "$labels" == true ]] && command -v gh >/dev/null; then
  repo=$(cd "$target" && gh repo view --json nameWithOwner --jq .nameWithOwner)
  echo "Creating labels in $repo"
  sed -n 's/.*"name": *"\([^"]*\)", *"color": *"\([^"]*\)", *"description": *"\([^"]*\)".*/\1\t\2\t\3/p' \
    "$src/.github/labels.json" | while IFS=$'\t' read -r name color desc; do
    gh label create "$name" --repo "$repo" --force --color "$color" --description "$desc" >/dev/null
  done
  default=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)
  if ! gh api "repos/$repo/branches/develop" >/dev/null 2>&1; then
    sha=$(gh api "repos/$repo/git/ref/heads/$default" --jq .object.sha)
    gh api "repos/$repo/git/refs" -f ref=refs/heads/develop -f sha="$sha" >/dev/null
    echo "Created branch develop from $default"
  fi
fi

[[ "${AGENT_TOOLKIT_QUIET_NEXT_STEPS:-}" == 1 ]] && exit 0
cat <<EOF

Next steps (see docs/ADD-TO-PROJECT.md in agent-toolkit):
  1. Review the "edit for your stack" blocks in .github/workflows/*.yml and fill in CLAUDE.md.
  2. Repository secrets:
       ANTHROPIC_API_KEY  (or CLAUDE_CODE_OAUTH_TOKEN)          required
       AGENT_APP_ID + AGENT_APP_PRIVATE_KEY                     recommended
       PROJECT_TOKEN                                            only for GitHub Projects
  3. Settings → Actions → General → Workflow permissions: "Read and write" and
     "Allow GitHub Actions to create and approve pull requests".
  4. Commit to the DEFAULT branch — workflow_run / schedule / dispatch only use
     workflow files from there.
  Or let scripts/install.sh do steps 2–4 for you.
EOF
