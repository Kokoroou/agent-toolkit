#!/usr/bin/env bash
# Install the agent pipeline into a project repository.
#
#   scripts/bootstrap.sh <path-to-project-checkout> [--ref v0] [--stack auto] [--tools k=v,...]
#                        [--branch-model gitlab-flow|github-flow] [--force] [--no-labels]
#
# Copies the caller workflows, issue/PR templates, dependabot config and a CLAUDE.md
# skeleton; pins every `uses: kokoroou/agent-toolkit/...@main` to --ref; fills in the
# stack-specific commands (--stack auto|node|pnpm|yarn|python|go|none; auto detects from
# the project's files) for the linter, formatter and test runner the project actually
# uses (detected; --tools overrides single keys, e.g. --tools test=vitest,format=none);
# creates the label taxonomy (and, for gitlab-flow, the develop branch) with gh. The
# branch model: github-flow (default) = agent PRs → main, release from main, no develop;
# gitlab-flow = agent PRs → develop, promotion PR develop → main, release from main, main
# synced back into develop (branch-sync.yml). scripts/switch-branch-model.sh switches.
# Existing files are kept unless --force. Records the toolkit version, --stack, the
# tools, the branch model and the copied files in .github/agent-toolkit.lock for
# scripts/upgrade.sh. For the full one-command setup (tools, secrets, repo settings,
# commit) use scripts/install.sh.
set -euo pipefail

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

target="" ref="main" stack="auto" tools_override="" force=false labels=true detect=""
branch_model="github-flow"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) ref="$2"; shift 2 ;;
    --stack) stack="$2"; shift 2 ;;
    --tools) tools_override+="${tools_override:+,}$2"; shift 2 ;; # repeatable; later keys win
    --branch-model) branch_model="$2"; shift 2 ;;
    --force) force=true; shift ;;
    --no-labels) labels=false; shift ;;
    --detect-stack) detect=stack; shift ;; # print the detected stack and exit
    --detect-tools) detect=tools; shift ;; # print the tools for --stack (+ --tools) and exit
    -h|--help) usage 0 ;;
    *) if [[ -z "$target" ]]; then target="$1"; else usage 1; fi; shift ;;
  esac
done
[[ -n "$target" && -e "$target/.git" ]] || { echo "error: <path> must be a git checkout" >&2; usage 1; }
case "$branch_model" in
  gitlab-flow|github-flow) ;;
  *) echo "error: unknown --branch-model '$branch_model' (gitlab-flow|github-flow)" >&2; exit 1 ;;
esac

toolkit="$(cd "$(dirname "$0")/.." && pwd)"
src="$toolkit/templates"

# ── stack + tool presets ────────────────────────────────────────────────────────
# The stack is the language + package manager; the tools are what the project's own
# files say it uses, so no command is written for a tool the project does not have (an
# empty command skips that CI step). Tools are "key=value,..." — JS stacks: lint=script|
# eslint|biome|none, format=script|prettier|biome|none, test=vitest|jest|script|none,
# coverage=yes|no, build=yes|no, tsc=yes|no, smoke=yes|no ("script" = the package.json
# script: lint, format:check, test); python: lint=ruff|flake8|none, format=ruff|black|none,
# test=pytest|none, coverage=yes|no, smoke=yes|no; go and none have no keys. smoke=yes
# needs a smoke test to exist (the merge gate reverts a merge when smoke-command fails).
# A preset rewrites single lines: <file> TAB <line prefix> TAB <new value>. The key is the
# prefix up to its first ":"; a folded (">-") value keeps its style and its continuation
# lines are dropped.
detect_stack() {
  if [[ -f "$target/package.json" ]]; then
    if [[ -f "$target/pnpm-lock.yaml" ]]; then echo pnpm
    elif [[ -f "$target/yarn.lock" ]]; then echo yarn
    else echo node; fi
  elif [[ -f "$target/pyproject.toml" || -f "$target/setup.py" || -f "$target/requirements.txt" ]]; then echo python
  elif [[ -f "$target/go.mod" ]]; then echo go
  else echo node; fi
}

