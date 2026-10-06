---
name: execute
description: This skill should be used when the user asks to "execute ONC-5", "run execute on this issue", "work on an issue", "start an issue", "implement this Asana/Linear issue", "take this issue to a PR", "take this issue to review", pastes an Asana task URL to build, or names a Linear issue key like ONC-5, or several at once like "execute ONC-5 ONC-6". Also use when the user says something like "the PR for <issue> merged", "the review for <issue> merged", "clean up merged issues", "the PR was closed", "the change landed", "that PR got abandoned", "that review was abandoned", or "close out merged work", to run the done-on-merge sweep on demand. Drives an existing tracker issue from breakdown through implementation to an open code review with resumable task tracking, on GitHub or any other forge with an adapter.
version: 1.0.0
---

# Execute

## Absolute boundary

Treat the connected tracker MCP as the only channel for tracker work.
When it is absent or disabled, refuse the request and stop.
Say which MCP is missing and that the user must connect it before this skill can continue.
Refuse even when a bypass looks possible and helpful.
Do not read or search for credentials in files, environment variables, or token caches.
Do not call tracker HTTP APIs.
Do not edit MCP or agent configuration.
Treat a disabled server as a deliberate user decision, a stop condition, never an obstacle to route around.

This skill drives one tracker issue through a single resumable autonomous pass, from breakdown through implementation to an open code review; several issues named at once each get that pass on a subagent, per `fan-out.md`.
There is no separate start step and finish step; re-invoke this same skill on the same issue to resume wherever the last run left off.
Every run begins by reading durable state from the repository and the tracker, not from anything remembered between invocations.

## Operating principles

- After the first-run tracker profile is confirmed, proceed without further mid-run confirmation; only stop when this procedure or `approval.md` says to stop.
- The memory backend is the source of truth for task state; state flows one way from it to the tracker, never the reverse.

## Read first

Before doing any tracker or memory work, read:

These paths are relative to the directory containing this SKILL.md file, not the current workspace, and they all point into the fathom-shared skill installed next to this one.
When `../fathom-shared/` does not exist there, stop before anything else and give its install command for the user to run, matching how this skill was installed; never run it yourself.
That is `npx skills@latest add crodris/skills -s fathom-shared -g` for a global install, without `-g` for a project install, with the same `-a <agent>` flag the install used, such as `-a kiro-cli` on Kiro, and `/plugin install fathom@crodris` again for a Claude Code plugin install.

- `../fathom-shared/trackers.md` for the tracker contract, phase names, and first-run profile setup.
- `../fathom-shared/forges.md` for the forge contract, adapter resolution, the capability tiers, and base-branch resolution.
- `../fathom-shared/memory.md` for the memory contract and backend resolution rules.
- `../fathom-shared/agents.md` for the per-agent notes that apply to whichever agent is running this skill.
- `../fathom-shared/conventions.md` for staging safety, commit messages, the plan document, and progress reporting.
- `../fathom-shared/approval.md` for the two approval modes, and for the stops that hold in both.

If any of these files cannot be found and read, stop immediately and report which paths were tried - never improvise their contracts from memory or proceed without them.

## Procedure

1. Resolve the approval mode per `../fathom-shared/approval.md` and state it, then run preflight verification per `../fathom-shared/trackers.md` before any other tracker step, inferring the target tracker by that section's precedence.
   Stop here, following that section's instructions, when the tracker's MCP does not verify.
   A forge that does not verify is not a stop: it selects a capability tier per `../fathom-shared/forges.md`; state the resolved tier before continuing.
   When a resumed run resolves the manual tier on an issue whose earlier bundles already have open reviews, leave those reviews alone and hand the remaining bundles off manually, saying that the tier changed between runs so the stack is now half automated and half manual.
   Say with it that no later run will move this issue to `done` on its own, because the manual tier cannot observe what happened to a review, so closing the issue is now a manual step.
