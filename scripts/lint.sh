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

echo "== Caller templates against local reusable workflows"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.github/workflows"
cp .github/workflows/*.yml "$tmp/.github/workflows/"
for f in templates/.github/workflows/*.yml; do
  sed 's#kokoroou/agent-toolkit/\(\.github/workflows/[a-z-]*\.yml\)@[A-Za-z0-9._-]*#./\1#' "$f" \
    >"$tmp/.github/workflows/caller-$(basename "$f")"
done
(cd "$tmp" && git init -q . && actionlint)

echo "== Shell scripts"
if command -v shellcheck >/dev/null; then shellcheck scripts/*.sh; else echo "shellcheck not installed; skipped"; fi

echo "OK"
