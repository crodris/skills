---
name: verification-audit
description: Audit how well a repository proves that agent work is correct, layer by layer, then close each gap with the matching pstack skill. Use when the user says "audit verification", "verification audit", "how verified is this repo", "set up verification here", or asks whether a repo has a verify skill, a formal check, a scheduled drive, or risk-scaled review.
version: 1.0.0
---

# Verification audit

Check one repository against the verification layers, report each gap, then close the gaps in order.
The layers run strongest first: the code and its types, then static checks (lint, tests, CI, formal verification), then prose, then human review.
When a gap can close at a stronger layer, close it there, such as a lint rule in place of a line in AGENTS.md.

## Find the building blocks

The fixes come from four pstack skills: `create-verification-skill`, `maintain-verification-skill`, `create-formal-verification-skill`, and `maintain-formal-verification-skill`.
They set `disable-model-invocation: true`, so the Skill tool cannot call them.
Read each one's `SKILL.md` from the installed pstack plugin in full, and follow it.
When several pstack versions are on disk, read the one the harness lists as installed, since older versions lack some of these skills.
When pstack is not installed, report the gaps and say that the fixes need pstack.

## Checks

Run every check before fixing anything.
Give each one a state, with the file, command, or run that shows it:

- **present**: it meets the whole bar below.
- **partial**: it exists but misses part of the bar. Name the part.
- **outdated**: it met the bar once, and the code has since moved past it.
- **missing**: nothing exists.
- **blocked**: it depends on an earlier check that is missing.

1. **Static gates.** The typecheck, lint, and tests run in CI on every pull request that can change what they check, and a failure blocks the merge.
   Read every CI config the repo has, such as GitHub Actions or Drone, not the package scripts alone.
   A failing check that branch protection or a ruleset does not require is partial, since the merge still goes through.
   Fix a gap directly in CI.
2. **Verify skill.** A project skill named `verify-<app>` launches the real app, drives it the way a user does, and captures evidence.
   Look under `.claude/skills/` and the repo's agent docs.
   Missing: follow `create-verification-skill`.
3. **Feature map.** The verify skill's `features/` covers the user-facing surfaces the app has now.
   List the routes, commands, or screens in source, and compare them with the map's files.
   It is outdated when a surface was added or removed after the map's last change, by `git log` on both. A fix inside an existing surface does not count.
   Outdated: follow `maintain-verification-skill`.
4. **Formal check.** A formal check covers the code where a bad order of events or an unexpected input costs users the most, such as optimistic writes, retries, sync, parsers, or money paths.
   Name the top one to three targets before you look for a check, so the audit judges the targets and not only the presence of a check.
   Each target without a check makes the state partial.
   It is outdated when a covered file changed in a commit that did not also change the verification.
   Missing or partial: follow `create-formal-verification-skill` for the uncovered target.
   Outdated: follow `maintain-formal-verification-skill`.
5. **Scheduled drive.** Something drives the default branch on a schedule (CI cron, systemd timer, cloud routine) and opens or updates one issue when the drive fails.
   Prove it from a recent run, such as a CI run, a log, or the issue's history, not from the schedule's file.
   A schedule on a machine you cannot reach is partial: say what stays unproven.
   A run that never starts files no issue, so report that the schedule has no outside check that it ran.
   Missing: write a script that runs the verify skill's drive against a fresh checkout of the default branch and files the issue on failure.
   Ask the user where it runs, since that needs a machine or CI minutes.
6. **Review setup.** The repo's delivery flow runs the static gates and the verify skill's drive, and gives risky paths a deeper review.
   In a repo that ships with the ship skill, that is its config in the repo's `.ship` folder: `verify` set to the static gates, `drive: skill:verify-<app>`, and `security-paths` for the code where a mistake costs the most.
   A repo with another flow, such as Fathom, gets the same bar from that flow's config.
   The repo also has the review bots the user's instructions name. A paused bot counts as missing.
   Fix a gap in the flow's config. Ask before adding a bot to a repo the user does not own, such as a client repo.

## Report, then fix

Report one table first: check, state, evidence, and fix.
Then close the gaps in check order, since a verify skill must exist before a feature map, a scheduled drive, or a `drive:` slot can point at it.
Ship each fix through the repo's normal delivery flow, one pull request per gap.
Prove each fix the way its pstack skill says, and never report a check as present from its file alone.
A check never seen to fail has not been tested.

## Several repositories

For a list of repositories, run the checks on all of them first and report one table per repository.
Fix one repository at a time, starting with the one the user works in most.
