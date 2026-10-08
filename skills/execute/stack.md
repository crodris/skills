# Stacks

A stack is one issue delivered as several dependent reviews, one per bundle, on chained branches.
Read the section that a step in `SKILL.md` points to.
Step numbers refer to the procedure in `SKILL.md`.
The `Bundles` section, the pending marker, the `none confirmed` line, the `Merge-closer` line, per-bundle reconciliation, and stacked review bodies are defined in `../fathom-shared/conventions.md`.

## Step 2: restack check

Run this only when the sweep's partial-progress case decided a stacked issue: some bundles merged and others are still open.
Never restack when any bundle reported `closed-unmerged`, since that would force-push a rebase onto work the user may be about to discard, and never when any bundle is undetermined or unrecorded.

Ask one forge-agnostic question of each remaining stack branch: is the merged bundle's content an ancestor of it?
Rebase a remaining branch onto its updated base only when the answer is no, and leave it alone when the answer is yes.
Use ancestry rather than the adapter's `stackedReviews` value, because a squash-merge on a `retarget` forge leaves a dependent review redisplaying the merged bundle's changes exactly as an unretargeted `none` forge would.
Rebase the remaining branches bottom-up, so each one lands on a base that is already correct.
Push a rebased branch with `--force-with-lease` and never with a bare force push.
When the lease is rejected, stop and hold: another commit reached that branch, and overwriting it discards someone's work.
When the rebase conflicts, note the conflicting files from `git ls-files -u`, run `git rebase --abort`, then stop and hold naming them.
A restack runs inside the sweep, before this issue's own work, so it leaves no rebase paused in the checkout; step 7's paused hold covers only the branch a run is about to implement on.
Skip the restack, and say so, while this checkout already holds an update paused by an earlier hold, as `SKILL.md` step 4 detects it.

## Step 7: recovering the stack

Recover every bundle's index, branch, sub-issue refs, and recorded review id from the `Bundles` section, and carry that recovered stack through the rest of this run, including step 10's loop and the per-bundle routine below.
The bundle in progress is the first one with no recorded review, so this run continues on that bundle's branch rather than on bundle 1's.
When every bundle already carries a recorded review, no bundle is in progress and the branch is bundle N's, the stack tip: all that can remain is the issue-level finalization, which step 11 puts on the tip branch.
In that case do not create another branch and do not go back to an earlier bundle's branch; this run is finishing the stack rather than building it.

### Bundle branches

Bundle 1's branch follows step 7's naming and creation rules.
Later bundles take the same name with their index appended, so bundle 2 of `feat/onc-5-add-webhooks` is `feat/onc-5-add-webhooks-2`.
Create each of those from the previous bundle's branch at the moment that bundle starts, not up front.
Give every one of them the same already-exists guard bundle 1 has: check out a bundle branch that already exists rather than creating it, and create it only when it is genuinely absent.
Genuinely absent means absent from the local repository and from the remote both, and also that the bundle's entry in the `Bundles` section carries no `- Review:` line of any kind, the pending marker included.
When a bundle's entry carries one of those lines and its branch is absent from both, do not create the branch: some run already committed on it, and recreating the name would produce an empty branch that silently drops that bundle's commits.
Stay on the highest bundle branch at or below that one that still exists, and let the run reach the per-bundle routine for that bundle, which records what it can learn about that bundle's review and then holds on the missing branch.
Stay rather than stop: the branch this run is on exists, so the routine's bookkeeping commit can be written and pushed on it, where branch k offers no write path.

## Step 8: proposing a split

Propose a split only when both conditions hold: the breakdown has five or more units of work, and at least one valid cut point exists.
A cut point is valid only where the planned units up to it form a self-contained change: the units after it build on the units before it and not the reverse, and the earlier units together deliver something that stands on its own rather than half of one thing.
Judge that from the plan alone, since nothing is built yet at this point.
When no valid cut point exists, proceed as a single review and say so rather than forcing a boundary.

When both conditions hold, shape the bundles as contiguous runs of the planned order from step 8.
Produce at most three bundles, each holding at least two units, so five units yield at most two bundles and six is the smallest breakdown that can yield three.
Exceed the cap only when the user asked for a specific larger split; never exceed it on the heuristic's own judgment.

Then present the proposed split before anything is written to the tracker: the bundles, which units fall in each, and the resolved forge's `stackedReviews` value with what it means for this run.
This is a skip-list stop per `../fathom-shared/approval.md`, so `ask` mode waits for an answer and `auto` mode applies the split and reports it.