# package.json is read with grep/awk (no node or jq needed), assuming the usual layout
# of one "key": value per line.
pkg_has() { # <name> — a dependency or top-level config key named <name>
  grep -Eq "\"$1\"[[:space:]]*:" "$target/package.json" 2>/dev/null
}
pkg_script() { # <name> — scripts.<name> exists (npm's "no test specified" stub doesn't count)
  local line
  line=$(awk '/"scripts"[[:space:]]*:/ { s = 1 } s { print } s && /}/ { exit }' "$target/package.json" 2>/dev/null \
    | grep -E "\"$1\"[[:space:]]*:" | head -n 1 || true)
  [[ -n "$line" && "$line" != *"no test specified"* ]]
}
has_file() { # <glob> relative to the project
  compgen -G "$target/$1" >/dev/null
}
has_smoke_test() { # a JS test file with "smoke" in its path (the runners' name filter)
  [[ -n "$(cd "$target" && find . \( -name node_modules -o -name .git \) -prune -o -type f -ipath '*smoke*' \
    \( -name '*.test.*' -o -name '*.spec.*' \) -print -quit 2>/dev/null)" ]]
}
has_smoke_mark() { # a pytest test marked smoke (what `pytest -m smoke` selects)
  grep -rqs --include='*.py' --exclude-dir=.git --exclude-dir=.venv --exclude-dir=venv \
    'mark\.smoke' "$target"
}
py_has() { # <tool> — named in the Python project/requirements/config files
  local f
  for f in "$target"/pyproject.toml "$target"/setup.cfg "$target"/setup.py "$target"/tox.ini \
           "$target"/requirements*.txt; do
    [[ -f "$f" ]] && grep -Eqi "(^|[^a-z0-9_-])$1([^a-z0-9_-]|$)" "$f" && return 0
  done
  return 1
}

detect_tools() { # <stack> → tools spec
  local lint=none format=none test=none coverage=no build=no tsc=no smoke=no
  case "$1" in
    node|pnpm|yarn)
      if [[ ! -f "$target/package.json" ]]; then
        # Not scaffolded yet: rely on the package.json scripts every tool can sit behind.
        echo "lint=script,format=none,test=script,coverage=no,build=yes,tsc=no,smoke=no"; return
      fi
      if pkg_script lint; then lint=script
      elif pkg_has eslint; then lint=eslint
      elif pkg_has @biomejs/biome; then lint=biome; fi
      if pkg_script format:check; then format=script
      elif pkg_has prettier || has_file '.prettierrc*' || has_file 'prettier.config.*'; then format=prettier
      elif pkg_has @biomejs/biome || has_file 'biome.json*'; then format=biome; fi
      if pkg_has vitest; then
        test=vitest
        if pkg_has @vitest/coverage-v8 || pkg_has @vitest/coverage-istanbul; then coverage=yes; fi
      elif pkg_has jest; then test=jest coverage=yes
      elif pkg_script test; then test=script; fi
      if pkg_script build; then build=yes; fi
      if pkg_has typescript; then tsc=yes; fi
      if [[ "$test" != none ]] && has_smoke_test; then smoke=yes; fi
      echo "lint=$lint,format=$format,test=$test,coverage=$coverage,build=$build,tsc=$tsc,smoke=$smoke" ;;
    python)
      if [[ ! -f "$target/pyproject.toml" && ! -f "$target/setup.py" && ! -f "$target/requirements.txt" ]]; then
        echo "lint=ruff,format=ruff,test=pytest,coverage=yes,smoke=no"; return # not scaffolded yet: the usual pair
      fi
      if py_has ruff || has_file 'ruff.toml' || has_file '.ruff.toml'; then lint=ruff
      elif py_has flake8 || has_file '.flake8'; then lint=flake8; fi
      if py_has black; then format=black
      elif [[ "$lint" == ruff ]]; then format=ruff; fi
      if py_has pytest || has_file 'pytest.ini' || has_file 'conftest.py' || has_file 'tests/conftest.py'; then
        test=pytest
        if py_has pytest-cov; then coverage=yes; fi
        if has_smoke_mark; then smoke=yes; fi
      fi
      echo "lint=$lint,format=$format,test=$test,coverage=$coverage,smoke=$smoke" ;;
    go|none) echo "" ;;
    *) echo "error: unknown --stack '$1' (auto|node|pnpm|yarn|python|go|none)" >&2; exit 1 ;;
  esac
}

