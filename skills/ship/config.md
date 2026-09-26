# Recording `.ship/config.md`

Read by the ship skill when stage 0 asked the user anything.

Write `.ship/config.md` at the repository root only when this run asked the user something and got an answer, and only once preflight has confirmed there is something to ship.
Write only the slots the user answered; what the file preserves is a human decision, and nothing else belongs in it.
Resolve that path against the repository root before reading or writing it, and refuse when `.ship` or `config.md` is a symlink or when the resolved target lands outside the repository.
Hold the answers in mind until then: a run that stops on a clean tree should leave no file behind for a shipping run that never happened.
A run that skips to stage 3 on an already-pushed branch writes nothing here at all, because that path never reaches the commit at the end of preflight that this write rides; hold the answer, and say in the final report that it was not recorded.

Every write to a file that already exists is an in-place edit of the lines it affects, and the format below describes a file created from scratch.

Use this format, omitting slots with no value; an omitted slot means unresolved, and a guessed value is worse than an absent one.
`light-paths`, `security-paths`, and `drive` are the exception: a human writes them, this skill never does, and an omitted one is resolved to its default rather than re-detected.
A slot whose true value is "this project has none of that" takes the literal value `none`, which is a resolved answer and stops later runs from re-detecting it.
`none` is legal only for `release` and `post-merge`, the slots whose absence simply means a step does not apply.
It is never legal for `verify`: that gate always runs, `none` there is a corrupt file rather than an answer, and reading it as permission to skip the gate would let an edited config disable the only thing standing between a change and the base branch.
Treat it as unresolved, re-detect, and ask.

```markdown
# ship pipeline profile
verify: pnpm verify:ci        # add "# asked" on any line the user answered
base: main
branch: feat/<slug>
worktrees: worktrees/<branch>
release: semantic-release on main
post-merge: /post-merge
light-paths: docs/**, **/*.md      # optional, hand-written
security-paths: **/auth/**, db/migrations/**
drive: bin/drive.sh run           # or skill:verify-<app>, a skill the repository ships
```

Commit the file only after preflight has settled which branch this run ships, before stage 1 begins.
When preflight moves work to a feature branch, the file travels with the rest of the uncommitted work and is committed there.
Give it its own commit, with a message that describes recording the pipeline and nothing else.
Never fold it into a commit carrying the shipped change, and never add it to `.gitignore` on the user's behalf.
Say in the final report that the file was written or updated.

## Red flag

- About to write pipeline values into `.ship/config.md` that nobody was asked about.
