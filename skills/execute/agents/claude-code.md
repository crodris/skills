# Claude Code

## Task display overlay

Mirror tasks into the TaskCreate, TaskUpdate, TaskList, and TaskGet tools, under the display-overlay rule in `memory.md`.

## Structured questions

Use the built-in question tool that renders selectable options.

## Invoking another skill

Call the Skill tool with the skill's name, such as "execute", and the arguments.

## Permissions

Tell the user to pre-approve the families `agents.md` lists in project or user `settings.json`.
For a path outside the working directories, name `permissions.additionalDirectories` in the same file, or `--add-dir` for one session.

## Subagents

Dispatch each fan-out subagent with the Agent tool, `subagent_type: general-purpose`, the role's model from Subagent models below, and `run_in_background: true`.
Start each `description` with that model in brackets, such as `[opus] Execute TES-246`, or `[inherit]` when `model` is omitted, since the agent list shows the description but not the model.
Leave `isolation` unset, since the parent creates every worktree itself.
An issue subagent fans out its own tasks only when `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` allows nested subagents; otherwise it runs them one at a time.
Install a fan-out worktree's dependencies by calling the Skill tool with `worktree-setup` when that skill is installed, and otherwise with the install command the lockfile names.
A headless run with a restricted tool allowlist needs `--add-dir <main checkout>.fathom`, where fan-out worktrees live.
A restricted headless run must allow the system temp directory with `--add-dir "${TMPDIR:-/tmp}"`, since `file-pr` writes the pull request body with `mktemp` outside the repository.

## Subagent models

Fan-out has two roles: `issue`, the subagent that runs one issue when several are named, and `task`, the implementer subagent that builds one task.
Resolve each role from the first source that names it:

1. The Fathom file, `$XDG_CONFIG_HOME/fathom/models.md`, or `~/.config/fathom/models.md` when that variable is unset, empty, or not an absolute path: its `issue:` and `task:` lines.
   Read it with the Read tool, since a restricted allowlist refuses a shell read outside the workspace.
2. The pstack model rule, `~/.claude/rules/pstack-models.md`: its `hardest tasks:` line for `issue` and its `feature, refactoring:` line for `task`, taking the first model a line lists.
   It is usually in context already; read it only when it is not.
3. Ask, at the point `SKILL.md` step 3 names, one structured question covering each unresolved role.
   Offer Sonnet for both, Opus for issues and Sonnet for tasks, Opus for both, and the parent session's model for both.
   For a single unresolved role, offer Sonnet, Opus, Haiku, or the parent session's model for that role.
   Accept a typed answer only when each role maps to an allowed value; otherwise ask again, naming the allowed values.
   Write the answer to the Fathom file, creating its directory, replacing each answered role's line and keeping every other line.
   In auto mode, skip the question, use `sonnet` for each unresolved role, write nothing, and say so in the run's report.

The Fathom file is per machine, never per repository, so the committed profile never holds these lines.
An allowed value is `fable`, `opus`, `sonnet`, or `haiku`; `inherit-parent` or `auto` means omit `model`, so the role runs on the parent session's model.
A line holding any other value does not name its role.

```markdown
# fathom subagent models
issue: opus
task: sonnet
```
