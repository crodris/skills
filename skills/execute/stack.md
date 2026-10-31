# Stacks

A stack is one issue delivered as several dependent reviews, one per bundle, on chained branches.
Read the section that a step in `SKILL.md` points to; step numbers refer to that procedure.
`conventions.md` defines the `Bundles` section, the pending marker, the `none confirmed` line, the `Merge-closer` line, per-bundle reconciliation, and stacked review bodies.

A bookkeeping commit stages only the plan document, by explicit path, confirms the staged diff carries only the one `- Review:` line it adds, replaces, or removes, and names no task in its body.
When the staged diff carries an unrelated edit as well, unstage that edit and leave it in the working tree for the run's final closing commit.

## Step 2: restack check

Run this only when the sweep's partial-progress case decided a stacked issue: some bundles merged and others are still open.
Never restack when any bundle reported `closed-unmerged`, is undetermined, or is unrecorded.
Skip the restack, and say so, while this checkout holds an update paused by an earlier hold, as `SKILL.md` step 4 detects it.

Before the first rebase, record `git branch --show-current`, or `git rev-parse HEAD` when it prints nothing.
After the last rebase or a hold below, run `git checkout <recorded value>`, so step 4 reads the invoked issue and not a stack branch's.

Rebase the remaining stack branches bottom-up, each onto its updated base, and only when the merged bundle's content is not an ancestor of it.
Rebase each one with `git rebase --onto <updated base> <cut point> <branch>`, where the cut point is the parent of the oldest commit in `<updated base>..<branch>` whose `Task:` trailer names one of that bundle's tasks, as the lower-bundle check finds it, so a squash-merged bundle's original commits are not replayed.
After each rebase and before pushing that branch, re-record every closed task whose recorded commit left the branch's range, as step 3 of The lower-bundle check below does.
Decide by ancestry, never by the adapter's `stackedReviews` value.
Push a rebased branch with `--force-with-lease`, never with a bare force push.
When the lease is rejected, stop and hold: another commit reached that branch.
When the rebase conflicts, note the conflicting files from `git ls-files -u`, run `git rebase --abort`, then stop and hold naming them.

## Step 7: recovering the stack

Recover every bundle's index, branch, sub-issue refs, and recorded review id from the `Bundles` section, and carry that stack through the rest of this run.
The bundle in progress is the first one with no recorded review, and the run continues on its branch.
When every bundle carries a recorded review, stay on bundle N's branch, the stack tip, and create no branch and return to no earlier one: only step 11's issue-level finalization remains.

### Bundle branches

Bundle 1's branch follows step 7's naming and creation rules.
Every push of a bundle branch follows step 7's push rule.
A later bundle's branch takes the same name with its index appended, so bundle 2 of `feat/onc-5-add-webhooks` is `feat/onc-5-add-webhooks-2`, created from the previous bundle's branch when that bundle starts.
The already-exists guard: check out a bundle branch that exists locally or on the remote.
Create it only when it is absent from both and the bundle's entry carries no `- Review:` line of any kind, the pending marker included.
When the entry carries such a line and the branch is absent from both, never create it, since a new branch would drop the commits a run already made on it.
Stay instead on the highest bundle branch below it that still exists, and let the per-bundle routine for that bundle record what it can and hold, per A missing bundle branch.

## Step 8: proposing a split

Propose a split only when the breakdown has five or more units and at least one valid cut point exists.
A cut point is valid where the units up to it form a self-contained change that stands on its own and that the later units build on, never the reverse, judged from the plan alone.
When no valid cut point exists, proceed as a single review and say so.

Shape the bundles as contiguous runs of step 8's planned order: at most three bundles, each holding at least two units.
Exceed three only when the user asked for a specific larger split.

Present the split before anything is written to the tracker: the bundles, the units in each, and the resolved forge's `stackedReviews` value with what it means for this run.
This is a skip-list stop per `approval.md`: `ask` mode waits for an answer, and `auto` mode applies the split and reports it.

### Creating a confirmed stack