merge_tools() { # <spec> <overrides> → spec with the overridden keys, validated
  local out="$1" kv k p new allowed
  local -a kvs parts
  case "$stack" in
    node|pnpm|yarn) allowed=" lint:script|eslint|biome|none format:script|prettier|biome|none test:vitest|jest|script|none coverage:yes|no build:yes|no tsc:yes|no smoke:yes|no " ;;
    python) allowed=" lint:ruff|flake8|none format:ruff|black|none test:pytest|none coverage:yes|no smoke:yes|no " ;;
    *) allowed=" " ;;
  esac
  IFS=, read -ra kvs <<<"$2"
  for kv in ${kvs[@]+"${kvs[@]}"}; do
    [[ "$kv" =~ ^([a-z]+)=([a-z0-9]+)$ ]] || { echo "error: --tools entry '$kv' is not key=value" >&2; exit 1; }
    k=${BASH_REMATCH[1]}
    [[ "$allowed" =~ \ $k:([^ ]+)\  ]] \
      || { echo "error: --tools key '$k' does not apply to stack '$stack'" >&2; exit 1; }
    [[ "|${BASH_REMATCH[1]}|" == *"|${kv#*=}|"* ]] \
      || { echo "error: --tools $kv: use $k=${BASH_REMATCH[1]}" >&2; exit 1; }
    new="" parts=()
    IFS=, read -ra parts <<<"$out"
    for p in ${parts[@]+"${parts[@]}"}; do [[ "${p%%=*}" == "$k" ]] && p=$kv; new+="${new:+,}$p"; done
    out=$new
  done
  echo "$out"
}

tool() { # <key> → its value in $tools
  if [[ ",$tools," =~ ,$1=([a-z0-9]+), ]]; then echo "${BASH_REMATCH[1]}"; fi
}

