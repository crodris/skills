---
name: prove
description: Runs the repository's own verify gates on the working tree until they pass, commits when the caller asks it to, and prints a one-line proof. Use when the user asks to verify or prove a change before pushing it.
version: 3.3.1
---

# Prove

Read `../ship/boundary.md` and `../ship/config.md` first, and stop as boundary.md's Missing skills section says when a sibling is missing.
When `../ship/boundary.md` itself is missing, stop and tell the user to install the ship skills (`ship`, `prove`, `file-pr`, `babysit`, `review-loop`, and `land`) from `crodris/skills`.

Inputs: `base`, what changed and why, how to commit (a message, the branch commit each fix corrects, or nothing to commit), and whether to skip the drive.

## Resolve verify

Take the first tier that answers, and never let a later tier override it.
A `verify` answer the user gave earlier in this run, such as in `ship`'s round of questions, answers before every tier.

1. `verify` in `.ship/config.md` at the repository root.
2. The project's docs: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README.md`.
   Collect every command they name to run before committing or in CI, in the order they present them.
3. The candidates `bash <this skill's directory>/resolve-verify.sh` prints, taking the first tier it prints: `aggregate`, then `ci`, then `compose`.
   A candidate that starts with `read ` names a workflow step or a whole CI file, so read that step or file and run what it runs, from the directory it sets.
   From `ci`, keep the steps that check the code, in order, and skip steps that install tools.
   In a monorepo, prefer a root task that fans out, such as a `turbo`, `nx`, or workspace script, over running each package by hand.

A review tool or a skill that wraps one is never a verify gate, wherever it was named.
Drop it from its tier, and take the next tier when nothing survives.

Ask the user, once, with every candidate verbatim as an option, when any of these holds:

- Two or more candidates are plausible and run different things.
- No tier produced a command.
- The command skips a tool the project configures, such as a typecheck script that the `ci` script never runs.
- The config's `verify` is a review tool, or fails with exit 127, `command not found`, `Missing script`, or `No rule to make target`.
  Re-detect from tier 2 first.

When `ship` called this, the question rides `ship`'s one round of questions.
Record the answer as `../ship/config.md` says.

## Verify loop

When the caller said nothing to commit, or prove was invoked directly with no commit instruction, the loop runs with no fix steps, and a failing round returns `FAIL <what still fails>`.
Before the first round, save the output of `git diff` and of `git diff --cached`, and `git rev-parse HEAD`.

1. Run `verify` on the current tree with a timeout generous against its usual runtime, and collect every failure.
   A run past the timeout is a failed round.
2. When the caller asked for a commit, group the failures by cause and fix them in one batch.
3. The loop ends on a round that passed with no fixes applied.
   Otherwise run the next round on the updated tree.
4. After five rounds, return `FAIL` with what still fails and what was fixed, and commit nothing.

When `drive` is set and the caller did not ask to skip it, read `drive.md` in this skill's directory, and run the drive where it says.

## Commit

When the caller said nothing to commit, or prove was invoked directly with no commit instruction, commit nothing, run the check below, and skip the rest of this section.
The check compares the output of `git diff`, of `git diff --cached`, and of `git rev-parse HEAD` after the last verify or drive run with the saved values, and returns `FAIL verify changed tracked files: <paths>` when any differs, with the paths `git diff --name-only`, `git diff --cached --name-only`, and `git diff --name-only <saved HEAD> HEAD` print.
When they match, end with the no-commit `PASS` line.

When the caller supplied target commits, check every fix group before staging or committing.
A fix with no target commit returns `FAIL no target commit for <path>` before anything is staged.
Take every path from `git status --porcelain` that belongs to the change: modified, deleted, and added, including an intent-to-add entry.
Stage each by explicit path, never with `git add -A`, and leave strays alone.
Ask before committing a file whose fate is unclear.

Commit with the caller's message, or in the format `git log` shows, choosing a Conventional Commits type for the release it should cause.
With targets, `git commit --fixup=<sha>` each group.
Never add a Co-Authored-By trailer.

## Result

End with one line:

- `PASS verify: <command> passed in <n> rounds`, with no commit, when there was nothing to commit, adding the drive's evidence path when a drive ran.
- `PASS <sha> verify: <command> passed in <n> rounds`, adding the drive's evidence path when a drive ran.
- `FAIL verify changed tracked files: <paths>`.
- `FAIL no target commit for <path>`.
- `FAIL <what still fails>`.
