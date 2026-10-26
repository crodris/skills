# Resuming a run

Each section covers state that only an earlier, interrupted run leaves behind.
Read the section a step in `SKILL.md` names when the run finds that state.
Step numbers refer to the procedure in `SKILL.md`.

## Paused base update

Step 4 found a merge or a rebase that an earlier hold paused.
- Read the branch from `git branch --show-current` mid-merge, or from the `head-name` file mid-rebase, since a paused rebase detaches HEAD.
  Use that branch as the current branch name in step 4.
- Run no branch switch, no fetch-and-update, and never `git merge --quit`, which drops the merge's second parent, until Finishing a base update below finishes or holds the update.
- At step 7, create no branch, and go straight to Finishing a base update.

## Existing branch

Step 7 found that the issue branch already exists.
- When it is checked out in another worktree, as a held issue from `fan-out.md` leaves it, continue the run from inside that worktree.
- When the base branch has moved on since, bring the branch up to date before implementing, and report that you did.
- When the update stops on a conflict, follow Finishing a base update below.

## Finishing a base update

1. When `git ls-files -u` lists this issue's beads file `.beads/<ISSUE-REF>.jsonl`, resolve that file first as `memory/beads.md` says, even when other files conflict too.
   A run that stopped inside that recipe leaves the file conflicted.
2. When `git ls-files -u` lists any other file, or `git diff --cached --check` reports a leftover conflict marker, hold as described below.
3. Otherwise finish a paused update with `git -c core.editor=true merge --continue` or `git -c core.editor=true rebase --continue`.
   When any `--continue`, including the one in the beads recipe, stops the rebase on its next commit, start again from item 1.

Hold on a conflict exactly as on a test failure that cannot be fixed:
- Leave the update paused where git stopped it, mid-merge or mid-rebase, so the user resolves it in place.
- Keep the work, leave the task in progress, and report each conflicting file with what this branch and the base each changed in it.
- Call the sides "this branch" and "the base", since a rebase swaps which one git calls ours.
- Ask the user to `git add` each file once it is resolved, and leave the choice of resolution to them, recommending neither side.
- When you say what keeping a side would mean, such as which planned tasks it would already cover, say it for both sides or for neither.
- Never resolve a conflict by discarding either side's changes.

## Manual tier on a stack

Step 7 found a `Bundles` section while the forge resolved the manual tier, so the tier changed after earlier bundles' reviews opened.
Leave those reviews alone, and hand the remaining bundles off manually.
Say that the tier changed between runs, so the stack is now half automated and half manual.
Say also that no later run will move this issue to `done` on its own, since the manual tier cannot observe a review, so closing the issue is now a manual step.

## Existing breakdown

Step 8 found that this issue already has a breakdown.
- Read the split, the bundles, and their branches from the plan document, and decide none of them again.
- When the plan document carries a `Bundles` section but step 7 recovered no stack, go back to step 7 and recover it before implementing anything.
- Call `init` for the issue, so the memory backend's checks still run and a run resumed on another machine imports the issue's tasks before step 10 reads them.
- On beads, run the sync steps in the Dolt remote section of `memory/beads.md`, which retries a sync that an interrupted run never finished.

Then go to step 9.

## Interrupted finalization

Step 11 found a stacked issue with no `- Finalization: complete` line, so an earlier run stopped before its closing actions finished.
Decide what remains from the durable record, not from what is claimable:
- The plan document's `Bundles` section says which bundles carry a recorded review.
- The memory backend says whether the parent task is still open.
- The tracker says the issue's phase and whether the completion comment is already on it.
- Branch N says whether the final closing commit exists and is pushed.

Every bundle has its review by now, since step 10 recovers a bundle whose tasks are all closed and whose review is missing.
Never call `openReview` for a bundle that carries a recorded review; reuse it as `stack.md`'s per-bundle routine says.

Then do only what the record shows is missing:
- Close the parent task only when the backend shows it open.
- Apply `inReview` only when the tracker shows the issue in an earlier phase.
- Post the completion comment only when `listComments` shows the issue does not carry one.
  When the tracker cannot list comments, post it and say that it may be a duplicate.
- Make and push the final closing commit, with the finalization line, only when branch N lacks the completed task state, as step 11's closing actions say.

When the record shows every one of these already done, write the finalization line, commit and push it as bookkeeping, and say that the issue was already finished and only its record was missing.
Then go to step 12.
