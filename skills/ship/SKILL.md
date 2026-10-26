---
name: ship
description: Use when the user says "ship", "ship it", "/ship", "ship and merge", "take this all the way", "get this merged and released", or asks for the current branch to be carried from working tree to a merged release. Plain "ship" stops at a green pull request, and the merge needs a request that says to merge or a `merge` value of `yes` in the repository's `.ship/config.md`. Also use when the branch is already pushed or already has an open pull request and the user asks to finish it, and when the user asks to babysit, watch, or monitor a pull request or get it green without merging. Not for a single commit or a release cut from an already-merged main.
version: 3.0.0
---

# Ship

Run the full delivery pipeline for the CURRENT branch's work, end to end, without stopping between stages; hold mode ends before the merge.

## Precedence

Before anything else, check whether the repository ships its own version of this skill at `.claude/skills/ship/SKILL.md`, `.agents/skills/ship/SKILL.md`, or `.kiro/skills/ship/SKILL.md`.
When one exists, read and follow that file instead of this one, and say which file is driving the run.
It carries the repository's specialized pipeline, and it decides every stage, command, and convention wherever the two disagree.
What it cannot do is relax `boundary.md` in this skill's folder, which holds whatever any repository-local file says.
This skill is the fallback for every repository without one.

## Mode

Settle the mode in stage 0, as soon as `base` is resolved, and before touching the working tree.
Take the first rule that matches:

1. A request that explicitly says to merge, such as "merge it", "ship and merge", "get it green and merge it", or "get this merged", is merge mode.
2. A request for a green pull request, such as "babysit", "watch", "monitor", "get it green", or "don't merge", is hold mode.
3. `merge: yes` in `.ship/config.md` on `origin/<base>` is merge mode.
   Run `git fetch origin "$base"` first, then read it with `git show "origin/$base:.ship/config.md"`; a missing file or a missing `merge` line falls through to rule 4.
   Only the exact value `yes` counts, ignoring a trailing `# comment`; any other value is hold mode, and the report names the value.
4. Everything else, including plain "ship" and "ship it", is hold mode.

Hold mode runs every stage up to the merge, and stops after stage 3 with the pull request reported; stage 3 says when a merge-mode run stops at the same point.

## Boundary and slots

Read `boundary.md` and `config.md` in this skill's folder before any command.
When `../prove/` or `../file-pr/` is missing, stop and give the install command `npx skills@latest add crodris/skills -s ship prove file-pr`, adding `-g` for a global install.

## Stage 0 - Resolve the pipeline

Resolve every slot in `config.md`'s table before touching the working tree, so the run never pauses mid-pipeline to look for a command.
Resolve `verify` by the Resolve verify section of `../prove/SKILL.md`.
The pre-merge review is always the code reviewer that `../review-loop/SKILL.md` defines, never a slot, a command, or a review skill.

Resolve `base` before anything depends on it, and confirm it still exists on the remote.
When the user names a pull request, `base` is that pull request's base branch.
A `base` from `.ship/config.md` is a deliberate answer that may not be the remote's default branch, so never overwrite it with the default.
A base that has disappeared from the remote is a stop-and-ask.

The Mode section says how `merge` selects the mode.

### Merge method

`merge-method` is `squash`, `rebase`, or `merge`.
Every run reads it from `.ship/config.md`, without any trailing `# comment`, since babysit's base update follows it in hold mode too.
Read the repository's allowed methods with `gh api repos/<owner>/<repo> --jq '[.allow_squash_merge, .allow_rebase_merge, .allow_merge_commit]'`.
A failed call or a `null` value means the settings are unreadable.
A configured value outside the three, or one the settings show as `false`, is unresolved.
A merge-mode run with no resolved value uses the one method when exactly one is `true`.
Otherwise it asks under When to ask.
Offer one option per allowed method, or all three when the settings are unreadable, with these examples:

- `squash`: the branch's commits become one commit on `base`, titled like the pull request.
  Five work-in-progress commits become `feat(api): add rate limits (#42)`.
- `rebase`: each branch commit lands on `base` as its own commit, including work-in-progress and review-fix commits.
  An import authored by someone else stays separate from the commit that wires it in.
- `merge`: a merge commit joins the branch to `base`, keeping its commits and their shape.
  A release branch merged back into `main` stays visible as a branch.

### When to ask

