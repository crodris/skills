# fathom-progress

Ryan Uesato built fathom-progress, and "I" in this README is Ryan.

fathom-progress is a Claude Code mod that draws a progress band above the prompt while Fathom works through an issue. The band shows the issue, how many of its tasks are done, and the task in progress. It is for people who run Fathom's `execute` skill and want to see where a run stands without reading the transcript.

A mod is a plugin that changes Claude Code's own interface or behavior. Fathom is a Claude Code plugin that takes an Asana or Linear issue from breakdown through implementation to an open code review, and records its tasks in Beads, a local issue tracker with a command-line tool called `bd`. In a repository that doesn't use Beads, Fathom records them in a checklist file instead. fathom-progress reads the tasks from either place and draws them. It never changes them.

I built it with Claude Code. It works in the terminal and in the Claude Code Desktop app. Inside cmux, a terminal app, it also puts the run on the workspace's sidebar row.

```
 ━━━━━━━━━━╸━━━━━━━━━━╸━━━━━━━━━━╸━━━━━━━━━━╸━━━━━━━━━━━ 40%
 ● PHA-368 Home page: Restrict actions and CTAs, add video · 1 in review
 ▸ now 3/5  Add the results toggle
```

*A schematic of the terminal layout, not a screenshot. Each task is a segment of the bar, colored by its state. The bar fills the width of the window, so it is longer in a wide terminal, and the percent follows it.*

## Setup

### What You Need

- Claude Code with mods. I built and tested this on 2.1.295 and 2.1.296. The Desktop app (version 2.31226.1) bundles Claude Code 2.1.293 and 2.1.295. I have not tried earlier versions.
- The Fathom plugin. I tested with 2.7.1.
- Beads (`bd`), if the project uses it. I tested with `bd` 1.1.0 and 1.3.1. Without Beads, Fathom records its tasks in `.fathom/tasks/<ref>.md`, which the band reads with no `bd` at all (see "Where It Reads the Tasks").
- `git`. The band reads the current branch name to find the issue when you don't type one.

### Install

fathom-progress is a plugin in the `crodris` marketplace, the same one that carries Fathom. Add the marketplace, then install the plugin.

```sh
claude plugin marketplace add crodris/skills
claude plugin install fathom-progress@crodris
```

In a session that is already running, run `/reload-plugins`. Otherwise it loads the next time you start Claude Code.

To update, run `claude plugin marketplace update crodris` and then `claude plugin update fathom-progress@crodris`. According to the Claude Code documentation, a copy installed from GitHub updates only when its `version` changes.

If you also use `beads-status`, install fathom-progress first. Both draw in the same spot above the prompt, and when both are installed, the one installed first gets the slot. I saw this in both orders. With fathom-progress installed first, the `beads-status` band shows while no Fathom run is active, and the Fathom band takes its place when a run starts. With `beads-status` installed first, its band stayed on screen for the 25 seconds I watched and the Fathom band never appeared, although the mod armed and followed the issue. The order is the order you installed them in, which is also the order of the two entries under `enabledPlugins` in `~/.claude/settings.json`. `claude plugin list` sorts by name, so it does not show it. Reinstalling fathom-progress by itself puts it last, and its band goes behind `beads-status`. Reinstalling `beads-status` by itself is safe. To put the order right, uninstall `beads-status` and install it again.

#### Loading a Folder Instead

You can load the mod's folder without installing it. Do this to try it quickly, or when you use `beads-status` from a folder (see below).

A mod loaded from a folder runs ahead of an installed one. `beads-status` draws above the prompt and never yields, so when it is loaded from a folder, an installed fathom-progress never gets the slot. I saw this: with fathom-progress installed and `beads-status` in `CLAUDE_CODE_PLUGIN_DIRS`, `beads-status` drew and the band did not, and with both in the variable and fathom-progress first, the band drew. If you load `beads-status` from a folder, load fathom-progress from a folder too.

1. Clone this repository.

   ```sh
   git clone git@github.com:crodris/skills.git
   ```

2. Add the mod's folder to `CLAUDE_CODE_PLUGIN_DIRS` in the `env` block of your Claude Code settings file (`~/.claude/settings.json`). Use the absolute path to `mods/fathom-progress`.

   ```json
   {
     "env": {
       "CLAUDE_CODE_PLUGIN_DIRS": "/absolute/path/to/skills/mods/fathom-progress"
     }
   }
   ```

   To load more than one mod, separate the paths with a colon. If you also use `beads-status`, which draws a Beads status band in the same spot above the prompt, list fathom-progress first. When `beads-status` is first it draws before fathom-progress gets a turn and never yields.

3. Start a new Claude Code session. A session that was already running when you saved the setting does not load the mod. After the mod is installed, edits to its files load with `/reload-plugins`.

If you run Claude Code with a separate config directory (the `CLAUDE_CONFIG_DIR` variable), that directory has its own `settings.json`, and the setting goes in each one you use.

The Desktop app reads the same settings file, so the same entry loads the mod there.

### Check That It Works

Run a Fathom issue.

```
/fathom:execute PHA-352
```

The band shows `fathom starting…` right away (`[fathom] starting…` in the Desktop app), then switches to the run's tasks once Fathom has made them. Replace `PHA-352` with one of your issues.

## Using It

### Starting the Band

The band appears when Fathom's `execute` or `scaffold` skill starts, and not before. Three signals can start it, and you don't choose between them:

