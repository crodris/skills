# Tracker adapters

Call the tracker only through the operations below, never through tracker tools directly from a skill body.
Resolve the adapter at runtime, before any tracker work.

## The contract

Use exactly these nine operations.
Adapter files implement each one against one tracker's tools.

| Operation | Purpose |
| --- | --- |
| `getIssue(ref)` | Fetch one issue's title, description, type or labels, URL, native id, current state, and existing children. |
| `listSubIssues(ref)` | List an issue's existing child issues, each with the ref `createSubIssue` returns, title, and state. |
| `listDestinations()` | List where a new top-level issue can be created (Asana projects, Linear teams), each as a destination value paired with a display name. |
| `resolveDestination(hint?)` | Turn a hint, or the profile's default destination when no hint is given, into one destination value; return null when the result is ambiguous. |
| `createIssue(title, description, type, destination)` | Create a top-level issue in the destination; return its ref and URL. |
| `createSubIssue(parentRef, title, description)` | Create a child issue under a parent; return its ref and URL. |
| `updateState(ref, phase)` | Move an issue to `inProgress`, `inReview`, or `done` through the profile's state mapping, never a hardcoded status name. |
| `comment(ref, body)` | Post a comment on an issue. |
| `listComments(ref)` | List an issue's comments, newest first, with at least each body. It exists so the sweep can read markers an earlier run wrote. When the MCP has no comment-listing tool, treat it as unavailable and use the fallback the sweep defines. |

The destination value is adapter-owned and opaque: skills only pass it between `listDestinations`, `resolveDestination`, and `createIssue`, and store it in the profile.

### Destination resolution

Resolve a new top-level issue's destination from the invocation's hint, or else from the profile's `default-destination`.
When neither exists, or `resolveDestination` returns null for the hint, call `listDestinations`, list the destinations, and ask once which one to use.
Never infer a destination from `.fathom/tasks/*.md`, from prior issues, or from any other source.
The question may suggest a destination that prior issues used, and it still waits for the answer before anything is created.
In auto mode, when `listDestinations` returns exactly one destination, record and report it instead of asking, per `approval.md`; any other count is asked in both modes.
A hint applies to its invocation only.
Change the profile's `default-destination` only when it is absent or the user asks to change it.

## Base branch resolution

Base branch resolution lives in `forges.md`.
First-run setup in `first-run.md` writes the profile's `base-branch` field.

## Preflight verification

Run this before any other tracker operation on every invocation, even when an earlier run in this session verified the MCP.

Infer the tracker by this precedence, which is also how every skill resolves the tracker for the run:
1. A tracker the invocation names explicitly.
2. The shape of a reference in the invocation, a pasted URL, or, for a skill that works on an existing issue, the current branch name, per Runtime resolution below.
3. The profile's `tracker` field.
4. The connected tracker MCPs.

Verify that tracker's MCP with the one cheap read-only call its adapter file names.
Treat any failure, missing tools, or a disabled server as unverified.
When it is unverified, start no tracker work and attempt no workaround: output the adapter file's setup instructions, tell the user to connect the MCP and re-invoke the skill, then stop.

In the same pass, resolve the forge adapter per `forges.md`, call its `verifyForge`, and read its declared capabilities for the rest of the run, so a user missing both gets one report.
When the repository has no `.fathom/config.md` yet, leave the forge unresolved here, since first-run setup asks the forge question as its question 3, and resolve the adapter once setup writes the profile.
An unverified forge does not stop the run: it selects a capability tier per `forges.md`, and a resolved adapter that fails `verifyForge` selects the manual tier with no further calls through it.
State the resolved tier and the fix for reaching a higher one before any work.
In every tier, follow Adapter or nothing in `forges.md`.

## Done-on-merge sweep

Run this before any other tracker work on every invocation, once preflight has verified the MCP.
It finds issues from repository state, and only its closure action goes through the tracker adapter.
Run it only when the resolved forge declares `reviewLookup: by-id` and the run is not in the manual tier, which includes an adapter that failed `verifyForge()`, per `forges.md`.
Otherwise skip the sweep and say once that it was skipped and why.

Search all of `.fathom/` for recorded reviews, not only `tasks/`, since a beads-backed issue's only record is its plan document under `plans/`.
Keep only records whose `- Issue:` URL belongs to the run's resolved tracker, and leave the others for a run of that tracker.
For each issue found, collect every recorded review id before deciding anything about it.
A single-review issue records one id, and a stack records one per bundle in the plan document's `Bundles` section, per `conventions.md`.
A stack's `- Review:` lines are spread across its bundle branches.
Read the branch names from the `Bundles` section.
For each branch, look it up as the `resolveBase(branch)` section of `forges.md` says.
Skip a branch that section says is missing.
When a lookup fails, including a name that fails validation, leave the issue undecided, as case 2 below does.
Fetch each other branch with an explicit refspec, the way the Base branch resolution section of `forges.md` fetches the base, with the branch name in place of `<base>`.
Read the plan document from those branches and from `origin/<base>`, the issue's resolved base, fetched as the Base branch resolution section of `forges.md` says, and take every `- Review:` line in each copy, not only the line for that branch's bundle.
A bundle has no record when it has no `- Review:` line on the current branch or any fetched branch, or when its review id stays unavailable.

