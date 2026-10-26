#!/usr/bin/env bash
# test-guard.sh - run skills/ship/guard.sh in scratch repositories with a bare
# remote, and check each case's exit code and what reached the remote.
set -euo pipefail

GUARD="$(cd "$(dirname "$0")/.." && pwd)/skills/ship/guard.sh"
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# repo: a fresh clone at $tmp/case.N/work of a bare remote whose main has one commit.
repo() {
  dir=$(mktemp -d "$tmp/case.XXXX")
  git init -q --bare -b main "$dir/remote.git"
  git clone -q "$dir/remote.git" "$dir/work" 2>/dev/null
  cd "$dir/work"
  git config user.email t@example.com
  git config user.name t
  git commit -q --allow-empty -m base
  git push -q origin main
}

run() { got=0; bash "$GUARD" "$@" > "$dir/out" 2>&1 || got=$?; }

expect() {
  if [ "$got" = "$2" ]; then echo "ok: $1"; else
    echo "FAIL: $1 (exit $got, want $2)"; sed 's/^/  | /' "$dir/out"; failures=$((failures + 1)); fi
}

remote_has() { git -C "$dir/remote.git" rev-parse -q --verify "refs/heads/$1" >/dev/null; }

repo
git switch -q -c feat/x
git commit -q --allow-empty -m work
run feat/x main
expect "pushes the checked-out shipping branch" 0
remote_has feat/x || { echo "FAIL: feat/x did not reach the remote"; failures=$((failures + 1)); }

repo
git switch -q -c feat/x
git switch -q -c other
run feat/x main
expect "refuses when another branch is checked out" 3
! remote_has other || { echo "FAIL: other reached the remote"; failures=$((failures + 1)); }

repo
run main main
expect "refuses to push the base" 3

repo
git switch -q -c feat/x
run 'feat x' main
expect "refuses a name that is not a valid branch" 3
grep -q 'not a valid branch name' "$dir/out" || { echo "FAIL: refused for another reason"; failures=$((failures + 1)); }

repo
git switch -q --detach
run feat/x main
expect "refuses a detached HEAD" 3

repo
git switch -q -c feat/x
git commit -q --allow-empty -m one
git push -q -u origin feat/x
old=$(git rev-parse HEAD)
git commit -q --amend --allow-empty -m one-amended
run feat/x main "$old"
expect "force-pushes when the remote is still at the lease" 0
[ "$(git -C "$dir/remote.git" rev-parse feat/x)" = "$(git rev-parse HEAD)" ] ||
  { echo "FAIL: the lease push did not move the remote"; failures=$((failures + 1)); }

repo
git switch -q -c feat/x
git commit -q --allow-empty -m one
git push -q -u origin feat/x
stale=$(git rev-parse HEAD)
git commit -q --allow-empty -m two
git push -q
git commit -q --amend --allow-empty -m two-amended
run feat/x main "$stale"
[ "$got" != 0 ] && [ "$got" != 3 ] && echo "ok: a stale lease fails in git push" ||
  { echo "FAIL: a stale lease got exit $got"; failures=$((failures + 1)); }

repo
run feat/x main not-a-sha
expect "rejects a lease that is not a full SHA" 2

if [ "$failures" != 0 ]; then echo "$failures case(s) failed"; exit 1; fi
echo "all guard.sh cases passed"