- You type `/fathom:execute` (or `/fathom:scaffold`).
- Claude calls the Skill tool with a Fathom skill, for example because you asked for it in plain words. This depends on Claude choosing to call the tool.
- The engine reports the skill's own text as a skill prompt. On the Team organization account I used, this signal never reached the mod (see "Team Organization Accounts" below), so the first two carry it there.

`/fathom:scaffold` writes no Beads tasks, so the band has no run to read. It follows a scaffold another way, described under "A Scaffold Run" below.

The band goes away when the session ends, and after `/clear`. When no Fathom run is active it passes the space to `beads-status`.

### Which Issue It Follows

The band follows one issue at a time and picks it in this order:

1. **The ref you typed.** `/fathom:execute pha-352` follows PHA-352, in any status, whether the run is open or finished. A ref with no matching issue shows `fathom starting…` and never another run. Refs are matched without regard to case, and a URL that contains the ref (a Linear issue URL does) works as well as the ref.
2. **The branch.** With no ref typed, the band reads the ref from the current git branch (`feat/pha-352-relabel-results-view-control` gives PHA-352). Fathom resumes a run the same way, so a run you pick up in a new session shows up. An issue created since you started wins over the branch's.
3. **The newest run.** With no ref and no ref in the branch name, the band follows the issue created since the invocation, or else the open one with the most recent activity.

Asana's numeric task refs are not read yet, and a ref written in a plain-words request is not used (only a typed command carries one).

### Where It Reads the Tasks

Fathom records a run's tasks in one of two places, and the band reads either one.

- **Beads.** Fathom uses Beads when the repository's base branch tracks a `.beads/` workspace and `bd` works. The band reads the tasks with `bd`, as "How a Run Becomes a Band" describes.
- **A checklist.** In any other repository Fathom keeps the tasks in `.fathom/tasks/<ref>.md`, one line per task, marked `[ ]` for open, `[>]` for in progress and `[x]` for done. The band reads that file from your working tree and not from git, because Fathom leaves the in-progress marker uncommitted until the task's commit. The band needs no `bd` for it.

An issue has one or the other. When `bd` finds a run for the ref, the band uses it and doesn't open a checklist. When `bd` finds none, the band looks for `.fathom/tasks/<ref>.md` for the ref you typed, or else the ref in the branch name. A `bd` that is missing or fails therefore doesn't hide a checklist. With no checklist either, the band depends on the repository. If it has a `.beads/` folder, the band shows `fathom unavailable` and the reason `bd` gave. If it has none, `bd` failing is the normal state (`no beads database found`), and the band shows `fathom starting…` until Fathom writes the checklist, which it does at breakdown, after it has read the issue.

A checklist has no creation time, so the third rule under "Which Issue It Follows", the newest run with no ref, doesn't apply to it. Type the ref, or work on the issue's branch.

The band reads a checklist's states from its markers and its `(deps: 1, 2)` lists. A `[x]` task is done and a `[>]` task is in progress. Several `[>]` lines are tasks running in parallel, and they all draw as in progress. A `[ ]` task is next when every task it depends on is done, and waiting when one isn't. A dependency on a task the file doesn't list counts as done, so one lost line can't stall the run. The title comes from the file's first line, as `# ONC-5: Add login flow`.

The plan document, `.fathom/plans/<ref>.md`, is also written for a checklist run: Fathom's `execute` writes it at breakdown whichever backend it uses and adds the checklist file only when the checklist is the backend. The band reads the same review lines from it, so a task in review is marked the same way. A run without a plan document still draws.

### What the Band Shows

In the terminal the first row is a bar with one segment per task, with the percent done right after it. The second row is a status dot, the issue's ref and its title (`PHA-368 Home page: Restrict actions and CTAs, add video`), followed by how many tasks are in review when any are. The third row names the task in progress, or the next one. The Desktop app has the same three rows. It writes `Progress band` after the ref instead of the title, because that is what the design's frames read, and I haven't designed a title for it.

| State | Looks like | When |
|---|---|---|
| Starting | `fathom starting…` | Fathom has started and the issue isn't in Beads or in a checklist yet, or nothing matches the ref you typed. Also in a repository with no `.beads/` folder when `bd` can't be read, which is the normal state there. |
| Planning | A bar that fills one slot for each task made, `0%`, the ref alone, then `▸ planning` and `3 tasks so far` | The run's issue and some tasks exist, but the plan document isn't written and no task has started, so the total isn't known. |
| Executing | The full bar, `▸ now 3/5`, and the task's title | The plan document exists or a task has been claimed, and not every task is closed. |
| Finished | A green bar and `✓ 5/5 done` | Every task is closed. |
| Unavailable | `fathom unavailable: <reason>` | `bd` failed or printed something the band can't read, in a repository that has a `.beads/` folder, and there is no checklist for the ref. Also a file at `.fathom/tasks/<ref>.md` that isn't a Fathom checklist. It never shows zeros in its place. |

The Desktop app writes the starting and unavailable lines with brackets (`[fathom] starting…`), and its lines under the label have no leading `▸`, since none of the design's Desktop frames has one.

Each task segment has a color. The Desktop app's dark-theme bar tells the states apart by color alone, as the terminal's does. The box bar the Desktop draws for other themes also has a mark in every segment except those not yet started.

| Task | Color | Mark (box bar, other Desktop themes) |
|---|---|---|
| Done | Green | ✓ |
| Done, review still open | Coral | ◐ |
| In progress | Yellow | ● |
| Next | Light grey on the Desktop's dark-theme bar, dark grey elsewhere | none |
| Waiting | Dark grey | none |

