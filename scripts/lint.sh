#!/usr/bin/env bash
# Validate the toolkit: plugin manifests, workflows (incl. callers against the local
# reusable workflows' inputs/secrets), JSON and shell scripts.
# Needs: claude, actionlint (+ shellcheck for embedded scripts), jq.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== JSON"
for f in $(git ls-files '*.json'); do jq empty "$f" || { echo "invalid JSON: $f"; exit 1; }; done

echo "== Claude plugin + marketplace"
claude plugin validate --strict plugins/pipeline
claude plugin validate --strict .

echo "== Workflows (actionlint)"
actionlint .github/workflows/*.yml

echo "== Caller templates (every bootstrap --stack) against local reusable workflows"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for stack in node pnpm yarn python go none; do
  d="$tmp/$stack"; mkdir -p "$d" && git -C "$d" init -q
  scripts/bootstrap.sh "$d" --stack "$stack" --no-labels >/dev/null
  w="$d/.github/workflows"
  for f in "$w"/*.yml; do
    sed 's#kokoroou/agent-toolkit/\(\.github/workflows/[a-z-]*\.yml\)@[A-Za-z0-9._-]*#./\1#' "$f" \
      >"$w/caller-$(basename "$f")" && rm "$f"
  done
  cp .github/workflows/*.yml "$w/"
  echo "-- $stack"; (cd "$d" && actionlint)
done

echo "== bootstrap: commands follow the tools the project uses"
t="$tmp/tools"
fresh() { rm -rf "$t" && mkdir -p "$t" && git -C "$t" init -q; }
expect() { # <file> <line>...
  local f="$t/$1" l; shift
  for l in "$@"; do grep -qxF -- "$l" "$f" || { cat "$f"; echo "$f: expected line: $l"; exit 1; }; done
}
# npm + Vitest behind a lint script, no formatter, no coverage provider: nothing Jest/Prettier.
fresh
printf '{\n  "scripts": {\n    "lint": "eslint .",\n    "test": "vitest run"\n  },\n  "devDependencies": {\n    "vitest": "^5.0.0"\n  }\n}\n' >"$t/package.json"
scripts/bootstrap.sh "$t" --no-labels >/dev/null
expect .github/workflows/ci.yml '      lint-command: npm run lint' '      format-check-command: ""' \
  '      test-command: npx vitest run' '      coverage-command: ""'
expect .github/agent-toolkit.lock 'tools=lint=script,format=none,test=vitest,coverage=no,build=no,tsc=no,smoke=no'
expect .github/workflows/agent-merge-gate.yml '      smoke-command: ""' # no smoke test, no build
if grep -rqiE 'jest|prettier' "$t/.github/workflows" "$t/CLAUDE.md"; then
  grep -rniE 'jest|prettier' "$t/.github/workflows" "$t/CLAUDE.md"; echo "Vitest project got Jest/Prettier commands"; exit 1
fi
w="$t/.github/workflows"
for f in "$w"/*.yml; do
  sed 's#kokoroou/agent-toolkit/\(\.github/workflows/[a-z-]*\.yml\)@[A-Za-z0-9._-]*#./\1#' "$f" >"$w/caller-$(basename "$f")" && rm "$f"
done
cp .github/workflows/*.yml "$w/" && (cd "$t" && actionlint)
# pnpm + Jest + Prettier + ESLint, with a coverage provider, a build script and a smoke test.
fresh && touch "$t/pnpm-lock.yaml" && mkdir "$t/test" && touch "$t/test/smoke.test.js"
printf '{\n  "scripts": { "build": "tsc" },\n  "devDependencies": {\n    "eslint": "^9.0.0",\n    "jest": "^30.0.0",\n    "prettier": "^3.0.0"\n  }\n}\n' >"$t/package.json"
scripts/bootstrap.sh "$t" --no-labels >/dev/null
expect .github/workflows/ci.yml '      lint-command: pnpm exec eslint .' '      format-check-command: pnpm exec prettier --check .' \
  '      test-command: ""' '      coverage-command: >-'
expect .github/workflows/agent-merge-gate.yml '      smoke-command: pnpm run build && pnpm exec jest smoke'
# Python with flake8 + black + pytest-cov instead of ruff.
fresh && printf '[project]\nname = "x"\n[project.optional-dependencies]\ndev = ["black", "flake8", "pytest", "pytest-cov"]\n' >"$t/pyproject.toml"
scripts/bootstrap.sh "$t" --no-labels >/dev/null
expect .github/workflows/ci.yml '      lint-command: flake8 .' '      format-check-command: black --check .' '      test-command: ""'
expect .github/workflows/agent-merge-gate.yml '      smoke-command: ""' # no @pytest.mark.smoke test
if grep -q ruff "$t/.github/workflows/ci.yml"; then echo "flake8/black project got ruff commands"; exit 1; fi
# --tools overrides a key; unknown keys and values are refused.
[[ "$(scripts/bootstrap.sh "$t" --detect-tools --tools lint=none)" == lint=none,format=black,test=pytest,coverage=yes,smoke=no ]]
if scripts/bootstrap.sh "$t" --detect-tools --tools test=jest 2>/dev/null; then echo "--tools accepted jest for python"; exit 1; fi
# npm with a build script but no smoke test: the post-merge check only builds.
fresh && printf '{\n  "scripts": {\n    "build": "vite build",\n    "test": "vitest run"\n  },\n  "devDependencies": {\n    "vitest": "^5.0.0"\n  }\n}\n' >"$t/package.json"
scripts/bootstrap.sh "$t" --no-labels >/dev/null
expect .github/workflows/agent-merge-gate.yml '      smoke-command: npm run build'

echo "== upgrade.sh: 3-way merge between two toolkit commits"
gitc() { git -C "$1" -c user.name=lint -c user.email=lint@localhost "${@:2}"; }
edit() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }
tk="$tmp/upgrade-toolkit" p="$tmp/upgrade-project"
mkdir -p "$tk" "$p" && git -C "$tk" init -q && git -C "$p" init -q
cp -R scripts templates version.txt CHANGELOG.md "$tk/"
gitc "$tk" add -A && gitc "$tk" commit -qm A
"$tk/scripts/bootstrap.sh" "$p" --ref v9 --stack python --no-labels >/dev/null
grep -qx 'stack=python' "$p/.github/agent-toolkit.lock"
grep -qx 'tools=lint=ruff,format=ruff,test=pytest,coverage=yes,smoke=no' "$p/.github/agent-toolkit.lock"
if grep -qx 'managed=CLAUDE.md' "$p/.github/agent-toolkit.lock"; then echo "CLAUDE.md must stay project-owned"; exit 1; fi
edit 's/max-turns: 80/max-turns: 50/' "$p/.github/workflows/agent-implement.yml"   # local only
edit 's/coverage-tolerance: "0"/coverage-tolerance: "1"/' "$p/.github/workflows/ci.yml" # both → conflict
gitc "$p" add -A && gitc "$p" commit -qm install
edit 's/description: Issue number/description: Issue to build/' "$tk/templates/.github/workflows/agent-implement.yml"
edit 's/coverage-tolerance: "0"/coverage-tolerance: "2"/' "$tk/templates/.github/workflows/ci.yml"
echo "# new" >"$tk/templates/.github/new-file.md"
gitc "$tk" add -A && gitc "$tk" commit -qm B && git -C "$tk" tag v9.9.9
if bash scripts/upgrade.sh "$p" --toolkit-dir "$tk" --to v9.9.9 --no-labels >"$tmp/upgrade.log"; then
  cat "$tmp/upgrade.log"; echo "upgrade.sh: expected exit 1 on a conflict"; exit 1
fi
w="$p/.github/workflows"
if ! { grep -q 'max-turns: 50' "$w/agent-implement.yml" && grep -q 'Issue to build' "$w/agent-implement.yml" \
  && grep -q 'implement.yml@v9.9.9' "$w/agent-implement.yml" && grep -q '^<<<<<<< yours' "$w/ci.yml" \
  && [[ -f "$p/.github/new-file.md" ]] && grep -qx 'ref=v9.9.9' "$p/.github/agent-toolkit.lock" \
  && grep -qx 'managed=.github/new-file.md' "$p/.github/agent-toolkit.lock" \
  && grep -qx 'tools=lint=ruff,format=ruff,test=pytest,coverage=yes,smoke=no' "$p/.github/agent-toolkit.lock"; }; then
  cat "$tmp/upgrade.log"; git -C "$p" diff; echo "upgrade.sh: unexpected result"; exit 1
fi

echo "== labels.json readable without jq (one object per line, as bootstrap.sh parses it)"
parsed=$(sed -n 's/.*"name": *"\([^"]*\)", *"color": *"\([^"]*\)", *"description": *"\([^"]*\)".*/\1/p' templates/.github/labels.json | wc -l)
[[ "$parsed" -eq "$(jq length templates/.github/labels.json)" ]] \
  || { echo "templates/.github/labels.json: keep one {\"name\", \"color\", \"description\"} object per line"; exit 1; }

