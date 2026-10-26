# Kiro

## Install

Install as the "Kiro, Codex, and other agents" section of `README.md` in this skill's folder says.
`execute/`, `scaffold/`, and `file-pr/` must sit as siblings in one skills directory, such as `~/.kiro/skills/` or a project's skills directory, since every `../execute/` and `../file-pr/` path depends on it.
Copying the `skills/` directory itself nests them one level too deep.

## Task display overlay

Use the built-in todo or task tools when the workspace exposes them, under the display-overlay rule in `memory.md`; otherwise skip the overlay silently.

## Structured questions

Use a structured prompt when the workspace exposes one; otherwise ask in prose, numbering the options so the reply can name one.

## Invoking another skill

Read the other skill's `SKILL.md` from its sibling folder next to this skill's own folder, such as `../execute/SKILL.md` from scaffold, and follow it with the arguments.

## Permissions

Tell the user to pre-approve the families `agents.md` lists in Kiro's trusted or allowed command configuration.
For a refused path, name the path and say it lies outside the directories the session may read.

## Subagents

Treat Kiro as an agent with no subagents, and run issues and tasks one at a time, as `fan-out.md` says for that case.
Install a worktree's dependencies with the install command the lockfile names.
