---
name: babysit
description: Watches one pull request until it is ready to merge, running CI, the review bots, and review-loop on each pass, pushing each pass's fixes, and keeping the branch current with its base. Use when the user asks to babysit, watch, or monitor a pull request, or to get it green without merging.
version: 3.1.0
---

# Babysit

Read `../ship/boundary.md` and `../ship/config.md` first, and stop as boundary.md's Missing skills section says when a sibling is missing.
When `../ship/boundary.md` itself is missing, stop and tell the user to install the ship skills (`ship`, `prove`, `file-pr`, `babysit`, `review-loop`, and `land`) from `crodris/skills`.

Inputs: a pull request number, whether the caller merges afterwards, the merge method, and whether this run created the branch.
A direct request is hold mode, and babysit itself never merges.
With no merge method passed, read `merge-method` from `.ship/config.md`.
When it has none, use the one allowed method as the Merge method section of `../land/SKILL.md` says.
With no method resolved, a base update merges the base in as the `squash` and `merge` path does, and the result line says so.

A branch is exclusively this run's only when this run created it, such as through `ship`'s `settle-branch.sh`.
A branch babysit found already pushed is not, whoever wrote its commits.

## Start

1. Read the pull request with `gh pr view <n> --json state,headRefName,baseRefName,isCrossRepository,autoMergeRequest`.
   Return `BLOCKED <reason>` when it is not open or its head lives on a fork.
   Validate `headRefName` and `baseRefName` each with `git check-ref-format --branch` before any command uses them, and return `BLOCKED <reason>` when either fails.
   Work in place when the current checkout is on the head branch and is clean, as the Worktrees section of `../ship/boundary.md` defines.
   Return `BLOCKED <reason>` naming the changed files when it is on the head branch and dirty, since git cannot check out one branch twice and a fix could stage those edits.
   Otherwise get the head branch as that section says.
   When Start made a new worktree, install its dependencies before any prove or watch step, as that section says.
   Before returning any result, remove that worktree as that section says.
   Read the run section with `gh pr view <n> --json body --jq .body`.
   Hold its ledger, push counts, and the minor-push record for Each pass step 3.
2. Hold the head branch as `$branch` and the base as `$base`, and pass them only as quoted arguments.
3. In hold mode, turn off auto-merge with `gh pr merge <n> --disable-auto` when it is on, and dequeue the pull request when `mergeQueueEntry` is set, as the GraphQL calls section of `bots.md` says, since `gh pr view` has no field for it.
4. Read `bots.md` in this skill's directory to resolve which review bots are present.

## Each pass

1. Capture the head SHA with `gh pr view <n> --json headRefOid`.
   Run `git fetch origin "+refs/heads/$branch:refs/remotes/origin/$branch"` and `git merge --ff-only "origin/$branch"`.
   Return `BLOCKED <reason>` when that fails, or when `git rev-parse HEAD` differs from the captured SHA.
2. Start `bash <this skill's directory>/watch.sh <n> <sha> --repo <owner/name>` in the background, where `<owner/name>` is the slug `../ship/boundary.md` defines, with the `--bot` and `--rerequest` arguments `bots.md` says this pass uses.
   Act on its exit code, and never write a polling loop.
   Without background commands, run it in the foreground with a `--deadline` above 120 seconds and below the tool's timeout.
3. Read `../review-loop/SKILL.md` and follow its Review section on the same SHA, passing the inputs its Inputs section lists.
4. Wait for watch.sh and every reviewer before touching the tree, then act on watch.sh's exit:

| Exit | Action |
| --- | --- |
| 0 | Go on to triage. |
| 1 | Go on to triage, with each failed check judged by the CI rules below, and with a base update due when it printed `base moved:`. |
| 3 | Restart the pass on the new head. |
| 4 | Run watch.sh again on the same SHA, up to 3 times in this pass, then `BLOCKED` naming what is still pending. |
| 6 | Go on to triage, list failed checks with `gh pr checks <n>` before the CI rules, then apply `bots.md`'s Unavailable bot rule. |
| 8 | Go on to triage, with a base update due. |
| other | `BLOCKED`, quoting the verdict line. |

5. Follow review-loop's Triage and Fix sections with every finding.
   On a large pull request, Triage step 5 can add a whole-diff Spec read.
   On `RESTART`, restart the pass on the new head.
   A second restart in a row, from watch.sh or review-loop, is `BLOCKED`, since something outside this run keeps pushing.
   On `BLOCKED <reason>`, return `BLOCKED <reason>` and push nothing.
   `FIXED <sha>` and `CLEAN` go on.
6. Read `mergeable,mergeStateStatus` with `gh pr view <n> --json mergeable,mergeStateStatus`.
   While `mergeable` is `UNKNOWN`, re-read as merge gate item 4 of `../land/SKILL.md` says, else return `BLOCKED mergeable unknown`.
   Update the base when it is due, as the Base update section says.
7. When this pass committed anything or updated the base, push once with `bash <this skill's directory>/../ship/guard.sh "$branch" "$base"`, adding the head the reviewers read as the lease after a base rebase.
   When the lane is light, add the comment `../review-loop/lanes.md` names to the command.
   Exit 3 or a failed push is `BLOCKED`.