Take step 8's create-versus-adopt decision as for a single review: create a sub-issue for each planned unit when the issue has no children, and adopt the existing children, skipping `createSubIssue` for each, when it has them.
Create them one at a time in the planned order, first unit to last.
Chain every task sequentially, so each task deps on its predecessor across bundle boundaries too, per the `createTask` row in `memory.md`.
Write the `Bundles` section, with each bundle's index, branch, and units, and the `- Merge-closer: suppressed` line into the plan document before the first tracker write, both per `conventions.md`.

## Step 10: bundles in the loop

Before the first pass, when every task in the bundle step 7 recovered is closed and that bundle carries no recorded review, its per-bundle routine was interrupted.
Run the routine for it now, then move to the next bundle as below.
Decide this from the memory backend and the plan document, not from what is claimable.
When every bundle's routine finished but the issue's closing actions did not, make no pass here; step 11 recovers that run.

When a pass closes the last task in its bundle, run the per-bundle routine for that bundle before claiming again.
Then, when a later bundle remains, move onto its branch under the already-exists guard, and continue the loop on it.

## Step 11: the per-bundle routine

Step 10 runs this once per bundle as that bundle's last task closes, in place of step 11's single-review path.
For bundle k of N, in this order:

1. Commit any leftover uncommitted change that belongs to this bundle's tasks, leaving unrelated working-tree edits alone.
2. For every bundle after the first, run the lower-bundle check.
3. Reconcile bundle k's closed tasks against the commits in its own range, per the per-bundle rule in `conventions.md`; when they disagree, stop and open no review.
4. Call `resolveBase` on bundle k's base: the resolved base branch for bundle 1, and branch k-1 for later bundles unless the lower-bundle check moved bundle k onto the resolved base branch.
5. Settle whether bundle k needs a review opened, per Reusing a bundle's review.
   A reused review skips the marker, `openReview`, `publishReview`, and the recorded line below.
6. Write `- Review: pending (bundle k/N)` beneath the bundle's line in the `Bundles` section, as a bookkeeping commit `chore(<issue-ref>): mark bundle k review pending` on branch k, before the next item's push.
7. Push branch k, unless the adapter declares `pushesForYou`.
8. Title the review as step 11's single-review path in `SKILL.md` says, reading that `git log` from the resolved base, since a later bundle's base is a bundle branch, and name the bundle in the title.
   Build the body from Body steps 1 to 4 of `../file-pr/SKILL.md` and the stack rules in `conventions.md`.
   Call `openReview` with branch k, that base, and that title and body as the supplied title and complete body, passing the previous bundle's review id as `dependsOn` for every bundle after the first.
9. When `openReview` fails, follow the single-review path in `SKILL.md`.
   When `openReview` returns the manual-handoff result, no review exists for this bundle.
   Call no `publishReview`, write no review record, remove the pending marker as a bookkeeping commit and push it on branch k even under `pushesForYou`, apply `inReview` when k is 1, as the single-review path does, and stop and report the handoff for bundle k.
   Say that this guard fired, since only a non-manual tier proposes a split.
10. Call `publishReview` with the returned id.
11. Replace the pending marker with `- Review: <id> <url> (bundle k/N)`, and commit and push it on branch k at once, as a bookkeeping commit `chore(<issue-ref>): record bundle k review id`.
12. Apply `inReview` when bundle 1's review publishes, and never for a later bundle.
    A resumed run that reuses bundle 1's review applies `inReview` instead whenever the tracker shows the issue in an earlier phase, and does nothing else to that review.

### The lower-bundle check

Skip this check, keeping branch k-1 as the base, when the resolved forge declares `reviewLookup: none`.
Otherwise call `getReviewState` on the recorded review of every bundle from 1 to k-1:
- When any reports `unknown` or `closed-unmerged`, stop and hold naming those bundles.
- When bundle k-1 reports `open`, change nothing.
- When bundle k-1 reports `merged` but a bundle below it does not, stop and hold naming them.
- When every one reports `merged`, move bundle k onto the base with the steps below.

1. Fetch the resolved base branch as the Base branch resolution section of `forges.md` says.
   The cut point is the parent of the oldest commit in `origin/<base>..<branch k>` whose `Task:` trailer names one of bundle k's tasks.
   When the cut point is already an ancestor of `origin/<base>`, skip the next step.
