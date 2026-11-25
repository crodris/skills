# Reviewer models

Read by review-loop when `reviewers` is set in `.full-send/config.md` on `origin/<base>`, and by step 2 of `../full-send/SKILL.md` to tell whether the Final review applies.

## The slot

`reviewers` is a comma-separated list of `<role>=<model>`, where several models on one role are joined with `+`, such as `reviewers: spec=neon+opus, final=sol`.
A role is `standards`, `spec`, `security`, or `final`, and a model is `sonnet`, `opus`, `fable`, `neon`, or `sol`.
Names are lowercase, and spaces around entries, `=`, and `+` are trimmed.
The slot is corrupt when it is empty, when an entry has another form, when it repeats a role or a model within a role, when it names an unknown role or model, or when `final` has more than one model.
Ignore a corrupt slot, use the table in `SKILL.md` with no final review, and record an informational ledger line that says why.
A `standards`, `spec`, or `security` entry sets both columns of its row in the table in `SKILL.md`, and a role the slot does not name keeps that row.

## Several models on one role

A role with several models runs one subagent per model, with the same brief, in every dispatch of that role, Triage step 5 included.
Triage step 5's read gets the source `Spec whole diff (<model>)`, which counts as a `Spec whole diff` line.
Each finding's ledger source names the role and the model, such as `Spec (neon)`.
When Triage step 4 merges reports with one root cause, the source names every model that found it, such as `Spec (neon, opus)`.
A finding that only some models of its role found adds `missed by <model>` to its ledger line, so the ledgers show what each model catches.

## Dispatching a model

`sonnet`, `opus`, and `fable` run as the Review section of `SKILL.md` says, with that model.
`neon` and `sol` run only through T3 Code's `delegate_task`, with `role: "review"`, `mode: "async"`, `isolation: "worktree"`, and a new `clientRequestId` for each dispatch.
Set `target` to `{providerInstanceId: <Provider>, model: <picked id>, options: <Effort>}` from the table below, or the child runs on the parent's model.
Set its `title` to the description the Review section gives, such as `review-loop: Spec c88f198`, and its `task` to the full brief, since the child gets no history.
Resolve the model with `orchestrator_capabilities`, called with the row's search term:

| Model | Provider | Search | Pick | Effort |
| --- | --- | --- | --- | --- |
| `neon` | `antigravity` | `gemini` | the latest id containing `neon` | `{thought_level: "high"}` |
| `sol` | `codex` | `sol` | the latest id containing `sol` | `{reasoningEffort: "high"}` |

Run `neon` only on `antigravity`, never on another provider that also offers it, such as `cursor`.
Latest is the highest version, skipping any model whose id or label marks it as an orchestrator or a reduced tier such as `mini` or `flash`.
Record `git rev-parse HEAD`, `git status --porcelain`, and `git ls-remote origin "refs/heads/<branch>"` before the dispatch, with `<branch>` from `git branch --show-current`.
Start the `delegate_task` reviewers first, in the same message as the dispatch's other subagents.
Then follow each result's `next` field: end the turn without polling, and read each report from the completion notice that wakes the thread.
For a `sol` call's usage, run `bash <this skill's directory>/codex-usage.sh "<worktreePath>"` with the child's `worktreePath` from `t3_thread_read`, and record the line it prints on stdout.
Record `not exposed` when `worktreePath` is missing or the script exits nonzero, and never record its stderr.
A `neon` call's usage is `not exposed`, since Antigravity keeps no usage log.
When every report is in, compare all three with the record, and return `BLOCKED` naming what changed when any differs, since a child wrote to the checkout or pushed the branch.

## Fallback

A model falls back when the run is outside T3 Code or inside a subagent or child task, since the completion notice reaches only the top-level thread.
It also falls back when `orchestrator_capabilities` offers no matching model, when it fails with a credit, quota, usage-limit, or rate-limit error, or when it fails twice for any other reason.
For `neon` and `sol`, that fallback replaces the Review section's rule that a subagent failing twice is `BLOCKED`.
`sol` falls back to `neon`, and `neon` falls back to the role's model in the table in `SKILL.md`, or to `opus` for `final`.
The fallback gets the same brief and replaces the model for the rest of the run.
A fallback to a model the role already lists drops the model instead.
Record each one as an informational ledger line, such as `F7 informational review-loop Spec: neon replaced by opus, rate limited. No action`.

## Final review

It applies only when the slot names `final`, and not when `light-paths` is set and every changed file matches it, as `lanes.md` resolves paths, with the config file never matching.
It runs only from step 5 of `before-push.md`.
Each call is described `review-loop: Final <the SHA's first 7 characters>` and is not a round for the Stops section of `before-push.md`, so its blocking findings count toward the round whose `CLEAN` started it.
Do not run the Stops check on that round again, and its count, Final findings included, is the round before's count for the next round.
A run makes at most two calls that return a usable report.

Make the first call when no ledger line has a source that starts with `Final`.
Dispatch the final model alone on the whole diff against `base`, with Spec's brief.
Record the read as an informational ledger line with source `Final (<model>)`, and give its findings that source.
Triage and Fix them like any other findings.
On `FIXED <sha>`, start the next round with pass kind `fixes`, as step 5 of `before-push.md` says, so every reviewer reads the fix.
On `RESTART` or `BLOCKED <reason>`, return `BLOCKED <reason>`, and when nothing blocks, hand `CLEAN` back to step 5.

Make the second call when a later round returns `CLEAN`, a first-call finding blocked, and no ledger line has the source `Final (<model>) confirm`.
Brief it with the full SHA, the Review section's read-only and severity lines, the ledger line of each first-call finding that blocked, and the fix commits since the first call.
Ask whether each finding is resolved and whether the fixes broke anything.
Record the read as an informational ledger line with source `Final (<model>) confirm`, and give its findings that source.
A finding it calls still open is disputed twice, so return `BLOCKED` with both sides, and the user decides.
Triage and Fix its new findings like any other, and the round after a fix reads it with no further call.
When nothing blocks, hand `CLEAN` back to step 5.