Call `getReviewState` on each id directly, never matching ids against a bounded listing of the forge's reviews.

A legacy record carries a branch name and no id.
When that issue's tracker state is already `done`, skip it.
Otherwise call the optional `findReviewByBranch` from `forges.md`.
Keep only candidates whose base is the resolved base branch, which `resolveBase` confirmed.
Treat the record as resolved only when exactly one candidate remains.
Add a resolved id to the issue's set and call `getReviewState` on it before evaluating any case below.
Leave the record unchanged and resolve it again on each later sweep, since a commit made now would land on this run's branch.
When resolution fails, or the adapter lacks the operation, report the record once and count it as unresolved.

Judge each issue on all of its results together, taking the first case below that applies.

1. Any review reports `closed-unmerged` and no later review recorded for the same issue, or on a stack for the same bundle, replaced it.
   Apply Reviews closed without merging below for that review, and on a stack name the bundles above it that it orphans.
   Close nothing for the issue, whatever its other reviews report.
2. Any review reports `unknown`, any bundle from 1 to N has no record, or a legacy record is unresolved.
   N comes from the `Bundles` section, so a missing record is visible.
   Change nothing about the issue and report nothing about its progress.
   Name the `unknown` ids, the missing bundles, the unresolved records, and any branch whose name or lookup failed, and say the issue was left undecided because of them.
   Never count any of them as `merged`, `open`, or still in review.
3. Every review reports `merged`: apply the merged path below.
   On a stack that means every bundle.
4. Some reviews merged and others are open: close nothing, and report the partial progress, naming the merged bundles.
5. Every review is `open`: close nothing, and say the work is still in review.

Cases 2, 4, and 5 leave the issue's phase unchanged.

On the merged path, read the issue's current state first.
When it is already complete, as after a merge-closer Action or a native integration closed it, do nothing more for that issue.
Otherwise apply `done` through `updateState`, plus any merged-path closure action the adapter defines.
An issue recorded with `- Merge-closer: suppressed` relies on this sweep alone for closure, and the state read still applies to it.
That state read is the merged path's whole idempotency, so write no stamp, marker, or file to record a merge.

### Reviews closed without merging

Treat a `closed-unmerged` result as an abandoned attempt.
Never mark the issue done, and never move its phase back, since retrying, rescoping, or dropping the work is the user's decision.
Report it: name the issue and the review, say the review was closed without merging, and ask whether to resume the work on a fresh branch or move the issue back to `inProgress`.

Record the report once as a comment on the issue through `comment`, carrying this sentinel line:

```
fathom: review-closed-unmerged <review url> <date>
```

Before reporting, call `listComments`, and skip the issue when any comment already contains the sentinel for that review, matched as a substring anywhere in the comment stream.
Also accept the legacy sentinel `workbench: review-closed-unmerged`, and write only the current one.
Keep the marker on the tracker, never in a file, since a file marker would need a push to the usually protected base branch.
When the tracker cannot list comments, write no marker: report the review on every run, and say that it repeats because the tracker cannot hold the marker.
Still read existing `- Review closed unmerged:` and legacy `- PR closed unmerged:` lines in `.fathom/` as valid markers.
Report again when a different review for the same issue is closed unmerged.
A review recorded after an abandoned one, for the same issue or bundle, replaces it in the sweep's cases, so a later merged review closes the issue normally.

## Runtime resolution

Decide which tracker owns a reference by the first rule that matches.
- An Asana URL, a bare numeric GID, or a ref with the prefix `asana`, as in `feat/asana-482913-add-login`, is Asana.
- A reference shaped like `ABC-123`, a short prefix, a dash, and digits, is Linear, with the prefix uppercase in a key and lowercase in a branch name, as in `feat/onc-5-add-webhooks`.
- When the shape is unclear and exactly one tracker MCP is connected, use that tracker.
- When both are connected, ask the user once which tracker they mean.
- When neither is connected, stop and name both supported trackers, Asana and Linear, telling the user to connect one.

Discover the chosen MCP's actual tool names at runtime, since the adapter files' tool names are only hints.
When the resolved tracker's MCP is not connected, stop and name it, and never fall back to the other tracker.
The connected tracker MCP is the only channel for tracker operations, under the absolute boundary in each skill's `SKILL.md`.

## Tracker profile

The tracker profile lives in `.fathom/config.md`.
When the working tree has no `.fathom/config.md`, read `first-run.md` and follow it.
Otherwise apply these rules on every load:
- When `git ls-files -u -- .fathom/config.md` lists the file, or it holds a leftover conflict marker, stop and hold as `approval.md` says for a conflict while updating from the base branch, so the user resolves it in place.
  Never re-run setup on it or hand-merge it.
- Otherwise use the profile without re-prompting.
- When the profile has no `merge-closer` line, run the tracker adapter's merge-closer check.
  When the resolved forge declares no `ciHooks`, record `merge-closer: none (forge has no hooks)` and skip the question.
  When nothing the adapter offers works on the resolved forge, record `merge-closer: none` with the reason.
- Re-run the setup questions in `first-run.md` when a mapped state no longer exists in the tracker, or when the user asks to redo setup.
- Commit every edit a run makes to the profile as Committing the profile in `first-run.md` says.
