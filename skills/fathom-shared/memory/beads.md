# beads adapter

This adapter is backed by the `bd` CLI, a local dependency-aware task tracker that stores its state in `.beads/` inside the consumer's repo.
Only use this adapter once `memory.md`'s resolution procedure has already chosen beads for this run.
The flags below were verified against `bd version 1.3.1` (Homebrew) using `bd --help` and `bd <subcommand> --help`.
When a later `bd` upgrade renames or removes a flag used here, re-run those same help commands and update this mapping before trusting it again.

## One database per repository

`bd` keeps one embedded Dolt database per repository in `.beads/embeddeddolt/`, which `.beads/.gitignore` excludes from git.
Linked git worktrees share the main checkout's database automatically, so the main checkout and every fan-out worktree read and write the same rows.
Concurrent writes from several worktrees are safe.
Let `bd` find that database on its own, and never pass `--db`, which this storage mode ignores without an error.
Never prefix a `bd` command with an environment variable assignment, since the command permission rules do not match a command that starts with one.

Every task row this adapter writes carries the label `<issueRef>`, and every read passes `-l "<issueRef>"`.
The label is what keeps issues apart, since the database holds every issue's rows at once.

Every command in this file runs from the root of the checkout the run is on, a fan-out worktree included.

Each issue's task state travels in git as its own file, `.beads/<issueRef>.jsonl`.
Write and stage the file with these three export steps, each run as its own command:
1. `bd export -o <main checkout>.fathom/<issueRef>-export.jsonl`
2. `sed -n '/"labels":\[[^]]*"<issueRef>"[],]/w .beads/<issueRef>.jsonl' <main checkout>.fathom/<issueRef>-export.jsonl`
3. `git add .beads/<issueRef>.jsonl`

Run them as three separate commands, since a restricted allowlist refuses a whole chained command when any part of it is not allowed.
`bd export` writes every issue in the database and has no label filter, so it writes to a scratch file in `<main checkout>.fathom/`, the sibling directory `../../execute/fan-out.md` names, and `sed` copies only the lines whose labels include `<issueRef>`.
`bd` and `sed` write their own files, since a shell redirect such as `>` needs the user's approval in an agent session, and so does a `jq` filter that uses a `$` variable.
`bd export` does not create a missing directory, which is why `init` creates `<main checkout>.fathom`, taking `<main checkout>` from the first line of `git worktree list --porcelain`.
Leave the scratch file in place; the next export overwrites it.

Nothing exports or imports automatically, so a file under `.beads/` changes only when this adapter writes it.
Nothing writes `.beads/issues.jsonl` any more.
A repository that tracks it keeps it as history, which `bd bootstrap` imports into a new database, so never stage or edit it.
Parallel issues never share a file, so only stacked branches of the same issue can conflict on one, as Repository hygiene below describes.

## Dolt remote

A repository can share its database through a Dolt remote, which is how teammates who run `bd` without Fathom see the same rows.
The repository has one when `bd dolt remote list` names a remote, and that command prints "No remotes configured." when it has none.
With no remote, skip every step in this section.

`init` pulls before the run reads or writes any task, as its mapping row says.
The sync steps send the database to the remote.
Run these two commands, each on its own:
1. `bd dolt pull`
2. `bd dolt push`, only when the pull exited 0.

`bd dolt push` sends the whole database, which carries every issue's rows and any schema migration a `bd` upgrade applied locally.
Never push without a pull that succeeded just before it.
After such an upgrade, the pull fails with "local changes would be stomped by merge".
`bd dolt push` alone was seen to send the migration to the remote.
When either command fails, report bd's error, name "Execute stops because `bd dolt pull` failed or a schema migration ran" in Fathom's `docs/fathom.md`, and continue the run.
`.beads/<issueRef>.jsonl` on the branch still holds the tasks, and the next sync sends them.

Never pass `--force` or `--strategy`, never run `bd dolt commit`, and never move or re-bootstrap the database to make a pull or push succeed.
Each of those decides whose history wins, so it is the user's decision.

The per-issue files stay the branch-scoped record that resume and the merge sweep read.
The database and the file converge, per the `bd import` note below.

## Operation mapping