preset() { # <stack>; reads $tools
  local ci=.github/workflows/ci.yml impl=.github/workflows/agent-implement.yml
  local gate=.github/workflows/agent-merge-gate.yml dep=.github/dependabot.yml
  local rel=.github/workflows/release.yml md=CLAUDE.md
  local setup="" lint="" fmt="" fmtw="" cov="" covmd="" test="" smoke="" build="" allow="" eco="" rtype=""
  local md_none="none" pct
  pct="node -e \"console.log(require('./coverage/coverage-summary.json').total.lines.pct)\""
  case "$1" in
    node|pnpm|yarn)
      local pm x smoke_test=""
      case "$1" in
        node) pm=npm x=npx setup="npm ci" allow="Bash(npm ci),Bash(npm run:*),Bash(npm test:*)" ;;
        pnpm) pm=pnpm x="pnpm exec" setup="corepack enable && pnpm install --frozen-lockfile"
              allow="Bash(corepack enable),Bash(pnpm install:*),Bash(pnpm run:*),Bash(pnpm test:*),Bash(pnpm exec:*)" ;;
        yarn) pm=yarn x=yarn setup="corepack enable && yarn install --frozen-lockfile"
              allow="Bash(corepack enable),Bash(yarn install:*),Bash(yarn run:*),Bash(yarn test:*),Bash(yarn:*)" ;;
      esac
      npx_allow() { if [[ "$pm" == npm ]]; then allow+=",Bash(npx $1:*)"; fi; } # pnpm exec / yarn cover the rest
      case "$(tool lint)" in
        script) lint="$pm run lint" ;;
        eslint) lint="$x eslint ."; npx_allow eslint ;;
        biome) lint="$x biome lint ."; npx_allow biome ;;
      esac
      case "$(tool format)" in
        script) fmt="$pm run format:check" fmtw="$pm run format" ;;
        prettier) fmt="$x prettier --check ." fmtw="$x prettier --write ."; npx_allow prettier ;;
        biome) fmt="$x biome format ." fmtw="$x biome format --write ."; npx_allow biome ;;
      esac
      case "$(tool test)" in
        vitest)
          test="$x vitest run" smoke_test="$x vitest run smoke"; npx_allow vitest
          if [[ "$(tool coverage)" == yes ]]; then
            covmd="$x vitest run --coverage"
            cov="$covmd --coverage.reporter=json-summary >&2 && $pct"
          fi ;;
        jest)
          test="$x jest" smoke_test="$x jest smoke"; npx_allow jest
          if [[ "$(tool coverage)" == yes ]]; then
            covmd="$x jest --coverage"
            cov="$covmd --coverageReporters=json-summary >&2 && $pct"
          fi ;;
        script) test="$pm test" smoke_test="$pm test -- smoke" ;;
      esac
      if [[ "$(tool tsc)" == yes ]]; then npx_allow tsc; fi
      if [[ "$(tool build)" == yes ]]; then build="$pm run build"; fi
      if [[ "$(tool smoke)" != yes ]]; then smoke_test=""; fi # no smoke test: just the build
      smoke="$build${build:+${smoke_test:+ && }}$smoke_test"
      allow="\"$allow\""
      eco=npm rtype=node ;;
    python)
      if [[ -f "$target/pyproject.toml" || -f "$target/setup.py" ]]; then setup="pip install -e \".[dev]\""
      else setup="pip install -r requirements.txt"; fi
      allow="Bash(pip install:*),Bash(python -m:*),Bash(mypy:*)"
      case "$(tool lint)" in
        ruff) lint="ruff check ." ;;
        flake8) lint="flake8 ."; allow+=",Bash(flake8:*)" ;;
      esac
      case "$(tool format)" in
        ruff) fmt="ruff format --check ." fmtw="ruff format ." ;;
        black) fmt="black --check ." fmtw="black ."; allow+=",Bash(black:*)" ;;
      esac
      if [[ "$(tool lint)" == ruff || "$(tool format)" == ruff ]]; then allow+=",Bash(ruff:*)"; fi
      if [[ "$(tool test)" == pytest ]]; then
        test="pytest"; allow+=",Bash(pytest:*)"
        if [[ "$(tool smoke)" == yes ]]; then smoke="pytest -m smoke"; fi
        if [[ "$(tool coverage)" == yes ]]; then
          covmd="pytest --cov"
          cov="pytest --cov --cov-report=term >&2 && coverage report --format=total"; allow+=",Bash(coverage:*)"
        fi
      fi
      build="python -m build"
      allow="\"$allow\""
      eco=pip rtype=python ;;
    go)
      setup="go mod download"
      lint="go vet ./..."; fmt="test -z \"\$(gofmt -l .)\""; fmtw="gofmt -w ."
      cov="go test -coverprofile=c.out ./... >&2 && go tool cover -func=c.out | tail -1 | awk '{print \$3}'"
      covmd="go test -cover ./..."
      test="go test ./..."; build="go build ./..."
      allow="\"Bash(go build:*),Bash(go test:*),Bash(go vet:*),Bash(gofmt:*),Bash(go mod:*),Bash(go tool cover:*)\""
      smoke="go build ./... && go test -run Smoke ./..."
      eco=gomod rtype=go ;;
    none) md_none="TODO" ;; # every command empty: fill them in by hand
    *) echo "error: unknown --stack '$1' (auto|node|pnpm|yarn|python|go|none)" >&2; exit 1 ;;
  esac
  y() { printf '%s' "${1:-\"\"}"; }                       # empty → "" (the step is skipped)
  m() { if [[ -n "$1" ]]; then printf "\`%s\`" "$1"; else printf '%s' "$md_none"; fi; }
  # With a coverage command the tests run once, inside it; without one, test-command runs them.
  local ci_test="$test"; [[ -z "$cov" ]] || ci_test=""
  printf '%s\t%s\t%s\n' \
    "$ci" "setup-command:" "$(y "$setup")" \
    "$ci" "lint-command:" "$(y "$lint")" \
    "$ci" "format-check-command:" "$(y "$fmt")" \
    "$ci" "test-command:" "$(y "$ci_test")" \
    "$ci" "coverage-command:" "$(y "$cov")" \
    "$impl" "setup-command:" "$(y "$setup")" \
    "$impl" "extra-allowed-tools:" "$(y "$allow")" \
    "$gate" "setup-command:" "$(y "$setup")" \
    "$gate" "extra-allowed-tools:" "$(y "$allow")" \
    "$gate" "smoke-command:" "$(y "$smoke")" \
    "$md" "- Install:" "$(m "$setup")" \
    "$md" "- Lint:" "$(m "$lint")" \
    "$md" "- Test:" "$(m "$test")" \
    "$md" "- Coverage:" "$(m "$covmd")" \
    "$md" "- Build:" "$(m "$build")"
  if [[ -n "$fmt" ]]; then printf '%s\t%s\t%s\n' "$md" "- Format:" "\`$fmtw\` (check: \`$fmt\`)"
  else printf '%s\t%s\t%s\n' "$md" "- Format:" "$md_none"; fi
  if [[ -n "$eco" ]]; then
    printf '%s\t%s\t%s\n' "$dep" "- package-ecosystem: npm" "$eco" "$rel" "release-type:" "$rtype"
  fi
}