Ask the user once, with AskUserQuestion, in a single round covering every slot still unresolved: the `verify` questions `prove` names, and a merge-mode run that Merge method leaves with no method.
Before prompting, check whether another local branch or worktree already carries a `.ship/config.md`, and offer to reuse it.
Put the detected candidates in as options, verbatim, and say the answer will be saved to `.ship/config.md`.
Never ask about a slot again later in the run: a slot still unresolved takes its absent default from `config.md` and is reported at the end.
The safety stops are not slot questions and always fire: an untracked file whose fate is unclear, a command outside `boundary.md`'s shape, and a base that vanished from the remote.
Record the answers as `config.md` says.

## Preflight

When the user names a pull request other than the current branch's, ship its head branch: stop when that head lives on a fork, and otherwise check it out, in a new worktree when the current checkout is dirty, and treat that worktree as one preflight created.

Confirm there is something to ship: a dirty tree, or commits ahead of the branch's upstream.
A clean tree with nothing ahead usually means there is nothing to ship - say so and do nothing else.
The exception is a branch whose work is already pushed and already has an open pull request into `base`: that run has nothing to commit but plenty left to do, so it skips to stage 3 and finishes the rest of the run.
Check for that pull request before stopping, because refusing it would make the skill unable to finish exactly the runs its own triggers describe.

On the resolved `base` with uncommitted work or with local commits ahead of its upstream, move all of it to a feature branch before anything else.
Key this on `base`, not on whatever the remote calls its default branch: a project whose `base` is a release branch hits this exactly the same way, and a rule written around the default branch simply never fires there.
Respect the resolved `worktrees` convention when there is one, and `mkdir -p` the worktree parent first, because git does not create missing parents.
Transfer uncommitted work losslessly: `git stash push --include-untracked`, apply it in the new branch or worktree, and VERIFY every expected file arrived before dropping the stash or resetting the default branch.
A `.ship/config.md` this run just wrote is part of that work, so confirm it arrived too.
Stashes are shared across worktrees, so the apply works from either side.
Never reset the default branch while the stash is the only copy of the work.
Cherry-pick the local `base` commits onto the feature branch, branching from the fetched `origin/<base>` that stage 0 resolved rather than from whatever the remote calls its default, so the cherry-pick is meaningful and the new branch starts where this run intends to merge back.
Then, once every local `base` commit is on the feature branch, reset the local `base` to its upstream.

The shipping branch is settled once this section is done.
Assert it: the settled branch must not equal `base`, and a run that somehow reaches this point still on `base` is a stop, never a push.
Then commit any `.ship/config.md` stage 0 wrote, on its own, before stage 1 starts.
When the settled branch has never been pushed and is behind `origin/<base>`, run `git rebase --autostash "origin/$base"` and resolve any conflict the way the change intends.

## Stage 1 - Prove

Verify is the only gate before the first push.
Read `../prove/SKILL.md` and follow it with `base`, what changed and why, and a commit message for the change.
On `FAIL`, stop and report what still fails, and push nothing.

## Stage 2 - Push, open the review

Hold the branch preflight settled as `$branch` and `base` as `$base`, each validated once with `git check-ref-format --branch`, and pass them only as quoted arguments.

1. Push with `bash <this skill's directory>/guard.sh "$branch" "$base"`.
   Exit 3 is a stop-and-report: the checkout is not the shipping branch.
2. Read `../file-pr/SKILL.md` and follow it with the settled branch, `base`, and this run's section.
   That section carries the summary and the verification evidence, with the drive's evidence path from the `PASS` line when one ran; stage 3 adds the review outcome to it once there is one.
   It returns `OPEN <number> <url>`, or `HANDOFF <url>` without a working `gh`, which ends the run after reporting, with no merge and no release watch.

## Stage 3 - Babysit

Read `../babysit/SKILL.md` and follow it with the pull request number and the mode.
It returns `READY <sha>`, `AWAITING-APPROVAL <sha>`, or `BLOCKED <reason>`.
In hold mode, and on `AWAITING-APPROVAL` or `BLOCKED`, stop here and report the pull request with that SHA, skipping the merge, the release watch, and the cleanup.

## Stage 4 - Merge, release, cleanup

1. On `READY` in merge mode, run `bash ../babysit/watch.sh <pr> <settled-sha> --repo <owner/name>` with no `--bot` on that SHA, the way babysit runs it.
   Exit 0 goes on, and any other exit is a stop-and-report.
   Re-read the pull request and confirm it is still open, still targets `base`, and its head is still that SHA; any of the three failing is a stop-and-report.
   Never merge past a required approval with `--admin`.
   Otherwise merge that SHA explicitly with the resolved method: `gh pr merge <n> --<merge-method> --match-head-commit <settled-sha>`, adding `--delete-branch` only when this run did NOT use a worktree.
   With `squash`, keep the subject identical to the pull request title, because release tooling may parse it.
   On a worktree run, leave both deletions to the cleanup step, which removes the worktree first and then deletes the local and remote branch in the right order.
   Record the SHA `gh pr view <n> --json mergeCommit --jq .mergeCommit.oid` prints, which is the commit the merge put at the tip of `base`; the next step needs it to know which run is this run's.
   From the merge through step 3 and the final report, run every command in the foreground and do not end the turn.
   This replaces babysit's background default for the rest of this ship run, and step 2's repeated calls are the one wait that babysit's ban on polling loops does not cover.
   Once the pull request has merged, a host may close the agent's session as soon as the turn goes idle, which kills every background command.
   T3 Code does this when it settles a thread whose linked pull request merged.
