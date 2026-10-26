# Forge adapter template

Copy this file to `.fathom/forge.md` in your repository, fill it in for your forge, and commit it.
A repo-local adapter wins over every bundled one, so this plugin does not need to be forked.

Before copying, read `../forges.md` for the contract, `github.md` for a complete example, and `generic-git.md` for the minimum one, all inside the plugin's `skills/execute/forges/` directory.

Guidance is in `>` blockquotes.
Delete each one as you fill its section in.

> **Write for an agent.** An agent reads this file at runtime and does what it says.
> Give exact commands.
> When a command's output needs interpreting, say which field to read and what each value means.

> **A partial adapter is legitimate.** Implementing `verifyForge`, `resolveBase`, and `openReview`, writing `publishReview` as a no-op when the forge publishes a review when it opens, and declaring `reviewLookup: none` with `getReviewState` always `unknown` opens reviews correctly and leaves the sweep unavailable.
> Never stub an operation with a guess: a wrong `getReviewState` closes issues that never shipped.

---

# <Forge name>

<One or two sentences: what this forge is, and which CLI drives it.>

## Declared capabilities

| Capability | Value |
| --- | --- |
| `ciHooks` | true / false |
| `draftState` | true / false |
| `pushesForYou` | true / false |
| `reviewLookup` | `by-id` / `none` |
| `stackedReviews` | `retarget` / `declared-dependency` / `none` |

> `ciHooks`: true only when a workflow can run in your repository on merge, the way GitHub Actions does.
> When false, the merge-closer question is skipped.
>
> `draftState`: true when your forge distinguishes a draft review from one that has notified reviewers.
> When it creates drafts by default, `publishReview` must do real work.
>
> `pushesForYou`: **get this one right.** Set true when your review CLI pushes the review ref itself, and the calling skill will not push.
> A wrong false makes the caller push as well, which produces a wrong branch state.
>
> `reviewLookup`: `by-id` only when you can look up one review's state directly, from any clone, given the id `openReview` returned.
> When reviews can only be found by listing, or not at all, use `none`.
>
> `stackedReviews`: pick the value in `../forges.md` that matches how your forge stacks reviews.
> `none` is a fine answer for a forge with no stacking model.

## Absolute boundary

> Keep this section.
> It stops an agent from routing around a missing credential.

Never call this forge's HTTP API directly.
Never read tokens from disk or from the environment.
Never modify the user's CLI configuration, and never authenticate on the user's behalf.
When the CLI is missing or unauthenticated, report the fix and stop.

## `verifyForge()`

<The one cheap, read-only command that proves the CLI is present and authenticated.>

> It runs on every invocation, so make it read-only and fast.
> An auth-status subcommand is ideal.
> Never create, modify, or list large amounts of data.

Treat a missing binary and an unauthenticated one identically: unverified.

When it does not verify, report the fix:

- <How to install the CLI.>
- <How to authenticate.>
- Re-invoke the skill.

## `resolveBase(branch)`

<How to confirm the named base branch exists on the remote and can be merged into.>

> Look the branch up as the `resolveBase(branch)` section of `../forges.md` says.

## `openReview(branch, base, title, body, dependsOn?)`

<The command that creates the review.>

> State whether this pushes.
> When `pushesForYou` is true, say that the caller must not push to open the review.
> Commits the caller makes afterwards, including the final closing commit, stay the caller's to push, per `../forges.md`.
>
> **Make it idempotent.** When a review for this branch against this `base` already exists, skip creation and return it.
> Skills re-run on the same issue to resume, and a second review is a real failure.
>
> **Say exactly how to extract the review id** from the command's output: which field, which format.
> Later runs look it up from any clone, so it must be stable, and a branch name is not one.
>
> **Say what you do with `dependsOn`, even when the answer is nothing.** For `retarget`, write "Ignore `dependsOn`" and say that `base` carries the relationship.
> For `none`, write "Ignore `dependsOn`" and say that `base` chains the branches and the caller states the dependency in the review body.
> For `declared-dependency`, give the exact command that records the dependency and how you scope the review to this bundle's commits, since an unscoped range shows the upstream bundle's changes twice.

Return the review id and the review's URL, or the manual-handoff result from `../forges.md` with no review id.
On failure, follow the openReview failure rule in step 11 of `../SKILL.md`.

<Note any body conventions your forge interprets: issue-closing keywords, trailers, required footers.>

## `publishReview(id)`

<The command that moves a draft review to notified-review state.>

> When `draftState` is false, write "A no-op." and nothing else.
>
> When your forge creates drafts by default, this operation matters: without it the tracker says "in review" while no reviewer has been notified.

## `getReviewState(id)`

<The command that reads one review's state by id, and how to map its output.>

Map the result to exactly one of:

- `merged`: the change landed. <Which field proves this, and where the merge timestamp comes from.>
- `closed-unmerged`: the review ended without landing. <Which field distinguishes this from merged.>
- `open`: still in flight.
- `unknown`: cannot be determined.

> **Take care with merged and closed-unmerged.** `merged` closes the tracker issue.
> When your forge reports both as "closed", map to `closed-unmerged` unless a field proves the change landed.
>
> When you cannot look up one review by id, do not improvise a listing here.
> Declare `reviewLookup: none` and write "Always `unknown`." in this section.

> **When `reviewLookup` is `none`,** also state that no later run will move an issue from `inReview` to `done`, and that closing issues is manual in this repository, as `../forges.md` requires at handoff.