# The templates are github-flow (everything targets main). gitlab-flow integrates on
# develop instead, and adds branch-sync.yml.
branch_model_rules() {
  [[ "$branch_model" == gitlab-flow ]] || return 0
  printf '%s\t%s\t%s\n' \
    .github/workflows/ci.yml "branches:" "[develop, main]" \
    .github/workflows/ci.yml "baseline-branch:" "develop" \
    .github/workflows/agent-implement.yml "base-branch:" "develop" \
    .github/workflows/agent-merge-gate.yml "base-branch:" "develop" \
    .github/workflows/agent-review.yml "branches:" "[develop]" \
    .github/dependabot.yml "target-branch:" "develop"
}
model_skips() { # <relative path> — not installed for this branch model
  [[ "$branch_model" == github-flow && "$1" == .github/workflows/branch-sync.yml ]]
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
        if (rest ~ /^>-/ && val[i] != "\"\"") { print pad key " >-"; print pad "  " val[i]; skip = 1 }
        else { print pad key " " val[i]; if (rest ~ /^>-/) skip = 1 }
        next
      }
      print
    }' "$1" "$3" >"$3.tmp" && mv "$3.tmp" "$3"
}

if [[ "$detect" == stack ]]; then detect_stack; exit 0; fi
[[ "$stack" == auto ]] && stack=$(detect_stack)
tools=$(detect_tools "$stack")
tools=$(merge_tools "$tools" "$tools_override")
if [[ "$detect" == tools ]]; then echo "$tools"; exit 0; fi
rules=$(mktemp); trap 'rm -f "$rules"' EXIT
{ preset "$stack"; branch_model_rules; } >"$rules"
echo "Stack: $stack${tools:+ ($tools)}"
echo "Branch model: $branch_model"
# Say which CI steps stay empty, so nobody mistakes a skipped step for a passing one.
case "$stack" in
  node|pnpm|yarn|python)
    [[ "$(tool lint)" != none ]] || echo "  ! no linter detected: lint step skipped (lint-command is empty)"
    [[ "$(tool format)" != none ]] || echo "  ! no formatter detected: format check skipped (format-check-command is empty)"
    if [[ "$(tool test)" == none ]]; then echo "  ! no test runner detected: no tests or coverage in CI"
    elif [[ "$(tool coverage)" != yes ]]; then
      case "$(tool test)" in
        vitest) echo "  ! no coverage gate: add @vitest/coverage-v8, then set coverage-command in ci.yml (docs/ADD-TO-PROJECT.md §3.3)" ;;
        pytest) echo "  ! no coverage gate: add pytest-cov, then set coverage-command in ci.yml (docs/ADD-TO-PROJECT.md §3.3)" ;;
        *) echo "  ! no coverage gate: coverage-command is empty (tests run via test-command)" ;;
      esac
    fi
    if [[ "$(tool test)" != none && "$(tool smoke)" != yes ]]; then
      if [[ "$stack" == python ]]; then
        echo "  ! no @pytest.mark.smoke test: no post-merge smoke test (smoke-command is empty)"
      else
        echo "  ! no smoke test file (*smoke*.test.*): the post-merge smoke check only builds"
      fi
    fi ;;
  none) echo "  ! stack 'none': every command is empty; fill in the \"edit for your stack\" blocks" ;;
