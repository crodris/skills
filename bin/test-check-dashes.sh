#!/usr/bin/env bash
# test-check-dashes.sh - run bin/check-dashes.sh in scratch repositories and check
# that it passes a clean tree and fails on a dash in a tracked or untracked file.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-dashes.sh"
DASH=$(printf '\xe2\x80\x94')
failures=0

scratch() {
  dir=$(mktemp -d)
  git -C "$dir" init -q
  mkdir -p "$dir/bin" "$dir/skills/demo"
  cp "$SCRIPT" "$dir/bin/check-dashes.sh"
  printf 'A plain line - with a hyphen.\n' > "$dir/skills/demo/SKILL.md"
  git -C "$dir" add bin skills
  echo "$dir"
}

expect() {
  name=$1 want=$2 dir=$3
  if "$dir/bin/check-dashes.sh" >/dev/null 2>&1; then got=0; else got=1; fi
  if [ "$got" = "$want" ]; then echo "ok: $name"; else echo "FAIL: $name (exit $got, want $want)"; failures=$((failures + 1)); fi
  rm -rf "$dir"
}

dir=$(scratch)
expect "clean tree passes" 0 "$dir"

dir=$(scratch)
printf 'Tracked %s dash.\n' "$DASH" >> "$dir/skills/demo/SKILL.md"
expect "tracked file with a dash fails" 1 "$dir"

dir=$(scratch)
printf 'Untracked %s dash.\n' "$DASH" > "$dir/skills/demo/new.md"
expect "untracked file with a dash fails" 1 "$dir"

dir=$(scratch)
mkdir -p "$dir/docs/plans"
printf 'Dated %s record.\n' "$DASH" > "$dir/docs/plans/old.md"
git -C "$dir" add docs
expect "docs/plans is not checked" 0 "$dir"

[ "$failures" = 0 ]
