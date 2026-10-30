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

each() {
  got=0
  if [ "${1:-}" = "--print" ]; then
    shift
    set -- --print "$dir/repo" "$@"
  else
    set -- "$dir/repo" "$@"
  fi
  TMPDIR="$dir/tmp" bash "$EACH" "$@" > "$dir/out" 2>&1 || got=$?
}
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

case_dir
commit "config verify is only a comment" 'mkdir -p .ship && printf "verify:   # asked\n" > .ship/config.md'
each base..HEAD false
expect "a comment-only config verify runs the passed command" 1

case_dir
commit "config verify is none" 'mkdir -p .ship && printf "verify: none   # asked\n" > .ship/config.md'
each base..HEAD true
expect "a corrupt verify: none runs the passed command" 0

case_dir
commit "config file is a symlink" 'mkdir -p .ship && printf "verify: false\n" > .ship/real.md && ln -s real.md .ship/config.md'
each base..HEAD true
expect "a symlinked config file runs the passed command" 0

case_dir
commit "ship directory is a symlink" 'mkdir -p shipdir && printf "verify: false\n" > shipdir/config.md && ln -s shipdir .ship'
each base..HEAD true
expect "a symlinked ship directory runs the passed command" 0

case_dir
commit "no config" 'echo a > a'
commit "config sets a gate" 'mkdir -p .ship && printf "verify: bash gate.sh   # asked\n" > .ship/config.md'
commit "symlinked config" 'printf "verify: false\n" > .ship/real.md && rm .ship/config.md && ln -s real.md .ship/config.md'
shorts=$(git -C "$dir/repo" log --reverse --format='%h' base..HEAD)
first=$(printf '%s\n' "$shorts" | sed -n '1p')
second=$(printf '%s\n' "$shorts" | sed -n '2p')
third=$(printf '%s\n' "$shorts" | sed -n '3p')
each --print base..HEAD passed
expect "--print exits 0" 0
expect_line "no config prints the passed command" "^${first}"$'\tpassed$'
expect_line "a verify line prints without its comment" "^${second}"$'\tbash gate.sh$'
expect_line "a symlinked config prints the passed command" "^${third}"$'\tpassed$'
check "print writes the three commands oldest first" '[ "$(cat "$dir/out")" = "$(printf "%s\t%s\n" "$first" passed "$second" "bash gate.sh" "$third" passed)" ]'
check "print writes three lines" '[ "$(wc -l < "$dir/out")" -eq 3 ]'
check "no worktree is left behind" '[ "$(git -C "$dir/repo" worktree list | wc -l)" -eq 1 ]'
check "the temp directory is empty afterwards" '[ -z "$(ls -A "$dir/tmp")" ]'

case_dir
commit "config would touch a file" 'mkdir -p .ship && printf "verify: touch %s\n" "$dir/ran" > .ship/config.md'
each --print base..HEAD true
expect "--print runs nothing" 0
expect_line "print shows the touch command it did not run" "^[0-9a-f]+"$'\t'"touch ${dir}/ran$"
check "print does not create the touched file" '[ ! -e "$dir/ran" ]'

case_dir
commit "config blob will be removed" 'mkdir -p .ship && printf "verify: false\n" > .ship/config.md'
blob=$(git -C "$dir/repo" rev-parse 'HEAD:.ship/config.md')
rm -f "$dir/repo/.git/objects/${blob:0:2}/${blob:2}"
each --print base..HEAD true
check "a missing config blob makes --print exit nonzero" '[ "$got" -ne 0 ]'
check "a missing config blob prints no line for that commit" '! grep -q "^$(git -C "$dir/repo" log -1 --format=%h)" "$dir/out"'

case_dir
commit "one commit" 'echo a > a'
each base..HEAD --print
expect "--print as the third argument exits 2" 2

case_dir
commit "one commit" 'echo a > a'
each --print base..HEAD "$(printf 'true\nfalse')"
expect "a verify command containing a newline exits 2" 2

case_dir
each --print base..HEAD
expect "--print without a verify command exits 2" 2

if [ "$failures" -gt 0 ]; then echo "$failures failed"; exit 1; fi
echo "all passed"