### Creating a confirmed stack

When a split was confirmed, take the same create-versus-adopt decision as step 8's single-review branches: create a sub-issue for each planned unit when the issue has no existing children, and adopt the existing children when it has them, skipping `createSubIssue` for each adopted one.
A split never changes whether the sub-issues already exist, so an issue that arrived with children never gets a duplicate set alongside them.
Create them strictly one at a time in the planned order, from the first unit to the last, rather than in whatever order the bundle records suggest.
Chain every task in the issue sequentially, so each task deps on its predecessor across bundle boundaries as well as within them, per the `createTask` row in `../fathom-shared/memory.md`.

With the plan document, write the `Bundles` section recording each bundle's index, branch, and sub-issue refs, and the `- Merge-closer: suppressed` line, both per `conventions.md`.
Write them at breakdown time, not when the first review opens.

## Step 10: bundles in the loop

Before the first pass, check the bundle step 7 recovered: when every task in that bundle is already closed and it still carries no recorded review, its per-bundle routine was interrupted.
Run that routine for that bundle now, and then, when a later bundle remains, move onto its branch under the already-exists guard above, exactly as the end of a pass would.
Decide that from the durable record rather than from what is claimable: the closed tasks live in the memory backend and the recorded reviews live in the plan document.
A run interrupted after every bundle's routine finished but before the issue's closing actions did leaves nothing claimable and makes no pass here; step 11 recovers that one.

When a pass closes the last task in its bundle, run the per-bundle routine below for that bundle before claiming again.
Then, when a later bundle remains, move onto the next bundle's branch under the already-exists guard above, creating it from this one only when it is absent and checking it out when it is not, and continue the loop on it.
Open each bundle's review as that bundle finishes, not after the loop drains.

## Step 11: the per-bundle routine

Step 10 runs this routine once per bundle as that bundle's last task closes, in place of step 11's single-review path.
For bundle k of N:

- Commit any leftover uncommitted change that belongs to this bundle's tasks, leaving unrelated working-tree edits alone rather than sweeping them into the review.
  A change left uncommitted here is absent from bundle k's review and lands in bundle k+1's instead.
- For every bundle after the first, run the lower-bundle check below.
- Then reconcile bundle k's closed tasks against the commits on its branch, over that bundle's own range as it stands after the steps above, per the per-bundle rule in `conventions.md`; stop and do not open this bundle's review when they disagree.
  Keep this order, because the leftover commit and the lower-bundle check's rebase both change the range the reconciliation counts.
- Call `resolveBase` on bundle k's base: the resolved base branch for bundle 1, and branch k-1 for every later bundle unless the lower-bundle check moved it to the resolved base branch.
- Write `- Review: pending (bundle k/N)` beneath that bundle's line in the `Bundles` section, and commit it on branch k, before calling `openReview` for this bundle.
  Stage only the plan document, by explicit path, list what is staged and confirm it carries only that one added marker line, and word it as bookkeeping rather than as a task: `chore(<issue-ref>): mark bundle k review pending`, naming no task in the body.
  Make it before branch k reaches the remote, so that whichever push puts the branch there carries it: the push below on an ordinary adapter, or the push `openReview` owns under `pushesForYou`.
- Push branch k, unless the adapter declares `pushesForYou`.
- Call `openReview` with branch k, that base, a title naming the bundle, and a body built per the stack rules in `conventions.md`.
  Pass the previous bundle's review id as `dependsOn` for every bundle after the first, and omit it for bundle 1.
- Branch on what `openReview` returned before doing anything with it.
  When it is the manual-handoff result, there is no review object for this bundle: do not call `publishReview`, do not write a `- Review: <id> <url>` record for it, and stop and report the handoff for bundle k rather than continuing to bundle k+1.
  Remove the pending marker as part of stopping, committing that removal as the same kind of bookkeeping commit, since this result says outright that no review object was created.
  The manual tier never proposes a split, so treat this branch as a guard against an adapter that returns the handoff result from a non-manual tier, and say that plainly when it fires.
- Call `publishReview` with the returned id.
- Replace that bundle's pending marker with `- Review: <id> <url> (bundle k/N)` in the `Bundles` section.
- Commit and push that recorded line immediately, on branch k, before moving to bundle k+1's branch or doing anything else.
  Stage only the plan document, by explicit path, and word it as bookkeeping rather than as a task: `chore(<issue-ref>): record bundle k review id`, naming no task in the body.
  Confirm the staged diff carries only the one `- Review:` line that replaced the marker.
  When it carries an unrelated edit as well, unstage that edit and leave it in the working tree for the run's final closing commit to carry.
