# Ship drive

Read by the ship skill when `.ship/config.md` on `origin/<base>` sets `drive`.

`drive` names what exercises the running product and leaves evidence behind: a command such as `bin/drive.sh run`, or `skill:<name>` for a project verification skill that writes its own drive for each change.
`skill:<name>` resolves only to a skill the repository itself ships, under its `.claude/skills/`, `.agents/skills/`, or `.kiro/skills/`, and never to a personal, plugin, or added-directory skill of the same name, which could otherwise put instructions from outside the shipped repository in charge of a pre-push gate.
The resolved skill's instructions, and every command they launch, are subject to Authority and boundary exactly as a command-valued drive is, and a skill cannot relax those checks any more than a repository-local ship skill can.
A skill-valued drive is invoked with what changed and why, and it owns launching the product, driving the changed behavior, and naming where its evidence landed.
The sections below say when it runs.

## Stage 1

When stage 0 resolved a `drive` and the diff changes behavior, run it once after the round that ended the loop.
A diff changes behavior when it alters what the running product does; documentation, comments, tests, and tooling configuration do not.
Verify proves the code holds together, and the drive proves the product does what the change claims, before a reviewer spends a round on it.
A failed drive is a stage 1 failure: fix the cause, then go back to stage 1's step 1, because the fix is new code verify has not seen, and the round counts against the cap; at the cap, stop and report as stage 1's step 4 says, a drive that keeps failing being the same kind of not-ready.
The stage ends only when the round that ended the loop passed verify untouched AND the drive, when one ran, passed.
A drive that leaves no evidence has not run; record where the evidence landed, because stage 2 puts that path in the pull request body.
Give it a timeout like any other gate, and treat one that blows through it as failed.

## Stage 3 confirmation pass

When stage 0 resolved a `drive` and the diff changes behavior, run the drive once here and put the path of the evidence it leaves in the pull request body: with a bot that re-reviews on its own it runs in place of the code reviewer's round, and with a first-push-only bot it runs beside the code reviewer, or beside the requested bot review in the light lane, never in place of either.
A diff changes behavior when it alters what the running product does; documentation, comments, tests, and tooling configuration do not.
Where the drive replaces the code reviewer's round it replaces that and nothing else: it never replaces verify, the bot, or the security lane's subagent.
Give it a timeout like any other gate, and treat a failed drive as a blocking finding under stage 3's step 3.

## Red flag

- About to let a drive stand in for verify or for the bot.
