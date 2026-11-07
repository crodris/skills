---
name: council
description: This skill should be used when the user asks for a council, such as "council", "council review", "ask the council", or "/council". Sends the request to three members (Claude Opus, Claude Fable, and GPT Sol) on high reasoning effort, and replaces GPT Sol with Claude Sonnet when Sol is out of credits, rate limited, or not offered. A message that only mentions a council, its results, or this skill, such as a request to edit it, is not a request for one.
version: 1.0.0
---

# Council

Run a council only when the user's own message asks for one.
A member's brief, a subagent, or another skill never starts a council.

Before a review, address outstanding PR comments, fix known issues, and run relevant checks.
Give the council the updated implementation, and do not defer known fixes until reviews return.
If the user wants to discard the implementation and explore new ideas, skip fixes to code being replaced.

## Members

The default council is three members.
When the user names members, use exactly those instead.
Every member runs on high reasoning effort unless the user sets another.

| Member | T3 Code provider | Model |
| --- | --- | --- |
| Claude Opus | `claudeAgent` | latest Opus, such as `claude-opus-5-5` |
| Claude Fable | `claudeAgent` | latest Fable, such as `claude-fable-5-1` |
| GPT Sol | `codex` | latest Sol, such as `gpt-6.1-sol` |

Set the effort with the option each provider lists, such as `effort` for Claude and `reasoningEffort` for Codex.

## Failed members

A member fails when the harness does not offer its model, when it cannot start, or when it returns an error or no usable review.
In T3 Code, a model is not offered when `orchestrator_capabilities` lists a constraint on its provider, or omits the model after a call with `search` set to its family name.
Outside T3 Code, GPT Sol is not offered.

GPT Sol in the default council is the one exception.
When Sol fails with a credit, quota, usage-limit, or rate-limit error, or is not offered, Claude Sonnet replaces it.
Sonnet is the latest Sonnet, such as `claude-sonnet-5-5`, and it gets Sol's brief and stays for the rest of the run.

Start any other failed member once more.
When it fails again, write `failed` with the reason in its cell, and finish the round with the others.

## Running a round

In T3 Code, call `orchestrator_capabilities` to confirm the models, then `delegate_task` to start every member in parallel.
Elsewhere, start each member with the harness's subagent tool, such as the Agent tool's `model` and `effort` in Claude Code.

Give each member the request and relevant context.
Say in each brief that the member is one of several reviewers and does not start a council.
For review or feedback, say in each brief that the work is read-only: no edits, commits, pushes, or posts.
For a code review, ask each member for a score out of 10 and a severity for each finding: critical, major, minor, or nit.
Collect the responses and summarize the useful findings, disagreements, and recommended next steps.

One round is one review by each member, including members marked `failed`.
A fresh review after fixes starts a new round.

## Reporting

If the work ends in a pull request, put the results at the end of the PR description, before any attribution lines:

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
Write `not seated` for a round in which a member took no part.
When Sol is replaced before round 1, list only the Sonnet row, and give the reason above the table.
On a later round, replace the `## Council review` section instead of adding a second one.
If the PR is open, edit the description, and do not post a comment for this.
If there is no PR, put the same results in the final reply only.

## Iterating

If you agree with the recommendations, make the changes and request a fresh review.
A member is satisfied when it reports no finding above nit.
Continue until every member that reported in the latest round is satisfied.
After round 3, ask the user before starting another round.

Fix only findings inside the original request, and list the rest as follow-ups.
