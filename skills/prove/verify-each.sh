#!/usr/bin/env bash
# verify-each.sh - run verify on every commit in a range, oldest first, each in
# its own detached worktree under the system temp directory, so a caller can
# stop a rebase merge from putting a commit on the base that fails on its own tree.
# Each commit runs the `verify:` line of its own .ship/config.md, with any
# trailing comment dropped, so a gate a later commit adds never runs on an
# earlier one. A commit whose config sets no verify, only a comment, or the
# corrupt value `none` runs <verify-command>.
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

wt=''
cleanup() {
  if [ -n "$wt" ]; then
    git -C "$repo" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    rm -f "$wt.log"
  fi
}
trap cleanup EXIT

failed=0
for sha in $shas; do
  wt=$(mktemp -d "${TMPDIR:-/tmp}/verify-each.XXXXXX")
  git -C "$repo" worktree add -q --detach "$wt" "$sha"
  own=''
  if [ -f "$wt/.ship/config.md" ]; then
    own=$(sed -n '/^verify:/{s/^verify:[[:space:]]*//;s/[[:space:]][[:space:]][[:space:]]*#.*$//;p;q;}' "$wt/.ship/config.md")
    case $own in '#'* | none) own='' ;; esac
  fi
  code=0
  (cd "$wt" && bash -c "${own:-$cmd}") > "$wt.log" 2>&1 || code=$?
  echo "$(git -C "$repo" log -1 --format='%h %s' "$sha"): exit $code"
  if [ "$code" -ne 0 ]; then
    failed=1
    tail -n 20 "$wt.log" | sed 's/^/  | /'
  fi
  cleanup
  wt=''
done

exit "$failed"