2. Run the done-on-merge sweep per `../fathom-shared/trackers.md`, including its collection of a stack's records from every bundle branch and its ordered cases.
   When the sweep's partial-progress case decides a stacked issue, run the restack check in `stack.md` in this skill's folder, on a cleanup-phrase run too.
   When the invocation itself was a cleanup phrase, run only this sweep and that restack check, report what they found, then stop; do not continue into the rest of this procedure.
   Treat any claim about a review's fate as a cleanup phrase, whether it says merged, closed, abandoned, landed, or shipped, and whether it names an issue or asks to clean up whatever is outstanding.
   Never act on the claim itself: confirm each referenced review's real state through `getReviewState` first, then apply the merged path or the closed-without-merging path accordingly, and say plainly when the confirmed state differs from what the user described.
   When the resolved forge declares `reviewLookup: none`, neither the claim nor the sweep can be checked: say so once and act on nothing, closing no issue on the strength of an unverifiable claim.
3. Resolve which tracker owns this issue and which memory backend owns its task state, following `trackers.md` and `memory.md`, including `memory.md`'s stop when the repo holds beads state but beads is unavailable.
   Load the existing `.fathom/config.md` tracker profile, or run first-run setup when none exists; either way, run the tracker adapter's profile-load checks and honor any one-time offers they define.
4. When the invocation names two or more issues, read `fan-out.md` in this skill's folder and follow its several-issues section instead of the rest of this procedure.
   Before reading the branch name, check whether this checkout holds a base update paused by an earlier hold: `git rev-parse -q --verify MERGE_HEAD` succeeds mid-merge, and the directory `git rev-parse --git-path rebase-merge` or `git rev-parse --git-path rebase-apply` names exists mid-rebase.
   When one is paused, read the branch from `git branch --show-current` mid-merge, or from the `head-name` file in that rebase directory mid-rebase, since a paused rebase detaches HEAD.
   Then run no switch, no fetch-and-update, and never `git merge --quit` until step 7's resume rule finishes or holds the update, since quitting drops the merge's second parent.
   Then determine the issue ref from the invocation argument, a pasted issue URL, or the current branch name, which for a paused update is the branch read above, in that order of preference; when the argument and the branch name refer to different issues, stop and ask the user which one to use.
5. Call `getIssue` for that ref and save its title, description, type, URL, and existing children for the rest of this run.
   Make this call even when this session just created the issue, as a scaffold handoff does, since the run works from what the tracker stored, which can differ from the draft that created it.
   When the issue is already in the `done` phase or marked complete, do not start work: say so, report what the sweep found for it, and ask whether to reopen it or pick a different issue.
6. Search the codebase and read the files that look relevant to this issue, noting existing patterns to follow during implementation.
7. Ensure the branch this run implements on exists, and continue on that one branch until step 10 moves a stack to its next bundle.
   Read this issue's plan document before creating anything, when one already exists.
   When it carries a `Bundles` section, this issue was already split: read `stack.md` in this skill's folder and follow its step 7 section, which picks the branch and recovers the stack.
   Otherwise this is a first run with no plan document yet, or a single-review issue, and the branch is the issue branch named below.

   Name a branch that must be created from the issue type (`feat/` for a feature, `fix/` for a bug, `chore/` for a chore, `docs/` for docs, `feat/` by default) followed by the issue ref, cased as the tracker adapter says, and a short title slug; skip creation when a matching branch already exists.
   When that branch is checked out in another worktree, as a held issue from `fan-out.md` leaves it, continue the run from inside that worktree.
   Resolve the base branch per the base-branch rules in `../fathom-shared/forges.md`, then fetch it and create the new branch from the fetched remote copy with `--no-track`, not from a local copy that may be behind.
   Without `--no-track`, git sets the new branch to track the base, so a plain `git push` would push to the base branch.
   When the branch already exists and the base branch has moved on since, bring it up to date before implementing, and report that you did.
   When the update conflicts in the beads export, resolve that file first as `../fathom-shared/memory/beads.md` says, even when other files conflict too.
   When any other file is still conflicted, stop and hold exactly as an unfixable test failure would, and leave the update paused where git stopped it, mid-merge or mid-rebase, so the user resolves it in place.
   Keep the work, leave the task in progress, and report each conflicting file with what this branch and the base each changed in it.
   Name the sides "this branch" and "the base", since a rebase swaps which one git calls ours.
   Ask the user to `git add` each file once it is resolved, and leave the choice of resolution to them, recommending neither side.
   Never resolve a conflict by discarding either side's changes.
   When step 4 finds an update paused, hold again while `git ls-files -u` lists a conflicted file or `git diff --cached --check` reports a leftover conflict marker.
   Otherwise finish it with `git -c core.editor=true merge --continue` or `git -c core.editor=true rebase --continue`, and hold the same way when the rebase stops on its next commit.
   On a stack these rules describe bundle 1's branch, and `stack.md` names and creates the later bundles' branches.
