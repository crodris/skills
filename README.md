# skills

[![SkillSpector](https://github.com/crodris/skills/actions/workflows/skillspector.yml/badge.svg)](https://github.com/crodris/skills/actions/workflows/skillspector.yml)

Agent skills I use every day, for taking work from a tracker issue to a merged pull request.
They run on any agent that skills.sh supports, and Fathom and ship also install as Claude Code plugins.

## Install

```bash
npx skills@latest add crodris/skills
```

The installer lists every skill, so take only the ones you want.
`scaffold` reads its contract files from `execute`, and `execute` opens its pull requests through `file-pr` from the ship plugin, so take all three.
Upgrading from Fathom 2, delete the old `fathom-shared` directory from your skills folder, since its files now live in `execute`.
The ship skills need each other, so take all six: `ship`, `prove`, `file-pr`, `babysit`, `review-loop`, and `land`.

On Claude Code, Fathom and ship also install as plugins, and so does the fathom-progress mod:

```text
/plugin marketplace add crodris/skills
/plugin install fathom@crodris
/plugin install ship@crodris
/plugin install fathom-progress@crodris
```

## Plugins

### fathom (v3.0.1)

`execute` takes a tracker issue through breakdown, implementation, tests, commits, and an open review, and resumes where the last run stopped.
`scaffold` turns requirements into a main issue with linked sub-issues, then offers to hand off to `execute`.
They need an Asana or Linear MCP, and the GitHub CLI for reviews on GitHub.
The [Fathom guide](./skills/execute/README.md) covers setup, task memory, stacked reviews, and troubleshooting.

### ship (v3.2.0)

Six skills that carry the current branch to a green pull request, and on to a merged release when you ask to merge.
Each one ends with a result line that the next one reads.

| Skill | Does | Runs on its own when you ask to |
| --- | --- | --- |
| `ship` | Settles the mode and the branch, calls the others in order, and reports | ship |
| `prove` | Runs the project's own verify gates until clean, then commits when the caller asks it to | prove or verify a change |
| `file-pr` | Opens or updates the pull request, with its title, body, and secrets check | file a pull request |
| `babysit` | Runs each pass: CI and the review bots, `review-loop`, one push, base updates | babysit, watch, or monitor a pull request |
| `review-loop` | Reviews with Standards and Spec subagents, triages every finding into a ledger, and fixes the blocking ones in one batch | run one review-and-fix pass |
| `land` | Checks the merge gate, merges with the repository's merge method, watches the release, and cleans up | land a ready pull request |

`review-loop` follows `cross-review: cursor` as its Review section says, and gets that second opinion through the `cursor` skill.

Plain "ship" stops at a green pull request.
It merges only when you ask it to, or when `.ship/config.md` sets `merge: yes` and the request does not ask only for a green pull request.
It merges with the `merge-method` in `.ship/config.md` (`squash`, `rebase`, or `merge`), and asks once, with an example for each, when that line is missing and the repository allows more than one method or its settings are unreadable.
When a review bot is rate limited, out of credits, or silent, `babysit` goes on without it on a low-risk pull request, and on a high-risk one runs a stand-in review and waits only for a short rate limit.
The skills need a git remote, an authenticated GitHub CLI, and `jq`.

### fathom-progress (v0.2.1)

Ryan Uesato built `fathom-progress`, a Claude Code mod that draws a progress band above the prompt while `execute` or `scaffold` runs.
It reads the run's tasks from beads or the committed checklist, and never changes them.
Its [README](./mods/fathom-progress/README.md) covers setup, what the band shows, and working on the mod.

## Standalone Skills

These install through skills.sh only.

### review (v1.2.1)

`review` checks a pull request against the issue it claims to close, on running builds of the branch and its base, and posts one review with inline findings.
It reads its build, serving, and measuring steps from `ui.md` only when the pull request changes what the app renders.
It needs the GitHub CLI, plus a browser driver such as Playwright for visual changes, and answers whether a pull request is safe to merge with `land`'s merge gate.

### rewrite (v3.1.1)

`rewrite` drafts and rewrites prose you post under your name, in your voice, and removes the patterns that mark text as machine-written.
It reads the voice file that `$XDG_CONFIG_HOME/voice/config.md` points at, or `~/.config/voice/config.md` when that variable is unset, empty, or not an absolute path, and builds one with you on first run from `setup.md`.
It runs [unslop](https://github.com/cursor/plugins/tree/main/pstack/skills/unslop) first when that is installed, and keeps a short fallback floor for installs without it.
To move from an old name, run `npx skills@latest remove my-voice -g` (or `npx skills@latest remove voice -g` for an install older than v2.0.0), then `npx skills@latest add crodris/skills -s rewrite -g`.

### frontend-design-pipeline (v1.3.1)

`frontend-design-pipeline` takes a UI from idea to build: candidate design systems, direction briefs, rendered mocks for you to pick from, motion, then the build.
It needs [impeccable](https://github.com/pbakaus/impeccable), and its `SKILL.md` lists the companion skills and the install command format.

### html-comms (v1.1.0)

`html-comms` turns a plan, report, comparison, or set of UI mocks into one HTML page and publishes it to a private link, or with the `local` publisher writes it as an unpublished file.
It asks once which publisher to use, the harness's private one such as the Artifact tool in Claude Code or a local file, and saves the answer in `$XDG_CONFIG_HOME/html-comms/config.md`.
A run with no user to answer, such as a delegate or headless run, uses the harness's publisher and saves nothing.
When `XDG_CONFIG_HOME` is unset, empty, or not an absolute path, that file is `~/.config/html-comms/config.md`.

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

### verification-audit (v1.1.1)

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

Ryan Uesato built the `fathom-progress` mod in `mods/fathom-progress/`.

Some rules are adapted from Matt Pocock's mattpocock/skills and obra/superpowers (MIT), including the merge-danger line, the summary visuals, and the before-and-after evidence in `file-pr`'s pull request body (from the `pr` skill, which credits Dex Horthy's `show-me`), execute's frontier fan-out (from `implement-spec`), and the "Call the Skill tool" wording for loading another skill.
Ship's hold mode, CI, and pull request title and body rules, now in `babysit` and `file-pr`, come from Theo Browne's (t3dotgg) babysit-pr and file-pr skills.
The ship family's split into small skills, `review-loop`'s finding ledger, round budget, nit relabel rule, and diff-size check, `babysit`'s auto-merge and merge-queue release, `file-pr`'s secrets check, `land`'s proof-coverage gate item, and `ship`'s list of decisions made on the user's behalf are adapted from Theo Browne's tstack (MIT).
`html-comms` is adapted from Theo Browne's html-communication, with its chart heuristic from [ruesato/agent-skill-floreo](https://github.com/ruesato/agent-skill-floreo) (MIT).
The `rewrite` skill's floor rows for arguing with no one, re-explained context, dramatic closers, and the document-describing half of meta commentary, and rewrite mode's no-new-facts rule, are adapted from Siqi Chen's (blader) humanizer (MIT).
