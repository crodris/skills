# beads adapter

This adapter runs the `bd` CLI once `memory.md`'s resolution has chosen beads.
Its flags were verified against `bd version 1.3.1` with `bd --help` and `bd <subcommand> --help`.
When a `bd` upgrade rejects a flag used here, re-run those help commands and update this mapping before relying on it.

## One database per repository

`bd` keeps one embedded Dolt database per repository in `.beads/embeddeddolt/`, which `.beads/.gitignore` excludes.
The main checkout and every linked worktree share it, and concurrent writes are safe.
Let `bd` find it, and never pass `--db`, which this storage mode ignores silently.
Never prefix a `bd` command with an environment variable assignment, since permission rules do not match such a command.
Run every command in this file from the root of the checkout the run is on.

Every task row carries the label `<issueRef>`, and every read passes `-l "<issueRef>"`, since the database holds every issue's rows.

Each issue's task state travels in git as `.beads/<issueRef>.jsonl`.
Write and stage it with these three export steps, each as its own command:
1. `bd export -o <main checkout>.fathom/<issueRef>-export.jsonl`
2. `sed -n '/"labels":\[[^]]*"<issueRef>"[],]/w .beads/<issueRef>.jsonl' <main checkout>.fathom/<issueRef>-export.jsonl`
3. `git add .beads/<issueRef>.jsonl`

`bd export` writes every issue, so it goes to a scratch file in the sibling directory `../fan-out.md` names, and `sed` keeps this issue's lines.
Let `bd` and `sed` write their files, since a shell redirect or a `jq` filter with a `$` variable needs approval.
Leave the scratch file in place.

Nothing exports or imports automatically.
Never stage or edit `.beads/issues.jsonl`, which nothing writes any more and `bd bootstrap` imports as history.

## Dolt remote

A repository has a Dolt remote when `bd dolt remote list` names one; it prints "No remotes configured." otherwise.
With no remote, skip this section.

`init` pulls before any task read or write.
The sync steps are these two commands, each on its own:
1. `bd dolt pull`
2. `bd dolt push`, only when the pull exited 0.

`bd dolt push` sends the whole database, every issue and any schema migration, so never push without a pull that just succeeded.
`init`'s pull stops the run on failure, as its row in Operation mapping says.
When a sync step fails, report bd's error, name "Execute stops because `bd dolt pull` failed or a schema migration ran" in Fathom's `execute/README.md`, and continue the run.
`.beads/<issueRef>.jsonl` on the branch still holds the tasks, and the next sync sends them.
Never pass `--force` or `--strategy`, never run `bd dolt commit`, and never move or re-bootstrap the database to make a sync succeed, since each decides whose history wins and that is the user's call.

## Operation mapping

| Contract operation | beads CLI mapping |
| --- | --- |
| `init(issueRef)` | 1. When `grep -q '"backend"' .beads/metadata.json` fails, stop and point the user to "From bd 0.x to bd 1.x" in Fathom's `execute/README.md`; never migrate it yourself. 2. Run `mkdir -p <main checkout>.fathom`, taking `<main checkout>` from the first line of `git worktree list --porcelain`. 3. Run `bd bootstrap`, which creates the database on a fresh clone and prints "Nothing to do" otherwise. 4. Run `bd config get issue_prefix --json` and stop when its `value` is empty, pointing the user to "Execute stops because the beads database has no issue prefix" in that README; never move `.beads/embeddeddolt` yourself. 5. When the repository has a Dolt remote, run `bd dolt pull`. Stop when it exits nonzero or when any `bd` command in this `init` printed `schema migration`: show bd's output, say the fix decides whose history wins so Fathom will not commit or force anything, and point the user to "Execute stops because `bd dolt pull` failed or a schema migration ran". 6. When `.beads/<issueRef>.jsonl` exists, run `bd import .beads/<issueRef>.jsonl`. |
| `createTask(title, description, subIssueRef, deps)` | Run one `bd create --title '<title>' -d '<description>' -l "<issueRef>" --external-ref "<subIssueRef>" --deps "<comma-separated blocker ids>" --silent` and return its one output line as the task id. Omit `--external-ref` when no `subIssueRef` was passed and `--deps` when `deps` is empty. Use the title as passed, single-quoted with each `'` written as `'\''`, and the description the same way, since tracker text can hold `$(...)`. |
| `listTasks()` | Run `bd list -l "<issueRef>" --type task --all --limit 0 --json` and return each task's `id` and `external_ref`. |
| `claimNext()` | Run `bd list -l "<issueRef>" --type task --status in_progress --limit 0 --json`, and when it returns a task, return the oldest without claiming it. Otherwise run `bd ready -l "<issueRef>" --type task --sort oldest --claim --json` and return element 0's id, or null for `[]`. |
| `ready()` | Run `bd ready -l "<issueRef>" --type task --sort oldest --limit 0 --json` and return its tasks. |
| `claim(taskId)` | Run `bd update <taskId> --claim`. |
| `close(taskId)` | Run `bd close <taskId> -r "commit <short hash>"`, per the commit-verification rules in `../conventions.md`. When the task is already closed, run `bd reopen <taskId>` first. |
| `status()` | Run `bd count -l "<issueRef>" --type task --by-status --json` and read `.groups[]`, counting a missing group as 0. Open is the sum of `open`, `blocked`, `deferred`, and `in_progress`; done is `closed`. List in-progress tasks with `claimNext`'s first `bd list` call. |
| `parentTask(issueRef)` | Run `bd list -l "<issueRef>" --type epic --all --limit 0 --json` and reuse the epic it returns. Otherwise run `bd create "<issueRef>" --type epic --external-ref "<issueRef>" -l "<issueRef>" -p 1 --silent` and capture the id. After every child exists, run `bd dep add <parentId> <childId>` per child. Never add an edge from a child to the parent, which deadlocks both. |

## Notes

Move tasks only through `open`, `in_progress`, and `closed`, and never set `blocked` or `deferred`.
Take claim decisions from `bd ready`, since an unmet dependency leaves a task's stored status at `open`.
`createTask` is one `bd create` call because separate writes can fail apart and leave an orphan task the retry cannot recognize.
Pass `--json` on every read, `--limit 0` on `bd list`, and `--all` where closed rows count.
Record the hash with `bd close -r`, never `bd update --notes`, which replaces existing notes.
`bd import` replaces a row only when the file's copy has a newer `updated_at`, so repeating an import never rolls tasks back.

## Repository hygiene

Leave ignore rules to `.beads/.gitignore` and add none at the repository root.
Track `.beads/metadata.json` and `.beads/config.yaml`.
Stage named paths only, per `../conventions.md`.
When runtime files are already tracked, untrack them once with `git rm --cached` and commit that removal.

Only stacked branches of the same issue can conflict on `.beads/<issueRef>.jsonl`.
A run resolves that file itself during a branch update, even when other files conflict too, and never hand-merges its lines:
1. Run `init` steps 1 through 5, with their stops.
   A resumed run reaches this in execute's step 7, before step 8 calls `init`.
2. `git checkout --ours -- .beads/<issueRef>.jsonl`, then `bd import .beads/<issueRef>.jsonl`.
3. `git checkout --theirs -- .beads/<issueRef>.jsonl`, then `bd import .beads/<issueRef>.jsonl`.
4. Re-export and stage the file with the three export steps, then finish the update unless another file is still conflicted, in which case execute's step 7 holds.

Commit the issue's file with the breakdown commit and with each task's commit, staged by the three export steps.
Without it in the breakdown commit, a run resumed before the first task commit has no tasks to import.
