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

Hold mode runs every stage up to the merge in stage 3, step 7, and stops there with the pull request reported; step 7 says when a merge-mode run stops at the same point.

## Boundary and slots

Read `boundary.md` and `config.md` in this skill's folder before any command.
When `../prove/` or `../file-pr/` is missing, stop and give the install command `npx skills@latest add crodris/skills -s ship prove file-pr`, adding `-g` for a global install.

## Stage 0 - Resolve the pipeline

Resolve every slot in `config.md`'s table before touching the working tree, so the run never pauses mid-pipeline to look for a command.
Resolve `verify` by the Resolve verify section of `../prove/SKILL.md`.
The pre-merge review is always the code reviewer that stage 3 defines, never a slot, a command, or a review skill.

Resolve which review bots the repository runs, and whether each reviews every push or only the first, by reading `bots.md` in this skill's folder.
A repository with none is a normal run that reviews with the subagents alone.

Resolve `base` before anything depends on it, and confirm it still exists on the remote.
When the user names a pull request, `base` is that pull request's base branch.
A `base` from `.ship/config.md` is a deliberate answer that may not be the remote's default branch, so never overwrite it with the default.
A base that has disappeared from the remote is a stop-and-ask.

When `light-paths` or `security-paths` is set, read `lanes.md` in this skill's folder before resolving the lane, and apply it at every step it names.
When `drive` is set, read `../prove/drive.md`.
The Mode section says how `merge` selects the mode.

### Merge method

`merge-method` is `squash`, `rebase`, or `merge`.
Every run reads it from `.ship/config.md`, without any trailing `# comment`, since step 4's base update follows it in hold mode too.
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

## Stage 3 - Review, fix each pass in one batch, confirm, merge, release, cleanup

Review gates the merge, not the pull request.
This stage spends every reviewer's first pass on the same pushed head at the same time, then pays for one batch of fixes per pass, and keeps confirming only while a reviewer still finds something blocking.
The normal run is two pushes, the one stage 2 made and the batched fixes, and a run with nothing blocking is one.

The code reviewer is two `general-purpose` subagents on the same pinned SHA, one per axis, so a change that passes one axis cannot hide a failure on the other.
The Standards reviewer checks the diff against the conventions this repository documents: AGENTS.md, CLAUDE.md, CODING_STANDARDS.md, contributing docs, and the intent behind its lint and format config, read from `origin/<base>` so a change cannot rewrite the rules it is graded against.
The Spec reviewer checks that the diff does what the originating issue or the pull request's stated intent asked, and reports what is missing, wrong, or not asked for.
Wherever this skill says the code reviewer, it means the Standards and Spec subagents together, dispatched in parallel; they share every round and confirmation pass, and their findings go through one triage and one root-cause dedupe.
Whenever a lane runs this review or the security lane's review beside it, dispatch each as the host agent's general-purpose subagent, subagent_type `general-purpose` on Claude Code, and write its brief from the change's intent and the SHA of the head it reviews; never pick any other agent type, including a plugin agent such as `coderabbit:code-reviewer`, since a named agent can wrap a vendor CLI or carry a generic brief.
A review skill offering to handle it - including one whose own description says it triggers whenever a review is needed - is describing the general case, and this run is not it: this run's reviewer is settled here, and a skill that shells out to a vendor CLI is the thing this rule exists to keep out.

On Claude Code, set each subagent's Agent `model` from this table; a host with no per-subagent model runs them on its default.
A full-diff round reads the whole change, and a confirmation pass reads only fix commits or conflict resolutions.

| Subagent | Full-diff round | Confirmation pass |
| --- | --- | --- |
| Standards | `sonnet` | `sonnet` |
| Spec | `opus` | `sonnet` |
| Security (security lane) | `opus` | `opus` |

