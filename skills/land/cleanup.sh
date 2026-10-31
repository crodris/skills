#!/usr/bin/env bash
# cleanup.sh - after a merge, remove only what one ship run created: its
# worktree when it made one, and its branch, locally and on the remote, keeping
# the local branch when a worktree has it checked out. Then fast-forward the
# local base, in the worktree that holds it, and leave it alone when that is not
# possible. It prints the checkout a post-merge command runs in only when that
# checkout is on the updated base with no uncommitted changes.
# Run it from a checkout other than the worktree it removes.
#
# usage: cleanup.sh <pr-number> <branch> <base> --repo <owner/name> [--worktree <path>]
#
# Exit 0 cleaned up, 2 usage, 3 refused (prints why); any other exit is git's.
set -euo pipefail

usage() { echo "usage: cleanup.sh <pr-number> <branch> <base> --repo <owner/name> [--worktree <path>]" >&2; exit 2; }
refuse() { echo "refuse: $1" >&2; exit 3; }
# A listed path can outlive its worktree, so a holder must still answer as this repository's worktree on the base.
holds_base() {
  [ "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" = "$(git rev-parse --path-format=absolute --git-common-dir)" ] &&
    [ "$(git -C "$1" branch --show-current 2>/dev/null)" = "$base" ]
}

pr='' branch='' base='' repo='' worktree=''
while [ $# -gt 0 ]; do
  case $1 in
    --repo | --worktree)
      [ $# -ge 2 ] || usage
      if [ "$1" = --repo ]; then repo=$2; else worktree=$2; fi
      shift 2
      ;;
    -*) usage ;;
    *)
      if [ -z "$pr" ]; then pr=$1; elif [ -z "$branch" ]; then branch=$1; elif [ -z "$base" ]; then base=$1; else usage; fi
      shift
      ;;
  esac
done

[[ $pr =~ ^[1-9][0-9]*$ ]] || usage
[[ $repo =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || usage
git check-ref-format --branch "$branch" >/dev/null 2>&1 || refuse "'$branch' is not a valid branch name"
git check-ref-format --branch "$base" >/dev/null 2>&1 || refuse "'$base' is not a valid branch name"
[ "$branch" != "$base" ] || refuse "'$branch' is the base branch"

# A squash or rebase merge leaves no ancestry, so the forge is the only proof of the merge.
pr_json=$(gh pr view "$pr" --repo "$repo" --json state,headRefName,headRefOid)
merged=$(jq -r '"\(.state) \(.headRefName)"' <<<"$pr_json")
[ "$merged" = "MERGED $branch" ] || refuse "pull request $pr is not merged from '$branch' (it is: $merged)"

# A commit pushed after the merge, or never pushed, must survive cleanup, so both tips are checked before anything is removed.
# Origin's tip is read with ls-remote because a narrowed fetch refspec may never update origin/<branch>.
head=$(jq -r '.headRefOid' <<<"$pr_json")
if tip=$(git rev-parse -q --verify "refs/heads/$branch"); then
  [ "$tip" = "$head" ] || refuse "refs/heads/$branch is at $tip, not the merged head $head"
fi
remote=$(git ls-remote origin "refs/heads/$branch")
tip=${remote%%$'\t'*}
if [ -n "$tip" ] && [ "$tip" != "$head" ]; then
  refuse "origin's $branch is at $tip, not the merged head $head"
fi

if [ -n "$worktree" ]; then
  wt=$(cd "$worktree" 2>/dev/null && pwd -P) || refuse "worktree '$worktree' does not exist"
  case "$(pwd -P)/" in "$wt/"*) refuse "run this from a checkout other than $wt" ;; esac
  git worktree list --porcelain | grep -xF "worktree $wt" >/dev/null || refuse "$wt is not a worktree of this repository"
  [ "$(git -C "$wt" branch --show-current)" = "$branch" ] || refuse "$wt is not on '$branch'"
  [ -z "$(git -C "$wt" status --porcelain)" ] || refuse "$wt has uncommitted changes"
  git worktree remove "$wt"
  echo "removed worktree $wt"
fi

# A narrowed fetch refspec may omit the base, so that ref is fetched on its own.
# Prune still follows the configured refspec.
git fetch -q --prune origin
git fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base"
# Git refuses to switch to a branch or fetch into it while a worktree holds it, so that worktree takes the fast-forward.
holder=$(git worktree list --porcelain | awk -v ref="branch refs/heads/$base" '
  substr($0, 1, 9) == "worktree " { path = substr($0, 10) }
  $0 == ref && !found { print path; found = 1 }')
if [ -z "$holder" ] && [ "$(git branch --show-current)" = "$branch" ]; then
  git switch "$base" || refuse "cannot switch to '$base' to free '$branch'"
  holder=$(git rev-parse --show-toplevel)
fi
post_merge_checkout=''
if [ -z "$holder" ]; then
  if git fetch origin "refs/heads/$base:refs/heads/$base"; then
    echo "post-merge has no checkout: no worktree holds $base"
  else
    echo "left $base alone: git could not fast-forward it to origin/$base"
  fi
elif ! holds_base "$holder"; then
  echo "left $base alone: $holder is listed as holding it, but it is not this repository's worktree on it"
elif ! git -C "$holder" merge --ff-only "refs/remotes/origin/$base"; then
  echo "left $base alone: git could not fast-forward $holder to origin/$base"
elif [ "$(git -C "$holder" rev-parse HEAD)" != "$(git rev-parse "refs/remotes/origin/$base")" ]; then
  echo "post-merge has no checkout: $holder is ahead of origin/$base"
elif [ -n "$(git -C "$holder" status --porcelain --untracked-files=no)" ]; then
  echo "post-merge has no checkout: $holder has uncommitted changes"
else
  post_merge_checkout=$holder
fi

# A branch a worktree has checked out, such as one ship reused, keeps its local copy.
holders=$(git worktree list --porcelain)
if git show-ref --verify --quiet "refs/heads/$branch"; then
  case $'\n'"$holders"$'\n' in
    *$'\n'"branch refs/heads/$branch"$'\n'*) echo "left $branch: a worktree has it checked out" ;;
    *) git branch -D "$branch" ;;
  esac
fi
# Exit 2 means the branch is gone from the remote, and any other failure means the lookup did not answer.
lookup=0
git ls-remote --exit-code --heads origin "refs/heads/$branch" >/dev/null || lookup=$?
case $lookup in
  0) git push --force-with-lease="refs/heads/$branch:$head" origin --delete "refs/heads/$branch" ;;
  2) ;;
  *) refuse "cannot tell whether origin still has '$branch' (git ls-remote exit $lookup)" ;;
esac
[ -z "$post_merge_checkout" ] || echo "post-merge checkout: $post_merge_checkout"
echo "cleaned up $branch"