8. Ensure the breakdown exists.
   - Skip the rest of this step when a breakdown already exists for this issue; a resumed run reads the split, the bundles, and their branches out of the plan document instead of deciding any of them again.
     When that plan document carries a `Bundles` section but step 7 recovered no stack, go back to step 7 and recover it before implementing anything.
   - Plan the units of work before writing anything to the tracker or the memory backend.
     When the issue has no existing children, plan three to seven units of work, each sized so it can be implemented and verified on its own, and hold that plan rather than creating anything from it yet.
     When the issue already has children, call `listSubIssues` to adopt them instead of inventing a new breakdown, which reads the tracker without writing to it.
     Make these reads even right after a scaffold handoff, for the reason step 5 gives.
     Call `getIssue` on each adopted child and read the `Blocked by:` line that scaffold ends its description with from that response, since `listSubIssues` returns no description and a list tool that does can cut one short.
     Order the children by those lines, so every blocker comes before what it blocks.
     Break ties, and order children whose line is missing or reads `none`, by creation order: ascending Linear keys, or Asana's subtask order under the parent, which scaffold fills in creation order; never the order a Linear list call returns.
     Children caught in a cycle also take their creation-order position, and the run says so.
     Either way the units are ordered, and that order is the creation order below and the order any bundle boundary follows; the `deps` below name only real prerequisites, except on a stack, which chains every task.
   - Decide whether this issue produces one review or a stack, from those planned units and before anything is written to the tracker.
     Never consider a split when the resolved forge tier is the manual tier.
     In that case, when the breakdown has five or more units, say the split was not offered because the tier cannot create reviews; below five units say nothing about it.
     Read the profile's `stacking` field per `../fathom-shared/approval.md`; treat an absent field as `never`, and stop considering a split immediately when it reads `never`, whether it was written or absent.
     When it reads `propose`, read `stack.md` in this skill's folder and follow its step 8 section, which decides whether to propose a split and runs the proposal stop.
     Without a confirmed split, the issue produces a single review.
   - Call `init` for the issue, then call `parentTask` for it, once the split question is settled.
     These are the first writes this step makes.
   - Create the sub-issues and their tasks next, passing each task's final `deps` to `createTask` itself, since no operation in `../fathom-shared/memory.md` adds deps to a task that already exists.
     When no split was confirmed and the issue has no existing children, for each planned unit call `createSubIssue` first, then call `createTask` with the newly created sub-issue's ref as `subIssueRef`, then write the returned task id back onto that sub-issue so the link reads both ways, setting `deps` to the ids of the tasks it builds on, so a unit that builds on nothing gets no deps.
     When no split was confirmed and the issue already had children, for each adopted sub-issue still call `createTask`, passing that sub-issue's existing ref as `subIssueRef` and skipping `createSubIssue` since the sub-issue already exists, then write the returned task id back onto that sub-issue the same way, and setting `deps` to the tasks of the sibling sub-issues its `Blocked by:` line names.
     A child whose line reads `none` gets no deps; a child with no line at all deps on the task created just before it, since nobody stated its blockers.
     A dep can only name a task that already exists, so a blocker caught in a cycle is replaced by a dep on the task created just before.
     Real deps rather than one chain are what let independent tasks run in parallel in step 10.
     Both branches create one sub-issue and its task at a time.
     When a split was confirmed, create them as `stack.md`'s step 8 section says.
   - After every child task exists, add the parent's dependency edge on each child, so the parent cannot close before its children.
   - Whether the sub-issues were newly created or adopted, write the plan document described in `conventions.md` and commit it with the breakdown.
     A confirmed split adds the `Bundles` section and the `Merge-closer` line that `stack.md` describes.
   - Write `.fathom/tasks/<ISSUE-REF>.md` only when the resolved backend is the checklist adapter.