2. Watch the base-branch pipeline after the merge, following the run whose head SHA is the SHA step 1 recorded.
   Whatever the project releases with, that run reaching a successful terminal state is the pass condition, and nothing else is.
   With semantic-release or similar, a landed release commit descending from the recorded merge is necessary but not sufficient: wait for its run to finish successfully too, since a release job can push the commit and then fail on publishing, tagging, or a downstream step.
   A finished-but-failed run is a stop-and-report, never a silent pass.
   Give this wait a deadline of roughly thirty minutes past the run's own typical duration; past it, report that the release did not settle and leave the merge as it stands.
   Find the release run with `gh run list --branch "$base" --commit <recorded-sha>`, and list again until it appears, since it can take a few seconds to start.
   When no release run appears within 5 minutes, report that the base branch started no run for that SHA.
   Wait on it with `gh run watch <run-id> --exit-status` under a time limit below the tool's timeout: `timeout <seconds>` on Linux, or `perl -e 'alarm <seconds>; exec @ARGV'` on macOS, which has no `timeout`.
   After each call, read `gh run view <run-id> --json status,conclusion`: a release run whose status is not `completed` means call again, and a completed one with any conclusion but `success` is a failed release run.
   The deadline counts across every call, and once it passes, stop calling and report that the release did not settle.
   Never push anything to the base branch while its release job may still be running.
3. Run the resolved `post-merge` command when there is one, and let it define its own scope.
   Otherwise the cleanup depends on whether preflight made a worktree.

   When it did, work from a checkout that is not the one being removed - the main worktree, or any checkout already on `base`.
   Never check out `base` inside the shipping worktree: git refuses a branch already checked out elsewhere, and the worktree is about to be removed from underneath that checkout anyway.
   Remove the worktree first, then the branch.

   When it did not, this checkout is the only one there is, so switching it to `base` is both allowed and required: the shipping branch cannot be deleted while it is checked out.
   Switch to `base` only after the merge is confirmed, since that is the moment the branch guard has no more work to do.

   Either way, `git fetch --prune`, then fast-forward `base` with `git merge --ff-only origin/<base>` and leave it alone if that refuses; a plain `pull` on the base branch can merge or rebase work this run never looked at.
   Then clean up ONLY what this run created: the branch it shipped and, when it made one, that branch's worktree.
   The guard here is on the deletion target, not on the current checkout - by this point the checkout is deliberately on `base` - so delete a branch only when its name equals the settled one, and remove a worktree only when it is the one preflight created.
   Confirm the merge through `gh pr view` before any `-D`, since a squash or rebase merge leaves no ancestry for `git branch --merged` to see, and confirm the worktree is clean before removing it.
   Leave every other local branch and worktree alone: they belong to work this run knows nothing about, and a sweep of everything that looks merged is how unrelated work disappears.

## Reporting

Give one final summary covering: the mode and the Mode rule that chose it, how the pipeline was resolved and whether the user was asked, the verify rounds and result, the lane and why it was chosen, the pull request number, the review bots found or that none were, the subagent rounds and each bot's passes and what each caught, the number of pushes, the drive evidence when there was one, the merge and the method it used, the release version or "no release", and the cleanup state.
Name `.ship/config.md` when this run wrote or updated it, and say which slots the user answered.
Say so too when a recorded answer could not be written because the run skipped to stage 3, and when a command was dropped from a tier's answer, naming the command and why.
Take the review rounds, bot passes, pushes, and skipped reviews from babysit's run section in the pull request body.
Surface anything skipped, red, or deferred the moment it happens, not only at the end.

## Red flags

Each of these means stop and correct course, not continue:

- About to ask a second slot question after stage 0 has already asked one; the safety stops are not covered by that rule and always fire.
- About to merge while any check is pending, or after babysit returned anything but `READY`.
- About to call a red release run "done" because the merge itself succeeded.
- About to merge in hold mode, or with `--admin` past a required review.