- Apply `inReview` when bundle 1's review publishes, and never again for the later bundles.
  A resumed run that reuses bundle 1's existing review publishes nothing, so apply `inReview` there instead, whenever the tracker still shows the issue in an earlier phase; read that phase from the tracker rather than assuming the interrupted run applied it.
  That is a phase update and nothing more: reusing a review never reopens it and never calls `publishReview` on it again.
  Later bundles never apply the phase, whether their reviews were newly opened or reused.

### The lower-bundle check

A reviewer can merge the bundles below bundle k before bundle k's review opens, often while a run is interrupted partway through bundle k.
A review against branch k-1 would then merge into a branch that never reaches the base, so bundle k targets the base instead.

Skip this check, keeping branch k-1 as bundle k's base, when the resolved forge declares `reviewLookup: none`, since it cannot report a review's state.
Otherwise call `getReviewState` on the recorded review of every bundle from 1 to k-1, and act on the results:
- When any reports `unknown` or `closed-unmerged`, stop and hold naming those bundles, since bundle k's base cannot be settled.
- When bundle k-1 reports `open`, change nothing: branch k-1 stays bundle k's base.
- When bundle k-1 reports `merged` but a bundle below it does not, stop and hold naming them, since bundle k-1 merged into a branch that has not reached the base.
- When every bundle from 1 to k-1 reports `merged`, move bundle k onto the base with the steps below.

Before those steps, stop and hold when bundle k's entry already carries a `- Review: pending (bundle k/N)` marker, since a review opened for it may target branch k-1.
Say that the user should retarget that review to the base and record it as a full `- Review:` line, or close it and replace the marker with `- Review: none confirmed (bundle k/N)`, as the pending-marker lookup describes.

1. Fetch the resolved base branch.
   The cut point is the parent of the oldest commit in `origin/<base>..<branch k>` whose `Task:` trailer names one of bundle k's tasks.
   When the cut point is already an ancestor of `origin/<base>`, as after a merge commit or a rebase an earlier run finished, skip to the last step below.
2. Rebase only bundle k's own commits: `git rebase --autostash --onto origin/<base> <cut point> <branch k>`.
   `--autostash` carries uncommitted edits across the rebase, such as checklist mode's pending hash edit, since git refuses to rebase a dirty tree.
   When the rebase conflicts, note the conflicting files from `git ls-files -u`, run `git rebase --abort`, then stop and hold naming them.
3. The rebase rewrote bundle k's commits, so re-record every closed task in bundle k.
   Find each one's new commit with `git log --format=%h --grep "^Task: <id>$" origin/<base>..<branch k>`, and call `close` on that task again with that commit.
   Commit the task-state files this changed as `chore(<issue-ref>): re-record bundle k commits after rebase`, naming no task in the body and staging them by explicit path as step 11's closing commit does; on beads that means the three export steps in One database per repository in `../fathom-shared/memory/beads.md`.
   When branch k is already on the remote, push it with `--force-with-lease`, never a bare force push.
   When the lease is rejected, stop and hold: another commit reached that branch, and overwriting it discards someone's work.
4. Use the resolved base branch as bundle k's base for the rest of this routine: the reconciliation range, `resolveBase`, `openReview`, and the pending-marker lookup.

### Reusing a bundle's review

Skip the `openReview` call for a bundle whose review already exists and reuse that review, so a resumed run never opens a second review for a bundle that has one.
Decide that from that bundle's entry in the `Bundles` section and from nothing else.
Exactly one of four cases holds for bundle k.

- The entry carries a full `- Review: <id> <url> (bundle k/N)` line: the review exists and is already recorded.
  Reuse it, open nothing, change no record, and skip the lookup below entirely.
- The entry carries no line at all: no run has ever reached this bundle's `openReview` call, because the marker is committed before the call.
  Write the marker as the routine above says, open the review, and skip the lookup below entirely.
  This is the ordinary case on a first run through a stack.
- The entry carries a `- Review: pending (bundle k/N)` marker and no id: a review may or may not exist.
  Work through the lookup below, and hold wherever it cannot settle the question.
- The entry carries a `- Review: none confirmed (bundle k/N)` line: the user already confirmed for an earlier hold that no review exists.
  Replace that line with the pending marker as the routine above says, open the review, and skip the lookup below entirely.