9. Call `updateState` to move the issue to the `inProgress` phase.
10. Run the implementation loop until `claimNext` reports nothing claimable.
    On a stacked issue, run the check in `stack.md`'s step 10 section before the first pass.
    On an issue not split into a stack, read `fan-out.md` in this skill's folder before the first pass and apply its parallel-tasks section at the start of every pass; its recovery rule applies even when the running agent cannot spawn subagents.
    Each pass through the loop does the following, in order.
    - Call `claimNext`, and record the claim in the memory backend's own format at claim time.
    - Move the claimed task's linked sub-issue to the `inProgress` phase, subject to the adapter's own rules for sub-issues; the Asana adapter degrades this to a no-op on subtasks, so read its subtask section rather than assuming a state change happens.
      Never redirect a sub-issue transition onto the main issue.
    - Implement that one unit of work, following the codebase patterns found in step 6.
    - Run the typecheck, when the project has one, and the test files covering that unit, not the full suite.
      On the last task of the issue, or of a bundle on a stack, run the typecheck and the full suite instead of the unit's test files, so a failure they find is fixed inside that task's commit or holds that task open.
      When the repository has no test framework, or the touched code has no tests, say so once and write a test for the unit using whatever the project already depends on, then treat that test as this task's verification.
      When the project genuinely cannot run tests, say so plainly in the progress line and in the review body rather than implying the work was verified.
    - On a passing run, commit the change with a message referencing the issue ref and the task, staged and worded per `conventions.md`.
    - Confirm the commit exists before closing anything, and record its short hash with the close per the commit-verification rules in `conventions.md`.
    - Close the task in the memory backend and move its sub-issue to `done`, again per the adapter's sub-issue rules, recording the close as it happens rather than summarizing at the end of the loop.
      A task is not closed until both its memory record and its sub-issue are closed; closing only the sub-issue leaves it claimable.
    - Print the per-task progress line from `conventions.md`.
    - On a stacked issue, when the closed task was the last one in its bundle, follow `stack.md`'s step 10 section before claiming again.
    - On a failure that cannot be fixed, stop and hold: keep the change, leave the task in progress, report the failure, and exit without continuing the loop.
      On a stacked issue, also name which bundles already have open reviews and which were never built.
    One commit per task, always, even when two tasks touch the same file.