Fathom can split a large issue into bundles, a stack of branches that each get their own review. A task is in review when it is done and its bundle has a review recorded in the run's plan document (`.fathom/plans/<ref>.md`). The plan document doesn't say whether that review has merged, so a recorded review counts as open, and the task stays in review until every task is closed. A finished run has no reviews open. When some tasks are in review, the second row adds `· 2 in review`.

The terminal's bar and the Desktop's dark-theme bar are thin, too thin for a mark, so there the states are told apart by color alone. The second and third rows carry what the colors can't: how many tasks are in review, and which task is running or next.

The segments are equal widths. Fathom doesn't record a size for each task yet.

#### Where the Title Comes From

Beads doesn't have it. Fathom creates its epic with the bare ref as the title, and gives it no description. The band reads the title from the plan document, `.fathom/plans/<ref>.md`, in its first heading, written as `# PHA-368: Home page: Restrict actions and CTAs, add video`. Everything after the first colon and space is the title, so a title with colons in it stays whole. A checklist has the title in its own first line, in the same form, and the band reads that one first.

Three of the four plans I read in my own repository have that heading. Fathom's conventions don't fix it the way they fix the `Issue`, `Ref` and `Branch` lines, so the band can find no title:

- **While Fathom is making the tasks.** The plan document is written after the last task, so the band shows the ref alone until then.
- **A plan whose heading has no title.** The fourth plan I read had `# PHA-186 plan`. The band shows the ref alone for it.
- **A heading for another issue.** If the heading's ref isn't the plan's own `Ref`, the band ignores it.

A title that is too long for the row is cut with an ellipsis. The count of tasks in review gives way first, and the ref stays whole while it can.

### A Scaffold Run

Scaffold makes a main issue and its sub-issues in Linear or Asana and records nothing in Beads, so the band can't read its progress the way it reads an execute run. It watches what Claude does instead: the tracker calls it makes and the questions it asks. The band shows four steps, `Resolve`, `Draft`, `Create` and `Done`, with a green dot before each finished step and an outlined circle in the band's color at the current one. While Claude creates the issues, the band also counts how many exist so far. There is no total and no percent, because the draft you approve is text, and the count is only known as the issues appear.

```
 Scaffold · Creating, 3 issues made (5m 22s)
 ● Resolve  ● Draft  ○ Create  Done
```

*A schematic of the terminal layout, not a screenshot.* The first row ends with how long the run has gone on, in the dim color, and stops counting when the run is done. The phase has a yellow dot in front of it only while the scaffold waits on you (a question, or the draft's approval), since that is the one state that needs you:

```
 Scaffold · ● Waiting on you (3m 55s)
 ● Resolve  ○ Draft  Create  Done
```

On the Desktop app, with the dark theme, the dots are drawn as circles 9 pixels across and not as `●` and `○`: the current step is a ring with a 2 pixel stroke inside the 9, as in the design, and the finished steps and the waiting dot are the same circle filled. Any other theme gets the characters, since a drawn circle can't follow the theme's colors.

The words the band adds start with a capital. Anything that comes from outside the band, such as an issue title, keeps its own case. On the cmux row it is a pill with the same wording, shortened to fit (`Scaffold · Waiting on you`).

What moves it, as I saw it in one run against Linear:

- **Resolve to draft.** Claude's call that verifies the tracker connection (`get_user` on Linear).
- **Waiting on you.** A question to you. Your answer, or your next message, puts the band back on draft.
- **Create.** Each `save_issue` call with no issue id. A call with an id is an update and isn't counted, and neither is a call the tracker refuses.
- **Done.** A question after an issue was made (the "run execute now?" hand-off), Claude starting execute, or the turn ending after an issue was made. Starting execute replaces the scaffold band with execute's.

Limits:

- Linear is the only tracker it reads. I haven't seen the calls Asana makes, so on Asana the band can't tell a finished scaffold from one waiting on you. Don't rely on it there.
- A scaffold that ends before it makes any issue (the tracker connection is missing, for example) stays on "Waiting on you" until you start another Fathom command or end the session.
- I haven't checked a Team organization account.
- The time is counted from when the band saw the scaffold start, so it is left off after `/reload-plugins`, which makes the band forget when the run began.

### The Terminal and the Desktop App

Both show the same run, in the same three rows. They draw the bar differently.

- **Terminal.** The band is three rows, as in the design: the bar and percent, then the dot, ref and label, then the task. The bar is a row of heavy line characters (`━`), so it is thin like the design's bar and sits in the middle of its row. It fills the window: it takes every character the left margin, the gap and the percent leave, with no upper limit, and the percent follows it. The segments are equal widths, so the bar can stop up to a few characters short of the end of the row. It has no marks and no step count in it. The design leaves 2 pixels between segments, and no line character stops closer to the edge of a character than its middle. Each segment but the last therefore ends in a heavy half line (`╸`), which leaves half a character between segments, about 4.5 pixels at the width the design uses. I tried a quarter-height block (`▂`) first, and its gaps were a whole character wide. `beads-status` gets about 1 pixel with a seven-eighths block (`▉`), but its bar is a full row tall. The first version of the bar stopped at 55 characters, the width of the design's first frame, and the percent was pushed to the end of the row, far from it in a wide window. The design's later frame (`64:792`) lets the bar fill the row with the percent right after it, which is what the terminal draws now.
- **Desktop app, dark theme.** The bar is an image (a Scalable Vector Graphics image, SVG) of thin rounded segments, one for each task, 3 pixels apart, as the design draws them. It has no count or marks in it. The percent follows it after 12 pixels, and the bar fills the rest of the row. While the tasks are being made it is one grey segment for each task made, sharing the whole bar. An SVG can't read theme colors, so its colors are fixed to the dark theme.
- **Desktop app, any other theme.** The bar is drawn from colored boxes that follow the theme, in the same three rows. A box is as tall as a row and can't be rounded, so this bar is not thin like the SVG, and it keeps the marks and the step count (`3 of 5`) in its last segment. I built and unit-tested this one but have not seen it in the app.

### The cmux Sidebar

cmux is a terminal app for macOS that lists your workspaces in a sidebar. When Claude Code runs inside it, fathom-progress also puts the run on that workspace's row, so you can see where a run stands in a workspace you aren't looking at. You don't need cmux for the band, and outside cmux the mod sends nothing to it.

The row gets a status pill (an icon and one line of text) and a progress bar with a label. cmux draws the bar in its own blue.

| Run | Pill | Bar |
|---|---|---|
| Starting | `starting…` | none |
| Making tasks | `planning`, then `planning · 3 tasks` | none, because the total isn't known yet |
| Working | `2/5 · now 3`, plus `· 1 in review` when it applies | `SLU-123 · 2 of 5`, two fifths full |
| Finished | `done 5/5`, in green | `SLU-123 · done`, full |
| `bd` can't be read | `bd unavailable`, in red | none |

The pill uses the band's colors: coral while Fathom is getting ready, yellow with a hammer icon while it works, green when it is done. The red is macOS's system red, because the Figma file has no failure state to take one from.

The row follows the band. `/fathom-progress` hides it, and `/clear` and the end of the session clear it. The mod's pill has its own name (`fathom-` and the first eight characters of the pane's id), so cmux's own Claude Code pill stays on the row and each pane's run has a pill of its own. The mod doesn't touch the workspace's checklist or description.

