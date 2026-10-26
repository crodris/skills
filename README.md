# skills

[![SkillSpector](https://github.com/crodris/skills/actions/workflows/skillspector.yml/badge.svg)](https://github.com/crodris/skills/actions/workflows/skillspector.yml)

Agent skills I use every day, for taking work from a tracker issue to a merged pull request.
They run on any agent that skills.sh supports, and Fathom and ship also install as Claude Code plugins.

## Install

```bash
npx skills@latest add crodris/skills
```

The installer lists every skill, so take only the ones you want.
`execute` and `scaffold` also need `fathom-shared`, which carries the files they read.

On Claude Code, Fathom and ship also install as plugins:

```text
/plugin marketplace add crodris/skills
/plugin install fathom@crodris
/plugin install ship@crodris
```

## Plugins

### fathom (v2.7.2)

`execute` takes a tracker issue through breakdown, implementation, tests, commits, and an open review, and resumes where the last run stopped.
`scaffold` turns requirements into a main issue with linked sub-issues, then offers to hand off to `execute`.
They need an Asana or Linear MCP, and the GitHub CLI for reviews on GitHub.
The [Fathom guide](./skills/execute/README.md) covers setup, task memory, stacked reviews, and troubleshooting.

### ship (v2.1.4)

`ship` carries the current branch to a ready pull request: verify until clean, commit, push, open the pull request, review it with subagents and any review bots, and fix until nothing blocking remains.
It merges, watches the release, and cleans up only when you ask it to merge, or when the repository's `.ship/config.md` sets `merge: yes` and the request does not ask only for a green pull request.
It needs a git remote, an authenticated GitHub CLI, and `jq`.

## Standalone Skills

These install through skills.sh only.

### review (v1.1.2)

`review` checks a pull request against the issue it claims to close, on running builds of the branch and its base, and posts one review with inline findings.
It needs the GitHub CLI, plus a browser driver such as Playwright for visual changes.

### rewrite (v3.0.0)

`rewrite` drafts and rewrites prose you post under your name, in your voice, and removes the patterns that mark text as machine-written.
It reads the voice file that `~/.config/voice/config.md` points at, and builds one with you on first run.
It runs [unslop](https://github.com/cursor/plugins/tree/main/pstack/skills/unslop) first when that is installed.
To move from an old name, run `npx skills@latest remove my-voice -g` (or `npx skills@latest remove voice -g` for an install older than v2.0.0), then `npx skills@latest add crodris/skills -s rewrite -g`.

### frontend-design-pipeline (v1.3.0)

`frontend-design-pipeline` takes a UI from idea to build: candidate design systems, direction briefs, rendered mocks for you to pick from, motion, then the build.
It needs [impeccable](https://github.com/pbakaus/impeccable), and its `SKILL.md` lists the optional companion skills with their install commands.

### html-comms (v1.0.1)

`html-comms` turns a plan, report, comparison, or set of UI mocks into one HTML page and publishes it to a private link.
It needs a private publisher, such as the Artifact tool in Claude Code or [here-now](https://github.com/heredotnow/skill).

### worktree-setup (v1.0.2)

`worktree-setup` makes a new git worktree runnable: it copies the main checkout's untracked env files and installs dependencies.
It needs Git 2.31 or newer, and the package manager the worktree's lockfile names on `PATH`.
Install it globally, then add this SessionStart hook to `~/.claude/settings.json` so worktrees created by other tools are covered too.
The hook expects the global install; a project-scoped install puts the script at `.claude/skills/worktree-setup/setup.sh`, so change the path to match, or the hook does nothing.

```bash
npx skills@latest add crodris/skills -s worktree-setup -g
```

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "f=\"$HOME/.claude/skills/worktree-setup/setup.sh\"; [ -f \"$f\" ] && bash \"$f\" 2>&1 || true",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

### verification-audit (v1.0.0)

`verification-audit` checks how well a repository proves agent work is correct, layer by layer, then closes each gap.
It uses the verification skills from [pstack](https://github.com/crodris/pstack-claude) to fix gaps, and only reports them without it.

## Security scanning

CI scans every skill with [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) and fails on any finding not suppressed in `.skillspector-baseline.yaml`.
To run the same scan locally:

```bash
uv tool install git+https://github.com/NVIDIA/skillspector.git@c7958a3268d9498644b22edb75d0f051bbc8cbfc # v2.12.0
bin/scan-skills.sh
```

## License

MIT

Some rules are adapted from Matt Pocock's mattpocock/skills and obra/superpowers (MIT), including ship's merge-danger line, the summary visuals and before-and-after evidence in ship's pull request body (from the `pr` skill, which credits Dex Horthy's `show-me`), execute's frontier fan-out (from `implement-spec`), and the "Call the Skill tool" wording for loading another skill.
Ship's hold mode, CI, and pull request title and body rules, and execute's title and body rules, come from Theo Browne's (t3dotgg) babysit-pr and file-pr skills.
`html-comms` is adapted from Theo Browne's html-communication, with its chart heuristic from [ruesato/agent-skill-floreo](https://github.com/ruesato/agent-skill-floreo) (MIT).
The `rewrite` skill's floor rows for arguing with no one, re-explained context, dramatic closers, and the document-describing half of meta commentary, and rewrite mode's no-new-facts rule, are adapted from Siqi Chen's (blader) humanizer (MIT).