2. When bundle k's entry carries a pending marker, stop and hold, since a review opened for it may target branch k-1.
   Say that the user should retarget that review to the base and record it as a full `- Review:` line, or close it and replace the marker with `- Review: none confirmed (bundle k/N)`.
   Otherwise run `git rebase --autostash --onto origin/<base> <cut point> <branch k>`, where `--autostash` carries uncommitted edits such as checklist mode's pending hash edit.
   Handle a conflict as the restack check does.
3. For every closed task in bundle k whose recorded commit is not in `origin/<base>..<branch k>` after this run's or an earlier run's rebase, find its new commit with `git log --format=%h --grep "^Task: <id>$" origin/<base>..<branch k>`, and call `close` on that task again with it.
   When any task was re-recorded, commit the task-state files it changed as `chore(<issue-ref>): re-record bundle k commits after rebase`, naming no task in the body and staging by explicit path as step 11's closing commit does; on beads, run the three export steps in One database per repository in `memory/beads.md`.
   When branch k is on the remote and differs from the local branch, push it and handle a rejected lease as the restack check does.
4. Use the resolved base branch as bundle k's base for the rest of the routine.

### Reusing a bundle's review

Decide from bundle k's entry in the `Bundles` section alone, which holds exactly one of these:
- A full `- Review: <id> <url> (bundle k/N)` line: reuse that review, open nothing, and change no record.
- No line: no run reached this bundle's `openReview` call, since the marker is committed before it.
  Write the marker and open the review.
- A `- Review: none confirmed (bundle k/N)` line: the user confirmed that no review exists.
  Replace it with the pending marker and open the review.
- A `- Review: pending (bundle k/N)` marker: a review may exist.
  Run the pending-marker lookup.

Never read the remote's branch list as evidence in any case, since a forge keeps a review after its head branch is deleted.

### A missing bundle branch

When branch k is absent from the local repository and the remote, first call `resolveBase` on bundle k's base as step 4 of the per-bundle routine names it, taking branch k-1 for a later bundle since the lower-bundle check is skipped, and stop and hold for bundle k when it fails.
Then run only the pending-marker lookup with that base and the recording it calls for, then stop and hold for bundle k.
Skip the leftover commit, the lower-bundle check, the reconciliation, and `openReview`.
Say that branch k is missing and that this run only recorded what it learned about the review.
Say what unblocks it, as the user's call: restore branch k from a clone, a reflog, or a branch above it that carries those commits, or decide the work is gone and rebuild it.
Never recreate branch k from branch k-1, since it would come back empty.

### The pending-marker lookup

Call `findReviewByBranch` for branch k, and keep only the candidates whose base is exactly the base `resolveBase` returned for this bundle.

- With exactly one candidate, call `getReviewState` on it.
  On `open` or `merged`, backfill its record, then continue the routine.
  On `closed-unmerged`, keep the pending marker, then stop and hold, naming bundle k and saying its review was abandoned.
  On `unknown`, keep the pending marker, then stop and hold.
- With more than one candidate, stop and hold naming them.
- With none, or when the adapter omits `findReviewByBranch`, which you say once, open no review and hold, since a bounded lookup that finds nothing proves nothing, per `forges.md`.
  Say that bundle k carries a pending marker, that a review may exist that this run could not find, and that the user should confirm whether one exists.

When the user confirms that no review exists, replace the marker with `- Review: none confirmed (bundle k/N)`.
When the user finds a review, record it as a full `- Review: <id> <url> (bundle k/N)` line.
A confirmation given only in conversation changes no record, so every later run holds the same way.

The backfill replaces the pending marker with `- Review: <id> <url> (bundle k/N)` from the matched candidate, and is pushed before the routine continues.
Write the backfill and both confirmations as bookkeeping commits pushed on the branch this run is on rather than on branch k, which may be deleted or reused.

### After bundle N

After bundle N's routine completes, close the parent task in the memory backend, a no-op for the checklist adapter, then continue into step 11's closing actions, which run once for the issue.
The final closing commit goes on branch N, the stack tip.
Say at handoff that the issue's record carries `- Merge-closer: suppressed`, so the merge-closer Action takes no action for it.
Say too that on a repository relying on that Action, the issue reaches `done` only when a later run's sweep sees every bundle merged.
