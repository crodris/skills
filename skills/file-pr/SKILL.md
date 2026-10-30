---
name: file-pr
description: Opens or updates the pull request for a pushed branch, with the title, body, and secrets check that ship and execute share. Use when the user asks to open, file, or create a pull request for the current branch.
version: 3.1.1
---

# File a pull request

Read `../ship/boundary.md` first when it exists.
When it does not, as in an execute install without the ship skills, follow the caller's own boundary, such as the Absolute boundary in `../execute/SKILL.md`.

Inputs: a pushed branch, its base, and the body parts the caller supplies, such as ship's run section or execute's `Closes <ref>` and task list.
An optional title and a complete body may come with them.
When the caller supplies that title and body, as `../execute/forges/github.md` does, skip the Title section and Body steps 1 to 4, and do not add that body again in Body step 5.

## Run section

The run section is the part of the body a ship run owns, between `<!-- run:start -->` and `<!-- run:end -->`.
It holds the summary and the evidence.
It holds the lane, the bots present, and the pass and push counts.
It holds the `PASS` line and the record of which push a minor bought.
It holds each skipped review.
It holds the ledger, with one line per finding in the form `F<n> <severity> <source> <location>: <claim>. <disposition>`.
A run with no findings records the single line `Ledger: none`.
Review bots' own summaries sit outside the markers.

## Secrets check

Before any create or edit, read the title, the body, and every attachment for tokens, keys, passwords, credentials in URLs, and environment file contents.
Remove each one, and return `FAIL <reason>` when removing it would lose what the text says.

## Reuse an open one

Without a working `gh`, skip this section and the Open it section, and go to the `HANDOFF` rule at the end of the file.
With a working `gh`, run `gh pr list --head <branch> --base <base> --state open --json number,url,isCrossRepository`.
Ignore a result whose `isCrossRepository` is `true`, since a fork's pull request can share the branch name.
When it finds one, never open a second.
Read the body with `gh pr view <n> --json body --jq .body`.
Read the current run section first and write the whole section back with the caller's changes.
A caller's body part between its own named markers replaces the text between those markers.
A caller's named markers that are missing from the body get their marked part appended.
Splice the new text into a temporary file made with `mktemp`, run `gh pr edit <n> --body-file <file>`, and delete the file as Open it does.
Any failed `gh` call in this section returns `FAIL <reason>`.
Return `OPEN <number> <url>`.

## Title

Match how the repository titles its merged pull requests, from `gh pr list --base <base> --state merged --limit 10 --json title`.
Name the outcome for the user, not the mechanism:

> Mechanism: `perf(server): negotiate permessage-deflate on the websocket`
> Outcome: `perf(server): cut websocket frame size by 70%+ with gzipping`

## Body

1. Open with the problem as the user or the issue described it, then the fix in a sentence or two, then any list of changes.

   > Inventory: Removed implicit workspace carry-over from every "new thread" entry point.
   > Problem first: My "new worktree" default was ignored on existing worktrees. Now your preferences always apply.

2. End that opening with a merge-danger line: a two-way door when the change is cheap to roll back, or a one-way door when it deletes data, migrates a schema, or publishes something others depend on, and who or what breaks if it is wrong.
3. Lead the summary with the smallest visual that makes the change clear, such as pseudocode, a call tree, a component tree, a file tree, Mermaid, or a `diff` sketch.
   Skip it when one sentence does.
4. Show evidence as before and after when a before exists: the drive's screenshot, or the command output that failed before and passes now.
5. Add the caller's body parts, with its run section between the two markers.

## Open it

Write the body to a temporary file outside the repository, such as one `mktemp` creates, never under `.git/`.
A caller's marked part goes in as given.
Run `gh pr create --base <base> --head <branch> --title <title> --body-file <file>` as a command of its own, ready rather than `--draft`, since a draft-to-ready flip does not reliably trigger CI.
When `gh pr create` fails, return `FAIL <reason>`.
Delete the body file in a separate command, and leave it when the session may not delete it.
Return `OPEN <number> <url>`.

Without a working `gh`, print the compare URL the remote host expects and return `HANDOFF <url>`.
The results are `OPEN <number> <url>`, `HANDOFF <url>`, and `FAIL <reason>`.