What I know about the limits:

- **Two runs in one workspace.** Each pane's run keeps its own pill, and ending one leaves the other's. cmux has one progress bar per workspace, so the run that changed last owns it. A run takes the bar off only while it still shows that run's reference, so a run that ends while the other owns the bar leaves it. A run that ends while it owns the bar clears it, and the other run's bar comes back at that run's next change, which can be a whole task. I saw both cases with two sessions. The pills look alike, since each shows only its own count.
- **No notification.** The mod doesn't post a cmux notification (an unread badge). cmux's own Claude Code integration posts a "Completed in <folder>" notification, and the pill already shows the finish on a workspace you aren't looking at.
- **What I have seen.** A full run, hiding and showing the band, `/clear` and the end of a session, with the workspace selected and not selected, in cmux's dark theme. I haven't seen a light theme or a remote workspace.

### Commands

- `/fathom-progress` toggles the band between shown and hidden. It replies "Fathom band hidden." or "Fathom band shown." It doesn't report whether a run is active.

### When It Doesn't Show

- **Nothing appears after `/fathom:execute`.** Run `/plugin` and look for fathom-progress in the line that counts the active mods. If it isn't there, check that the session started after you installed it or saved the setting, then check the path. A session that was already running at that point doesn't load the mod.
- **`beads-status` draws instead.** If you load both from folders, move fathom-progress ahead of it in `CLAUDE_CODE_PLUGIN_DIRS`. If fathom-progress is installed and `beads-status` is loaded from a folder, load fathom-progress from a folder too. If you installed both, `beads-status` was installed first. Uninstall it and install it again so that it comes second (see Install).
- **The band stays on `fathom starting…`** (`[fathom] starting…` in the Desktop app). Either Fathom hasn't created its issue yet, or no issue matches the ref you typed. Run `bd list --type epic --all` in the project and look for the issue ref in the epic's external ref. In a repository that doesn't use Beads, look for `.fathom/tasks/<ref>.md` in your working tree.
- **The band says `Waiting on you` after a scaffold finished.** On Asana the band can't read a finished scaffold, and a scaffold that stopped before it made an issue looks the same. Start another Fathom command or end the session to clear it.
- **`fathom unavailable: …`** (with brackets in the Desktop app). The reason is the first line `bd` printed to stderr. Run the same `bd` command by hand. If the reason says `.fathom/tasks/<ref>.md is not a Fathom checklist`, open that file: it needs a first line like `# ONC-5: Add login flow` and a `## Tasks` section.
- **You hid it.** Run `/fathom-progress` once more.

### Team Organization Accounts

On the account I use for work, which is in a Team organization, Claude Code seats a built-in security plugin (`cc-plugin-sec-default`) ahead of every mod. It answers the skill prompt event itself and never passes it on, so a mod's skill prompt hook doesn't run. The first version of this mod armed only from that event, and the band never appeared on that account. fathom-progress now also arms from the typed prompt and the Skill tool call, and those do reach it. I haven't checked an account in any other kind of organization.

To see whether your account does this, run a Fathom skill with `claude -p "<prompt>" --debug-file /tmp/dbg.txt` and search the file for `bypassed`.

---

## For Developers

### Repository Layout