Do not read the remote's branch list as evidence in any of these four cases, and never treat a branch the remote does not carry as proof that no review was opened from it.
A forge retains a review after its head branch is deleted, so branch absence cannot tell a bundle no run ever reached from one whose review was opened and whose branch later went away.

### A missing bundle branch

When branch k is absent from both the local repository and the remote, run only the lookup below and the recording it calls for, then stop and hold for bundle k.
Skip the leftover-commit step, the lower-bundle check, the reconciliation, and `openReview`, since all four read or write a branch that is not there.
Say that branch k is missing, that bundle k's commits cannot be located from it, and that this run recorded what it learned about that bundle's review and changed nothing else.
Say what unblocks it: restore branch k from a clone, a reflog, or a branch above it that still carries those commits, or decide that bundle's work is gone and rebuild it.
Both are the user's judgment call.
Never recreate branch k from branch k-1 as the remedy, since the name would come back empty and this bundle's commits would be silently absent from its review.

### The pending-marker lookup

Call `findReviewByBranch` for branch k, then keep only the candidates whose base is exactly the base `resolveBase` returned for this bundle.
Bundle branches chain, so a head branch can carry a review opened against a different base than this bundle now targets; matching the exact head and base pair keeps this bundle's commits out of that review.

When exactly one candidate survives that filter, that review belongs to this bundle.
Backfill its id and URL into the record first, as described below, then call `getReviewState` on that id to decide whether this run may continue.
The state decides continuation and never whether the record is written: a merged, closed, or undetermined review whose id goes unrecorded is a bundle the sweep reads as missing a record forever.

- On `open`, carry on with the rest of the routine for bundle k.
- On `merged`, carry on the same way.
- On `closed-unmerged`, stop and hold after recording, naming bundle k and saying its review was abandoned, since whether to retry, rescope, or drop that work is the user's judgment.
- On `unknown`, stop and hold after recording.

When more than one candidate survives, stop and hold naming them.

When no candidate matches, do not call `openReview`: stop and hold, since a bounded lookup that finds nothing does not prove that nothing exists, per `../fathom-shared/forges.md`.
Say in the hold report that bundle k carries a pending marker, that a review may already exist for this bundle, that this run could not find one and cannot prove there is none, and that the user should confirm whether a review exists for that bundle before the run continues.
Say with it what unblocks the next run.
When the user confirms that no review exists, replace bundle k's marker with a `- Review: none confirmed (bundle k/N)` line, committed and pushed on the branch this run is on as the same bookkeeping commit the backfill makes, and the next run opens that bundle's review.
When the user instead finds a review that does exist, record it as a full `- Review: <id> <url> (bundle k/N)` line the same way, and the next run reuses it.
Either confirmation belongs in the `Bundles` section; a confirmation given only in conversation leaves the record unchanged and every later run holds identically.

When the resolved adapter omits `findReviewByBranch`, no lookup is possible: say once that the forge cannot be asked, then hold on exactly those same terms.

The backfill: replace the pending marker with a `- Review: <id> <url> (bundle k/N)` line built from the id and URL on the matched candidate record.
Commit it exactly as the routine's recording step does: stage only the plan document, by explicit path, verify the staged diff carries only that one replaced line before committing, and word it as the same bookkeeping commit.
Push it on the branch this run is on before anything else, including before any hold the state above calls for, then continue or hold as that state directs.
A matched candidate is always backfilled, whatever its state.
Both recovery records, the backfilled line and the `none confirmed` line, go on the branch this run is on rather than on branch k, because branch k may have been deleted or reused; the sweep still reads them, per `conventions.md`.
A bundle whose entry already carries its full `- Review:` line never reaches the lookup, so it changes nothing and makes no commit.

### After bundle N

After bundle N's routine completes, close the parent task in the memory backend (a no-op for the checklist adapter, whose file is the parent record).
Then continue into step 11's closing actions, which run once for the issue rather than once per bundle, so the finalization line is written and pushed before the loop drains.
The final closing commit goes on branch N, the stack tip, because that branch contains every bundle's history and is the only one whose review shows the completed task state.
Say plainly at handoff that the issue's record carries `- Merge-closer: suppressed`, so the merge-closer Action will take no action for it however its bundles merge.
On a repository that relies on that Action for closure, a stacked issue reaches `done` only when a later run's done-on-merge sweep sees every bundle merged, where a single-review issue still closes on merge without one.
