---
name: land
description: Merges a pull request that babysit reported ready, after a merge gate, with the repository's merge method, then watches the release run and cleans up what the ship run created. Read by ship in merge mode; use when the user asks to land a ready pull request.
version: 3.1.0
---

# Land

Read `../ship/boundary.md` and `../ship/config.md` first, and stop as boundary.md's Missing skills section says when a sibling is missing.
When `../ship/boundary.md` itself is missing, stop and tell the user to install the ship skills (`ship`, `prove`, `file-pr`, `babysit`, `review-loop`, and `land`) from `crodris/skills`.

Inputs: the pull request, the SHA babysit returned with `READY`, the branch, `base`, and the worktree ship created, if any.

## Merge method

`merge-method` is `squash`, `rebase`, or `merge`.
Read the allowed methods with `gh api repos/<owner/name> --jq '[.allow_squash_merge, .allow_rebase_merge, .allow_merge_commit]'`, where `<owner/name>` is the slug `../ship/boundary.md` defines, and a failed call or a `null` means unreadable.
A configured value outside the three, or one the settings show as `false`, is unresolved.
With no resolved value, use the one method when exactly one is `true`.
Otherwise ship asks in its one round of questions, with one option per allowed method, or all three when unreadable, and these examples:

- `squash`: the branch's commits become one commit titled like the pull request, so five work-in-progress commits become `feat(api): add rate limits (#42)`.
- `rebase`: each branch commit lands as its own commit, so an import authored by someone else stays separate from the commit that wires it in.
- `merge`: a merge commit joins the branch, so a release branch merged back into `main` stays visible as a branch.

## Merge gate

When `gh pr view <n> --json state --jq .state` prints `MERGED`, skip this gate and the merge, record the merge commit as the Merge section says, run every later command in the foreground as it says, and go on to Release.
Merge only when every item holds, and return `BLOCKED <item>` on the first that fails.

1. Run `bash <this skill's directory>/../babysit/watch.sh <n> <sha> --repo <owner/name>` with no `--bot`, in the background, or in the foreground with a `--deadline` above 120 seconds and below the tool's timeout, as Each pass step 2 of `../babysit/SKILL.md` says.
   On exit 4, run it again, up to 3 times, then `BLOCKED`.
   It passes this gate only on exit 0.
2. The pull request is open, targets `base`, and its head is still `<sha>`.
3. `reviewDecision` is neither `REVIEW_REQUIRED` nor `CHANGES_REQUESTED`.
   Never merge past either with `--admin`.
4. Read `mergeable` and `mergeStateStatus` with `gh pr view <n> --json mergeable,mergeStateStatus`.
   While `mergeable` is `UNKNOWN`, re-read it up to 5 times, 10 seconds apart, before deciding.
   `mergeable` is `MERGEABLE` and `mergeStateStatus` is neither `BLOCKED` nor `DIRTY`, since green checks and a blocked merge button are separate facts.
5. The ledger in the run section has no open confirmed critical or major, and no open blocking finding.
   A run section with neither ledger lines nor `Ledger: none` fails this item.
6. On a direct land request with no `PASS` line in the run section, return `BLOCKED proof` and say to run `ship` on the pull request first, since `ship` records the `PASS` line.
7. The proof covers the diff.
   Every file that `gh api --paginate "repos/<owner/name>/pulls/<n>/files" --jq '.[].filename'` lists was exercised by verify or the drive, or changes no behavior.
   Name a behavior-changing file that nothing exercised, and return `BLOCKED proof coverage`.
8. With `rebase`, no subject that `gh pr view <n> --json commits --jq '.commits[].messageHeadline'` prints starts with `fixup!` or `squash!`.

## Merge

Run `gh pr merge <n> --<merge-method> --match-head-commit <sha>`, and leave the branch to cleanup.sh, which deletes it only at the merged head.
On a nonzero exit from `gh pr merge`, read `gh pr view <n> --json state,mergeCommit` first, and return `BLOCKED` with its stderr only when the state is not `MERGED`.
When the lane is light, add the comment `../review-loop/lanes.md` names to the command, and the lane is the one the run section records.
With `squash`, keep the subject identical to the pull request title, since release tooling may parse it.
When `gh pr merge` leaves the pull request open, the merge wait starts.
During the wait, poll `gh pr view <n> --json state --jq .state` every 30 seconds for up to 30 minutes, in commands of at most 10 minutes each.
The wait ends when the state is `MERGED`.
Keep polling while the GraphQL `mergeQueueEntry` that `../babysit/bots.md` reads is set.
For auto-merge with no queue, keep polling while `gh pr view <n> --json autoMergeRequest` is non-null.
After the first poll that shows neither a queue entry nor `autoMergeRequest`, poll twice more, 30 seconds apart, before returning `BLOCKED`.
Return `BLOCKED` when the pull request is closed unmerged, or still not merged after 30 minutes.
Record the merge commit from `gh pr view <n> --json mergeCommit --jq .mergeCommit.oid`.

From the merge to the final report, run every command in the foreground and never end the turn.
A host may close the session once the pull request merges and the turn goes idle, which kills background commands, as T3 Code does.

## Release

Fetch the base first, as the Fetching the base section of `../ship/boundary.md` says.
Skip this section when `release` is `none`, or when `git ls-tree <merge-sha> .github/workflows/` lists no workflow in the merged tree, and say which.
Run `bash <this skill's directory>/release-watch.sh <merge-sha> --repo <owner/name> --base "$base"` with a `--deadline` below the tool's timeout.
Exit 0 is a passed release.
On exit 4, run it again, until about thirty minutes past the release's usual duration, then report that the release did not settle.
Exit 1 is a failed release.
Exit 3 means the base started no run for the merge commit.
After exit 0, exit 1, exit 3, exit 4 after its reruns, or any other exit, report the result and go on to Cleanup.
When the release run pushes a release commit, such as with semantic-release, watch that commit's runs too.
Never push to `base` while a release may still be running.

## Cleanup

Run cleanup.sh after the merge on every path, including after a failed or unsettled release, from a checkout other than the worktree ship created, with `bash <this skill's directory>/cleanup.sh <n> <branch> "$base" --repo <owner/name>`, adding `--worktree <path>` when ship created one.
It removes the worktree ship created, and it deletes the local and remote branch after checking that each is at the merged head, keeping a local branch another worktree has checked out, as the Worktrees section of `../ship/boundary.md` says.
Exit 3 prints a reason.
Report it, and say which of worktree removal, base fast-forward, local branch delete, and remote branch delete ran before it.
When `post-merge` names a command, run that command only after cleanup.sh exits 0, from the checkout cleanup.sh ran in, in addition to cleanup.sh.
When cleanup.sh exits nonzero, report `post-merge` as skipped and why.
Report a nonzero exit from that command in the cleanup result line.

## Result

End with `MERGED <merge-sha> <merge-method>`, then the release result and the cleanup result, each in one line, or with `BLOCKED <reason>` when the gate or the merge stopped.