echo "== Shell scripts"
if command -v shellcheck >/dev/null; then shellcheck scripts/*.sh templates/scripts/*.sh; else echo "shellcheck not installed; skipped"; fi
for f in scripts/*.sh templates/scripts/*.sh; do bash -n "$f"; done
for f in templates/scripts/*.sh; do [[ -x "$f" ]] || { echo "$f must be executable (git update-index --chmod=+x)"; exit 1; }; done

echo "== agent-session.sh: encrypt/decrypt round trip, generated settings"
if command -v age >/dev/null; then
  a="$tmp/agent-session" && mkdir -p "$a/scripts" && git -C "$a" init -q && cp templates/scripts/agent-session.sh "$a/scripts/"
  (
    # One check per line: set -e (inherited) stops at the first failing one.
    cd "$a"
    export HOME="$a/home" XDG_CONFIG_HOME="" XDG_STATE_HOME=""
    unset AGE_SECRET_KEY
    scripts/agent-session.sh init >/dev/null
    echo 'K=v#1' >.env
    scripts/agent-session.sh encrypt 2>/dev/null
    git check-ignore -q .env
    if git check-ignore -q .env.age; then exit 1; fi
    rm .env
    scripts/agent-session.sh decrypt 2>/dev/null
    [[ "$(cat .env)" == 'K=v#1' ]]
    scripts/agent-session.sh settings \
      | jq -e '.sandbox.enabled and .sandbox.network.strictAllowlist and (.permissions.deny | index("Bash(rclone:*)"))' >/dev/null
    mv home/.config/agent-session home/key-elsewhere
    rm .env
    scripts/agent-session.sh decrypt --if-key
    [[ ! -e .env ]]
  )
else
  echo "age not installed; skipped"
fi

echo "OK"
