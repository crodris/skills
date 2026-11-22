# Review before the push

Read by `ship` and babysit before a push in a repository with no table bot, so each push starts CI once and no later push cancels it.
A round is one Review, Triage, and Fix on local commits, a pass that pushes nothing.

Inputs: the committed head, `base`, the pull request if one is open, what changed and why, the pass kind, the merge method, whether the branch is exclusively this run's, and the ledger so far.

## Rounds

1. Pin the head with `git rev-parse HEAD`.
2. Follow the Review section of `SKILL.md` on that SHA.
   With no pull request open, Spec checks the diff against what changed and why.
3. Follow the Triage section, where a step that reads the pull request reads nothing while none is open, and step 2 compares the pinned SHA with `git rev-parse HEAD`.
4. Follow the Fix section, which commits through `../prove/SKILL.md`.
5. On `FIXED <sha>`, start the next round on the new head with pass kind `fixes`.
   On `CLEAN`, return `CLEAN <sha>`, where `<sha>` is the full SHA the last round read, with the ledger, the lane, the round count, the last `PASS` line from prove, and the drive's evidence path when a drive ran in any round.
   On `RESTART` or `BLOCKED <reason>`, return `BLOCKED <reason>` and push nothing.

The caller pushes only while `git rev-parse HEAD` equals that `<sha>`, and returns `BLOCKED` otherwise.

## Stops

A round is not a push, so the limit of three passes that push in `SKILL.md` does not apply.
A contained minor blocks in every round.
From round 3, a round whose count of blocking findings is not below the round before's returns `BLOCKED` with both counts, so the user decides.
The Budget section's stops for a finding disputed twice and for fixes going in circles still apply, with an earlier round counting as an earlier push.