```
.claude-plugin/marketplace.json the marketplace at the repository root: lists mods/fathom-progress
mods/fathom-progress/
  .claude-plugin/plugin.json    manifest: name, version, the types file
  types.d.ts                    RunTask, Snapshot, Plan and the mod's state
  tsconfig.json                 extends .claude-plugin/types/tsconfig.json
  hooks/
    hooks.json                  lists the one module the engine loads
    register.tsx                every call into the engine ($), and the hook wiring
    lifecycle.ts                pure: which skills start a run, refs, plan and checklist paths, poll timing
    scaffold.ts                 pure: a scaffold run's calls and turns to its phase and count
    state.ts                    pure: bd output to epics, the run to follow, the snapshot
    plan.ts                     pure: reads .fathom/plans/<ref>.md
    checklist.ts                pure: reads .fathom/tasks/<ref>.md, its snapshot, and beads or checklist
    bd.ts                       reads what bd printed, or says why there is nothing
    draw.tsx                    draws the band from a snapshot (Box and Text, plus Svg)
    desktop.ts                  the Svg bar, the dark palette, the Desktop's pixel sizes
    bar.ts                      splits the bar's cells across segments
    cmux.ts                     pure: a snapshot to the cmux row's pill and bar
    fixtures.ts                 real bd output, captured by the seed script
    *.test.ts, *.test.tsx       unit and render tests
  bin/seed-fathom-fixture.sh    drives a scratch Beads repo and writes fixtures.ts
  bench/                        drives the band through checklist runs in tmux (see bench/README.md)
```

### Working on the Mod

Add your clone as a marketplace from its path, and install from it.

```sh
claude plugin marketplace add /path/to/skills
claude plugin install fathom-progress@crodris
```

The plugin then loads in place from `mods/fathom-progress`. According to the Claude Code documentation, your edits take effect at the next session start or `/reload-plugins`, and you don't change `version` while you work. `claude plugin list` shows where it reads from.

Don't load that folder through `--plugin-dir` or `CLAUDE_CODE_PLUGIN_DIRS` in the session where Claude Code edits it. The documentation makes a folder loaded that way a protected path. In auto mode an edit to it goes to the classifier, which returned no verdict every time I tried, and an allow rule in settings can't change that. I saw the same edit refused in a session that loaded the folder and accepted in a session where the mod was installed. If you also run `beads-status` from a folder, see the note under Install.

To release a version, raise the `fathom-progress` entry's `version` in `.claude-plugin/marketplace.json` at the repository root, and run `bin/sync-versions.sh`, which copies it into `plugin.json` and the main README. People who installed from GitHub get the new copy when the version changes.

### How a Run Becomes a Band