1. Launch every reviewer against the pushed head, concurrently.
   Capture that head's SHA once, before launching any, and hold every reviewer to it: each subagent is told the SHA and reviews that diff, and a bot's review counts only when it settled as `bots.md` defines it.
   Review dispatches the code reviewer's Standards and Spec subagents in parallel, in the background, on the diff of the pushed head against `base`, each told what changed and why.
   When a lane is configured, `lanes.md` says whether it skips them or adds a security subagent beside them.
   All are subagents, never a review CLI nor a review skill that wraps one.
   Tell each what stage it is: findings feed one batched fix rather than a loop, and severity is what sorts them in step 3, so require exactly one severity per finding, drawn from critical, major, minor, nit, or informational.
   Quote each the line step 2 draws between minor and nit, word for word, so its labels start where triage will put them.
   A subagent that returns nothing usable fails its round rather than passing silently: record that the review produced no result, and run that subagent again, not the ones that returned.
   Give it a timeout, generous against the size of the diff, and treat one that blows through it the same way.
   Any one subagent failing twice in a row is a stop-and-report rather than a merge without it, because its axis has not reviewed the run.
   Wait on the checks and on every review bot `bots.md` finds present, including one that first shows up on this pull request, by running `bash <this skill's directory>/watch.sh <pr> <captured-sha> --repo <owner/name>` with one `--bot` per bot this pass waits on, named as `bots.md` says.
   It also waits on the SHA's GitHub Actions workflows until they finish, and it never settles in its first 120 seconds, so a workflow that registers after another one passed is still waited on.
   Run it in the background where the harness notifies on exit, and act on its exit code; never write a polling loop.
   Exit 0 or 1 goes on to step 2's triage, with any failed check it names among the findings.
   Exit 3 is step 2's restart, never a new SHA to chase, and exit 7 is a stop-and-report that the pull request is no longer open.
   Exit 4 is a stop-and-report that the review never settled.
   Exit 5 and exit 6 are a stop-and-report that quotes the error or the bot's notice the script printed.
   Any other exit is a stop-and-report.
   When the harness cannot run a command in the background, run it in the foreground with `--deadline` above 120 seconds and below the tool's timeout, raising that timeout when it is lower, because watch.sh never settles in its first 120 seconds.
   Each bot is a final bar and is never skipped: the code reviewer is a different reviewer with a different brief, and a clean code reviewer round says nothing about what a bot will find.
   A first-push-only bot, with its mode read as `bots.md` says, is waited on in this pass, and in a later one only for a review that step 5, `bots.md`, or `lanes.md` requests.
   Collect findings from every surface - inline comments, the summary comment, full review bodies, and the summaries bots write into the pull request description - because nitpicks hide in collapsed sections.
   Read inline threads with their resolution and outdated state (on GitHub, the GraphQL `reviewThreads` nodes with `isResolved` and `isOutdated`), and skip a thread that is resolved or outdated, so a later pass does not re-triage a finding on code that has since changed.
   Skipping a thread settles nothing: a blocking fix still needs step 5's confirmation, and a finding a bot repeats on the new head is still unresolved under step 6.
   Wait for EVERY reviewer before touching the tree: a fix pushed while any is still reading stales that reviewer's diff, and splits one batch into two pushes.
2. Triage every finding with rigor, then dedupe by root cause.
   Re-read the pull request's head first: when it no longer equals the SHA every reviewer read, a push landed underneath them, so discard every result and restart the pass on the new head; a second discard in a row is a stop-and-report, since something outside this run keeps pushing to the branch.
   When another pull request, open or merged, already makes this one obsolete, stop, report it, and ask before closing this one.
   Reviewers are sometimes wrong, so check each claim against the code before acting on it.
   No reviewer's labels are this skill's severities: assign every finding exactly one of critical, major, minor, nit, or informational from what it describes, not from what a bot or a subagent called it.
   A finding with no severity, or with one outside that set, is severity-assigned here the same way, and treated as major when triage cannot place it.
   Minor and nit sit on opposite sides of step 3's bar, so place that line deliberately: a nit is cosmetic, such as formatting, wording, or a naming preference, and changes nothing the product or the next reader depends on; a defect, code smell, or piece of tech debt is at least minor, whatever section a bot filed it under.
   Placing a severity and confirming a claim are separate judgments on separate axes: a finding whose severity triage could not place is not thereby a finding triage could not confirm, and it still gets a confirmation attempt rather than falling into that bucket by default.
   Two independent reviewers often land on the same root cause, and that is one finding with two reports: it gets one fix, and each report gets the disposition.