| Contract operation | beads CLI mapping |
| --- | --- |
| `init(issueRef)` | When `grep -q '"backend"' .beads/metadata.json` fails, stop and tell the user that this workspace predates bd 1.x and needs the "From bd 0.x to bd 1.x" upgrade steps in Fathom's `docs/fathom.md`. Never migrate it yourself. Otherwise run `mkdir -p <main checkout>.fathom`, then `bd bootstrap`, which creates the database and imports the tracked `.beads/issues.jsonl` on a fresh clone and prints "Nothing to do" when the database already exists. Then run `bd config get issue_prefix --json` before any other `bd` command. It exits 0 whether or not a prefix is set, so read the `value` it prints, and stop when `value` is empty. `bd where` and `bd bootstrap` both pass on a database with no prefix, but every `createTask` would fail. Tell the user to follow "Execute stops because the beads database has no issue prefix" in Fathom's `docs/fathom.md`, and never move `.beads/embeddeddolt` yourself. Then, when the repository has a Dolt remote, as Dolt remote above defines, run `bd dolt pull`, and stop when it exits nonzero or when any `bd` command in this `init` printed a line containing `schema migration`. On that stop, show bd's output, say that the fix decides whose history wins, so it is the user's to choose and Fathom will not commit or force anything, and tell the user to follow "Execute stops because `bd dolt pull` failed or a schema migration ran" in Fathom's `docs/fathom.md`. Then, when `.beads/<issueRef>.jsonl` exists, run `bd import .beads/<issueRef>.jsonl`, so a run resumed on another machine or after the local database was lost recovers its tasks. Repeating the import is safe, per the `bd import` note below. |
| `createTask(title, description, subIssueRef, deps)` | Run one `bd create "<title>" -d "<description>" -l "<issueRef>" --external-ref "<subIssueRef>" --deps "<comma-separated blocker ids>" --silent` and capture the single line of output as the new task id. Do it in that one call rather than as a create followed by separate writes, for the durability reason in the notes below. Tagging the task with the issue ref lets every task for one issue be listed directly with `bd list -l "<issueRef>"` instead of matching on titles, and `--silent` makes `bd create` print only the issue id, which this adapter always needs for its return value. Omit `--external-ref` entirely when no `subIssueRef` was passed, and omit `--deps` entirely when `deps` is empty, rather than passing an empty value to either. Each id in `--deps` makes the new task depend on that blocker, so it stays excluded from `claimNext` until the blocker closes. Use the title and description exactly as passed in; embedding the issue ref into the title (the `<issueRef>: <task title>` naming convention) is the caller's responsibility, not this adapter's. |
| `claimNext()` | First run `bd list -l "<issueRef>" --type task --status in_progress --limit 0 --json`. When it returns a task, an interrupted run left it in progress, so return the oldest one to be resumed without claiming it. Otherwise run `bd ready -l "<issueRef>" --type task --sort oldest --claim --json`, which atomically claims this issue's oldest task with no open blockers and returns it as a one-element array. Return element 0's id, or null when the result is `[]`. The label filter is not optional on either call: without it `bd` reads the whole repository, so an unscoped call will hand back or claim another issue's task, and the loop will implement it on this issue's branch and close the wrong sub-issue. |
| `ready()` | Run `bd ready -l "<issueRef>" --type task --sort oldest --limit 0 --json` and return its tasks, which are this issue's open tasks with no open blockers, oldest first. Claim nothing. |
| `claim(taskId)` | Run `bd update <taskId> --claim`, which is idempotent for the same actor. |
| `close(taskId)` | Run `bd close <taskId> -r "commit <short hash>"`, which marks the task done and records the hash of the commit that implemented it in the same write, per the commit-verification rules in `../conventions.md`. When the task is already closed, run `bd reopen <taskId>` first, since `bd close` on a closed task keeps its old reason. |
| `status()` | Run `bd count -l "<issueRef>" --type task --by-status --json`; the label filter is required here for the same reason as `claimNext`, since an unscoped count reports the whole repository. It returns `{"groups":[{"count":1,"group":"in_progress"},...],"total":N}` and omits every empty group, so read `.groups[]` and count a missing group as 0. Compute the open count as the sum of the `open`, `blocked`, `deferred`, and `in_progress` groups, never the `open` group alone: a task with an open dependency can report as `blocked`, the claimed task reports as `in_progress`, and dropping either would undercount pending work; this matches the checklist adapter, whose open count also includes the in-progress line. Compute the done count as the `closed` group. List the in-progress tasks with the same `bd list` call `claimNext` makes first; when it returns no rows, report that none is in progress. |
| `parentTask(issueRef)` | Fetch first: run `bd list -l "<issueRef>" --type epic --all --limit 0 --json` and reuse the returned epic's id when one exists. Create it otherwise: `bd create "<issueRef>" --type epic --external-ref "<issueRef>" -l "<issueRef>" -p 1 --silent`, capturing the printed id. Do not attempt to add child dependency edges here; at the time `parentTask` runs the children do not exist yet. After every child task has been created, add one edge per child with `bd dep add <parentId> <childId>` so the parent depends on all of them and cannot close first. Never add the reverse edge, from a child to the parent, which would deadlock both. |

## Notes

