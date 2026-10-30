#!/usr/bin/env bash
# verify-each.sh - run verify on every commit in a range, oldest first, each in
# its own detached worktree under a private directory in the system temp
# directory, so a caller can stop a rebase merge from putting a commit on the
# base that fails on its own tree.
# Each commit runs the `verify:` line of its own .ship/config.md, read from
# git, with any trailing comment dropped, so a gate a later commit adds never
# runs on an earlier one.
# A symlinked or missing config, no verify line, an empty value, a comment, or
# `none` all yield <verify-command>.
# The worktree holds only tracked files, so a verify that needs installed
# dependencies has to install them itself.
#
# usage: verify-each.sh [--print] <repo> <range> <verify-command>
#
# --print comes first.
# After it, any argument count other than three is a usage error, as is any of
# the three arguments that starts with -.
# A <verify-command> that contains a newline is a usage error, since --print
# prints one line per commit.
# Without --print, prints "<short sha> <subject>: exit <code>" for each commit,
# plus the last 20 lines of output for each commit that failed.
# With --print, prints one line "<short sha><TAB><command>" per commit, oldest
# first, creates no worktree, and runs nothing. <command> is the string a
# normal run would pass to bash -c.
# Exit 0 when every commit passed, or when --print finishes. Exit 1 when at
# least one failed (the first line with a nonzero exit names the first failing
# commit). Exit 2 on usage or an empty range. Any other exit is git's.
set -euo pipefail

usage() { echo "usage: verify-each.sh [--print] <repo> <range> <verify-command>" >&2; exit 2; }

# Bash turns errexit off inside $(...), so each git call returns its own failure,
# and the callers' assignments stop the script with it.
command_for() {
  own=''
  meta=$(git -C "$repo" ls-tree "$1" -- .ship/config.md) || return
  mode=${meta%% *}
  case "$mode" in
    100644 | 100755)
      cfg=$(git -C "$repo" show "$1:.ship/config.md") || return
      own=$(sed -n '/^verify:/{s/^verify:[[:space:]]*//;s/[[:space:]][[:space:]][[:space:]]*#.*$//;p;q;}' <<< "$cfg")
      case $own in '#'* | none) own='' ;; esac
      ;;
  esac
  printf '%s\n' "${own:-$cmd}"
}

print=0
if [ "${1:-}" = "--print" ]; then
  print=1
  shift
fi
[ $# -eq 3 ] || usage
case "$1" in -*) usage ;; esac
case "$2" in -*) usage ;; esac
case "$3" in
  -*) usage ;;
  *$'\n'*) echo "verify-each.sh: <verify-command> must be one line; join several commands with &&" >&2; exit 2 ;;
esac
repo=$1 range=$2 cmd=$3

shas=$(git -C "$repo" rev-list --reverse "$range")
[ -n "$shas" ] || { echo "verify-each.sh: no commits in $range" >&2; exit 2; }

if [ "$print" -eq 1 ]; then
  for sha in $shas; do
    c=$(command_for "$sha")
    printf '%s\t%s\n' "$(git -C "$repo" log -1 --format='%h' "$sha")" "$c"
  done
  exit 0
fi

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
  run=$(command_for "$sha")
  code=0
  (cd "$base/wt" && bash -c "$run") > "$base/log" 2>&1 || code=$?
  echo "$(git -C "$repo" log -1 --format='%h %s' "$sha"): exit $code"
  if [ "$code" -ne 0 ]; then
    failed=1
    tail -n 20 "$base/log" | sed 's/^/  | /'
  fi
  cleanup
  base=''
done

exit "$failed"
