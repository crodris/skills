# Ship lanes

Read by the ship skill when `.ship/config.md` on `origin/<base>` sets `light-paths` or `security-paths`.

Read these slots from the base rather than from the working tree, because a change could otherwise widen its own lane before anyone reviewed it; for the same reason a change that touches `.ship/config.md` at all is never light.
`light-paths` and `security-paths` each hold a comma-separated list of globs, matched against repository-relative paths, with `**` crossing directories.
Project paths belong in that file and never in this skill.

Resolve the lane in stage 0, from every file this run will ship: whatever differs from `origin/<base>`, committed or not, plus the untracked files that belong to the change.

- Light: EVERY changed file matches `light-paths`. Stage 3 skips the subagent review, and the bot is the only reviewer.
- Security: ANY changed file matches `security-paths`. Stage 3's subagent round also runs a security review of the diff.
- Standard: neither, which is every run in a repository with no lane slots.

Security outranks light: a glob broad enough to call a security-sensitive file light is a mistake in the config, and the cheap lane is the wrong way to find that out.
The light lane needs a configured review bot, because it trades the code reviewer for the bot, and a run with neither has had no review at all; without one, run the standard lane.
A lane describes the change rather than the run, so re-check it before every push: a light run that stops being light, because its fixes reach a file outside `light-paths` or into `security-paths`, owes the subagent review it skipped, which runs as a full-diff code reviewer round against the new head in place of the fix-only round in stage 3's step 5.
A run that became a security run this way gets the security subagent on the full diff in that same round.
No lane skips verify, the bot, or the merge conditions.

## Stage 3 review

The security lane's review is a third `general-purpose` subagent beside the Standards and Spec subagents, on the same diff, briefed to review it for security alone.
That third subagent never spends a round of its own: it shares the code reviewer's round here, and at stage 3's step 5 it shares the confirmation pass whether or not a drive replaced the code reviewer there.

## Stage 3 confirmation pass

The light lane confirms with the bot alone; with a first-push-only bot it requests the bot's review on every confirmation pass, since that lane has no subagent to confirm with.
In the security lane the security subagent reads the fix commits in the same pass, and a drive does not stand in for it: a blocking fix can land inside `security-paths` as easily as the change did.

## Red flag

- About to skip the subagent review on a change that is not entirely inside `light-paths`, or to write a project's paths into this skill instead of its `.ship/config.md`.
