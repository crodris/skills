# Drive

Read by `prove` and by `review-loop`'s fix pass when `drive` is set in `.ship/config.md` on `origin/<base>`.

`drive` names what exercises the running product and leaves evidence behind: a command such as `bin/drive.sh run`, or `skill:<name>` for a verification skill that writes its own drive for each change.
`skill:<name>` resolves only to a skill the repository ships under `.claude/skills/`, `.agents/skills/`, or `.kiro/skills/`, never to a personal, plugin, or added-directory skill of that name.
The skill and every command it launches stay inside `../ship/boundary.md`.
Invoke a skill-valued drive with what changed and why; it launches the product, drives the changed behavior, and names where its evidence landed.
Give the drive a timeout, and treat one past it as failed.

A drive runs only when the diff changes behavior, meaning what the running product does.
Documentation, comments, tests, and tooling configuration do not.

## In prove

Run the drive once, after the verify loop ends.
A failed drive is a failed round.
When the caller asked for a commit, fix the cause and go back to the verify loop's step 1, and the round counts against its cap of five; otherwise return `FAIL <what failed>` without changing the tree.
`prove` passes only when the last round passed verify with no fixes and the drive passed.
A drive that leaves no evidence has not run.
Return the evidence path with the `PASS` line, since the pull request body carries it.

## In review-loop's fix pass

Fix runs this drive once, and this section is that run.
Put its evidence path in the pull request body.
The next pass's Review does not run the drive again.
When at least one bot is present and every present bot re-reviews every push, the drive replaces the code reviewer's fix-commit read for that pass.
Otherwise, including a run with no bot or a first-push-only bot, the code reviewer, or the requested bot review in the light lane, still reads the fix commits.
A drive never replaces verify, a bot, or the security lane's subagent.
Per `../review-loop/SKILL.md` Fix, failed drives are `BLOCKED`.
