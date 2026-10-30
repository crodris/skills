---
name: verification-audit
description: Audit how well a repository proves that agent work is correct, layer by layer, then close each gap with the matching pstack skill. Use when the user says "audit verification", "verification audit", "how verified is this repo", "set up verification here", or asks whether a repo has a verify skill, a formal check, a scheduled drive, or risk-scaled review.
version: 1.1.1
---

# Verification audit

Check one repository against the verification layers, report each gap, then close the gaps in order.
The layers run strongest first: the code and its types, then static checks (lint, tests, CI, formal verification), then prose, then human review.
Close each gap at the strongest layer that can hold it, such as a lint rule in place of a line in AGENTS.md.

## Find the building blocks

The fixes come from four pstack skills: `create-verification-skill`, `maintain-verification-skill`, `create-formal-verification-skill`, and `maintain-formal-verification-skill`.
The Skill tool cannot call them, so read each one's SKILL.md in full from the pstack version the harness lists as installed, and follow it.
When pstack is not installed, report the gaps and say that the fixes need pstack.

## Checks

Run every check before fixing anything.
Give each one a state, with the file, command, or run that shows it:

- **present**: it meets the whole bar below.
- **partial**: it misses a named part of the bar.
- **outdated**: it met the bar once, and the code has since moved past it.
- **missing**: nothing exists.
- **blocked**: it depends on an earlier check that is missing.

With the ship skill, read each `.ship/config.md` slot the way `../ship/config.md` says.

1. **Static gates.** CI runs the typecheck, lint, and tests on every pull request they apply to, and branch protection or a ruleset requires them to pass.
   Read every CI config the repo has, not only the package scripts.
   A check that runs but is not required is partial.
   Fix a gap in CI.
   When a partial check needs branch protection or a ruleset changed, report the gap and ask the user before changing that setting.
2. **Verify skill.** A `verify-<app>` project skill, under `.claude/skills/`, `.agents/skills/`, or `.kiro/skills/`, launches the real app, drives it as a user does, and captures evidence.
   Missing: follow `create-verification-skill`.
3. **Feature map.** The verify skill's `features/` covers every user-facing route, command, or screen the app has now.
   It is outdated when `git log` shows a surface added or removed after the map's last change, and a fix inside a surface does not count.
   Outdated: follow `maintain-verification-skill`.
4. **Formal check.** First name the one to three targets where a bad order of events or an unexpected input costs users most, such as optimistic writes, retries, sync, parsers, or money paths.
   A target without a formal check makes the state partial.
   It is outdated when a covered file changed in a commit that left the verification alone.
   Missing or partial: follow `create-formal-verification-skill` for each uncovered target.
   Outdated: follow `maintain-formal-verification-skill`.
5. **Scheduled drive.** A CI cron, systemd timer, or cloud routine drives the default branch on a schedule and opens or updates one issue when the drive fails.
   Prove it from a recent run, not from the schedule's file.
   A schedule on a machine you cannot reach is partial, so say what stays unproven.
   Report that nothing checks the schedule itself runs, since a run that never starts files no issue.
   Missing: read the delivery flow's drive, then ask the user where the schedule runs.
   A script cannot start the agent session a `skill:<name>` drive needs, so only a cloud routine can run that drive and open or update the issue.
   A CI cron or timer runs a script, which runs the drive when it is a command, and otherwise a command the user gives.
   The script runs on a fresh checkout of the default branch, opens or updates one issue on failure, and ships through the repo's delivery flow.
   Install or enable the schedule where the user named, then trigger one run.
   Leave the check partial until a scheduled run exists.
6. **Review setup.** The delivery flow runs the static gates and the configured drive and gives risky paths a deeper review.
   With the ship skill, `.ship/config.md` sets `verify` to the static gates, `drive` to a value `../prove/drive.md` accepts, and `security-paths` to the riskiest code, and the audit checks the Verify skill whether or not `drive` names one.
   Another flow, such as Fathom, meets the same bar in its own config.
   The repo also has the review bots the user's instructions name, and a paused bot counts as missing.
   Fix a gap in the flow's config, and ask before adding a bot to a repo the user does not own.

## Report, then fix

Report one table first: check, state, evidence, and fix.
Then close the gaps in check order, since the later checks point at the verify skill.
Ship each fix through the repo's normal delivery flow, one pull request per gap.
Prove each fix the way its pstack skill says, including seeing the check fail, and never report a check as present from its file alone.

## Several repositories

For a list of repositories, run the checks on all of them and report one table per repository before any fix.
Fix one repository at a time, starting with the one the user works in most.
