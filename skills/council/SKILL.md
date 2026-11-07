---
name: council
description: This skill should be used when the user says "council", "council review", or "ask the council". Brings in three delegates on high reasoning effort, Claude Opus, Claude Fable, and GPT Sol, to review or give feedback on the work, and swaps Claude Sonnet in for GPT Sol when Sol is out of credits.
version: 1.0.0
---

# Council

Before an audit, address outstanding PR comments, fix known issues, and run relevant checks.
Give the council the updated implementation, and do not defer known fixes until reviews return.
If the user wants to discard the implementation and explore new ideas, skip fixes to code being replaced.

## Members

The council is three delegates, all on high reasoning effort.
If the user's instructions name council members, use those instead.

| Member | T3 Code provider | Model |
| --- | --- | --- |
| Claude Opus | `claudeAgent` | latest Opus, such as `claude-opus-5-5` |
| Claude Fable | `claudeAgent` | latest Fable, such as `claude-fable-5-1` |
| GPT Sol | `codex` | latest Sol, such as `gpt-6.1-sol` |

Set high effort with the option each provider lists, such as `effort` for Claude and `reasoningEffort` for Codex.

GPT Sol has one fallback, Claude Sonnet (latest Sonnet, such as `claude-sonnet-5-5`) on high effort.
Use Sonnet when Sol is out of credits, rate limited, or not offered, which shows as a Codex constraint in the capabilities list, a failed `delegate_task`, or a usage-limit error in Sol's result.
When Sol fails that way mid-round, start Sonnet with the same brief and keep the other two results.
Use Sonnet for the rest of the run, and say in the results that Sonnet replaced Sol and why.
If Opus or Fable is unavailable, report it instead of substituting.

## Running a round

In T3 Code, call `orchestrator_capabilities` to resolve the models, then `delegate_task` to start one delegate per member in parallel.
Elsewhere, use the harness's subagent tools.

Give each delegate the request and relevant context.
For review or feedback, keep their work read-only.
Collect their responses and summarize the useful findings, disagreements, and recommended next steps.

For a code review, ask each delegate for a score out of 10.
Count each full review pass as one round.
A fresh review after fixes starts a new round.

## Reporting

If the work ends in a pull request, put the results in the PR description, before the model and harness line at the end:

```markdown
## Council review

Rounds: 2

| Delegate | Round 1 | Round 2 |
| --- | --- | --- |
| Claude Opus | 7/10 | 9/10 |
| Claude Fable | 8/10 | 10/10 |
| GPT Sol | 7/10 | out of credits |
| Claude Sonnet, for GPT Sol | | 9/10 |
```

If a delegate gives no score, write `no score`, and do not invent one.
If the PR is open, edit the description, and do not post a comment for this.
If there is no PR, put the same results in the final reply only.

## Iterating

If you agree with their recommendations, make the changes and request a fresh review after.
Continue until all delegates are satisfied with the outcome.

Do not let repeated reviews cause scope creep.
It is your job to keep scope limited.
