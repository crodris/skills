#!/usr/bin/env bash
# settle-branch.sh - move uncommitted work and local commits off the base
# branch onto a new branch cut from origin/<base>, in place or in a new
# worktree, and reset the local base only after every changed file arrived.
# Run it from the checkout that is on <base>.
# A relative --worktree <path> resolves against the repository root, since the
# script changes to the root.
#
# usage: settle-branch.sh <base> <new-branch> [--worktree <path>]
#
# Prints "SETTLED <branch> <checkout path>" on success.
# Exit 0 settled, 2 usage, 3 refused or stopped (prints why, and leaves the
# stash in place when it holds the only copy of the work).
set -euo pipefail

usage() { echo "usage: settle-branch.sh <base> <new-branch> [--worktree <path>]" >&2; exit 2; }
refuse() { echo "refuse: $1" >&2; exit 3; }

[ $# = 2 ] || { [ $# = 4 ] && [ "$3" = --worktree ]; } || usage
base=$1 branch=$2 worktree=${4:-}
git check-ref-format --branch "$base" >/dev/null 2>&1 || refuse "'$base' is not a valid branch name"
git check-ref-format --branch "$branch" >/dev/null 2>&1 || refuse "'$branch' is not a valid branch name"
[ "$(git branch --show-current)" = "$base" ] || refuse "this checkout is not on '$base'"
! git show-ref --verify --quiet "refs/heads/$branch" || refuse "branch '$branch' already exists"

cd "$(git rev-parse --show-toplevel)"
git fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base"
commits=$(git rev-list --reverse "origin/$base..$base")
changed=$(git status --porcelain --untracked-files=all)
[ -n "$commits$changed" ] || refuse "nothing on '$base' to move"

# Each changed path with a hash of its content, or "deleted", to compare after the move.
fingerprint() {
  local dir=$1 path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -e "$dir/$path" ]; then echo "$path $(git hash-object --no-filters -- "$dir/$path")"; else echo "$path deleted"; fi
  done <<<"$paths"
}
paths=$(git status --porcelain --untracked-files=all -z | tr '\0' '\n' | sed -n 's/^.. //p')
before=$(fingerprint .)

stash=''
if [ -n "$changed" ]; then
  tag="settle-branch $branch $$"
  git stash push -q --include-untracked -m "$tag"
  stash=$(git stash list --format='%H %gs' | awk -v t="$tag" 'index($0, t) { print $1; exit }')
  [ -n "$stash" ] || refuse "could not find the stash it just made"
fi

if [ -n "$worktree" ]; then
  mkdir -p "$(dirname "$worktree")"
  if ! git worktree add -q -b "$branch" "$worktree" "origin/$base"; then
    [ -z "$stash" ] || refuse "creating $worktree failed; the work is still in stash $stash"
    refuse "creating $worktree failed"
  fi
  target=$(cd "$worktree" && pwd -P)
else
  if ! git switch -q -c "$branch" "origin/$base"; then
    [ -z "$stash" ] || refuse "creating $branch failed; the work is still in stash $stash"
    refuse "creating $branch failed"
  fi
  target=$(pwd -P)
fi

for sha in $commits; do
  if ! git -C "$target" cherry-pick "$sha" >/dev/null; then
    [ -z "$stash" ] || refuse "cherry-pick of $sha failed in $target; the local '$base' is untouched; the work is still in stash $stash"
    refuse "cherry-pick of $sha failed in $target; the local '$base' is untouched"
  fi
done
if [ -n "$stash" ]; then
  git -C "$target" stash apply -q "$stash" ||
    refuse "applying the work in $target failed; it is still in stash $stash and on '$base' nothing was reset"
  [ "$(fingerprint "$target")" = "$before" ] ||
    refuse "not every changed file arrived in $target; the work is still in stash $stash"
  ref=$(git stash list --format='%gd %H' | awk -v s="$stash" '$2 == s { print $1; exit }')
  [ -z "$ref" ] || git stash drop -q "$ref"
fi

if [ -n "$commits" ]; then
  if [ -n "$worktree" ]; then git reset -q --keep "origin/$base"; else git branch -q -f "$base" "origin/$base"; fi
fi
echo "SETTLED $branch $target"