3. Sort the surviving findings into blocking and non-blocking, and fix only the blocking ones.
   Blocking means a verify failure, a failed drive, a failed check that the change caused, or a review finding at critical or major severity that triage confirmed.
   Read a failed check's log (`gh run view <run-id> --log-failed`) before judging it; a failure that traces to the diff or reproduces locally is the change's.
   An infrastructure failure, such as a lost runner, a network or registry timeout, a rate limit, or a cache error, is rerun once with `gh run rerun <run-id> --failed`, and the same check failing again on the same SHA is a stop-and-report.
   A failure that is neither, such as a check already red on `base` or a test that fails intermittently, is a stop-and-report.
   A minor that triage confirmed is blocking too when the fix is worth making before merge and stays contained: it changes only the code the finding names, plus at most a test for it, and adds no behavior the change did not already intend.
   Judge every confirmed minor on its own, whether or not anything else blocks, rather than dispositioning minors as a class; worth fixing covers a real defect and a code smell or piece of tech debt the next reader would trip over, and triage states in one sentence why the code is better after the fix.
   A minor whose fix sprawls past the flagged code, is speculative, or is pure preference stays non-blocking, and its disposition says which; a smell that needs a wider refactor names that follow-up in its disposition instead of growing this push.
   A worth-fixing minor rides any push a critical or major buys, but minors buy a push on their own only once per run; after that, a minor still rides a push a critical or major buys and otherwise is dispositioned, because fixing minors found in minor fixes is how the loop stops converging.
   Everything else - nit, informational, cosmetic style, a minor judged not worth fixing or not contained, and anything triage could not confirm against the code - is non-blocking: give it a disposition and the reason, and move on.
   For a non-blocking bot finding, reply under the bot's comment and resolve its thread (on GitHub, the GraphQL `resolveReviewThread` mutation); a blocking one's thread waits for step 5.
   A finding that came only from a bot's summary in the description has no thread, so record its disposition in this run's section of the pull request body.
   For a subagent finding, record it in this run's section of the pull request body.
   Start every reply under a bot's comment with a label line and a rule, so a reader can tell the agent's replies from the user's:

   ```markdown
   [<model id>] replying on behalf of @<forge login>

   -----

   <reply>
   ```

   A non-blocking finding never causes a push.
   Apply one only when the edit is a one-liner, touches nothing the blocking fixes touch, AND a blocking fix is already buying the push it rides; when in doubt, disposition it.
4. Apply every blocking fix, from every reviewer, in ONE batch.
   Run `../prove/SKILL.md` on the batch, re-check the lane, then push once with `guard.sh` as stage 2 does; the drive is step 5's to run, not this step's.
   When the pull request conflicts with `base`, or `base` requires an up-to-date branch and this one is behind, the batch also runs `git fetch origin "$base"` and merges `origin/$base` into the branch, resolving any conflict the way the change intends; a squash merge in step 7 drops that merge commit.
   When the resolved merge method is `rebase`, rebase the branch onto `origin/$base` instead, before committing the fixes, since a rebase merge needs a branch with no merge commits.
   Record the merge base and the head from before the rebase as `<old-base>` and `<old-head>`, and the rebased tip as `<rebased-head>`.
   Push the rebased branch with `guard.sh` and the head the reviewers read as its lease, and only when the branch is exclusively this run's; otherwise stop and report.
   A run takes at most one base update, riding a push or buying one, and a branch that needs a second is a stop-and-report.
   Update this run's section of the pull request body with the review outcome and every disposition recorded so far.
   When nothing was blocking and no base update was due, nothing is pushed, and this pass is the one step 6 can terminate on.
5. Confirm each push once, and only when step 4 pushed.
   The push buys one confirmation pass on the new head: each bot that reviews every push re-reviews it on its own, and concurrently the code reviewer's subagents read the fix commits alone, at the same bar, without re-reading the whole change.
   Standards checks the fix commits against the documented conventions, and Spec checks that each one resolves the finding it was pushed for and adds nothing else; a fix that does not resolve its finding leaves that finding open under step 6, whether or not a bot repeats it.
   A base merge is confirmed on its conflict resolutions alone (`git show --remerge-diff <merge-sha>`).
   A base rebase is confirmed on `git range-diff <old-base>..<old-head> origin/$base..<rebased-head>`, with the values step 4 recorded.
   A base update with no conflicts needs verify and the checks, not a subagent read.
   A first-push-only bot is re-requested here when the push fixed a confirmed critical or major that bot raised.
   For a bot that labels its own findings, such as CodeRabbit, that finding must carry the bot's own Critical or Major label; triage's higher grade does not count, and watch.sh refuses the re-request when no finding on the pull request carries that label, as the Re-request section of `bots.md` says.
   Run step 1's watch.sh command with `--rerequest <bot>` for that bot instead of `--bot`, so the script posts its review command once and waits on that review.
   Otherwise its first review was its pass, and the code reviewer's subagents confirm every fix, including fixes for that bot's other findings.
   A pass with no bot to wait on settles on the code reviewer alone.
   When a lane or a `drive` is configured, `lanes.md` and `../prove/drive.md` say how each changes this pass.
   Findings from this pass go through steps 2 and 3 again, at the same bar.
   Once a pass confirms the fix for a blocking bot finding, reply under it naming the fix commit, then resolve its thread when the bot has not resolved it itself; a finding with no thread gets that confirmation in this run's section of the pull request body.
