---
name: prove
description: Runs the repository's own verify gates on the working tree until they pass, commits the change, and prints a one-line proof. Use when the user asks to verify or prove a change before pushing it.
version: 3.0.0
---

# Prove

Read `../ship/boundary.md` and `../ship/config.md` first, and stop as boundary.md's Missing skills section says when a sibling is missing.
When `../ship/boundary.md` itself is missing, stop and tell the user to install the ship skills (`ship`, `prove`, `file-pr`, `babysit`, `review-loop`, and `land`) from `crodris/skills`.

Inputs: `base`, what changed and why, how to commit (a message, a commit to fix up, or nothing to commit), and whether to skip the drive.

## Resolve verify

Take the first tier that answers, and never let a later tier override it.

1. `verify` in `.ship/config.md` at the repository root.
2. The project's docs: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README.md`.
   Collect every command they name to run before committing or in CI, in the order they present them.
3. The candidates `bash <this skill's directory>/resolve-verify.sh` prints, taking the first tier it prints: `aggregate`, then `ci`, then `compose`.
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

1. Run `verify` on the current tree with a timeout generous against its usual runtime, and collect every failure.
   A run past the timeout is a failed round.
2. Group the failures by cause and fix them in one batch.
3. The loop ends on a round that passed with no fixes applied.
   Otherwise run the next round on the updated tree.
4. After five rounds, return `FAIL` with what still fails and what was fixed, and commit nothing.

When `drive` is set and the caller did not ask to skip it, read `drive.md` in this skill's directory, and run the drive where it says.

## Commit

Take every path from `git status --porcelain` that belongs to the change: modified, deleted, and added, including an intent-to-add entry.
Stage each by explicit path, never with `git add -A`, and leave strays alone.
Ask before committing a file whose fate is unclear.

Commit with the caller's message, or in the format `git log` shows, choosing a Conventional Commits type for the release it should cause.
With a commit to fix up, run `git commit --fixup=<sha>`.
Never add a Co-Authored-By trailer.

## Result

End with one line:

- `PASS <sha> verify: <command> passed in <n> rounds`, adding the drive's evidence path when a drive ran.
- `FAIL <what still fails>`.
