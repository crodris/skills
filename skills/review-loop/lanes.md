# Lanes

Read by review-loop when `light-paths` or `security-paths` is set in `.ship/config.md` on `origin/<base>`.

Each slot holds comma-separated globs over repository-relative paths, with `**` crossing directories.
A change that touches `.ship/config.md` is never light, so a change cannot widen its own lane.

Fetch the base as the Fetching the base section of `../ship/boundary.md` says.
Then resolve the lane from every file the change ships: whatever differs from `origin/<base>`, committed or not, plus the untracked files that belong to it.

- Security: any changed file matches `security-paths`.
  A third `general-purpose` subagent reviews the diff for security alone, beside Standards and Spec, in every pass they run.
- Light: every changed file matches `light-paths`, and at least one review bot is present.
  The review bots are the only full-diff reviewers.
  Add `# review-gate: light lane` to each push and merge command, since a push gate that requires Standards and Spec reads that comment as this lane's exception.
  Ship's first push comes before the pull request exists, so that push needs no light-lane comment.
- Standard: neither.

Security outranks light.
A bot that shows up later never turns a standard run light.
No lane skips verify, the bots, or the merge gate.

Re-check the lane before every push.
A light run whose fixes reach a file outside `light-paths` runs a full-diff Standards and Spec round on the next pass, and one that reaches `security-paths` adds the security subagent to that round.

## Fix passes in the light lane

A bot reads every fix.
Re-request each first-push-only bot whose confirmed critical or major the push fixed, as `../babysit/bots.md` says.
When that is none and no present bot reviews every push, pass `--rerequest` for the first first-push-only bot, in table order, that the Which pass waits on which bot section of `../babysit/bots.md` allows.
When none is allowed, Standards and Spec read the fix commits as in the standard lane.
