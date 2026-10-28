---
name: ship
description: Use when the user says "ship", "ship it", "/ship", "ship and merge", "take this all the way", or "get this merged and released", or asks to carry the current branch or its open pull request from working tree to a ready or merged pull request. Plain "ship" stops at a green pull request, and it merges only when the request says to merge or `.ship/config.md` sets `merge` to `yes`. Not for a single commit or a release cut from an already-merged main.
version: 3.1.0
---

# Ship

Carry the current branch's work to a green pull request, and in merge mode on to a merged release, without stopping between steps.
Each step is a skill that ends with one result line.

## Precedence

When the repository ships its own ship skill at `.claude/skills/ship/SKILL.md`, `.agents/skills/ship/SKILL.md`, or `.kiro/skills/ship/SKILL.md`, follow that file instead and say so.
It decides every step, command, and convention, but it cannot relax `boundary.md` in this skill's directory.

## Before anything

1. Read `boundary.md` and `config.md` in this skill's directory.
   When `../prove/`, `../file-pr/`, `../babysit/`, `../review-loop/`, or `../land/` is missing, stop as boundary.md's Missing skills section says.
2. Resolve `base`: a named pull request's base, else `base` in `.ship/config.md`, else the remote's default branch.
   Validate it with `git check-ref-format --branch` before any command uses it, and stop when it fails.
   Never replace a configured `base` with the default, and stop and ask when the base no longer exists on the remote.
3. Settle the mode with the first rule that matches:
   1. A request that says to merge, such as "merge it", "ship and merge", or "get this merged", is merge mode.
   2. A request for a green pull request, such as "get it green" or "don't merge", is hold mode.
   3. `merge: yes` in `.ship/config.md` on `origin/<base>` is merge mode, and any other value is hold mode that the report names.
   4. Everything else, including plain "ship", is hold mode.
4. Resolve every slot in `config.md`'s table: `verify` by the Resolve verify section of `../prove/SKILL.md`, and in merge mode `merge-method` by the Merge method section of `../land/SKILL.md`.
5. Ask the user once, with AskUserQuestion, covering every slot still unresolved, with the detected candidates verbatim as options.
   First offer to reuse a `.ship/config.md` that another local branch or worktree already carries.
   Say the answers will be saved to `.ship/config.md`, and hold them until Settle the branch writes them, since `config.md` allows the write only once there is work to ship.
   Never ask about a slot again in the run: a slot still unresolved takes its absent default and is reported.
   The safety stops are not slot questions and always fire.

## Settle the branch

Fetch the base as the Fetching the base section of `boundary.md` says.
Then take the first case that matches the checkout, reading `git status --porcelain`, `git rev-parse --abbrev-ref @{u}` (which fails with no upstream), `git rev-list --count @{u}..HEAD`, `git rev-list --count "origin/$base..HEAD"` for commits ahead of the base, and `gh pr list --head <branch> --base <base> --state open --json number,isCrossRepository` (ignoring fork results) for an open pull request.
With no upstream, the count of commits ahead of the upstream is unavailable, so the cases read it as the commits ahead of `origin/$base`.
Writing the config means writing `.ship/config.md` from the held answers as `config.md` says, and dropping the answers means writing nothing.

1. The user names a pull request other than the current branch's: stop when its head lives on a fork.
   Validate its head branch with `git check-ref-format --branch` before any command uses it, and stop when that fails.
   Get the head branch as the Worktrees section of `boundary.md` says, and take the next case.
   Install dependencies in a new worktree as that section says.
2. HEAD is detached: stop, say so, and ask for the branch to ship.
3. On `base` with uncommitted work or local commits: write the config, then run `bash <this skill's directory>/settle-branch.sh "$base" <new-branch>`, naming the branch by `branch` or the project's convention, and adding `--worktree <path>` with the path `config.md` gives when `worktrees` is set.
   The run continues in the checkout its `SETTLED` line names, and any other exit is a stop-and-report.
   Install dependencies in a new worktree as the Worktrees section of `boundary.md` says.
4. On another branch with uncommitted work, commits ahead of its upstream, or no upstream and commits ahead of `origin/$base`: write the config and keep the branch, since `prove` commits the work and `guard.sh` pushes it.
5. On another branch, clean, with nothing ahead of its upstream, and an open pull request into `base`: drop the answers, read `../prove/SKILL.md` and follow it with nothing to commit and any `verify` answer the user gave, and stop on `FAIL`.
6. On another branch, clean, with nothing ahead of its upstream, commits ahead of `origin/$base`, and no open pull request into `base`: write the config, commit a config it wrote on its own, read `../prove/SKILL.md` and follow it with nothing to commit, and stop on `FAIL`, so a `FAIL` pushes nothing.
7. Anything else: drop the answers, stop, and say there is nothing to ship.

After cases 3 to 6:

1. Hold the settled branch as `$branch` and the base as `$base`, validate `$branch` with `git check-ref-format --branch`, and pass both only as quoted arguments.
   A settled branch equal to `base` is a stop.
2. For cases 3 and 4, commit a `.ship/config.md` this run wrote, on its own.
3. For cases 3 and 4, when the branch has never been pushed and is behind `origin/$base`, run `git rebase --autostash "origin/$base"` and resolve any conflict the way the change intends.
4. For case 5, go to Call the skills step 4, with the `PASS` line added to the run section through the Reuse an open one section of `../file-pr/SKILL.md`, and stop on its `FAIL`.
5. For case 6, push with `bash <this skill's directory>/guard.sh "$branch" "$base"`, and go to Call the skills step 3 with the `PASS` line in the run section.

## Call the skills in order

1. Read `../prove/SKILL.md` and follow it with `base`, what changed and why, and a commit message.
   On `FAIL`, stop and push nothing.
2. Push with `bash <this skill's directory>/guard.sh "$branch" "$base"`, where any nonzero exit is a stop.
3. Read `../file-pr/SKILL.md` and follow it with the branch, `base`, and a run section holding the summary, the `PASS` line, and any drive evidence.
   On `FAIL`, stop.
   On `HANDOFF`, report and end.
4. Read `../babysit/SKILL.md` and follow it with the pull request, the mode, the resolved merge method, and whether this run created the branch.
   In hold mode, and on `AWAITING-APPROVAL` or `BLOCKED`, stop and report.
5. In merge mode on `READY`, read `../land/SKILL.md` and follow it with the pull request, the `READY` SHA, the branch, `base`, and the worktree this run created or babysit's result line reported, if any.
   On `BLOCKED`, stop and report.

## Report

Give one summary with:

- each skill's result line, in order;
- the mode and the rule that chose it;
- how each slot resolved, what the user answered, and whether `.ship/config.md` was written, or why not;
- the lane, the bots, the review rounds, the pushes, and any skipped review, from the run section;
- every decision made on the user's behalf, such as a dropped verify command, a bot skipped as unavailable, or a default taken for an unresolved slot.

Report anything skipped, red, or deferred when it happens, not only at the end.
