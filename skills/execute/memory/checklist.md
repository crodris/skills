# checklist adapter

This adapter keeps the issue's tasks in `.fathom/tasks/<ISSUE-REF>.md`, committed on the feature branch, once `memory.md`'s resolution has chosen the checklist.
The file is the issue's parent record and the only store for its task status, and it stays in the repository after the review merges.
Commit it with every change this adapter makes, except the in-progress marker and the hash append under `close`, which wait for a later commit.

## File format

```markdown
# ONC-5: Add login flow

- Issue: https://linear.app/acme/issue/ONC-5
- Branch: feat/onc-5-add-login
- Review: (id and url, filled at open)
- PR: (legacy, read but no longer written)

## Plan

One-paragraph approach summary.
Testing notes.

## Tasks

- [x] 1. Create login form component -> sub-issue: https://... (done 2026-07-28, a1b2c3d)
- [>] 2. Wire auth API (deps: 1) -> sub-issue: https://...
- [ ] 3. Add e2e test (deps: 2) -> sub-issue: https://...
```

`Review` holds the id and URL `openReview` returns, since the done-on-merge sweep looks a review up by id.
Keep reading a legacy `PR` line, which carries only a URL, and find its review by branch matching, but never write one.
`## Plan` holds the planning notes.
Each `## Tasks` line is numbered in creation order, the number is its permanent task id, and markers are `[ ]` open, `[>]` in progress, and `[x]` done.
Write several deps as `(deps: 1, 2)` and dates as `YYYY-MM-DD`.
An older file may end with a `- Closed: <date>` line; leave it in place, never count it as a task, and never write one.

## Operation mapping

| Contract operation | Checklist file mapping |
| --- | --- |
| `init(issueRef)` | When the file is missing, create it with the header, `Issue`, `Branch`, and `Review` lines and empty `## Plan` and `## Tasks` sections, and commit it. Never overwrite an existing file. |
| `createTask(title, description, subIssueRef, deps)` | Append `- [ ] N. <title> (deps: <dep-ids>) -> sub-issue: <subIssueRef>` with the next unused `N`, omitting `(deps: ...)` when `deps` is empty and folding any `description` into the title. Commit it with the breakdown commit. Return `N`. |
| `listTasks()` | Return each `## Tasks` line's number and sub-issue tail. |
| `claimNext()` | Read the working tree. Return the first `- [>]` line to resume when one exists. Otherwise rewrite the first `- [ ]` line whose deps are all `- [x]` to `- [>]`, uncommitted, so it rides the task's commit. This adapter has no lock: when the file changes between read and rewrite, or the branch has commits this runner did not make, stop and report a second runner. |
| `ready()` | Return every `- [ ]` line whose deps are all `- [x]`, in number order, changing nothing. |
| `claim(taskId)` | Rewrite that task's `- [ ]` to `- [>]`, uncommitted. |
| `close(taskId)` | Rewrite `- [>]` to `- [x]` with the done date, and commit it with the implementation as one commit. Then state that commit's short hash in the progress line and append it to the line, uncommitted, so the next commit touching this file carries it. Never amend a commit to add its own hash, and never commit only a hash, except to re-record hashes after a rebase. On a task already `- [x]`, replace its hash. |
| `status()` | `[ ]` and `[>]` lines are open, `[x]` lines are done, and `[>]` lines are in progress. |
| `parentTask(issueRef)` | The file is the parent task: return its path, with its header and `Issue`, `Branch`, and `Review` or legacy `PR` lines as fields. Closing it is a no-op, since it counts as closed once every task is `- [x]`. |
