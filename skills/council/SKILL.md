---
name: council
description: This skill should be used when the user asks for a council, such as "council", "council review", "ask the council", or "/council". Sends the request to three members (Claude Opus, Claude Fable, and GPT Sol) on high reasoning effort, and replaces GPT Sol with Claude Sonnet when Sol is out of credits, rate limited, or not offered. A message about the council skill itself, such as a request to edit it, is not a request for one.
version: 1.0.0
---

# Council

Run a council only when the user's own message asks for one.
A delegate brief, a subagent, or another skill never starts a council.

Before a review, address outstanding PR comments, fix known issues, and run relevant checks.
Give the council the updated implementation, and do not defer known fixes until reviews return.
If the user wants to discard the implementation and explore new ideas, skip fixes to code being replaced.

## Members

The default council is three members, all on high reasoning effort.

| Member | T3 Code provider | Model |
| --- | --- | --- |
| Claude Opus | `claudeAgent` | latest Opus, such as `claude-opus-5-5` |
| Claude Fable | `claudeAgent` | latest Fable, such as `claude-fable-5-1` |
| GPT Sol | `codex` | latest Sol, such as `gpt-6.1-sol` |

Set high reasoning effort with the option each provider lists, such as `effort` for Claude and `reasoningEffort` for Codex.

When the user names members, use exactly those, and report a named member that is unavailable instead of replacing it.

## Replacing GPT Sol

In the default council, Claude Sonnet (latest Sonnet, such as `claude-sonnet-5-5`) on high reasoning effort replaces GPT Sol when Sol is out of credits, rate limited, or not offered.
Sol is out of credits or rate limited when its `delegate_task` or its result reports a credit, quota, usage-limit, or rate-limit error.
Sol is not offered when `orchestrator_capabilities` lists a constraint on Codex, or lists no Sol after a call with `search: "sol"`.
Outside T3 Code, Sol is not offered, so Sonnet replaces it from round 1.
When Sol is replaced mid-round, start Sonnet with the same brief and keep the other results.
Sonnet stays for the rest of the run, and the results say that Sonnet replaced Sol and why.

When any member fails for another reason, start it once more.
When it fails again, finish the round without it and report the failure.

## Running a round

In T3 Code, call `orchestrator_capabilities` to confirm the models, then `delegate_task` to start every member in parallel.
Elsewhere, start each member with the harness's subagent tool, such as the Agent tool's `model` and `effort` in Claude Code.

Give each member the request and relevant context.
Say in each brief that the member is one reviewer and does not start a council.
For review or feedback, say in each brief that the work is read-only: no edits, commits, pushes, or posts.
Collect the responses and summarize the useful findings, disagreements, and recommended next steps.

For a code review, ask each member for a score out of 10.
Count each full review by every member as one round.
A fresh review after fixes starts a new round.

## Reporting

If the work ends in a pull request, put the results at the end of the PR description:

```markdown
## Council review

Rounds: 2

| Member | Round 1 | Round 2 |
| --- | --- | --- |
| Claude Opus | 7/10 | 9/10 |
| Claude Fable | 8/10 | 10/10 |
| GPT Sol | 7/10 | replaced, out of credits |
| Claude Sonnet, for GPT Sol | not seated | 9/10 |
```

If a member gives no score, write `no score`, and do not invent one.
Write `not seated` for a round a member did not sit in, and give the reason in the round where Sol was replaced.
When Sol is replaced before round 1, list only the Sonnet row, marked as replacing GPT Sol.
If the PR is open, edit the description, and do not post a comment for this.
If there is no PR, put the same results in the final reply only.

## Iterating

If you agree with the recommendations, make the changes and request a fresh review.
A member is satisfied when it reports no finding above nit.
Continue until every member is satisfied.
After round 3, ask the user before starting another round.

Fix only findings inside the original request, and list the rest as follow-ups.
