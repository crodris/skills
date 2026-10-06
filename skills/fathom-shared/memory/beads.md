# beads adapter

This adapter is backed by the `bd` CLI, a local dependency-aware task tracker that stores its state in `.beads/` inside the consumer's repo.
Only use this adapter once `memory.md`'s resolution procedure has already chosen beads for this run.
The flags below were verified against `bd version 0.49.0` (Homebrew) using `bd --help` and `bd <subcommand> --help`.
When a later `bd` upgrade renames or removes a flag used here, re-run those same help commands and update this mapping before trusting it again.

## One database per issue

Run every `bd` command for an issue as `bd --no-daemon --db <checkout>/.beads/<issueRef>.db-fathom <subcommand>`.
`<checkout>` is the absolute path of the checkout the run is on, a fan-out worktree included.
Every command in this file takes these two flags, though the commands below omit them for brevity.

That database holds the rows of the export the issue branch started from, plus this issue's own rows.
After each change, `bd` writes it to the export beside it, `<checkout>/.beads/issues.jsonl`, so the export carries no other issue's rows into this issue's review.
The default database is shared by every branch and every linked worktree of the repository, and its automatic export always writes the main checkout's JSONL (verified on 0.49.0).
That export carries every issue the database has seen, including ones whose reviews are still open.

The `.db-fathom` suffix keeps these files out of the user's own `bd` use.
Plain `bd` and `bd daemon start` look for `.beads/*.db`, and a second `.db` file there makes the daemon refuse to start with "Multiple database files found" (verified on 0.49.0).
The `.gitignore` beads creates already excludes `*.db?*`, so these files never reach a commit.

`--no-daemon` is required alongside `--db`, since a daemon serving the default database answers a call for another database with a "database mismatch" error.
A database that does not exist yet is created, and the export imported into it, by the first `bd` call that names it, which is how a run resumed on another machine recovers its tasks.

Treat the working tree's `.beads/issues.jsonl` as output only, since a daemon can rewrite it with every issue's rows at any time.
Outside the conflict recipe below, whose own checkouts take the restore's place, restore the committed export with `git checkout HEAD -- .beads/issues.jsonl` at these points, whenever `git cat-file -e HEAD:.beads/issues.jsonl` shows that HEAD tracks it:
- Before the first `bd` call that names this issue's database, since that call imports the file on its own.
- Before every `bd import`.
- Before any git command that switches or updates the branch, such as step 7's base update in `../../execute/SKILL.md` or a stack restack, since git refuses to overwrite a working copy a daemon changed.

The issue's database already holds every change this run made, so a restore loses nothing.

When a `bd` call refuses with "Database out of sync with JSONL", restore the committed export, run `bd import -i <checkout>/.beads/issues.jsonl`, and retry the call.
This happens after the branch is updated from its base, after an explicit `bd export`, and after a daemon rewrites the working copy.
The import keeps whichever copy of a row is newer, so it never rolls back this issue's tasks.
Run that import in place of the `bd sync --import-only` the error suggests, which was verified only against the default database.

A beads daemon already running for the repository keeps running beside the run and acts on the main checkout on its own.
It exports the default database into `.beads/issues.jsonl`, and it can run `git pull` on the checked-out branch (both seen on 0.49.0).
Leave it running, since it may serve the user's own beads work.
At `init`, run `bd daemon status --json`, which takes neither per-issue flag.
When it reports `"status": "running"`, say in the run summary that a beads daemon is running for this repository, and that `bd daemon start --local` keeps it without its git sync.

## Operation mapping

