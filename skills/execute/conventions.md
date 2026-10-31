# Working conventions

## Staging safety

Never stage a file that could carry a secret: `.env` and every `.env.*` variant, any name containing `credential` or `secret`, keys such as `*.pem` and `*.key`, and stores such as `config/master.key` and `config/credentials.yml.enc`.
When a change requires one of those paths, stop and ask the user to stage it themselves.
Stage the files this task changed by path, never with `git add -A`, `git add .`, or `git add --all`.
Before committing, list what is staged and unstage any path that does not belong to the task.

## Commit messages

Use a conventional-commit subject scoped by the issue ref: `type(<issue-ref>): summary`.
Omit the scope only when the work has no issue.
Pick the one most specific type:

| Type | Use for |
| --- | --- |
| `feat` | new user-facing behavior |
| `fix` | a bug fix |
| `refactor` | restructuring with no behavior change |
| `test` | tests only |
| `docs` | documentation only |
| `chore` | build, tooling, dependencies, task-state bookkeeping |
| `perf` | a performance improvement |
| `style` | formatting or whitespace only |

Choose `feat` over `refactor` when any user-visible behavior changed.
Choose `fix` over `feat` when the change restores intended behavior.
Write the summary in lowercase imperative mood, under 72 characters, with no trailing period.
Name the task in the body as a `Task: <id>` line, with the id the memory backend returned.

## The plan document

At breakdown, write a plan for the issue at `.fathom/plans/<ISSUE-REF>.md`, and commit it before the first tracker write and again with the breakdown.
It carries structure a resumed run reads back, such as the branch, the review ids, and a stack's bundles, and never task status, which lives only in the memory backend.
Update it when something material changes.

Include these sections:

- **Issue.** The first line is the heading `# <ISSUE-REF>: <title>`, followed by `- Issue: <tracker url>`, `- Ref: <issue ref>`, and `- Branch: <branch>`, each on its own line.
  Use these labels exactly.
  The merge-closer Action matches the `Branch` line exactly and reads the tracker id only from a `Tracker`, `Issue`, or `Ref` line, so any other label makes it silently close nothing.
- **Issue description.** What the issue asks for, in your own words.
- **Codebase context.** The files and patterns this work touches, with paths.
- **Implementation approach.** How the change will be made, and what is out of scope.
- **Tasks.** The planned units of work in planned order, one line each: `- Unit <n>: <title> -> sub-issue: pending`.
  Replace `pending` with the sub-issue's ref as soon as it exists, using the ref `listSubIssues` or `createSubIssue` returned, since that ref is what matches a unit to its child and its task.
- **Bundles.** Only for an issue split into a stack.
  Write it when the split is confirmed, one line per bundle in stack order: `- Bundle <k>/<N>: <branch> - <sub-issue refs, comma separated>`.
  Until a sub-issue exists, its place in the list holds `unit <n>`, the number on its `- Unit` line.
  Every bundle line names its branch, since the sweep and a resumed run fetch each one and read the `- Review:` lines in its copy of this document.
  Beneath a bundle, write `- Review: pending (bundle k/N)` before calling `openReview` for it, and replace it with `- Review: <id> <url> (bundle k/N)` once the review exists.
  The pending marker names no id, so readers treat it as no record: the sweep leaves the issue undecided, and `execute` looks the review up rather than risk a duplicate.
  A bundle with no `- Review:` line never had a review attempted.
  When the lookup cannot settle whether a review exists, hold, report the marker, and ask the user.
  When the user confirms none exists, replace the marker with `- Review: none confirmed (bundle k/N)`, which readers also treat as no record, so the next run opens that review.
  The first `Bundles` section goes in the commit that records the planned units, and the breakdown commit carries its refs.
  Commit and push each `- Review:` line as a `chore` bookkeeping commit as soon as it is written, on the branch the run is on.
  That is the bundle's own branch, except when a recovery finds that branch deleted or reused and records the outcome on its current branch.
- **Merge-closer.** Only for an issue split into a stack: the line `- Merge-closer: suppressed`, written when the split is confirmed.
  The merge-closer Action skips an issue carrying it, so the sweep closes the issue once every bundle merges, instead of the Action closing it on the first.
- **Breakdown.** The line `- Breakdown: pending`, written with the planned units and removed in the breakdown commit.
  While it is there, the breakdown is unfinished, whatever else the document holds.
- **Finalization.** The line `- Finalization: complete`, written by the last of the issue's closing actions, so it rides the final closing commit.
  `execute` stops finalizing when the committed plan document carries it, as step 11 of `SKILL.md` says, so no closing action runs twice.
- **Testing strategy.** Which tests prove the work, and which could regress.
- **Notes.** Open questions, risks, and decisions.

## Commit verification

Record each task's close with the short hash of its implementing commit, read from the repository after committing.
On beads, record it as the close reason per `memory/beads.md`.
On the checklist, write the hash into the task's line after committing and let that edit ride the next commit that touches the file, never an amend, and state the hash in the progress line now.
When a backend cannot store the hash, state it in the progress line.
Never name a commit that does not exist in the log.

Reconcile before opening a review.
A task commit has a subject scoped to this issue's ref and implements a task.
A bookkeeping commit is typed `chore`, touches only records under `.fathom/` and, on beads, `.beads/<ISSUE-REF>.jsonl`, and names no task: the breakdown commit, every plan document commit, and every task-state commit.
Count task commits from the resolved base branch to the current head, and compare the count to the tasks closed for this issue.
Every recorded hash must name a commit inside that range, and no two closed tasks may share one.
When either check fails, stop and report it, and do not open the review.

On a stacked issue, reconcile each bundle before its review opens, over that bundle's own range against the tasks closed for that bundle only.
The range starts at the resolved base branch for bundle 1, and at branch k-1 for bundle k, or at the resolved base branch when the lower-bundle check in `stack.md` moved bundle k onto it.

## Review test plan

Give every review a test plan in this shape:

- The command a reviewer runs, in a fenced block.
- The observed result as counts, such as tests passed and the change in total.
- What the new tests cover, one line per behavior.
- What is deliberately not covered, and why.

Describe only what you ran, and say so here when the project cannot run tests.

## Progress reporting

After each task closes, print one line: the task's position in the queue, its id, the commit subject, the test result, and how many tasks remain.
State the resolved tracker and memory backend once at the start, and name the backend whenever it differs from the one other open issues here use.

## Review bodies in a stack

Only the last bundle's review body carries the issue-closing reference: `Closes <ref>` for a Linear issue, or the task's URL for an Asana task.
Earlier bundles link the issue with no closing keyword, since the tracker integration closes it on the first merge carrying the reference.

Every bundle's body also carries `Part <k> of <N>`, and every bundle after the first carries `Depends on <previous review url>`.
That line is prose for a human reviewer, and the forge records the dependency only through `openReview`.
