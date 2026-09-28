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
for stack in node pnpm yarn python go; do
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

echo "== labels.json readable without jq (one object per line, as bootstrap.sh parses it)"
parsed=$(sed -n 's/.*"name": *"\([^"]*\)", *"color": *"\([^"]*\)", *"description": *"\([^"]*\)".*/\1/p' templates/.github/labels.json | wc -l)
[[ "$parsed" -eq "$(jq length templates/.github/labels.json)" ]] \
  || { echo "templates/.github/labels.json: keep one {\"name\", \"color\", \"description\"} object per line"; exit 1; }

echo "== Shell scripts"
if command -v shellcheck >/dev/null; then shellcheck scripts/*.sh; else echo "shellcheck not installed; skipped"; fi
bash -n scripts/install.sh

echo "OK"
