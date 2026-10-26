# GitHub

The forge adapter for GitHub, driven through the GitHub CLI, `gh`.
It implements the contract in `../forges.md`, where a review is a pull request and a review id is a pull request number.

## Declared capabilities

| Capability | Value |
| --- | --- |
| `ciHooks` | true |
| `draftState` | true |
| `pushesForYou` | false |
| `reviewLookup` | `by-id` |
| `stackedReviews` | `retarget` |

GitHub retargets a dependent pull request when its upstream merges.
After a squash merge, the dependent branch still shows the upstream bundle's changes until it is rebased, so the calling skill decides rebases by commit ancestry.

## Absolute boundary

Never call the GitHub HTTP API directly.
Never read tokens from disk or the environment, including `GITHUB_TOKEN` and `GH_TOKEN`.
Never modify the user's `gh` configuration or run `gh auth login` for the user.
A missing or unauthenticated `gh` selects a tier per `../forges.md`.

## `verifyForge()`

Run `gh auth status`.
A missing binary and an unauthenticated one are both unverified.
When it does not verify, report the fix and stop:

- Install the CLI with `brew install gh` on macOS, or the platform package listed at https://github.com/cli/cli#installation.
- Authenticate with `gh auth login`.
- Re-invoke the skill.

## `resolveBase(branch)`

Look the branch up as the `resolveBase(branch)` section of `../forges.md` says.
A base that exists only locally is not a valid target.

## `openReview(branch, base, title, body, dependsOn?)`

The caller has already pushed the branch.
Wrap the body in `<!-- execute:start -->` and `<!-- execute:end -->`, outside the run markers, and pass the branch, the base, the title as given, and that body by following `../../file-pr/SKILL.md`.
The caller supplied this title and applied Body steps 1 to 4, so this is that title and body.
Follow `../../file-pr/SKILL.md`, reusing an open pull request for the branch or opening one.
From its `OPEN <number> <url>` result, return the number as the review id and the URL.
On `FAIL <reason>`, follow the openReview failure rule in step 11 of `../SKILL.md`, never return the manual-handoff result.
When it returns `HANDOFF <url>`, return the manual-handoff result.

Ignore `dependsOn`, since the base branch carries the dependency.
Never encode the dependency a second way, such as a label or an extra API call.
The `Depends on <url>` line in a body is prose, not a second encoding.

In the body, `Closes <ref>` closes a Linear issue through Linear's GitHub integration when the pull request merges into the default branch, and an Asana task URL is what Asana's GitHub integration attaches to.

## `publishReview(id)`

A no-op, since pull requests open ready for review.

## `getReviewState(id)`

Run `gh pr view <id> --json state,mergedAt`, and map it:

- `mergedAt` is non-null: `merged`, with `mergedAt` as the merge timestamp.
- state is closed and `mergedAt` is null: `closed-unmerged`.
- otherwise: `open`.

Look up each recorded id directly, never by listing pull requests.

## `findReviewByBranch(branch)`

Run `gh pr list --state all --head <branch> --json number,url,baseRefName,isCrossRepository --limit 10`.
Drop each result whose `isCrossRepository` is `true`, since a fork's pull request can share the branch name.
Return one record per pull request listed, newest first, with the number as the review id, its URL, and `baseRefName` as its base, or an empty list.
Never collapse the list to its newest entry.
Never use it for a record that already carries an id.
