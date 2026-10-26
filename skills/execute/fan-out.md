# Fan-out

`execute` runs work on background subagents in two ways: several issues at once, and independent tasks inside one issue.
The agent file `agents.md` routes to says whether the running agent can spawn them and with which tool.
Without subagents, run several issues one after another and every task through the ordinary pass, and still apply the recovery rule under Parallel tasks when step 10 says to.

Put each fan-out worktree at `<main checkout>.fathom/<name>`, a sibling directory of the main checkout, reading the main checkout's absolute path from the first line of `git worktree list --porcelain`.
Remove only worktrees this run created, with `git worktree remove <path>` and no `--force`.
When git refuses, leave the worktree in place and report its path and the output of `git -C <path> status --porcelain`.
Remove that directory once its last worktree is gone.

Every subagent brief carries this shell-command rule, stated in full: run one command per call, reach the worktree through each tool's directory option or absolute paths instead of `cd` (`git -C <worktree>`, `npm --prefix <worktree>`), and read an id a command prints from its output instead of capturing it with `$(...)`.

## Several issues

Use this when the invocation names two or more issue refs or URLs.

1. Run steps 1 to 3 of the procedure once, in the parent: approval mode, preflight, the done-on-merge sweep, and the tracker profile.
   Name any ref that does not belong to the tracker preflight verified, and leave it for a separate invocation.
   Drop a ref that `getIssue` shows is a sub-issue of another named ref, and say that its parent's run covers it.
2. Give each issue its own worktree.
   Reuse the worktree that has the issue's branch checked out, or the one at `<main checkout>.fathom/<ISSUE-REF>`, which finds a held issue paused mid-rebase whose worktree is detached.
   Otherwise fetch the base as the Base branch resolution section of `forges.md` says, and run `git worktree add --detach <main checkout>.fathom/<ISSUE-REF> origin/<base>`; the run creates or checks out the issue's branch there at step 7.
   When `.fathom/config.md` is not on `origin/<base>`, copy the parent's file into the worktree, so the subagent loads the profile step 3 settled.
3. Dispatch one background subagent per issue.
   Its brief carries pointers: this skill's `SKILL.md` path, the issue ref, the worktree path, the resolved approval mode, the resolved `issue` and `task` models, and the shell-command rule.
   Tell it to run the procedure for that one issue against its worktree, skipping step 2's sweep and step 3's one-time offers, and to give its implementer subagents the `task` model without resolving models again.
   Once step 7 puts it on the issue branch, it installs the worktree's dependencies as the agent file `agents.md` routes to says.
   Any other question the procedure would ask the user becomes a hold: it stops and reports the question.
4. Report as each subagent finishes: the step 12 summary for a finished issue, or the hold and its question, with any refused tool calls the subagent named.
   Remove the worktree of every issue that finished without a hold, keeping its branch.
   Keep a held issue's worktree, and tell the user to answer by running `execute <ISSUE-REF>` from inside it.

## Parallel tasks

Apply this at the start of a pass when step 10 of `SKILL.md` says to.

The parent run is the only writer of the tracker, the memory backend, `.fathom/`, and the issue branch, and an implementer writes only inside its task worktree.
Each task dispatched here gets a task branch named `<issue branch>--task-<id>`, and the parent's commit that integrates it carries the `Task: <id>` line from `conventions.md`.

Recover first, before anything is claimed:
- For each task branch whose task is already closed, remove its worktree and delete the branch.
- For each in-progress task whose task branch carries a commit beyond the issue branch, integrate that commit as step 3 below does.
- On an agent with subagents, dispatch any other in-progress task again in a parallel pass, as step 2 does but without `claim`, and count it as in flight for the overlap check.
  Reuse its worktree when one is left, and add the worktree without `-b` when only its branch is.
  In a sequential pass, which is every pass on an agent without subagents, `claimNext` resumes it.

The frontier is what `ready()` returns: this issue's open tasks whose deps are all closed.
Run the pass in parallel when the frontier holds two or more tasks whose files do not overlap, judged from the plan document's codebase context and each sub-issue's description, or when a recovered task is still in flight.
Otherwise, with nothing in flight, run the ordinary sequential pass.

1. Pick the wave: the frontier tasks whose files overlap neither each other nor a task still in flight.
   Leave the rest for a later pass.
2. For each task in the wave, in the parent:
   - Call `claim(taskId)`, and move its sub-issue to `inProgress`.
   - Run `git worktree add -b <issue branch>--task-<id> <main checkout>.fathom/<ISSUE-REF>-<id> HEAD`, then install its dependencies as the agent file `agents.md` routes to says.
   - Dispatch a background implementer subagent with pointers: the plan document path, the task id and title, the sub-issue ref, the worktree path, and the shell-command rule.
     Brief it to implement only that unit; run the typecheck and that unit's test files; make one commit on its branch; and report the commit hash, or the failure it could not fix.
     It leaves `.fathom/`, `.beads/`, the tracker, and every push to the parent.
3. Integrate each implementer's commit as it reports, in the order they finish.
   - Run `git cherry-pick --no-commit <hash>` in the parent's checkout.
     When it conflicts, run `git reset --merge`, which keeps the checklist's unstaged markers, then remove its worktree, delete the task branch, and dispatch the task again from the new HEAD, as step 2 does but without `claim`.
     A task that conflicts a second time holds, naming the conflicting files, as a base-branch conflict does.
   - Continue with the ordinary pass from its verification step: run the typecheck and tests, commit per `conventions.md`, record the hash, close the task and its sub-issue, and print the progress line.
     The last task is the one whose close leaves no other task open or in flight, whatever its planned position, and it runs the full suite.
   - Remove that task's worktree and delete its task branch.
   - Read `ready()` again and dispatch any new task whose files overlap nothing still in flight.
4. When an implementer reports a failure it could not fix, let the others in flight finish and integrate them, then hold as the ordinary pass does.
   Keep the failed task's worktree.

The parallel pass ends when nothing is in flight, and step 10's loop then continues from its next pass.