| Contract operation | beads CLI mapping |
| --- | --- |
| `init(issueRef)` | First run the daemon check that the One database per issue section describes. Then do nothing more when this issue's database already exists. When `.beads/` is absent from the checkout, run `bd init`, passing a short prefix of three or four characters abbreviated from the repository name and the flag that skips git hook installation. Take the repository name from the main checkout's directory, since a fan-out worktree's directory is named after the issue. The short prefix keeps task ids readable, and skipping hooks avoids installing pre-commit and post-merge hooks that block branch switching and interfere with unrelated commits. When HEAD tracks `.beads/issues.jsonl`, restore it as the One database per issue section describes, then run `bd import -i <checkout>/.beads/issues.jsonl`, which creates this issue's database from the committed export. When `.beads/` exists but HEAD tracks no export, run `bd config set issue_prefix <prefix>` with the `issue-prefix` that `.beads/config.yaml` sets, or the abbreviation above when it sets none, since a database created without an export has no prefix and refuses every `bd create`. Never run `bd init` when `.beads/` already exists, since it either aborts or creates a stray default `beads.db` beside this issue's database. |
| `createTask(title, description, subIssueRef, deps)` | Run one `bd create "<title>" -d "<description>" -l "<issueRef>" --external-ref "<subIssueRef>" --deps "<comma-separated blocker ids>" --silent` and capture the single line of output as the new task id. Do it in that one call rather than as a create followed by separate writes, for the durability reason in the notes below. Tagging the task with the issue ref lets every task for one issue be listed directly with `bd list -l "<issueRef>"` instead of matching on titles, and `--silent` makes `bd create` print only the issue id, which this adapter always needs for its return value. Omit `--external-ref` entirely when no `subIssueRef` was passed, and omit `--deps` entirely when `deps` is empty, rather than passing an empty value to either. Each id in `--deps` makes the new task depend on that blocker, so it stays excluded from `claimNext` until the blocker closes. Use the title and description exactly as passed in; embedding the issue ref into the title (the `<issueRef>: <task title>` naming convention) is the caller's responsibility, not this adapter's. |
| `claimNext()` | Run `bd ready -l "<issueRef>" --type task --limit 50 --json` to get this issue's tasks that have no open blockers. The label filter is not optional: `bd ready` without it returns ready work from the whole repository, so an unscoped call will hand back another issue's task and the loop will implement it on this issue's branch and close the wrong sub-issue. The explicit limit matters too, since `bd ready` defaults to showing only ten. Note that `bd ready` includes tasks already `in_progress`, so inspect status before claiming: when a returned task is already `in_progress` from an interrupted run, resume that task and do not call `--claim` on it, because `bd update --claim` fails when the task is already claimed. Otherwise take the oldest still-open task and run `bd update <id> --claim` to set it to `in_progress` atomically, then return that id. Return null only when the scoped result contains no open and no in-progress task. |
| `ready()` | Run the same scoped `bd ready` call as `claimNext` and return the tasks whose status is `open`, oldest first. Claim nothing. |
| `claim(taskId)` | Run `bd update <taskId> --claim`. |
| `close(taskId)` | Run `bd close <taskId>` to mark the task done. Record the short hash of the commit that implemented the task as well, per the commit-verification rules in `../conventions.md`; attach it with `bd update <taskId> --notes` when that flag exists on the installed version, and otherwise state the hash in the progress line. Verify the flag with `bd update --help` rather than assuming it. |
| `status()` | Run `bd count -l "<issueRef>" --type task --by-status --json` to get counts for this issue's tasks only, grouped by status; the label filter is required here for the same reason as `claimNext`, since an unscoped count reports the whole repository. Compute the open count as the sum of the `open`, `blocked`, `deferred`, and `in_progress` buckets, never the raw `open` bucket alone: a task with an open dependency reports as `blocked`, the claimed task reports as `in_progress`, and dropping either would undercount pending work; this matches the checklist adapter, whose open count also includes the in-progress line. Compute the done count as the `closed` bucket. Run `bd list -l "<issueRef>" --type task --status in_progress --json` to list the in-progress tasks; when it returns no rows, report that none is in progress. |
| `parentTask(issueRef)` | Fetch first: run `bd list -l "<issueRef>" --type epic --json` and reuse the returned epic's id when one exists. Create it otherwise: `bd create "<issueRef>" --type epic --external-ref "<issueRef>" -l "<issueRef>" -p 1 --silent`, capturing the printed id. Do not attempt to add child dependency edges here; at the time `parentTask` runs the children do not exist yet. After every child task has been created, add one edge per child with `bd dep add <parentId> <childId>` so the parent depends on all of them and cannot close first. Never add the reverse edge, from a child to the parent, which would deadlock both. |