Beads exposes five status values: `open`, `in_progress`, `blocked`, `deferred`, and `closed`.
The memory contract only ever needs this adapter to move a task through `open` then `in_progress` then `closed`.
Never set `blocked` or `deferred` directly.
Beads does not rewrite a task's stored status when a dependency is added; an unmet dependency keeps the task at `open` while `bd ready` and `bd blocked` compute blocking from the dependency graph at query time.
That is why claim decisions must come from `bd ready` rather than from a status filter.
The `in_progress` filter in `claimNext` only finds a task to resume and never claims one.
`bd ready` no longer returns tasks already in progress, which is why `claimNext` looks for them first.
`bd update <id> --claim` resolves the current actor from `--actor`, then `$BD_ACTOR`, then git's `user.name`, then `$USER`, in that order.
Do not pass a separate `--assignee` flag unless multiple agents share one checkout and need distinct identities.
Prefer `--json` on every read command (`bd list`, `bd ready`, `bd count`) when parsing output programmatically, since plain output is meant for a human terminal and can change formatting across versions.
`bd list` shows only 50 rows and hides closed issues by default, which is why the calls above pass `--limit 0`, and `--all` where closed rows count.
Record the commit hash with `bd close -r` rather than `bd update --notes`, which replaces any notes the task already has.
`createTask` is one `bd create` call rather than a create followed by `bd update --external-ref` and one `bd dep add` per blocker, because those are three writes that can fail apart.
A run interrupted between them leaves a task carrying no external ref and no dependency edges, and nothing on that orphan identifies which sub-issue it belongs to, so the retry cannot recognize it and creates a second task for the same sub-issue.
One call either produces a complete task or produces nothing, which makes a retry safe.
The flags were verified equivalent on 0.49.0, and `bd create` is unchanged on 1.3.1: a task created with `--deps <blockerId>` is excluded from `bd ready` until that blocker closes and appears once it does, exactly as one given the same edge by `bd dep add`.
`parentTask` still adds its edges with `bd dep add` afterwards, which is unavoidable, since the children do not exist when the parent is created.
`bd import` upserts each row and replaces a local row only when the file's copy has a strictly newer `updated_at`.
It reports older rows as `stale_skipped_ids` and merges labels, dependencies, and comments, so importing an issue's file never rolls back that issue's tasks.

## Repository hygiene

The beads tooling writes its own ignore rules in `.beads/.gitignore`, which excludes the embedded database and the other per-machine runtime files.
Do not add a second copy of those rules at the repository root.
A duplicate block drifts from what the tooling actually ignores, and one earlier hand-written version wrongly ignored `metadata.json`, which beads intends to be tracked alongside `.beads/config.yaml`.
bd 1.x registers no merge driver, so it writes no `.gitattributes` entry, and a `merge=beads` line left by bd 0.x is removed by the upgrade steps that `init` points to.

Ignore rules cannot rescue a file that is already tracked.
The dirty-working-tree and failed-branch-switch problems that look like ignore-rule gaps are almost always caused by blanket staging having committed runtime files before any rule existed.
Follow the staging rules in `../conventions.md`: stage named paths only, never `git add -A` or `git add .`.
When runtime files are already tracked in a repository, stop staging them and untrack them once with an explicit cached removal, then commit that removal.

Parallel issues each write their own `.beads/<issueRef>.jsonl`, so they never conflict on task state.
Only stacked branches of the same issue can conflict on that file, when one bundle's branch is updated from another.
The issue's file is the one conflicted file a run resolves itself during a branch update, since it is generated from task state, and it does so even when other files conflict too.
Never hand-merge the JSON lines; run these in order:
1. Run the steps of `init` that come before its `bd import`, with the same stops: the metadata check, `mkdir -p <main checkout>.fathom`, `bd bootstrap`, the `issue_prefix` probe, and the Dolt pull.
   A resumed run reaches this recipe in execute's step 7, before step 8 calls `init`.
   On a fresh clone, a `bd import` with no database fails and still creates `.beads/embeddeddolt` with no prefix, which `bd bootstrap` then leaves as it is.
2. `git checkout --ours -- .beads/<issueRef>.jsonl`, then `bd import .beads/<issueRef>.jsonl`.
3. `git checkout --theirs -- .beads/<issueRef>.jsonl`, then `bd import .beads/<issueRef>.jsonl`.
4. Re-export and stage the file with the three export steps in One database per repository, then finish the update unless another file is still conflicted, in which case execute's step 7 holds.

Importing both sides gives the database the rows from both branches, in a merge or a rebase alike.
A rebase swaps which side `--ours` names, so the recipe never depends on it.

A conflict in any other file still holds, as execute's step 7 says.

Commit the issue's file with the breakdown commit and with each task's commit, not only at the end of the run.
Without it in the breakdown commit, a run resumed before its first task commit finds the plan document, skips the breakdown, and has no tasks to import.
The database itself is ignored by design, so a file left uncommitted means a task closed on this machine is invisible to any other clone, which breaks resume on a different machine.
Stage it with the three export steps in One database per repository, so the staged file always holds this issue's current rows.
