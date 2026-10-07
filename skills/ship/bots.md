# Ship review bots

Read by the ship skill on every run: in stage 0, and at every stage 3 step that polls or re-requests a review bot.

A review bot is a forge app that reviews the pull request on its own.
Ship waits on and re-requests only the bots in this table, in the table's order when a rule asks for any one of them.
Any other bot's comments are still findings for stage 3's triage, but ship never waits on one.

| Bot | Login | Config file | Reviews every push when | Settled on the SHA when | Re-request |
| --- | --- | --- | --- | --- | --- |
| CodeRabbit | `coderabbitai[bot]` | `.coderabbit.yaml` | `reviews.auto_review.auto_incremental_review` is not `false` (default: every push) | its `CodeRabbit` commit status is `success` with "Review completed" | comment `@coderabbitai review` |
| Greptile | `greptile-apps[bot]` | `.greptile/config.json`, else `greptile.json` | `autoReview` includes `push`, or the legacy `triggerOnUpdates` is `true` (default `["open"]`: first push only) | its `Greptile Review` check run on the SHA completes, or, when its config sets `statusCheck: false`, it submitted a review whose `commit_id` is the SHA | comment `@greptileai` |

## Which bots are present

Resolve the set in stage 0, reading config files in the tree this run will push: every file the push will carry, committed or not, whether or not the change touches it.
A table bot is present when its config file exists on `origin/<base>` or in that tree, or when its login submitted a review on any of the last five merged pull requests.
A bot whose config in that tree turns automatic review off (`reviews.auto_review.enabled: false` for CodeRabbit, `autoReview: []` or the legacy `skipReview: "AUTOMATIC"` for Greptile) is absent in stage 0, whatever the base config or its history says.
`gh pr view --json` prints a bot's login without the `[bot]` suffix, so match on the name before it.
Stage 3 adds any table bot that shows up on this pull request, with a status, check, reaction, review, or comment from its login, at any point before the merge; that covers a bot installed since the last merge.
A bot added after stage 3's step 1 is waited on until its review settles, and its findings go through stage 3's steps 2 and 3 before the merge.
A first-push-only bot found after its review landed on an earlier head is re-requested on the current head with its command, and that review is the one it settles on.
An empty set is a normal run: stage 3 reviews with the subagents alone, and the report says no bot was found.

## First push or every push

Read each present bot's mode from its config file in the tree this run will push, whether or not the change touches it; that is the version the bot itself reads.
A file that does not set it, or no file at all, takes the table's default.
A setting made only in the bot's web dashboard is invisible here, so a repository that changes the mode there should set it in the file too.

## Settled

A bot has settled on the captured SHA when the table's signal says so for that SHA and no other.
`watch.sh` in this skill's folder implements the table's settle signals and the notice rules: a notice in place of a review settles nothing, a rate limit or a skipped review is re-requested once and waited on, and a notice that the bot will not review at all ends the wait.
Pass it `--bot coderabbit` for CodeRabbit and `--bot greptile` for Greptile, once for each present bot that the current pass waits on.
A bot this run must re-request on a head, as `lanes.md` asks, is passed with `--rerequest` instead of `--bot`.
A first-push-only bot's skipped notice on a head after the one it reviewed is expected: outside the light lane, do not pass that bot on that head, and never re-request it.
A bot that will not review at all, such as after an ended trial or a spent plan quota, is a stop-and-report at once, since waiting cannot change it and merging without that bot is the user's call.

## Red flag

- About to wait on or re-request a bot that is not present, or to count a bot's notice as its review.