8. Reply under each bot finding as `bots.md`'s Replies section says.
   Write the run section through the Reuse an open one section of `../file-pr/SKILL.md` with the ledger, lane, and evidence path review-loop returned and the bots present and this run's pass and push counts.
   On file-pr's `FAIL`, return `BLOCKED <reason>`.
9. A pass that pushed anything starts the next pass.

## CI rules

Read a failed check's log with `gh run view <run-id> --log-failed` before judging it.
A failure that traces to the diff or reproduces locally is a blocking finding.
An infrastructure failure, such as a lost runner, a network or registry timeout, a rate limit, or a cache error, gets one `gh run rerun <run-id> --failed`, and failing again on the same SHA is `BLOCKED`.
Any other failure, such as a check already red on `base` or a flaky test, is `BLOCKED`.

## Base update

A base update is due on watch.sh's exit 8, on an exit 1 that printed `base moved:`, on `mergeable` `CONFLICTING`, or on `mergeStateStatus` `BEHIND` when the base requires an up-to-date branch.
Make it after the pass's fixes are committed.
A base update is `BLOCKED` when the checkout is dirty, as the Worktrees section of `../ship/boundary.md` defines it, and the report names the paths.
A run takes at most one, and a second one due is `BLOCKED`.

With `merge-method: rebase`:

1. Return `BLOCKED` when the branch is not exclusively this run's, since the rebase needs a force-push.
2. Fetch the base as the Fetching the base section of `../ship/boundary.md` says, then run `git rebase --no-autosquash "origin/$base"`, resolving conflicts the way the change intends, so this pass's `fixup!` commits stay for the next pass to read.
3. Record the old base, the old head, and the rebased head, so the next pass can read `git range-diff <old-base>..<old-head> origin/$base..<rebased-head>`.

With `squash` or `merge`, fetch the base as the Fetching the base section of `../ship/boundary.md` says, then merge `origin/$base` into the branch, resolving conflicts the way the change intends.

Then run `../prove/SKILL.md` on the result, after a rebase with each verify fix committed as a fixup of the branch commit it corrects, or after a merge with the merge commit's message.
A verify fix with no clear target commit returns `BLOCKED`.
On `FAIL`, return `BLOCKED` with what still fails, and push nothing.

## Result

Return on a pass that pushed nothing and that review-loop returned `CLEAN` for.

1. With `merge-method: rebase`, `fixup!` commits on the branch, and a branch exclusively this run's, fold them:
   1. Record the current head as the reviewed head.
   2. Run `GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash "$(git merge-base "origin/$base" HEAD)"`, which keeps the base the reviewers read.
   3. Return `BLOCKED` unless `git diff --quiet <reviewed head> HEAD` passes.
   4. Push with the reviewed head as `guard.sh`'s lease.
      When the lane is light, add the comment `../review-loop/lanes.md` names to the command.
   5. Start another pass on the pushed head, since the bots that review every push have not read it, and return from that pass's Result instead.
2. With `merge-method: rebase` and more than one commit in `origin/$base..HEAD`, resolve the verify command as the Resolve verify section of `../prove/SKILL.md` says, hold it in `$verify`, and run `bash <this skill's directory>/../prove/verify-each.sh "$(git rev-parse --show-toplevel)" "origin/$base..HEAD" "$verify"`.
   Exit 0 goes on.
   On exit 1, when only earlier commits fail, return `BLOCKED` naming the first failing commit.
   When the head fails too, run `bash -c "$verify"` from this checkout's root: when it passes there, the worktree lacks something verify needs, so say so in the run section and go on, and otherwise return `BLOCKED` naming the head.
   Any other exit is `BLOCKED`, quoting the script's output.
3. Check the pull request once more for a table bot no pass waited on, and run a pass for it as `bots.md` says when one shows up.
4. Run watch.sh with no `--bot` on the current head, the way step 2 of each pass does.
   Exit 0 goes on.
   Exit 1 goes back to triage.
   Exit 4 runs it again as the exit table says.
   Exit 8 makes the base update, pushes as Each pass step 7 does, then runs another pass.
   Any other exit is `BLOCKED`.
   Result starts its own count of 3 for these exit 4 reruns.
5. Re-read the pull request, and return `BLOCKED` unless it is open, targets `base`, and its head is the current head.
6. Read `mergeable,mergeStateStatus,reviewDecision` with `gh pr view <n> --json mergeable,mergeStateStatus,reviewDecision`.
   While `mergeable` is `UNKNOWN`, re-read as Each pass step 6 does.
   When a base update is due, make that update.
   Push as Each pass step 7 does.
   Run another pass and return from that pass's Result.
   Otherwise return `AWAITING-APPROVAL <sha>` when `reviewDecision` is `REVIEW_REQUIRED` or `CHANGES_REQUESTED`.
   Then return `READY <sha>` when `mergeable` and `mergeStateStatus` pass merge gate item 4 of `../land/SKILL.md`, and `BLOCKED <reason>` naming the `mergeStateStatus` otherwise, with the current head as `<sha>`.
