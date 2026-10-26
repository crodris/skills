# Task memory

Task state lives in exactly one durable backend per issue, resolved by probing.

## The contract

Use exactly these eight operations, which each adapter implements.
Every operation reads and claims only the issue being worked, so a run never implements another issue's task or closes the wrong sub-issue.

| Operation | Purpose |
| --- | --- |
| `init(issueRef)` | Prepare the backend for this issue. A repeated call never duplicates, rolls back, or drops tasks, though it may update them from a newer committed copy. |
| `createTask(title, description, subIssueRef, deps)` | Create a task tagged with the issue ref and `subIssueRef`, and return its id. Only this operation sets `deps`, so create tasks in planned order and decide whether the issue is split before the first call. In a split issue every task deps on its predecessor, so a later bundle's task is never claimable while an earlier task is open. |
| `claimNext()` | Mark in progress and return the first open task whose deps are all closed, or null. When a task is already in progress from an interrupted run, return it instead. |
| `ready()` | Return the open tasks whose deps are all closed, in creation order, claiming none. |
| `claim(taskId)` | Mark one task from `ready()` in progress, so several can run at once. |
| `close(taskId)` | Mark a task done with its commit. On a task already done, replace the recorded commit. |
| `status()` | Return the open and done counts and the in-progress tasks. |
| `parentTask(issueRef)` | Create or fetch the issue's parent task. Its edges on the children are added once the children exist. |

## Resolution

Probe once per run, before any task-memory work, and never switch an issue's backend mid-issue.

1. When `.fathom/tasks/<ISSUE-REF>.md` exists, even with no task lines, use the checklist adapter, whatever beads state the repository has.
2. Otherwise take the base per Base branch resolution in `forges.md`, the same base the issue branch starts from, and fetch it as Base branch resolution in `forges.md` says when `origin/<base>` is missing or may be outdated.
   When `git cat-file -e origin/<base>:.beads/metadata.json` succeeds, run `bd where`, and use the beads adapter when it succeeds.
   When `bd where` fails, stop, show its error, and ask the user to install or upgrade beads or to continue on a machine where it succeeds.
   Never fall back to the checklist adapter then.
3. Otherwise use the checklist adapter.
   A repository adopts beads by initializing it by hand and merging that into the base, as Fathom's `execute/README.md` describes.

Do not ask the user to choose a backend.
State the resolved backend in the run summary when other open issues in the repository use the other one.

Another machine resumes only from committed and pushed state.
Resume from the working tree, since an in-progress marker may be uncommitted.

## Display overlay

When the agent has built-in task-list tools, mirror tasks into them for a live view.
Rebuild the overlay from the backend on every resume, and never read it as the source of truth.

## No dual truth

Task status lives only in the resolved backend.
The plan document at `.fathom/plans/<ISSUE-REF>.md`, per `conventions.md`, never carries status, and beads writes no file under `.fathom/tasks/`.

A file under `.fathom/` records the issue's branch, its review id once one exists, and its tracker URL, since the merge sweep and a merge-closer search that directory.
A stacked issue records each bundle's branch and review id in the plan document's `Bundles` section.
The plan document's `Branch` line always names bundle 1's branch, because the merge-closer Action matches that exact label.
