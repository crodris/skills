#!/usr/bin/env bash
# test-verify-each.sh - run skills/prove/verify-each.sh against scratch
# repositories whose commits pass or fail a fake verify command.
# shellcheck disable=SC2016 # check takes its condition in single quotes and evals it.
set -euo pipefail

EACH="$(cd "$(dirname "$0")/.." && pwd)/skills/prove/verify-each.sh"
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

case_dir() {
  dir=$(mktemp -d "$tmp/case.XXXX")
  mkdir "$dir/tmp"
  git init -q "$dir/repo"
  git -C "$dir/repo" config user.email test@example.com
  git -C "$dir/repo" config user.name test
  git -C "$dir/repo" commit -q --allow-empty -m base
  git -C "$dir/repo" tag base
}
commit() { (cd "$dir/repo" && eval "$2" && git add -A && git commit -q --allow-empty -m "$1"); }
expect() {
  if [ "$got" = "$2" ]; then echo "ok: $1"; else
    echo "FAIL: $1 (exit $got, want $2)"; sed 's/^/  | /' "$dir/out"; failures=$((failures + 1)); fi
}
expect_line() {
  if grep -qE -- "$2" "$dir/out"; then echo "ok: $1"; else
    echo "FAIL: $1 (output lacks /$2/)"; sed 's/^/  | /' "$dir/out"; failures=$((failures + 1)); fi
}
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; failures=$((failures + 1)); fi; }

each() { got=0; TMPDIR="$dir/tmp" bash "$EACH" "$dir/repo" "$@" > "$dir/out" 2>&1 || got=$?; }
VERIFY='test ! -e broken'

case_dir
commit "first passes" 'echo a > a'
commit "second fails" 'echo x > broken'
commit "third passes" 'rm broken'
each base..HEAD "$VERIFY"
expect "a failing middle commit exits 1" 1
expect_line "the first commit passes" '^[0-9a-f]+ first passes: exit 0$'
expect_line "the middle commit is named with its exit" '^[0-9a-f]+ second fails: exit 1$'
expect_line "the third commit still runs and passes" '^[0-9a-f]+ third passes: exit 0$'
check "no worktree is left behind" '[ "$(git -C "$dir/repo" worktree list | wc -l)" -eq 1 ]'
check "the temp directory is empty afterwards" '[ -z "$(ls -A "$dir/tmp")" ]'

case_dir
commit "one" 'echo a > a'
commit "two" 'echo b > b'
each base..HEAD "$VERIFY"
expect "every commit passing exits 0" 0
check "no worktree is left behind when all pass" '[ "$(git -C "$dir/repo" worktree list | wc -l)" -eq 1 ]'

case_dir
each HEAD..HEAD "$VERIFY"
expect "an empty range exits 2" 2

case_dir
each base..HEAD
expect "a missing verify command exits 2" 2

case_dir
commit "config sets true" 'mkdir -p .ship && printf "verify: true   # asked\n" > .ship/config.md'
commit "adds a gate" 'echo "exit 0" > gate.sh && printf "verify: bash gate.sh   # asked\n" > .ship/config.md'
each base..HEAD 'bash gate.sh'
expect "each commit runs its own config's verify, so a later gate skips earlier commits" 0

case_dir
commit "config gate fails" 'mkdir -p .ship && printf "verify: false   # asked\n" > .ship/config.md'
each base..HEAD true
expect "a commit's own config verify wins over the passed command" 1

if [ "$failures" -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
