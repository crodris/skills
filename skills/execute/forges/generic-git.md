# Generic git

The fallback adapter for a forge this plugin cannot drive, needing only git and a reachable remote.
It implements the contract in `../forges.md`, and the manual tier runs on it.
Work is still committed, pushed, and handed to a human, but no run can observe the review afterwards.

## Declared capabilities

| Capability | Value |
| --- | --- |
| `ciHooks` | false |
| `draftState` | false |
| `pushesForYou` | false |
| `reviewLookup` | `none` |
| `stackedReviews` | `none` |

`reviewLookup: none` means the done-on-merge sweep cannot run here, and every skill that would sweep says so rather than reporting a clean sweep.
`ciHooks: false` means the merge-closer question is never asked, and the profile records `merge-closer: none (forge has no hooks)`.

## `verifyForge()`

Run `git rev-parse --git-dir`, then `git ls-remote origin >/dev/null`.
Verified when both succeed.
Do not ask for any particular ref, since `git ls-remote --exit-code origin HEAD` fails on a reachable remote that does not advertise `HEAD`.
An unreachable remote stops the push, so report it as a failure.
Never check for or ask about a forge CLI here.

## `resolveBase(branch)`

Look `<branch>` up as the `resolveBase(branch)` section of `../forges.md` says, and report a lookup failure as a failure to look it up.

## `openReview(branch, base, title, body, dependsOn?)`

The caller has already pushed the branch.
Return the manual-handoff result, with no review id, and print it:

- The branch that was pushed.
- The base branch it should target.
- The suggested title.
- The suggested body, in full.

Ignore `dependsOn`.
Then say all three:

- No review was opened, and opening it is now the user's step.
- The tracker issue is in the `inReview` phase anyway, so the board and the forge disagree until the user opens the review.
- No later run will move the issue to `done`, so closing it is manual, as `../forges.md` requires.

In the run's reporting, name the tracker phase and the missing review separately, never "in review" alone.

## `publishReview(id)`

A no-op.

## `getReviewState(id)`

Always `unknown`.
A caller infers nothing from `unknown`: it is neither `open` nor `merged`.