1. **Arm.** `arm` in `register.tsx` records when the run started (`armedAt`) and any refs you typed, and sets the snapshot to `starting`. One start can arrive by two signals, and a repeat within three seconds is counted once. The second signal can still add the typed refs, which only `prompt.submit` carries.
2. **Refresh.** `refresh` runs once at arm, then every 10 seconds (`POLL_MS`) while the snapshot isn't `finished`, and after any Bash call that runs `bd` or `git commit` (`touchesRun`). One refresh runs at a time. A call that arrives during one asks for another straight after, so the last change is never missed.
3. **Build.** `build` runs `bd list` for the epics (`epicsOf`, which keeps bd's error instead of throwing it) and picks the run (`pickRun` in `state.ts`). When there is an epic, it runs `bd list` for that epic's tasks and `bd ready` for the next one. When there is none, `checklistsOf` reads `.fathom/tasks/<ref>.md` for the typed or branch ref, and `runSourceOf` in `checklist.ts` chooses between the epic, the checklist, `starting` and `unavailable`. Then it reads the plan document. The `bd` calls run in sequence because `bd` keeps one embedded database.
4. **Snapshot.** `toSnapshot` orders the tasks by their `blocks` edges (`bd` lists them in no useful order, and `created_at` ties), and marks each as done, in progress, next or waiting. `toChecklistSnapshot` does the same for a checklist, from its markers and `deps`, in task-number order. A done task whose bundle has a recorded review is marked in review. The result is stored in the engine's state.
5. **Draw.** The `ui.render` hook for `AbovePrompt` reads the snapshot and calls `drawBand`. It passes the event on with `next(e)` when idle, hidden, or when a survey holds the spot.

Fathom makes its epic with the issue ref as both the epic's `external_ref` and a label, and labels each task with the ref. `parseEpics` relies on that pair, so an epic without both is someone else's and is not a run. `bd` timestamps have one-second resolution, so `pickRun` rounds the arm time down to the second before comparing.

The module registers these hooks:

| Event | Does |
|---|---|
| `session.start` | Starts the poll timer and registers `/fathom-progress`. |
| `session.end` | Resets the arm time, the typed refs and the snapshot. |
| `skill.prompt` | Arms on `fathom:execute` and `fathom:scaffold`. |
| `prompt.submit` | Arms from a typed `/fathom:execute` or `/fathom:scaffold`, and takes the typed refs. |
| `tool.call` (Skill) | Arms from the Skill tool. The event carries the skill name and no arguments. A scaffold calling `execute` ends the scaffold run. |
| `tool.call` (`AskUserQuestion`, MCP tools) | Moves a scaffold run: the tracker check, each issue made, each question. Does nothing for an execute run. |
| `turn.start`, `turn.complete` | A reply resumes a scaffold that is waiting on you, and the end of a turn after an issue was made finishes it. |
| `tool.call` (Bash) | Refreshes when the command touched the run. |
| `command.run` (`fathom-progress`) | Toggles the band. |
| `ui.render` (`AbovePrompt`) | Draws the band. |

### The cmux Row

`cmuxEntries` in `cmux.ts` turns a snapshot into the row's entries: a pill (`text`, an SF Symbols icon name and a `color`) or none, and a bar (`value` and `label`) or none. It is pure and has tests, including that no pill is longer than 30 characters, which is about what the row shows before it cuts the text. `register.tsx` sends the entries with `$.process.run(['cmux', ...])`:

| Entries | Command |
|---|---|
| a pill | `cmux set-status fathom-<pane> <text> --icon <name> --color <hex>` |
| no pill | `cmux clear-status fathom-<pane>` |
| a bar | `cmux set-progress <0 to 1> --label <text>` |
| no bar, and the mod set one | `cmux sidebar-state`, then `cmux clear-progress` if the bar's label still starts with this run's reference |

`<pane>` is the first eight characters of `CMUX_SURFACE_ID`, which cmux gives each pane. `pillKeyFor` in `cmux.ts` builds the key, and `barLabelOn` and `isOurBar` read the bar.

`publish` runs after each snapshot update, after `arm`, at `session.start` (forced), at `session.end` and when `/fathom-progress` toggles the band. The rules are in `syncCmux` and `publish`:

- **Guard.** Nothing is sent unless `CMUX_WORKSPACE_ID` is set, which cmux sets in its own terminals. The mod reads one more, `CMUX_SURFACE_ID`, for the pill's key. `claude plugin validate` lists both.
- **Only changes.** The entries are compared with what was last sent, so the 10-second poll sends nothing while the run is unchanged.
- **One at a time.** Sends go through a promise queue, and each reads the snapshot when its turn comes, so the last one wins.
- **Best effort.** Each call has a 3-second timeout. A failure goes to the debug channel and never reaches the band.
- **Its own key.** cmux's Claude Code integration owns the `claude_code` pill. The mod's key is `fathom-<pane>`, so two runs in a workspace each have a pill and each clears only its own. Without an id the key is `fathom`.
- **Clears only its own.** `clear-progress` runs only if the mod set a bar and `cmux sidebar-state` shows a bar whose label still starts with this run's reference, because another run may have taken the workspace's one bar. If cmux can't answer, the mod clears it. `session.start` sends a forced clear, to remove a pill that a session left when it ended badly and to put the run back after `/reload-plugins`.
- **Leaves alone** the workspace checklist and the `workspace status set` lane, which cmux's documentation reserves for the user, and the description, which is the user's text.

The sending is in `register.tsx`, so it has no unit tests, for the reason in the next section. I checked it live: run a Fathom issue in a scratch Beads repository inside cmux, and read the row with `cmux list-status` (the pill) and `cmux sidebar-state` (the bar). To count the calls a session makes, put a script named `cmux` first on `PATH` that appends its arguments to a file. With `CMUX_WORKSPACE_ID` unset it recorded none, and with it set the same session recorded three. For two panes I ran two sessions in one workspace, the second with its own `CMUX_SURFACE_ID`, and read both pills and the bar while the runs changed and ended.

### Why the Code Is Split This Way

Two constraints from the engine shape the files.

The engine's validator follows `$` (the handle to the engine) only inside the file that receives it, not across imports. A helper that takes `$` has to live in `register.tsx`. A helper in another file that took `$` would be rejected, which is why `draw.tsx` never sees `$`: `register.tsx` resolves the UI elements and fetches the data, and `draw.tsx` only draws them.

The second is that `register.tsx` reads engine state, which is empty in a test, so none of its own code can be tested. Everything that decides something (which skill started a run, which ref was typed, which epic to follow, what the tasks' states are) is a pure function in `lifecycle.ts`, `state.ts`, `plan.ts`, `checklist.ts` or `bd.ts`, and has tests.

### Working With the Engine

What I learned while building this, on Claude Code 2.1.295 and 2.1.296:

- **Hooks run in tiers, outermost first:** `prepend`, `user`, `append`, `builtin`, `core`. A hook that doesn't call `next(e)` stops every tier inside it. A mod is in `user`. In a Team organization the built-in security plugin is seated outside it, and the debug log says `skill.prompt bypassed by cc-plugin-sec-default`. `prompt.submit` and `tool.call` aren't in its list.
- **A hook that throws is skipped**, and the chain carries on. The hooks that only read (`prompt.submit`, the Skill `tool.call`) wrap their work in `try/catch` so a failure can't hold up a prompt or a tool.
- **`session.start` doesn't fire again after `/clear`**, but the module and its timer survive. The reset is on `session.end`.
- **A command name that is already taken throws** in `$.command.register`. The registration is wrapped, and it's the last thing `session.start` does.
- **`/reload-plugins` fires `session.start` again.**
- **An `Svg` is drawn as an image.** It can't use theme keys, CSS variables or the page's fonts. Its colors are literal, which is why the Desktop's SVG bar is dark-theme only.
- **A cell is 7.9 pixels on the Desktop.** I measured it with a strip `bodyColumns` cells wide (95 cells filled a 752-pixel card). It holds at the app's default font size. `desktop.ts` uses it to size the bar to the row.

### Tests, Validation and Type-Check

Run the tests with the engine's own runner.

```sh
claude plugin test mods/fathom-progress
```

It runs every `*.test.ts` and `*.test.tsx` under the folder you give it, each in a child process that is set up like the mod's hooks. A test imports its kit from `claude-code/testing`, and the sandbox allows relative imports and `claude-code` only, so a test can't read a file from disk. That is why the captured `bd` output is a TypeScript module (`fixtures.ts`) and not a JSON file. The render tests mount the band on both the terminal and Desktop surfaces.

Validate the manifest and hooks.

```sh
claude plugin validate --strict mods/fathom-progress
```

This passes. On Claude Code 2.1.310 it reports four notes of "gating hook without .catch", for `prompt.submit` and the three `tool.call` hooks. They are notes, not errors.

Type-check with TypeScript. This repository has no `package.json`, so use any TypeScript install you have.

```sh
tsc -p mods/fathom-progress --noEmit
```

The config extends `.claude-plugin/types/tsconfig.json`, which turns on strict mode and `noUncheckedIndexedAccess`. Claude Code writes that folder when a session loads the mod from its folder (see "Loading a Folder Instead"), so the type-check needs one such session first. CI runs the tests and the validation on every change under `mods/`, and does not type-check, because no session loads the mod there. With TypeScript 6.0.3 the check reports no errors. Under `noUncheckedIndexedAccess` an array index can be `undefined`, so `bar.ts` reads each one with `?? 0`. The types the mod is checked against declare `key` as a string, so `draw.tsx` passes `String(i)`, and `$.fs.read(path)` returns text unless you pass `{ as: 'bytes' }`.

### Fixtures

`hooks/fixtures.ts` holds real `bd` output for one Fathom run at each stage, so the state tests run against what `bd` prints and not against a guess. `bin/seed-fathom-fixture.sh` regenerates it.

```sh
bash mods/fathom-progress/bin/seed-fathom-fixture.sh [scratch-dir] [out-file]
```

The script runs the commands Fathom's Beads adapter runs (Fathom 2.2.0) in a scratch repository, and writes what `bd` printed to `hooks/fixtures.ts`. It refuses a scratch folder inside this repository or one that isn't empty, checks that `bd` resolves to the scratch repository before it writes anything, and deletes nothing. The fixtures in the repository were captured with `bd` 1.1.0. Re-run the script after a `bd` upgrade that changes its JSON (a text format for data), since `parseEpics` and the task parsing read a missing key as a missing field and don't trust it.

### Debugging

The mod logs to the debug channel. Start Claude Code with `--debug-file <path>` and search for `fathom-progress`:

- `fathom-progress: armed (execute) by prompt.submit, typed refs PHA-352` says which signal armed the band.
- `fathom-progress: following PHA-352 (typed PHA-352, branch -)` says which issue the band picked and why. It is logged once per change.
- `fathom-progress: refresh failed: <reason>` says why the band is `unavailable`.
- `fathom-progress: cmux set-status exited 1: <first line of stderr>` or `fathom-progress: cmux set-status failed: <reason>` says a call to cmux didn't land. `fathom-progress: cmux sync failed: <reason>` says the whole send failed. None of them touch the band.

Running `claude -p "..." --debug-file f` with a prompt that starts a Fathom skill reproduces the arming without opening the interface. That run uses the `sdk-cli` entry point and not the Desktop app's, so it can't show how the Desktop behaves.

### Design Source

The terminal band follows the States section of the Claude Mods Figma file (file key `oG40tY6cPL2NzsJiZQ2gwg`, node `59:791`): planned, executing, finished and creating, each in a terminal frame. The file's Band component (`56:220`) adds the starting, unavailable, between-tasks, nine-task and narrow variants, and the terminal follows those too. A few notes in the component are out of date. Its text still describes marks inside the bar and a 45-cell bar at 78 columns, and the frames no longer show either.

The Desktop band follows the Desktop section (`79:1402`): Creating, Planned, Executing 1/5, Executing with two done tasks in review, Completed and Error, each in a 500-pixel card. It replaces the earlier frames, A1 Planned (`9:274`), A2 Executing (`9:289`) and A3 Done (`9:314`), and the first drafts with per-task pills in section `11:77`. The section has no starting or unavailable frame, so the Desktop's two are still placeholders (`claude-mods-fathom-5l2.7`).

Three things in the section I read rather than copied. The task line says `planning  3 tasks so far` in all six frames, so only the Creating frame's text is the design's, and the other lines are the terminal's without the `▸`. The frames hide the `· N in review` that the Row component has, and the band shows it after the label, because a bar with no marks says "in review" by color alone. The design's bar is 420 pixels in a 500-pixel card, and the band's fills the row, as it did before. The band does not draw the Error frame (task 4 red, task 5 waiting), because nothing in the Beads data says a task failed.

`desktop.ts` takes its colors from the "Claude Code theme" collection in that file (Dark mode). I checked success, claude and subtle against what a terminal renders for the dark theme, and each is within two of the Figma value. The yellow for in progress is the collection's `warning` and the lighter grey for the next task is its `inactive`, and I haven't compared either to a terminal render. The terminal band uses theme keys, not those values. The design's dim text (`dimText`, `#8c8c8c`) isn't one of the engine's theme keys, so I read it as the `dimColor` the band already used for its second row. I haven't compared that to a terminal render either.

### Extending It

- **Task sizes.** Segments are equal widths. When Fathom records a size per task, the terminal bar changes where `barCells` passes its values to `allocate` (a task's size where there is one, 1 where there isn't), and the SVG bar changes where `barSvg` works out `seg`. The request to Fathom is `claude-mods-fathom-5l2.10`.
- **A full task list.** A pane that shows every task of the run, opened from the band, is planned under `claude-mods-fathom-5l2.13`. It starts with a probe, `claude-mods-fathom-5l2.12`, to see whether a pane seats in the Desktop app and how wide it is. The probe isn't built.
- **More trackers' refs.** `REF` in `lifecycle.ts` reads refs shaped like `PHA-352` (letters, a hyphen, digits). Asana's numeric task ids aren't read.
- **A ref from plain words.** The Skill tool's call event has no arguments, so a request in plain words can arm the band but can't name the issue. A prompt's text would have to be parsed for it.
- **Continuing a run without a Fathom command.** `claude --continue` followed by ordinary prompts leaves the band idle, because nothing arms it.
- **Two runs in one workspace.** The pill is per pane and the bar is shared. A run that ends while the other owns the bar leaves it, and a run that ends while it owns the bar clears it, so the other run's bar returns only at that run's next change. Resending the bar on a slow timer would close that gap, at one cmux call per interval, against the goal that a poll sends nothing. The options are in `claude-mods-fathom-5l2.14.7`.
- **An error state.** The design's Error frame colors a failed task red (`error`, `#F83A55`). When a task fails, Fathom keeps it in progress and reports the failure in the transcript, and Beads has no status for a failed task, so the band has nothing to read. Fathom would have to record the failure first.
- **A rounded bar on other Desktop themes.** `Box` has no corner radius and an `Svg` has fixed colors, so only the dark theme gets the rounded bar. Another theme needs its own palette in `desktop.ts` (`paletteFor` returns one only for `dark`).

### Issue Tracking

I track work on the mod in my own tracker, so ids such as `claude-mods-fathom-5l2.10` above are mine.

## Status

The terminal band's three-row layout with the thin bar is new. Its unit and render tests pass, and the type-check and `claude plugin validate` are clean. I watched it in an interactive Claude Code session inside tmux, on a scratch repository, through the creating, executing (two tasks in review) and finished states at 100, 80 and 50 columns. The `[-]` sat on the bar's row, and the band needed no row of padding above the bar. That run drew a 55-character bar with `▂`. After I let the bar fill the window, I read the row at 200, 150, 100, 80 and 60 columns: the bar grew with the window, the percent started one character after it each time, and six characters separated the percent from the `[-]`. I then switched it to `━` with half-line gaps and saw the new bar come up after `/reload-plugins`, but I haven't compared it with the design's bar. tmux drew the colors from the 256-color palette, so I haven't seen the exact theme colors. At 22 columns the bar gives way to the count, and the label wraps onto a second line. Before that change, the terminal band, the Desktop's dark-theme SVG bar and the arming on a Team organization account had each been seen working: the first two in a scratch repository, the third in a work profile. The typed-ref and branch-fallback logic has unit tests and headless runs in a real repository, and I haven't yet watched it in a live session. I haven't seen the Desktop's non-dark bar, or the new arming signals in the Desktop app. The Desktop's dark-theme bar that I saw working was the earlier one, with the track and the pill. The new one, with thin segments in three rows, has unit and render tests, and I haven't type-checked it or seen it in the Desktop app. I haven't checked whether the app centers the 6-pixel bar on the percent's line, or how it sets the 12 pixels before the percent.

The checklist reader is new. Its unit tests pass, and the type-check and `claude plugin validate` are clean. I wrote it from the format in Fathom's `memory/checklist.md` and wrote the test text by hand to match it, so no line in the tests comes from a real Fathom run. I watched the band follow checklists that a script wrote (`bench/`), in a live Claude Code session in tmux where `bd` failed on every call, through a chain, a parallel run and a file that wasn't a checklist. A real Fathom run on a one-task issue in a scratch repository with no Beads wrote a checklist that reads as the format says, and the `fathom unavailable` line the band showed before the checklist existed went away once Fathom started working. I haven't watched the band's progress through a real run. Beads wins whenever `bd` returns an epic to follow. When only the branch names the issue and the branch's ref has no epic, `pickRun` can still return another issue's epic (one made since the invocation, or the latest open one), and the band then shows that run and not the branch's checklist. A ref you type avoids it, because a typed ref matches only its own epic. I haven't seen how Fathom writes the `Review` line on a checklist: the reader takes an id and a URL, as the format describes, and the band doesn't need it to draw.

The scaffold band is new. Its tests pass, including ones that raise the real hooks and move the band from `resolve` through `create` to `done`, and the type-check and `claude plugin validate` are clean. The calls it reads come from one Linear run. In a terminal session I saw it end a Linear scaffold on `done, 3 issues made` with all four steps checked (this was before the redesign: the row now reads `Scaffold · Done, 3 issues made`, the steps carry dots, and the time is new), and the transcript shows that run made three issues and one earlier update, which the band didn't count. I haven't checked the steps before `done` by eye, or the Desktop app or cmux, so the yellow dot, the elapsed time, the Desktop layout and the three cmux icon names (`pencil`, `questionmark.circle` and `plus.circle`) are unchecked.

The cmux row has been seen working in cmux's dark theme, for a full run, hiding and showing the band, `/clear`, the end of a session, a failed `bd` read, and with the workspace both selected and not. With two runs in one workspace, each pane keeps its pill, and a run that ends leaves a bar that is the other run's. If the run that ended owned the bar, the other run's bar is missing until that run's next change. I haven't seen it in a light theme or a remote workspace, and the Desktop app doesn't use it. I haven't verified that a finished run leaves an unread badge from cmux's own integration.
