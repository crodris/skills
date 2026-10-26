#!/usr/bin/env bash
# test-settle-branch.sh - run skills/ship/settle-branch.sh in scratch
# repositories with a bare remote, and check where the work landed and what
# happened to the local base.
# shellcheck disable=SC2016 # check takes its condition in single quotes and evals it.
set -euo pipefail

SETTLE="$(cd "$(dirname "$0")/.." && pwd)/skills/ship/settle-branch.sh"
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

expect() {
  if [ "$got" = "$2" ]; then echo "ok: $1"; else
    echo "FAIL: $1 (exit $got, want $2)"; sed 's/^/  | /' "$dir/out"; failures=$((failures + 1)); fi
}
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; failures=$((failures + 1)); fi; }

# repo: a clone at $dir/work, on main, of a bare remote whose main has a.txt and gone.txt.
repo() {
  dir=$(mktemp -d "$tmp/case.XXXX")
  git init -q --bare -b main "$dir/remote.git"
  git clone -q "$dir/remote.git" "$dir/work" 2>/dev/null
  w=$dir/work
  git -C "$w" config user.email t@example.com
  git -C "$w" config user.name t
  echo one > "$w/a.txt"
  echo bye > "$w/gone.txt"
  git -C "$w" add a.txt gone.txt
  git -C "$w" commit -q -m base
  git -C "$w" push -q origin main
}
settle() { got=0; (cd "$w" && bash "$SETTLE" "$@") > "$dir/out" 2>&1 || got=$?; }
our_stashes() { git -C "$w" stash list | grep -c 'settle-branch' || true; }

repo
echo two > "$w/a.txt"
mkdir -p "$w/new"
echo fresh > "$w/new/b.txt"
git -C "$w" rm -q gone.txt
settle main feat/x
expect "uncommitted work moves to a new branch in place" 0
check "the checkout is on the new branch" '[ "$(git -C "$w" branch --show-current)" = feat/x ]'
check "a modified file arrived" '[ "$(cat "$w/a.txt")" = two ]'
check "an untracked file arrived" '[ "$(cat "$w/new/b.txt")" = fresh ]'
check "a deleted file stays deleted" '[ ! -e "$w/gone.txt" ]'
check "the stash is dropped" '[ "$(our_stashes)" = 0 ]'
check "the local base still matches origin" '[ "$(git -C "$w" rev-parse main)" = "$(git -C "$w" rev-parse origin/main)" ]'

repo
echo local > "$w/c.txt"
git -C "$w" add c.txt
git -C "$w" commit -q -m local
settle main feat/x
expect "a local commit on the base moves to the new branch" 0
check "the commit is on the new branch" '[ "$(git -C "$w" log -1 --format=%s feat/x)" = local ]'
check "the local base is reset to origin" '[ "$(git -C "$w" rev-parse main)" = "$(git -C "$w" rev-parse origin/main)" ]'

repo
echo local > "$w/c.txt"
git -C "$w" add c.txt
git -C "$w" commit -q -m local
echo two > "$w/a.txt"
settle main feat/x --worktree "$dir/trees/feat-x"
expect "work and commits move to a new worktree" 0
check "the worktree has the commit and the change" '[ -e "$dir/trees/feat-x/c.txt" ] && [ "$(cat "$dir/trees/feat-x/a.txt")" = two ]'
check "the main checkout is back on a clean origin base" '[ -z "$(git -C "$w" status --porcelain)" ] && [ "$(git -C "$w" rev-parse main)" = "$(git -C "$w" rev-parse origin/main)" ]'
check "the output names the worktree" 'grep -q "^SETTLED feat/x $(cd "$dir/trees/feat-x" && pwd -P)$" "$dir/out"'

repo
echo upstream > "$dir/up.txt"
git -C "$w" switch -q -c side
cp "$dir/up.txt" "$w/clash.txt"
git -C "$w" add clash.txt
git -C "$w" commit -q -m clash
git -C "$w" push -q origin side:main
git -C "$w" switch -q main
echo mine > "$w/clash.txt"
settle main feat/x
expect "work that cannot apply on the new branch stops" 3
check "the work is still in the stash" '[ "$(our_stashes)" = 1 ]'

repo
git -C "$w" switch -q -c other
echo two > "$w/a.txt"
settle main feat/x
expect "a checkout that is not on the base is refused" 3
check "a refused run leaves the work in place" '[ "$(cat "$w/a.txt")" = two ] && [ "$(our_stashes)" = 0 ]'

repo
settle main feat/x
expect "a base with nothing to move is refused" 3

repo
echo two > "$w/a.txt"
settle main main
expect "a new branch named like the base is refused" 3

repo
echo two > "$w/a.txt"
mkdir -p "$dir/occupied"
echo keep > "$dir/occupied/keep.txt"
settle main feat/x --worktree "$dir/occupied"
expect "a worktree path that already exists is refused" 3
check "the refusal names the stash" 'grep -qF "$(git -C "$w" rev-parse "stash@{0}")" "$dir/out"'
check "the stash is still present" '[ "$(our_stashes)" = 1 ]'

repo
echo two > "$w/a.txt"
mkdir -p "$w/sub"
got=0
(cd "$w/sub" && bash "$SETTLE" main feat/x) > "$dir/out" 2>&1 || got=$?
expect "a run from a subdirectory settles" 0
check "the changed file at the root arrived" '[ "$(cat "$w/a.txt")" = two ]'
check "the SETTLED line names the root" 'grep -q "^SETTLED feat/x $(cd "$w" && pwd -P)$" "$dir/out"'

repo
echo two > "$w/a.txt"
git -C "$w" config remote.origin.fetch '+refs/heads/other:refs/remotes/origin/other'
git -C "$w" update-ref -d refs/remotes/origin/main
settle main feat/x
expect "a fetch refspec that omits the base still settles" 0
check "the checkout is on the new branch" '[ "$(git -C "$w" branch --show-current)" = feat/x ]'

if [ "$failures" != 0 ]; then echo "$failures case(s) failed"; exit 1; fi
echo "all settle-branch.sh cases passed"
