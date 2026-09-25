# skills

[![SkillSpector](https://github.com/crodris/skills/actions/workflows/skillspector.yml/badge.svg)](https://github.com/crodris/skills/actions/workflows/skillspector.yml)

Personal agent skills for issue-driven development workflow automation, installable as Claude Code plugins or onto any agent via [skills.sh](https://www.skills.sh).
All skills are scanned with [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) on every change; the build fails on any non-suppressed security finding.

## Installation (30-second setup)

**Recommended: any agent** - use [skills.sh](https://www.skills.sh), which installs the same skills on Claude Code, Kiro, Codex, and other agents, and `npx skills update` pulls the latest when this repo ships:

```bash
npx skills@latest add crodris/skills
```

The installer lists every skill in `skills/` regardless of which plugin owns it.
Take `ship`, `review`, `voice`, or `frontend-design-pipeline` on its own if that is all you want.
`execute` and `scaffold` require `fathom-shared`, which carries the contract files they read, and each stops with its install command when it is missing.

**Claude Code plugins** - also available, for Claude Code only:

```text
/plugin marketplace add crodris/skills
/plugin install fathom@crodris
/plugin install ship@crodris
```

The two plugins are independent: install either one alone.
Fathom needs a tracker MCP. Ship needs a git repository with a remote.
`review`, `voice`, and `frontend-design-pipeline` belong to no plugin on purpose, so they install through skills.sh and not through `/plugin install`.

> Individual plugins may have additional prerequisites that run in your **terminal** (e.g., `brew install`). See each plugin's README for details.

## Available Plugins

### fathom (v2.3.0)

Fathom provides two agent skills, execute and scaffold, that carry a tracker issue from requirements to an open code review, on GitHub or any other forge with an adapter.
It works with Asana or Linear as your issue tracker, and both skills run unchanged on Claude Code and Kiro.

#### Prerequisites

- An Asana or Linear MCP plugin installed and authenticated
- [Beads CLI](https://github.com/gastownhall/beads) installed (`bd` command available); optional, but recommended for the richest task memory
- A forge adapter for wherever your reviews live. Two ship built in: GitHub, which needs the [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh` command available), and a generic-git fallback that pushes the branch and hands the review off to you. Write a `.fathom/forge.md` from the bundled template only for a forge Fathom does not ship.

#### Install

```bash
/plugin install fathom@crodris
```

#### Skills

| Skill | Description |
|-------|-------------|
| `execute` | Drives one tracker issue through a single resumable pass: breakdown, implementation, tests, commits, and an open code review. |
| `scaffold` | Turns requirements text into a scaffolded main issue plus linked sub-issues, then offers to hand off to execute. |

Talk to either skill in plain language; there are no slash commands to memorize.

```bash
execute ONC-5
work on <asana task url>
scaffold these requirements
```

#### Features

- **Resumable pass** - execute reads durable state from disk and the tracker on every invocation, never from memory of a previous run
- **Scaffold-to-execute handoff** - scaffold drafts a main issue plus sub-issues, then offers to hand straight into execute
- **Task memory** - beads-backed when available, with a plain checklist file fallback
- **Conventional Commits** - one commit per task, referencing the issue ref
- **Tracker-only access** - tracker work only happens through the connected tracker MCP; when it is missing, the skill refuses and stops
- **Forge-portable** - reviews go through a five-operation forge contract; GitHub and a generic-git fallback ship built in, and any other forge is a `.fathom/forge.md` you write without forking

#### Tracker Status Lifecycle

```text
Todo → In Progress (execute starts) → In Review (review opened) → Done (review merged)
```

See the [full guide](./docs/fathom.md) for setup, task memory, and the security boundary.

---

### ship (v1.5.0)

Ship takes the current branch from working tree to merged release in one pass: verification runs until clean, five rounds at most, then commit, push, pull request, one parallel review by Standards and Spec subagents and the pull-request bot, batched fix pushes, each one confirmed, until nothing blocking remains, squash-merge, release watch, and post-merge cleanup.
Everything from the pull request onward needs an installed and authenticated GitHub CLI; without one, ship stops after pushing the branch and printing the compare URL, and the review, merge, and release are yours to drive.

#### Prerequisites

- A git repository with a remote
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh`) for the pull request, merge, and check-polling stages; without it ship pushes the branch, prints the compare URL, and hands the review off to you

#### Install

```bash
npx skills@latest add crodris/skills
```

Pick `ship` in the installer. On Claude Code, `/plugin install ship@crodris` also works.

#### Skills

| Skill | Description |
|-------|-------------|
| `ship` | Resolves the project's own verification pipeline, then drives the branch through review, CI, pull request, merge, release, and cleanup without stopping between stages. |

```bash
ship
ship it
```

#### Features

- **Project-resolved pipeline** - the verify command comes from `.ship/config.md`, then the project's docs, then a declared aggregate task, then the pull-request CI job, then a composed fallback; the first tier that answers wins
- **Asks once, remembers** - when detection is ambiguous ship asks a single question before touching the tree, then records the answer in `.ship/config.md` and commits it on its own, so the decision reaches the next branch, clone, and teammate; the commit keeps it separable from the change it rode in with, and it is still reviewed and merged as part of the pull request
- **No config for free answers** - a pipeline detection resolved on its own gets no file, because a file that restates what is already discoverable only goes stale; `.ship/config.md` exists to preserve a human decision
- **Review gates the merge, not the pull request** - the subagents and the pull-request bot read the same pushed head at the same time, their findings are deduped by root cause, and every blocking fix on a pass lands in one batched push followed by a confirmation pass; the normal run is two pushes, and one when nothing was blocking
- **Exit only on an untouched pass** - the review loop ends only on a settled pass that pushed nothing, with no pass cap: it runs until a settled pass has nothing blocking, and stops to report when a root cause an earlier push carried a fix for comes back, so a green result always describes the code that actually merges
- **A blocking bar, not a nit hunt** - ship fixes verify failures, confirmed critical or major findings, and confirmed minors (defects or code smells) worth fixing whose fix stays contained to the flagged code, replies with a disposition for everything else, lets minors buy a push on their own only once per run, and never pushes for a nit; fixing every nit hands the next pass fresh code to find fault with, which is how a review loop never converges
- **Lanes from your config** - optional `light-paths` and `security-paths` globs in `.ship/config.md` skip the subagents for changes that are entirely low-risk, or add a security review when a sensitive path is touched; an optional `drive`, a command or a `skill:<name>` verification skill, runs once before the push on a behavior-changing diff, and again on each confirmation pass a fix push buys, where it replaces the subagents' confirmation round unless the bot reviews only the first push
- **Different reviewers, not one twice** - the pre-merge review is two `general-purpose` subagents on the same SHA, one checking the repository's documented conventions and one checking the change against its issue or stated intent, and the pull-request bot is the final bar that still has to settle green; ship never shells out to a review CLI, because the vendors that ship one also run the bot and the CLI would spend that quota on a judgment the bot reaches anyway; a bot that reviews only the first push is asked for another review after each fix for a critical or major finding it raised, until its latest review raises no confirmed critical or major, and the subagents confirm every other fix
- **Bot review mode from the repo** - ship learns that CodeRabbit reviews only the first push from `reviews.auto_review.auto_incremental_review: false` in `.coderabbit.yaml`; a setting made only in the CodeRabbit web app is invisible to ship, which then waits on a re-review that never comes, so keep it in the file with `inheritance: true` to leave the web-app settings in force
- **Project-local override** - a repository that ships its own `.claude/skills/ship/SKILL.md` takes precedence, carrying its specialized pipeline

---

## Standalone Skills

Skills here that no plugin claims. They install through [skills.sh](https://www.skills.sh) (`npx skills@latest add crodris/skills`) rather than `/plugin install`.

### review (v1.1.0)

Review verifies a pull request against the tracker issue it claims to close, on a build it actually runs, and posts one review with line-specific findings anchored inline and general findings in the summary body.

Its premise is that a diff review cannot see the things worth catching. The findings it was built from were a border removal that read as correct in light mode and gutted the card edge in dark, two halves of one panel whose content sat 388px apart at wide viewports, a dropdown that `toBeVisible()` reported as visible while it was clipped, and an animation that un-clipped a zero-height node one frame before unmount. So it builds the branch and its merge-base side by side, measures both, and reports the difference.

#### Prerequisites

- A git repository with a remote
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh`) for reading pull request metadata and posting the review
- A browser driver for the visual stages, such as Playwright or a browser MCP; a purely behavioural pull request needs neither

#### Install

```bash
npx skills@latest add crodris/skills
```

#### Skills

| Skill | Description |
|-------|-------------|
| `review` | Builds the pull request and its merge-base, measures both, proves the new tests are load-bearing, then posts one review with severity-marked findings. |

```bash
review this PR
review #107
```

#### Features

- **Never concludes from the diff** - the branch and its merge-base are built and served side by side, so every claim comes from a running app rather than from reading a change
- **A/B before blame** - a finding measured on the base build too is reported as pre-existing, which is the difference between telling an author they broke something and telling them they inherited it
- **Pixels over computed styles** - for any claim that something is or is not visible, the screenshot is decoded and the painted colours compared; `border: 0` plus a 1.1:1 background step reads as conclusive and is routinely wrong
- **Checks the house rules too** - the diff is read against the conventions the repository documents, such as AGENTS.md, CLAUDE.md, and contributing docs, separately from the issue check
- **Tests the tests** - reverts the changed source to confirm the new assertions fail without it, then adversarially checks the ones that pass either way by making the exact change they claim to catch
- **Fails closed on a moved head** - the fetched ref is verified against the pull request's reported head before anything is measured, so a re-review never silently describes yesterday's commit
- **Severity that means something** - 🔴 is reserved for a regression the pull request introduces with a cheap fix, and findings are deduped to root causes first, so a good pull request does not read as riddled with defects
- **Costs what it should** - both builds stay warm, every measurement batches through one browser session, and the gates come from CI rather than being re-derived locally

---

### voice (v1.1.0)

Voice drafts, rewrites, and checks the prose you post under your own name, in your own voice, with the tells that mark text as machine-written removed.
PR descriptions and review comments, issues, Slack, email, READMEs, blog posts, release notes, cover letters.
It reads your voice file at the start of each conversation and applies a built-in floor of AI writing patterns on top: the negation-then-correction construction ("it's not X, it's Y"), the rule of three, puffery, participle tails, chat leakage, dead vocabulary.
Your voice file wins over the floor, so anything it re-allows comes back.

Nothing personal ships in this repository.
The skill reads the voice file that `$XDG_CONFIG_HOME/voice/config.md` points at, or `~/.config/voice/config.md` when that variable is unset.
On first run it takes a voice file you already have, or a folder of things you wrote and builds the voice file from excerpts of it, or interviews you and builds one from the bundled `template.md`.
The folder or pasted samples stay listed in the config, so when the output drifts you can say "recalibrate my voice" and the skill goes back to your real writing instead of its own last draft.

#### Prerequisites

- A writable `$XDG_CONFIG_HOME/voice/` (or `~/.config/voice/` when that variable is unset) for the config file and, when the interview builds one, the voice file

#### Works best with

[unslop](https://github.com/cursor/plugins), an optional pre-pass that voice runs on the draft before its own pass when installed: `npx skills@latest add cursor/plugins -s unslop -g`.
Voice works fully without it.

#### Install

```bash
npx skills@latest add crodris/skills
```

#### Skills

| Skill | Description |
|-------|-------------|
| `voice` | Loads your voice file(s), drafts or rewrites the text in your register, then runs a pass for machine-writing tells before handing it back. |

```bash
rewrite this so it sounds like me
this sounds too AI
draft the PR description for this branch
voice setup
recalibrate my voice
```

#### Features

- **Your file, your machine** - the voice lives wherever the config points, so the public skill carries no one's personal style doc and the same skill serves every installer
- **First-run setup** - point it at a voice file you already have, or at a folder of things you wrote, or answer a short interview in your own words; it builds the file from the template and shows it to you before saving
- **Recalibrate from the source** - the folder or samples the voice was built from stay in the config, so "recalibrate my voice" re-reads your real writing and fixes the excerpts and rules that drifted
- **Samples beat rules** - the template keeps your real writing verbatim, and the skill matches rhythm and register against those before it reads any rule
- **A floor everyone gets** - the built-in checklist covers the patterns research and readers both flag as machine-written, with the negation-then-correction construction treated as fatal; your voice file can re-allow any of it
- **Four modes** - draft from facts, rewrite existing text keeping every fact and link, check-only, which quotes each failing line and names the tell without touching the text, and recalibrate
- **Never from memory** - the voice files are read in full at the start of each conversation, because a summary of a voice is the default register with a costume on
- **Knows when to stay out** - code, commit messages, test names, config, and text addressed to another agent are left alone

---

### frontend-design-pipeline (v1.0.0)

Frontend design pipeline takes a UI from product idea to finished build by chaining four design skills in a fixed order, and adds one stop for you to pick a direction.
It generates candidate design systems with ui-ux-pro-max, turns each into a direction brief with one taste-skill preset, pins the one you pick in DESIGN.md, adds motion decisions with emil-design-eng, and hands DESIGN.md to impeccable to build, critique, and polish.
It ships no design knowledge of its own and never copies the skills it calls.
Only impeccable is required; the rest improve the result when installed.

#### Prerequisites

- [impeccable](https://github.com/pbakaus/impeccable), which builds and finishes every run: `npx skills@latest add pbakaus/impeccable -s impeccable -g`

#### Works best with

Each of these runs one stage.
When one is missing, the pipeline skips that stage, says so once with the install command, and carries on.

| Skill | Stage | Install |
|-------|-------|---------|
| [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | Candidate design systems (needs `python3` or `python`) | `npx skills@latest add nextlevelbuilder/ui-ux-pro-max-skill -s ui-ux-pro-max -g` |
| [taste-skill](https://github.com/Leonxlnx/taste-skill) presets | Direction briefs, one preset per candidate | `npx skills@latest add Leonxlnx/taste-skill -s minimalist-ui high-end-visual-design industrial-brutalist-ui gpt-taste design-taste-frontend redesign-existing-projects -g` |
| [emil-design-eng](https://github.com/emilkowalski/skills) | Motion and interaction decisions | `npx skills@latest add emilkowalski/skills -s emil-design-eng -g` |

#### Install

```bash
npx skills@latest add crodris/skills
```

#### Skills

| Skill | Description |
|-------|-------------|
| `frontend-design-pipeline` | Runs options, direction, your pick, motion, and build in order, and writes the picked direction to DESIGN.md for impeccable to build against. |

```bash
design a landing page for my app and give me directions first
redesign the settings screen
run the full design flow
```

#### Features

- **One preset per candidate** - taste-skill presets contradict each other, so each candidate gets exactly one
- **One source of truth** - after your pick, DESIGN.md beats the generated candidates, any ui-ux-pro-max MASTER.md, and taste-skill hard bans
- **Existing looks skip ahead** - a new page or a refinement inside the current look goes straight to motion or build
- **Works outside Claude Code** - ui-ux-pro-max's search script is resolved from its own skill directory instead of the Claude Code-only `${CLAUDE_PLUGIN_ROOT}` path its SKILL.md uses

## Workflow

1. **Scaffold requirements**: talk to the scaffold skill, for example "scaffold these requirements"
2. **Execute the issue**: talk to the execute skill, for example "execute ONC-5"
3. **Resume if interrupted**: re-invoke execute on the same issue; it picks up where the last run left off
4. **Review the pull request**: talk to the review skill, for example "review #107", to verify it against its issue on a running build
5. **Ship the branch**: talk to the ship skill, for example "ship it", to carry the reviewed branch through merge and release

## Repository Layout

Every skill lives in a flat `skills/<name>/` directory, and `.claude-plugin/marketplace.json` decides which plugin owns which skill through a per-entry `skills` array.
A skill claimed by no entry, such as `review`, `voice`, or `frontend-design-pipeline`, is still published by skills.sh and is simply unreachable through `/plugin install`; `bin/sync-versions.sh` reports it so the omission stays deliberate rather than accidental.
Both plugins therefore share one marketplace root (`source: "./"`), and there is deliberately no `.claude-plugin/plugin.json`: with that source a single root manifest would apply to every entry and its version would silently win over each entry's own.
`bin/sync-versions.sh` syncs the versions into this README and fails when a skill directory is claimed by no plugin, by more than one, or is claimed but missing.

## Security Scanning

Every skill in `skills/` is scanned by [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector) in CI, and the build fails on any non-suppressed finding.
Run the same scan locally before committing:

```bash
uv tool install git+https://github.com/NVIDIA/skillspector.git
bin/scan-skills.sh            # all skills; or name specific ones: bin/scan-skills.sh execute
```

When a finding is a reviewed false positive, suppress it in the repo-root `.skillspector-baseline.yaml` with a written reason; never suppress a finding you have not understood.

## License

MIT

Some rules adapted from mattpocock/skills (MIT).
