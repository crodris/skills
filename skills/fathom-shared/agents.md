# Agent notes

These skills follow the open Agent Skills standard (SKILL.md, agentskills.io) and run unchanged in Claude Code and Kiro.
This file holds only the differences that are specific to each agent.
Read the rest of this plugin's skills as agent-neutral; when you need an agent-specific detail, come back here.

## Install

Claude Code: install this plugin from its marketplace repo.
Kiro: install with the skills CLI, `npx skills add crodris/skills -a kiro-cli`, which places `execute/`, `scaffold/`, and `fathom-shared/` as siblings under `~/.kiro/skills/`; or copy or symlink the contents of this plugin's `skills/` directory there by hand so the three sit as siblings directly under the destination. Copying the `skills/` directory itself would nest them one level too deep and break every `../fathom-shared/` reference.

## Task display overlay

The shared memory contract defines a durable backend as the only source of truth for task state, plus an optional display overlay for a live progress UI.
Read `memory.md` before this section; do not treat what follows as a replacement for its display-overlay rule.

Claude Code: mirror tasks into the TaskCreate/TaskUpdate/TaskList/TaskGet tool family.
Kiro: use its built-in todo/task tools when the workspace exposes them; when it does not expose such tools, skip the overlay silently.

The rules governing the overlay live in `memory.md` and are not restated here, so the two files cannot drift apart.
This file only names which tools each agent offers for it.

## Subagents

`execute`'s fan-out runs issues and tasks on background subagents, as `../execute/fan-out.md` describes.

Claude Code: dispatch each one with the Agent tool, `subagent_type: general-purpose`, the role's model from Subagent models below, and `run_in_background: true`.
Leave `isolation` unset, since the parent creates every worktree itself so a task's branch starts from the issue branch and outlives the subagent for resume.
An issue subagent can fan out its own tasks only when `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` allows nested subagents; otherwise it runs them one at a time.

To install a fan-out worktree's dependencies, Claude Code calls the Skill tool with `worktree-setup` when it is installed.
Kiro, or Claude Code without that skill, runs the install command the lockfile names.
Kiro: treat it as an agent with no subagents, and run issues and tasks one at a time.

A headless Claude Code run with a restricted tool allowlist also needs `--add-dir <main checkout>.fathom`, since fan-out worktrees and the GitHub review body file live in that sibling directory.

### Subagent models

Claude Code fan-out has two roles: `issue`, the subagent that runs one issue when several are named, and `task`, the implementer subagent that builds one task.
Each person picks their split once per machine, never per repository, so it lives outside the committed profile.
Resolve each role in this order, and stop at the first source that names it.
Read both files with the Read tool, since a restricted allowlist refuses a shell read outside the workspace.

1. The person's Fathom file, `$XDG_CONFIG_HOME/fathom/models.md`, or `~/.config/fathom/models.md` when that variable is unset: its `issue:` and `task:` lines.
2. The pstack model rule, `~/.claude/rules/pstack-models.md`: its `hardest tasks:` line for `issue` and its `feature, refactoring:` line for `task`.
   When a line lists several models, use the first.
3. Ask, at the point `../execute/SKILL.md` step 3 names, as one structured question covering each role still unresolved.
   Offer Sonnet for both, Opus for issues and Sonnet for tasks, Opus for both, and the parent session's model for both.
   Write the answer to the Fathom file, creating its directory, and keep any line already there.
   In auto mode skip the question, use `sonnet` for each unresolved role, write nothing, and say so in the run's report, so the next run in ask mode asks.

A value is `fable`, `opus`, `sonnet`, or `haiku`; `inherit-parent` or `auto` means omit `model`, so the role runs on the parent session's model.
A file in this format:

```markdown
# fathom subagent models
issue: opus
task: sonnet
```

## MCP tool naming

Tool name prefixes for a connected tracker MCP server differ per agent and per MCP build.
Do not hardcode any tracker tool name in any skill, script, or note.
Discover the connected tracker server's actual tool names at runtime, every run, before calling any of them.

Tool coverage also differs, not just tool names.
One Asana build exposed a section-move tool and moved tasks between board sections, while another exposed none and correctly degraded to a phase comment through the adapter's fallback chain.
Expect that variation, and see `trackers/asana.md` for the details.

## Structured questions

Prefer a structured, multiple-choice question over free prose whenever this plugin asks the user to choose something, such as the tracker, the destination, the state mapping, or a one-time offer.
Concrete options are easier to answer unambiguously, which matters because an ambiguous reply must never be treated as approval.

Claude Code: use its built-in question tool that renders selectable options.
Kiro: use an equivalent structured prompt when the workspace exposes one; otherwise ask in prose, numbering the options so the reply can name one.

## Permissions

For smooth autonomous runs, pre-approve these command families ahead of time: `git`, `bd`, the CLI named by the resolved forge adapter (`gh` for GitHub, and whatever a repo-local `.fathom/forge.md` names), and whichever tool names the runtime discovery step in the previous section resolves for the connected tracker MCP server.

Claude Code: add these to the permissions allowlist in settings (project or user settings.json).
Kiro: add these to its trusted/allowed command configuration.

Without this pre-approval, each command triggers an interactive confirmation prompt and breaks autonomous execution.

Run each command that reads git or tracker state on its own, never in a shell loop or through `$(...)`, since a permission check can deny a command it cannot read in advance, even when its parts are pre-approved.
