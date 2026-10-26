# Agent notes

These skills run unchanged in Claude Code and Kiro.
Read the agent file for the agent running this skill, and only that one:

- Claude Code: `agents/claude-code.md`.
- Kiro: `agents/kiro.md`.

Outside the agent files, only setup and install steps name an agent.
When a file points to an agent detail in `agents.md`, such as Subagent models, the display overlay tools, or the structured question mechanism, read it in the agent file.

## MCP tool naming

Discover the connected tracker MCP's actual tool names at runtime, every run, before calling any of them, and hardcode no tracker tool name in any skill, script, or note.
Builds also differ in which tools they expose, as `trackers/asana.md` describes.

## Structured questions

Whenever these skills ask the user to choose, such as the tracker, the destination, the state mapping, or a one-time offer, ask a multiple-choice question with the mechanism the agent file names.

## Invoking another skill

When a skill hands off to another, such as scaffold running execute, invoke it with the mechanism the agent file names.

## Permissions

The command families a run needs are `git`, `bd`, the CLI the forge adapter names, and the tracker MCP tools.
Note each tool call the harness refuses when it happens, a path outside the allowed working directories included, and keep that list until the run ends.
In the report that ends any run of a Fathom skill, a hold or a stop included, name every noted call, and tell the user to pre-approve its family or allow its directory where the agent file's Permissions section says; edit nothing there yourself.
Run each command that reads git or tracker state on its own, never in a shell loop or through `$(...)`, since a permission check can deny a command it cannot read in advance, even when its parts are pre-approved.
