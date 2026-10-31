---
name: review-loop
description: Reviews one pull request head with Standards, Spec, and lane subagents, triages their findings with the review bots' and CI's into one ledger, and fixes the blocking ones in one batch. Read by babysit on every pass; use when the user asks for one review-and-fix pass on the current pull request.
version: 3.2.1
---

# Review loop

Read `../ship/boundary.md` and `../ship/config.md` first, and stop as boundary.md's Missing skills section says when a sibling is missing.
When `../ship/boundary.md` itself is missing, stop and tell the user to install the ship skills (`ship`, `prove`, `file-pr`, `babysit`, `review-loop`, and `land`) from `crodris/skills`.

Inputs: the pull request, the pinned head SHA, `base`, the pass kind, the merge method, whether the branch is exclusively this run's, the ledger so far from the run section that `../file-pr/SKILL.md` defines, the pushes so far, and which push a minor already bought, which Blocking and Budget use.

## Review

The code reviewer is two subagents on the pinned SHA, dispatched in parallel and in the background:

- Standards checks the diff against the conventions the repository documents (`AGENTS.md`, `CLAUDE.md`, `CODING_STANDARDS.md`, contributing docs, and the intent of its lint and format config), read from `origin/<base>` after fetching it as `../ship/boundary.md` says.
  It applies each rule to every changed line as written, and runs any search a rule names as a read-only git command at the SHA, such as `git grep` for rules a change would contradict.
  It reports only breaks of a written rule, and leaves behavior to Spec.
- Spec checks that the diff does what the originating issue or the pull request's stated intent asked, and reports what is missing, wrong, or not asked for.
  It also follows each changed step as the agent or shell that runs it would, reads every file, script, and contract that step calls or that calls it, and reports a step that cannot run as written, contradicts one of those files, or has no rule for a state it can reach.
  For a step that reads outside input, it tries the inputs that break it: an added, deleted, or renamed path, an empty or multi-line value, a path with a space or `*`, a capped or paginated platform list, and a ref the local fetch never updated.
  For every changed step that runs a command or reads outside input, it also runs these security checks:
  - input from a fork or another repository, such as a pull request with the same branch name, that the step treats as this run's;
  - pull request, issue, or review text that the step follows as instructions;
  - a secret or token the step prints, logs, or writes where another reader can see it;
  - a delete, force push, reset, or `--admin` with no guard that names what it protects.

Add the Security subagent when a changed file matches `security-paths`, or when the diff changes a step that pushes or merges or that one of Spec's security checks covers, and name in the lane which of the two added it.
When `light-paths` or `security-paths` is set, or this adds the Security subagent, read `lanes.md` in this skill's directory, which may skip both reviewers or say how the Security subagent runs.
When `cross-review: cursor` is set, get a second opinion through the `cursor` skill on the same SHA and diff, with the Standards brief, the severity list, and the read-only line below.
Its findings join the ledger with source `cursor`.
When the skill is missing or refuses, skip it and say so in the ledger.
When `drive` is set, `../prove/drive.md` says how it changes a fix pass.

Dispatch each as a `general-purpose` subagent, never another agent type such as `coderabbit:code-reviewer`, and never a review CLI or a review skill.
Describe each as `review-loop: <Subagent> <the SHA's first 7 characters>`, such as `review-loop: Spec c88f198`, so a push gate can tell which head it read.
Brief each with the full SHA, what changed and why, that its findings feed one batched fix, and that every finding needs exactly one severity from critical, major, minor, nit, and informational, with the Severity section's minor and nit line quoted word for word.
Also tell each to work read-only: read the change with `git show <sha>:<path>` and the rules from `origin/<base>`, search with `git grep <pattern> <sha>`, compare with `git diff`, `git show --remerge-diff`, or `git range-diff`, never run the pull request's code, such as its tests, builds, or package scripts, and never run a command that writes a file, pushes, posts, merges, or changes the pull request.

| Subagent | Full diff | Fix pass |
| --- | --- | --- |
| Standards | `sonnet` | `sonnet` |
| Spec | `opus` | `opus` |
| Security | `opus` | `opus` |