esac

# ── copy templates ──────────────────────────────────────────────────────────────
copied=() skipped=()
while IFS= read -r -d '' f; do
  rel="${f#"$src"/}"
  [[ "$rel" == ".github/labels.json" ]] && continue
  model_skips "$rel" && continue
  dst="$target/$rel"
  if [[ -e "$dst" && "$force" != true ]]; then skipped+=("$rel"); continue; fi
  mkdir -p "$(dirname "$dst")"
  # Pin every toolkit reference to --ref: reusable workflows (`uses: …@main`), the plugin
  # marketplace in callers (`…agent-toolkit.git#main`) and in .claude/settings.json.
  sed -e "s#\(kokoroou/agent-toolkit/\.github/workflows/[a-z-]*\.yml\)@main#\1@$ref#" \
      -e "s|\(kokoroou/agent-toolkit\.git\)#main|\1#$ref|" \
      -e "s|\(\"repo\": \"kokoroou/agent-toolkit\", \"ref\": \"\)main\"|\1$ref\"|" "$f" >"$dst"
  apply_preset "$rules" "$rel" "$dst"
  if [[ -x "$f" ]]; then chmod +x "$dst"; fi
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
    echo "tools=$tools"
    echo "branch-model=$branch_model"
  fi
  for f in ${copied[@]+"${copied[@]}"}; do [[ "$f" == CLAUDE.md ]] || echo "managed=$f"; done
} | awk '!/^managed=/ || !seen[$0]++' >"$lock.tmp" && mv "$lock.tmp" "$lock"

# ── labels + develop branch (gitlab-flow) ───────────────────────────────────────
gh_at_least() { # <major> <minor> — true if the installed gh is at least that version
  [[ "$(gh --version 2>/dev/null)" =~ ([0-9]+)\.([0-9]+) ]] || return 1
  (( BASH_REMATCH[1] > $1 || (BASH_REMATCH[1] == $1 && BASH_REMATCH[2] >= $2) ))
}
# labels.json keeps one {"name", "color", "description"} object per line (checked by
# scripts/lint.sh), so it is read with sed and needs no jq.
if [[ "$labels" == true ]] && command -v gh >/dev/null; then
  repo=$(cd "$target" && gh repo view --json nameWithOwner --jq .nameWithOwner)
  echo "Creating labels in $repo"
  label_force=false; gh_at_least 2 9 && label_force=true # 'gh label create --force'
  sed -n 's/.*"name": *"\([^"]*\)", *"color": *"\([^"]*\)", *"description": *"\([^"]*\)".*/\1\t\2\t\3/p' \
    "$src/.github/labels.json" | while IFS=$'\t' read -r name color desc; do
    if [[ "$label_force" == true ]]; then
      gh label create "$name" --repo "$repo" --force --color "$color" --description "$desc" >/dev/null
    else # older gh (e.g. distro packages): create, or update the existing label
      gh api "repos/$repo/labels" -f name="$name" -f color="$color" -f description="$desc" >/dev/null 2>&1 \
        || gh api -X PATCH "repos/$repo/labels/$name" -f color="$color" -f description="$desc" >/dev/null
    fi
  done
  default=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)
  if [[ "$branch_model" == gitlab-flow ]] && ! gh api "repos/$repo/branches/develop" >/dev/null 2>&1; then
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
