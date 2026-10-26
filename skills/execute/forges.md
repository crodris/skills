# Forge adapters

The forge hosts the remote and the code review, and is resolved independently of the tracker.
Resolve the adapter before any forge work, and call the forge only through the operations below, never through forge tools called from a skill body.

## The contract

| Operation | Purpose |
| --- | --- |
| `verifyForge()` | Read-only preflight: return verified or unverified, nothing else. |
| `resolveBase(branch)` | Confirm the base branch exists on the remote as a merge target. |
| `openReview(branch, base, title, body, dependsOn?)` | Create the review and return its id and URL, the manual-handoff result, or a failure. `dependsOn` is the id of the review this one stacks on, absent otherwise. |
| `publishReview(id)` | Move a draft review to notified, where the forge has drafts; otherwise a no-op. |
| `getReviewState(id)` | Return `open`, `merged` with its timestamp, `closed-unmerged`, or `unknown`. |

`pushesForYou` alone decides who pushes the branch that opens the review: `openReview` when it is true, and the caller, before calling `openReview`, when it is false.
Commits made after the review is open, including the final closing commit, stay the caller's to push, per the closing actions in `SKILL.md`.

The review id must let `getReviewState` look the review up directly, from any clone, without a listing call.
A branch name is not a review id.

The **manual-handoff result** is an outcome of `openReview`: no id, plus the pushed branch, the base, a suggested title, and the suggested body in full.
It is a typed outcome, not a failure.
A caller receiving it does not call `publishReview`, records no review id, and says that opening the review is now the user's step.

### `resolveBase(branch)`

This is the one definition of the branch lookup, and every adapter and caller that checks a branch on the remote follows it and does not restate it.
Validate the name with `git check-ref-format --branch "<branch>"`.
Run `git ls-remote --exit-code --heads origin -- "refs/heads/<branch>"`.
Exit 2 means the branch is missing on the remote.
Any other nonzero exit, and a name that fails validation, is a lookup failure, and a lookup failure never means the branch is missing.

### `findReviewByBranch(branch)`, optional

It returns a bounded list of the reviews opened from a head branch, newest first, each with its id, URL, and target base, or an empty list.
Match within it by base, since one head branch can carry reviews against different bases.
A caller may act on a match, but a missing match never proves absence: a caller that would create something must prove absence otherwise, or stop and hold.

Use it only where a review may exist with no recorded id: a record written before review ids were recorded, or a bundle whose review opened before its `- Review:` line was committed.
When the adapter omits it, say so once, name the record, and take the unresolvable-record path in `trackers.md` or `stack.md`.

## Declared capabilities

Every adapter declares this table, read from its file and never probed.
An absent capability means false.

| Capability | Values | Drives |
| --- | --- | --- |
| `ciHooks` | true / false | Whether the merge-closer question is asked. |
| `draftState` | true / false | Whether `publishReview` does work, and when `inReview` is applied. |
| `pushesForYou` | true / false | Whether `openReview` owns the push. |
| `reviewLookup` | `by-id` / `none` | Whether the done-on-merge sweep can run. |
| `stackedReviews` | `retarget` / `declared-dependency` / `none` | What `openReview` does with `dependsOn`, below. |

- `retarget`: ignore `dependsOn`, since the previous bundle's branch as `base` is the whole mechanism and the forge retargets the review when its upstream merges.
- `declared-dependency`: pass `dependsOn` to the forge's dependency mechanism and scope the review to this bundle's commits, with no automatic retarget.
- `none`: ignore `dependsOn`; `base` chains the branches, and the calling skill states the dependency in the body.

## Adapter resolution

Explicit configuration resolves the adapter, and detection only suggests an answer to the first-run forge question.
Resolve in this order, first match winning:

1. `.fathom/forge.md`, the repo-local adapter, when the repository contains one.
2. When the profile records `forge: local` and that file is absent, stop, never falling back to a bundled file.
   Say that the profile points at the missing `.fathom/forge.md`, to be restored from `forges/TEMPLATE.md`, or that `forge` must name a bundled adapter or `none`.
3. When the profile records `forge: none`, run in the manual tier and make no offers.
4. The bundled adapter the profile's `forge` field names, such as `forges/github.md` for `forge: github`.
   When that file does not exist, stop and report the missing adapter and the field that named it.
5. Otherwise ask the first-run forge question.

Never infer a forge from a CLI on `PATH` alone, or from another repository's profile.

A team adds an unknown forge by committing a filled-in copy of `forges/TEMPLATE.md` as `.fathom/forge.md`, and a partial adapter with `reviewLookup: none` is valid.

### First-run forge question

Ask once per repository with the structured question mechanism in the agent file that `agents.md` routes to, and record the answer as `forge`.
First-run setup writes it into `.fathom/config.md` with its other answers, and a profile that exists without a `forge` line gets that line added.
Seed it with the first suggestion that applies: a bundled adapter matching the `origin` remote's host, then candidate forge CLIs found on `PATH`, then the manual tier.
Report what detection found and let the user choose.

## Capability tiers

Every run is in exactly one tier, stated at the start of the run.

**Tier 1, adapter.**
An adapter resolved and `verifyForge()` passed, so every operation is available.
When a resolved adapter fails `verifyForge()`, the run is in the manual tier, not tier 2: make no further calls through it, hand off as tier 3 does through the generic-git adapter, and name the failed check and its fix.

**Tier 2, assisted.**
No adapter resolved, and a candidate forge CLI is on `PATH`.
Push the branch, then offer three choices: use the candidate for this run only, write `.fathom/forge.md` now, or fall through to the manual tier.

**Tier 3, manual.**
No adapter and no candidate, the user declined tier 2, or the profile records `forge: none`, which makes this tier permanent.
Push the branch, then print the manual-handoff result through the generic-git adapter in forges/generic-git.md, which the manual tier runs on.
`getReviewState` is unavailable, so the done-on-merge sweep does not run, and a stack is never proposed.

### Adapter or nothing

Only a written adapter file, or the user's explicit acceptance at this stop of a named candidate CLI for one run, authorizes anything the agent executes against a forge.
The ordinary `git push` of the branch that tiers 2 and 3 run first is outside that boundary, since it needs no forge CLI.
This stop fires in both approval modes, and anything durable or unattended requires the adapter file.

The Absolute boundary in `SKILL.md` applies to forges too.
Never search for or read forge credentials in files, environment variables, or token caches.
Never call a forge's HTTP API directly.
Never modify the agent's or the user's configuration to install, enable, or authenticate a forge CLI.
A missing or unauthenticated CLI selects a tier.

### Tier 3 and issues that never close

In the manual tier no run can observe review state.
Still apply `inReview` at handoff, and say plainly that no later run will move the issue to `done` and that closing it is a manual step.
Record the same fact in the profile when `forge: none` is written.

## Base branch resolution

Feature branches start from, and reviews target, one base branch, resolved in this order:

1. The base the invocation names, for this run only.
2. The profile's `base-branch`.
3. The current branch, named in the run's output.

When the current branch is itself a Fathom feature branch, carrying an issue ref and a branch prefix, ask which base to use instead.
Fetch the base with `git fetch origin "+refs/heads/<base>:refs/remotes/origin/<base>"`.
This is the one Fathom definition of the fetch, so every Fathom step that reads `origin/<base>` runs it first, and no other Fathom file restates the command.
Create the new branch from that remote copy.
Confirm the base with `resolveBase` before opening a review against it.