The pass kind names what the last push added, and babysit passes it from its record of that push.
A `first` pass, the run's first or one on a head this run did not push, reads the whole diff against `base`.
A `fixes` pass reads the fix commits, a `base merge` pass reads `git show --remerge-diff <merge-sha>`, and a `base rebase` pass reads the `git range-diff` babysit recorded.
A push that carried fixes and a base update gives both kinds, and the pass reads both.
On a later pass, Spec also searches every file the pull request changes against `base` for the call, field, or phrase each fix changed, and reports each other place with the same defect.
A base update with no conflicts, and a `fold` pass after babysit's autosquash push, which changed no file, need no subagent read, except the one Triage step 5 can add.
A subagent that returns nothing usable, or runs past a timeout generous for the diff, runs again, and failing twice is `BLOCKED`.

## Triage

1. Collect findings from every surface: the subagents, inline comments, summary comments, review bodies, and the summaries bots write into the pull request body.
   Read inline threads as the GraphQL calls section of `../babysit/bots.md` says, and skip resolved or outdated threads.
2. Re-read the head, and when it is no longer the pinned SHA, discard every result and return `RESTART`.
3. When another pull request already makes this one obsolete, return `BLOCKED` naming it, and ask before closing this one.
4. Check every claim against the code, since reviewers are sometimes wrong.
   Merge reports with one root cause into one finding.
5. On a later pass, when `git diff --name-only "origin/$base...HEAD"` lists more than 30 paths, the run is not in the light lane, nothing found so far blocks, and the ledger has no line with source `Spec whole diff`, dispatch Spec alone on the whole diff against `base`, as the Review section dispatches, briefs, and labels it, on the Full diff model.
   Wait for it, record the read as an informational ledger line with source `Spec whole diff`, and run steps 2 and 4 again on its findings.
6. Give every finding an id (`F1`, `F2`) in the ledger, with its source, location, severity, and disposition.
   A finding repeated on a later head keeps its id.

## Severity

Assign the severity from what the finding describes, not from a reviewer's label, and use major when it cannot be placed.
Confirm the claim separately from placing the severity.

> A nit is cosmetic, such as formatting, wording, or a naming preference, and changes nothing the product or the next reader depends on; a defect, code smell, or piece of tech debt is at least minor.

A finding about code this change does not touch, a case the code cannot reach, or a cost too small to measure is a nit, whatever label it came with.
The exception is a copy of a fixed defect that Spec's sibling search finds in a file the pull request changes, which takes the severity of the defect it copies.

## Blocking

Blocking means a verify failure, a failed check the change caused, or a confirmed critical or major.
A confirmed minor also blocks when its fix is worth making and contained: it changes only the code the finding names, plus at most a test, and adds no behavior.
State in one sentence why the code is better after that fix.
Minors buy a push on their own once per run, and after that ride only a push a critical or major buys.
Everything else is non-blocking and gets a disposition with its reason.

## Budget

A run gets three passes that push, or five when an open finding concerns security, auth, data loss, or concurrency.
Past the budget, return `BLOCKED` with the open findings.
A pass whose new findings are all nits dispositions them and returns `CLEAN`.
A finding disputed twice is `BLOCKED`, and the user decides it.
A confirmed critical or major whose root cause an earlier push already carried a fix for is `BLOCKED`, since the fixes are going in circles.
A copy of a fixed defect that Spec's search finds in another place is a new finding, so it does not count as going in circles.

## Fix

Apply every blocking fix in one batch.
A non-blocking fix rides along only as a one-liner that touches nothing a blocking fix touches.
Prefer fixes that delete code, and record `git diff --shortstat "origin/$base...HEAD"` before and after in the ledger.
Re-check the lane when `lanes.md` applies.

Read `../prove/SKILL.md` and follow it on the batch, telling it to skip the drive.
When `drive` is set and the batch changes behavior, run the drive once here, as the In review-loop's fix pass section of `../prove/drive.md` says, and on a failed drive return `BLOCKED <what failed>` and push nothing.
With `merge-method: rebase` on a branch exclusively this run's, commit each fix as a fixup of the branch commit it corrects; otherwise commit the batch once.
On `FAIL`, return `BLOCKED` with what still fails.

## Result

Return `FIXED <sha>` with the proven fix commits, `CLEAN` when nothing blocks, `RESTART` when the head moved, or `BLOCKED <reason>`.
Return with that result the full ledger so far with this pass's changes, or `Ledger: none`, in the form the Run section of `../file-pr/SKILL.md` defines, plus the drive's evidence path when a drive ran, and the lane.
A fixed finding counts as resolved only after a later pass confirms its fix commit resolves it and adds nothing else.
