#!/usr/bin/env bash
# verify-each.sh - run verify on every commit in a range, oldest first, each in
# its own detached worktree under a private directory in the system temp
# directory, so a caller can stop a rebase merge from putting a commit on the
# base that fails on its own tree.
# Each commit runs the `verify:` line of its own .ship/config.md, read from
# git, with any trailing comment dropped, so a gate a later commit adds never
# runs on an earlier one. A symlinked config counts as absent. A commit whose
# config sets no verify, only a comment, or the corrupt value `none` runs
# <verify-command>.
# The worktree holds only tracked files, so a verify that needs installed
# dependencies has to install them itself.
#
# usage: verify-each.sh <repo> <range> <verify-command>
#
# Prints "<short sha> <subject>: exit <code>" for each commit, plus the last 20
# lines of output for each commit that failed.
# Exit 0 every commit passed, 1 at least one failed (the first line with a
# nonzero exit names the first failing commit), 2 usage or an empty range; any
# other exit is git's.
set -euo pipefail

usage() { echo "usage: verify-each.sh <repo> <range> <verify-command>" >&2; exit 2; }
[ $# -eq 3 ] || usage
repo=$1 range=$2 cmd=$3

shas=$(git -C "$repo" rev-list --reverse "$range")
[ -n "$shas" ] || { echo "verify-each.sh: no commits in $range" >&2; exit 2; }

base=''
cleanup() {
  if [ -n "$base" ]; then
    git -C "$repo" worktree remove --force "$base/wt" 2>/dev/null || true
    rm -rf "$base"
  fi
}
trap cleanup EXIT

failed=0
for sha in $shas; do
  base=$(mktemp -d "${TMPDIR:-/tmp}/verify-each.XXXXXX")
  git -C "$repo" worktree add -q --detach "$base/wt" "$sha"
  own=''
  meta=$(git -C "$repo" ls-tree "$sha" -- .ship/config.md)
  mode=${meta%% *}
  case "$mode" in
    100644 | 100755)
      own=$(git -C "$repo" show "$sha:.ship/config.md" | sed -n '/^verify:/{s/^verify:[[:space:]]*//;s/[[:space:]][[:space:]][[:space:]]*#.*$//;p;q;}')
      case $own in '#'* | none) own='' ;; esac
      ;;
  esac
  code=0
  (cd "$base/wt" && bash -c "${own:-$cmd}") > "$base/log" 2>&1 || code=$?
  echo "$(git -C "$repo" log -1 --format='%h %s' "$sha"): exit $code"
  if [ "$code" -ne 0 ]; then
    failed=1
    tail -n 20 "$base/log" | sed 's/^/  | /'
  fi
  cleanup
  base=''
done

exit "$failed"
