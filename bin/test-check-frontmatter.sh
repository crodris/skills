#!/usr/bin/env bash
# test-check-frontmatter.sh - run bin/check-frontmatter.sh in scratch repositories
# and check that it passes clean frontmatter and fails on a parse error or a
# description cut short by a comment.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-frontmatter.sh"
failures=0

scratch() {
  dir=$(mktemp -d)
  git -C "$dir" init -q
  mkdir -p "$dir/bin" "$dir/skills/demo"
  cp "$SCRIPT" "$dir/bin/check-frontmatter.sh"
  printf -- '---\nname: demo\ndescription: %s\n---\n\n# Demo\n' "$1" > "$dir/skills/demo/SKILL.md"
  git -C "$dir" add bin skills
  echo "$dir"
}

expect() {
  name=$1 want=$2 dir=$3
  if "$dir/bin/check-frontmatter.sh" >/dev/null 2>&1; then got=0; else got=1; fi
  if [ "$got" = "$want" ]; then echo "ok: $name"; else echo "FAIL: $name (exit $got, want $want)"; failures=$((failures + 1)); fi
  rm -rf "$dir"
}

dir=$(scratch 'Use when the user says "demo it".')
expect "clean frontmatter passes" 0 "$dir"

dir=$(scratch 'Merge needs `merge: yes` in the config.')
expect "an unquoted colon fails" 1 "$dir"

dir=$(scratch 'Use when the user says "review #107" or "review this".')
expect "a description cut short by a comment fails" 1 "$dir"

dir=$(scratch '"Use when the user says \"review #107\"."')
expect "a quoted description with a hash passes" 0 "$dir"

dir=$(scratch 'Use when the user says "demo it".')
mkdir -p "$dir/skills/bare" && printf -- '---\nname: bare\n---\n' > "$dir/skills/bare/SKILL.md"
expect "an untracked skill with no description fails" 1 "$dir"

[ "$failures" = 0 ]