6. Terminate only on a settled pass that pushed NOTHING and whose actionable findings are, after triage, all dispositioned or already resolved.
   A fixed finding counts as resolved only after a pass checked its fix commit against it: Spec where it runs, and step 2's triage where it does not.
   A pass that pushed anything always runs another pass, however complete the fixing felt.
   There is no cap on passes: the loop runs until a settled pass has nothing blocking under step 3, and every push gets step 5's confirmation, so no push goes unreviewed.
   Convergence bounds it instead: a confirmed critical or major, or a failed drive, whose root cause an earlier push already carried a fix for is a stop-and-report, because the fixes are going in circles and choosing between them is the user's call.
   Say what is open, and leave the pull request unmerged.
7. Run `bash <this skill's directory>/watch.sh <pr> <settled-sha> --repo <owner/name>` with no `--bot` on the SHA the review settled on, the way step 1 runs it.
   Exit 0 goes on; exit 1 goes to step 3's triage, and a blocking failure sends the run back to step 4; any other exit is a stop-and-report.
   Check the pull request once more for a table bot no pass waited on, and handle one that shows up as `bots.md` says before going on.
   Re-read the pull request's state and confirm all three of: it is still open, it still targets `base`, and its head is still the SHA the review settled on.
   Any of the three failing is a stop-and-report, not another wait: the pull request changed underneath the run, and deciding what that means is the user's.
   Then read its `reviewDecision`.
   In hold mode, or when `reviewDecision` is `REVIEW_REQUIRED` or `CHANGES_REQUESTED`, stop here and report the pull request with that SHA as ready to merge, awaiting approval, or changes requested, and skip the merge, the release watch, and the cleanup.
   Never merge past a required approval with `--admin`.
   Otherwise merge that SHA explicitly with the resolved method: `gh pr merge <n> --<merge-method> --match-head-commit <settled-sha>`, adding `--delete-branch` only when this run did NOT use a worktree.
   With `squash`, keep the subject identical to the pull request title, because release tooling may parse it.
   On a worktree run, leave both deletions to the cleanup step, which removes the worktree first and then deletes the local and remote branch in the right order.
   Record the SHA `gh pr view <n> --json mergeCommit --jq .mergeCommit.oid` prints, which is the commit the merge put at the tip of `base`; the next step needs it to know which run is this run's.
   From the merge through step 9 and the final report, run every command in the foreground and do not end the turn.
   This replaces step 1's background default for the rest of this ship run, and step 8's repeated calls are the one wait that step 1's ban on polling loops does not cover.
   Once the pull request has merged, a host may close the agent's session as soon as the turn goes idle, which kills every background command.
   T3 Code does this when it settles a thread whose linked pull request merged.
8. Watch the base-branch pipeline after the merge, following the run whose head SHA is the SHA step 7 recorded.
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
9. Run the resolved `post-merge` command when there is one, and let it define its own scope.
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
Surface anything skipped, red, or deferred the moment it happens, not only at the end.

## Red flags

Each of these means stop and correct course, not continue:

- About to run a review CLI as the pre-merge review, whether directly, as part of `verify`, or by invoking a review skill that wraps one; this run reviews with the code reviewer's subagents, and the review bots are the vendor pass.
- About to push a fix while any first-pass reviewer is still reading, or to push a second fix batch where one would do.
- About to push because of a nit, an informational note, a minor judged not worth fixing or not contained, or a finding triage could not confirm; only a failed drive, a failed check the change caused, a confirmed critical or major, a worth-fixing contained minor, or a due base update buys a push, and minors do so once per run and a base update once.
- About to ask a second PIPELINE-SLOT question after stage 0 has already asked one; the safety stops are not covered by that rule and always fire.
- About to end stage 3's review loop on a pass that pushed fixes; it exits only on a pass that changed nothing.
- About to merge with a confirmed critical or major still open from any reviewer, or to fix again a root cause an earlier push already carried a fix for instead of stopping.
- About to merge while any check is pending, or while the review loop still has actionable findings.
- About to call a red release run "done" because the merge itself succeeded.
- About to push a branch other than the one being shipped.
- About to merge in hold mode, or with `--admin` past a required review.