## Notes

Beads exposes five status values: `open`, `in_progress`, `blocked`, `deferred`, and `closed`.
The memory contract only ever needs this adapter to move a task through `open` then `in_progress` then `closed`.
Never set `blocked` or `deferred` directly.
Beads does not rewrite a task's stored status when a dependency is added; an unmet dependency keeps the task at `open` while `bd ready` and `bd blocked` compute blocking from the dependency graph at query time.
That is why claim decisions must come from `bd ready` rather than from a status filter.
`bd update <id> --claim` resolves the current actor from `--actor`, then `$BD_ACTOR`, then git's `user.name`, then `$USER`, in that order.
Do not pass a separate `--assignee` flag unless multiple agents share one checkout and need distinct identities.
Prefer `--json` on every read command (`bd list`, `bd count`) when parsing output programmatically, since plain output is meant for a human terminal and can change formatting across versions.
`createTask` is one `bd create` call rather than a create followed by `bd update --external-ref` and one `bd dep add` per blocker, because those are three writes that can fail apart.
A run interrupted between them leaves a task carrying no external ref and no dependency edges, and nothing on that orphan identifies which sub-issue it belongs to, so the retry cannot recognize it and creates a second task for the same sub-issue.
One call either produces a complete task or produces nothing, which makes a retry safe.
The flags were verified equivalent on 0.49.0: a task created with `--deps <blockerId>` is excluded from `bd ready` until that blocker closes and appears once it does, exactly as one given the same edge by `bd dep add`.
`parentTask` still adds its edges with `bd dep add` afterwards, which is unavoidable, since the children do not exist when the parent is created.

## Repository hygiene

The beads tooling handles its own ignore rules and merge setup during `init`; verify rather than duplicate.

After `init`, confirm two files exist and keep them: `.beads/.gitignore`, which excludes the database, write-ahead and shared-memory files, daemon runtime files, merge artifacts, and per-machine sync state, and `.gitattributes`, which registers the beads merge driver for the JSONL export.
Do not add a second copy of those rules at the repository root.
A duplicate block drifts from what the tooling actually ignores, and one earlier hand-written version wrongly ignored `metadata.json`, which beads intends to be tracked alongside the JSONL exports.

Ignore rules cannot rescue a file that is already tracked.
The dirty-working-tree and failed-branch-switch problems that look like ignore-rule gaps are almost always caused by blanket staging having committed runtime files before any rule existed.
Follow the staging rules in `../conventions.md`: stage named paths only, never `git add -A` or `git add .`.
When runtime files are already tracked in a repository, stop staging them and untrack them once with an explicit cached removal, then commit that removal.

Long-lived parallel branches that both write task state will conflict on the JSONL export.
The merge driver registered by `.gitattributes` is what resolves those conflicts, so keep that file when beads creates it.
A fresh clone has no merge driver configured, so the export can still conflict when the branch is updated from its base.
A conflict in `.beads/issues.jsonl` alone is the one branch-update conflict a run resolves itself, since the file is generated from task state.
Never hand-merge the JSON lines; run these in order:
1. `git checkout --ours -- .beads/issues.jsonl`, then `bd import -i <checkout>/.beads/issues.jsonl`.
2. `git checkout --theirs -- .beads/issues.jsonl`, then `bd import -i <checkout>/.beads/issues.jsonl`.
3. Stage the export as the commit rules below describe, and finish the update.

Importing both sides gives the database this issue's rows and the base's, in a merge or a rebase alike, even when the database did not exist yet.
A rebase swaps which side `--ours` names, so the recipe never depends on it.

A conflict in any other file still holds, as execute's step 7 says.

Commit the JSONL export with each task's commit, not only at the end of the run.
The database itself is ignored by design, so an export left uncommitted means a task closed on this machine is invisible to any other clone, which breaks resume on a different machine.
Stage the export with one command, `bd export -o <checkout>/.beads/issues.jsonl && git add .beads/issues.jsonl`, so the staged file holds this issue's database, and a daemon can only rewrite it in the moment between the two commands.
