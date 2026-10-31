# What the progress band reads

The `fathom-progress` mod in `mods/fathom-progress/` draws the progress band, a summary of a Fathom run above the prompt.
The band reads repository state and the names below, and never reads these skill files.
A change to anything listed here changes what the band shows, so change the mod in the same pull request.

`mods/fathom-progress/bin/sync-contract.sh` copies these formats from the skill files into the mod, and `hooks/contract.test.ts` parses them with the mod's own readers.
The repository's verify pipeline runs both, so a format change that the band cannot read fails verify.

## Skill names

The band arms when `fathom:execute` or `fathom:scaffold` starts, or when a prompt starts with `/fathom:execute` or `/fathom:scaffold`.
Keep the plugin name `fathom` and the skill names `execute` and `scaffold`.

## Which run

The band follows the issue ref typed after the command.
With none typed, it takes the first issue ref in the current branch name.

## The plan document

The band reads `.fathom/plans/<ISSUE-REF>.md`, whose lines `conventions.md` defines, and skips lines inside code fences.

- The first heading gives the band its title, when its ref matches the `- Ref:` line.
- The `- Breakdown: pending` line means the run is still being created.
- A done task shows as in review when its sub-issue is on a `- Bundle` line whose `- Review:` line records a review.
- The `- Finalization:` line clears those in-review marks.

## The checklist

On the checklist backend, the band reads `.fathom/tasks/<ISSUE-REF>.md` from the working tree, in the format `memory/checklist.md` defines.

- The header line gives the ref and the title.
- Each task line under `## Tasks` gives one task through its marker, its number, its deps segment, its sub-issue tail, and its done tail.

## Beads

On the beads backend, the band runs three read commands in the repository root:

- `bd list --type epic --all --limit 0 --json`, keeping the epic whose `external_ref` is the issue ref and whose labels include it.
- `bd list -l <ISSUE-REF> --type task --all --limit 0 --json` for the run's tasks.
- `bd ready -l <ISSUE-REF> --type task --limit 50 --json` for the next task.

From each task it reads `status`, `created_at`, `external_ref`, the `blocks` entries in `dependencies`, and the title without its `<ISSUE-REF>: ` prefix.
Those fields come from the `bd create` calls in `memory/beads.md`: the epic's type, external ref, and label, and each task's label, external ref, and deps.

## Scaffold

`scaffold` writes nothing the band reads.
The band infers scaffold's steps from the order of its tracker calls and its questions to the user, so a change to that order changes the band.
