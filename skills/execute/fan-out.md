# Fan-out

Two ways `execute` runs work on subagents in parallel: several issues at once, and independent tasks inside one issue.
Both need an agent that can spawn background subagents; `../fathom-shared/agents.md` names the tool per agent.
Without one, run several issues one after another and every task through the ordinary loop, but still apply the recovery rule under Parallel tasks.

Both keep one rule: the parent run is the only writer of the tracker, the memory backend, `.fathom/`, and every branch it pushes.
A subagent writes only inside the worktree the parent made for it.

Task worktrees live under the repository's git directory, so they never show up as untracked files in any checkout.
Resolve that directory with `git rev-parse --git-common-dir` and put each worktree at `<that dir>/fathom/<name>`.
Install a new worktree's dependencies before dispatching into it: call the Skill tool with `worktree-setup` when it is installed, and otherwise run the install command the lockfile names.

## Several issues

Use this when the invocation names two or more issue refs or URLs.

1. Run steps 1 to 3 of the procedure once, in the parent: approval mode, preflight, the done-on-merge sweep, and the tracker profile.
   Every ref must belong to the tracker preflight verified; name any that do not and leave them for a separate invocation.
   First-run setup writes `.fathom/config.md` here, before any dispatch, so no subagent ever asks a setup question.
2. Give each issue its own worktree.
   When the issue's branch already exists and is checked out in another worktree, use that worktree.
   Otherwise fetch the resolved base and run `git worktree add --detach <that dir>/fathom/<ISSUE-REF> origin/<base>`, and let the run create or check out the issue's branch there at step 7.
3. Dispatch one background subagent per issue.
   Its brief carries pointers, not restated rules: this skill's `SKILL.md` path, the issue ref, the worktree path, and the resolved approval mode.
   Tell it to run this procedure for that one issue from inside its worktree, and to skip step 2's sweep and step 3's one-time offers, because the parent already ran both.
   Any other question the procedure would ask the user becomes a hold: it stops and reports the question.
4. Report as each subagent finishes, without waiting for the rest: the step 12 summary for a finished issue, the hold and its question for a held one.
   Remove the worktree of every issue whose run finished without a hold, which keeps its branch; keep a held issue's worktree, since the held work lives there.

Each issue already owns its branch, its plan document, its checklist file, and its tracker issue, so nothing else needs coordinating.
On beads, every worktree shares one database and every call is scoped to its issue's label, as `../fathom-shared/memory/beads.md` describes.

## Parallel tasks

Use this at the start of every pass through step 10's loop on an issue that was not split into a stack.
A stack chains every task onto its predecessor, so its frontier never holds more than one task and this section never applies to it.

Recover every in-progress task first, on every pass, before anything is claimed.
When its branch `<issue branch>--task-<id>` carries a commit beyond the issue branch, integrate that commit as in step 3 below.
Otherwise dispatch it again in a parallel pass, reusing its worktree when one is left; in a sequential pass `claimNext` resumes it.

The frontier is what `ready()` returns: this issue's open tasks whose deps are all closed.
Run the pass in parallel when the frontier holds two or more tasks whose files do not overlap, judged from the plan document's codebase context and each sub-issue's description.
Otherwise run the ordinary sequential pass.

1. Pick the wave: the frontier tasks whose files overlap neither each other nor a task still in flight.
   Leave the rest for a later pass.
2. For each task in the wave, in the parent:
   - Call `claim(taskId)`, and move its sub-issue to `inProgress` exactly as the ordinary pass does.
   - Run `git worktree add -b <issue branch>--task-<id> <that dir>/fathom/<ISSUE-REF>-<id> HEAD`.
   - Dispatch a background implementer subagent with pointers: the plan document path, the task id and title, the sub-issue ref, and the worktree path.
     Brief it to implement only that unit, following the plan; run the typecheck and that unit's test files; make one commit on its branch; and report the commit hash, or the failure it could not fix.
     It leaves `.fathom/`, `.beads/`, the tracker, and every push to the parent.
3. Integrate each implementer's commit as it reports, in the order they finish.
   - Run `git cherry-pick --no-commit <hash>` in the parent's checkout.
     When it conflicts, run `git cherry-pick --abort` and hold, naming the conflicting files, as a base-branch conflict does.
   - Continue with the ordinary pass from its verification step: run the typecheck and tests, commit per `../fathom-shared/conventions.md`, record the hash, close the task and its sub-issue, and print the progress line.
     The last task is the one whose close leaves no other task open or in flight, whatever its planned position, and it runs the full suite.
     The commit on the issue branch is the parent's own, so one commit per task and the reconciliation in `conventions.md` hold unchanged.
   - Remove that task's worktree and delete its task branch.
   - Read `ready()` again and dispatch any new task whose files overlap nothing still in flight.
4. When an implementer reports a failure it could not fix, let the others in flight finish and integrate them, then hold as the ordinary pass does.
   Keep the failed task's worktree, since its partial work lives there.

The parallel pass ends when nothing is in flight, and step 10's loop then continues from its next pass.