11. Once `claimNext` returns none remaining, finish the issue.
    Read this issue's plan document before anything else in this step and look for the `- Finalization: complete` line described in `conventions.md`.
    When it is present, this issue is already finished: say so, change nothing else in this step, and go to step 12.
    The one exception is a line sitting on a commit that was never pushed; push that commit before reporting.
    When the line is absent, run the rest of this step.

    A single-review issue follows the single-review path below, then the closing actions at the end of this step.
    A stacked issue skips the single-review path entirely and goes straight to the closing actions, because step 10 already opened every one of its reviews through `stack.md`'s per-bundle routine.

    A run interrupted before that line was written arrives here with it absent, and recovering such a run is the only reason a stacked issue ever runs this step's body.
    Decide what remains from the durable record rather than from what is claimable: the plan document's `Bundles` section says which bundles carry a recorded review, the memory backend says whether the parent task is still open, the tracker says the issue's phase and whether the completion comment is already on it, and branch N says whether the final closing commit exists and is pushed.
    Then do only what that record shows is missing, and skip whatever it shows is already done.
    Never call `openReview` for a bundle that already carries a recorded review; reuse it, exactly as `stack.md`'s per-bundle routine says.
    A bundle whose tasks are all closed and whose review is missing is recovered in step 10 rather than here, before any claiming, so by the time this step runs every bundle has its review.
    Close the parent task only when the backend shows it open, apply `inReview` only when the tracker shows the issue in an earlier phase, post the completion comment only when `listComments` shows the issue does not already carry one, and make and push the final closing commit only when branch N does not already carry the completed task state.
    When the resolved tracker cannot list comments, post the comment and say that it may be a duplicate.
    When the record shows every one of those already done, write the finalization line described below, commit and push it as bookkeeping, and say that the issue was already finished and only its record was missing.

    The single-review path, for an issue that was not split into a stack:

    Commit any leftover uncommitted change that belongs to this issue's tasks, leaving unrelated working-tree edits alone rather than sweeping them into the review.
    Then run the commit reconciliation from `conventions.md` and stop if the task and commit counts disagree; run it after that commit, so the range it counts carries every commit this issue's tasks produced.
    Close the parent task in the memory backend (a no-op for the checklist adapter, whose file is the parent record).

    Then open the review through the forge contract in `../fathom-shared/forges.md`, never by invoking a forge CLI directly from this procedure.
    - Confirm the resolved base with `resolveBase` first, as the contract requires, before anything is created against it.
    - Push the branch, with `-u origin <branch>` when it has no upstream yet, unless the resolved adapter declares `pushesForYou`.
    - Call `openReview` with the branch, the resolved base, a title, and a body.
      Title it the way merged reviews are titled in the resolved base's `git log` (a squash subject, or a merge commit's title line), naming the outcome for the user: `perf(server): cut websocket frame size by 70%+ with gzipping` names the outcome, where `perf(server): negotiate permessage-deflate on the websocket` names only the mechanism.
      Open the body with the problem as the issue states it, then the fix in a sentence or two, then `Closes <ref>` for a Linear issue or the task's URL for an Asana task, the list of completed tasks, and a test plan.
    - Skip this when a review already exists for the branch, and reuse that one; resuming an issue must never open a second review.
    - Call `publishReview` with the returned id.
    - Record `- Review: <id> <url>` in this issue's file under `.fathom/`, alongside the existing `- PR:` line.
    - Call `updateState` to move the issue to the `inReview` phase.

    When `openReview` returns the manual-handoff result instead of an id, there is no review object: skip `publishReview`, record no review id, print the handoff.
    Still apply `inReview`, and say plainly that no later run will move this issue to `done` on its own because the forge cannot be observed, so closing it is now a manual step.

    Finally, post a completion comment on the issue, including the done-on-merge note from `asana.md` when the tracker is Asana, then write `- Finalization: complete` into this issue's plan document per `conventions.md`, and commit and push the task-state files this run changed as a final closing commit so the branch carries the completed state, staging them by explicit path per the staging rules in `conventions.md`: the beads JSONL export and `metadata.json` when beads is the backend, and this issue's files under `.fathom/`; never sweep `.beads/` or `.fathom/` as directories, since the beads database and runtime files must not ride into the review.
    Write that line last, after every other closing action has been taken; a line written earlier would make the check at the top of this step skip the rest of it forever.
    It rides this same closing commit.
    Push this closing commit with an ordinary `git push` of the branch even when the adapter declares `pushesForYou`, since that capability governs only the push that opens the review, per `../fathom-shared/forges.md`.
    On a stacked issue, `stack.md`'s after-bundle-N section says which branch carries this commit and what to say at handoff.
12. Report a final summary: the issue, the review URL when one was opened, every bundle's review URL in order when the issue was split into a stack, or the resolved tier when no review was opened, the tracker's current phase, and the task counts from `status()`.

## Display overlay

When the running agent exposes built-in task-list capabilities, mirror progress into them for a live view; follow the display-overlay rule in `memory.md` and never treat that view as authoritative.
