# Bench: testing fathom-progress without Beads

These scripts check that the band follows a Fathom run that uses the checklist backend (`.fathom/tasks/<ref>.md`), with no `bd` involved. They cost no model tokens for the run itself. The only model work is one turn that you interrupt, to arm the band.

## How it works

The band reads the checklist from disk about every 10 seconds. `play-checklist.sh` rewrites that file, step by step, the way a Fathom run would. `watch-band.sh` reads the band off a tmux pane after each step and checks the text. Nothing here calls Fathom or a tracker.

| File | Does |
|---|---|
| `make-bench-repo.sh` | Makes a scratch git repo with a bare `origin`, a Fathom profile committed on `main` and no `.beads/`, so Fathom picks the checklist backend. |
| `start-session.sh` | Starts Claude Code in a detached tmux session inside the bench repo. `--bd shim` puts a fake `bd` that exits 127 first on `PATH`. |
| `play-checklist.sh` | Writes one timeline step (or all of them, paced) into the bench repo. |
| `watch-band.sh` | Arms the band, plays each step, reads the pane until the step's patterns match, and exits 1 if one never does. |
| `timelines/*.tl` | The runs, as data: `chain`, `parallel` and `bad-file`. |

## Quick start

```sh
WORK=$(bash scripts/bench/make-bench-repo.sh | tail -n 1)
bash scripts/bench/start-session.sh --bench "$WORK" --bd shim --trust -- --model haiku
bash scripts/bench/watch-band.sh --bench "$WORK" --target fathom-bench --arm --timeline chain
tmux kill-session -t fathom-bench
```

- `make-bench-repo.sh` takes its tracker destination and state mapping from this repository's `.fathom/config.md`, which names the Claude Mods and Tools project. For the Fathom bench project, pass `--destination "Ruesato / Fathom bench (team 8dc97a9b-f60c-4803-886c-d79009ad9b2b, project dd7e6ad4-6946-42ab-a29f-d7b692906f85)"`. Pass `--config-from` to use another profile.
- The persistent bench repo is `~/code/fathom-bench/work`; its README lists the Linear issues for real Fathom runs.
- The mod must be installed and on the branch under test. It loads from the working tree of the marketplace you installed it from.
- `--arm` types `/fathom:execute BENCH-1` and presses Esc after 3 seconds. Typing the command arms the band, and Esc stops Claude before it does Fathom's work. It still costs one started model turn, so `-- --model haiku` keeps it small. A finished run stops polling, so pass `--arm` again for each timeline.
- Each step takes about 10 seconds to show, because of the poll. A nine-step timeline runs about two minutes.
- The screens are saved next to the bench repo, in `out/<time>-<timeline>/step-N.txt`, and the debug log in `out/claude-debug-<session>.log`. In the log, look for `armed (execute) by prompt.submit` and `following BENCH-1 (checklist)`.

## Timelines

A step is one line of five fields, separated by `::`:

```
5::x>o::plan::::now 2/3 ~~ 33% ~~ !now 1/3
```

| Field | Values |
|---|---|
| step | A number. |
| tasks | `-` for no file, `header` for a header with no tasks, `raw:<text>` for exact file text (`{ref}` is filled in), or one marker per task: `o` open, `>` in progress, `x` done. |
| plan | `plan` or `noplan`: whether `.fathom/plans/<ref>.md` exists. |
| extras | A comma list. `nohash`: the last done task has no commit hash yet. `footer`: a trailing `- Closed:` line. |
| expectations | Extended regular expressions joined by ` ~~ `, each matched against the screen. A leading `!` means the pattern must not match. |

Lines starting with `@` set the title (`@title`), the task titles (`@titles`, separated by `;`) and the dependencies (`@deps 3=1,2`). Copy `timelines/chain.tl` to start a new one. The expectations are the band's own words from `draw.tsx`, so they match the terminal band. The Desktop app writes `[fathom]` and different lines.

## What was run

On 2026-10-20, on Claude Code 2.1.304 with `--bd shim`, with the mod on the `feat/rue-29-read-checklists-in-the-band` branch:

- `chain`, `parallel` and `bad-file` passed every step. The saved screens show the real band, for example `▸ now 2/3  Create bench/b.txt` at 33%, and the log shows the band following the checklist.
- The watcher's checks were also tried on canned screens: right screens pass, and a wrong one fails and exits 1.
- The text `play-checklist.sh` writes is also a unit test in `checklist.test.ts`, so the parser and the harness cannot drift apart unnoticed.

## What it does not cover

- **A control run.** I haven't run the timelines against a build of the mod without checklist support to see them fail.
- **The real `bd`.** The default `--bd real` was not run. In a bench repo with no `.beads/` I expect `bd` to error on each read, like the shim.
- **Colors.** The text can't tell two yellow segments from one. For `parallel` step 4, attach to the session and look, or capture with `tmux capture-pane -e -p` and read the color codes.
- **A real Fathom run.** The checklist text comes from `memory/checklist.md`, not from a Fathom run. The next layer is Fathom on pre-made, trivial Linear issues in this bench repo.
- **The Desktop app and cmux.** Both draw from the same snapshot, and neither is driven by tmux.
