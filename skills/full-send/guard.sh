#!/usr/bin/env bash
# guard.sh - push the shipping branch only when it is a valid branch name, the
# branch checked out, and not the base. Every push of the shipping branch runs
# through it, so a run that drifted onto another branch refuses instead of
# pushing that branch.
#
# usage: guard.sh <shipping-branch> <base> [<lease-sha>]
#   With <lease-sha>, force-pushes with --force-with-lease, so the push fails
#   when the remote branch is no longer at <lease-sha>.
#
# Exit 0 pushed, 2 usage, 3 refused (prints why); any other exit is git push's.
set -euo pipefail

usage() { echo "usage: guard.sh <shipping-branch> <base> [<lease-sha>]" >&2; exit 2; }
refuse() { echo "refuse: $1" >&2; exit 3; }

[ $# -ge 2 ] && [ $# -le 3 ] || usage
branch=$1 base=$2 lease=${3:-}
[ -z "$lease" ] || [[ $lease =~ ^[0-9a-f]{40}$ ]] || usage

git check-ref-format --branch "$branch" >/dev/null 2>&1 || refuse "'$branch' is not a valid branch name"
current=$(git branch --show-current)
[ "$current" = "$branch" ] || refuse "checked out on '${current:-a detached HEAD}', not '$branch'"
[ "$branch" != "$base" ] || refuse "'$branch' is the base branch"

if [ -n "$lease" ]; then
  git push --force-with-lease="refs/heads/$branch:$lease" -u origin "$branch"
else
  git push -u origin "$branch"
fi
