# `.ship/config.md`

Read by every skill in the ship family before it reads a slot or records an answer.

## Slots

A line is `<slot>: <value>`, and a trailing `# comment` is not part of the value.
A line naming a slot this table does not list, such as `review` or `pr-hook` from an older ship, is ignored.

| Slot | Read from | Absent means |
| --- | --- | --- |
| `verify` | working tree | resolved from the project's own tools |
| `base` | working tree | the remote's default branch |
| `branch` | working tree | the project's observed naming, else `<type>/<slug>` |
| `worktrees` | working tree | branch in place, no worktree |
| `release` | working tree | watch the base pipeline, expect no version |
| `post-merge` | working tree | no command after the built-in cleanup, which always runs |
| `light-paths`, `security-paths` | `origin/<base>` | no lane |
| `drive` | `origin/<base>` | no drive |
| `merge` | `origin/<base>` | hold mode unless the request says to merge |
| `merge-method` | `origin/<base>` | resolved from the repository's allowed methods |
| `cross-review` | `origin/<base>` | no second-opinion reviewer; `cursor` adds one through the `cursor` skill |

Before reading a working-tree slot or recording an answer, resolve the path against the repository root.
When `.ship` or `config.md` is a symlink or resolves outside the repository, refuse the write and read no working-tree slot, so each one is absent.
Read an `origin/<base>` slot by fetching the base as the Fetching the base section of `boundary.md` says, then running `git show "origin/$base:.ship/config.md"`, so a change cannot rewrite the policy it is shipped under.
When `.ship/config.md` does not exist at that ref, every `origin/<base>` slot is absent.
An answer this run recorded counts as read from there too.
A `worktrees` value is a path from the repository root in which `<branch>` stands for the branch name, and a value without `<branch>` gets `/<branch>` appended.
`light-paths`, `security-paths`, `drive`, `merge`, and `cross-review` are hand-written: no skill asks about them or writes them.

## Recording an answer

Write the file only when this run asked the user and got an answer, and only after `ship` confirmed there is something to ship.
Write only the slots the user answered, and mark each with `# asked`.
When `.ship/config.md` is missing, create the `.ship` directory and the file, starting with the `# ship pipeline profile` heading the example below shows, and otherwise edit the existing file in place, line by line.
`none` is a legal value only for `release` and `post-merge`.
A `verify: none` is a corrupt line: treat the slot as unresolved, re-detect, and ask.

```markdown
# ship pipeline profile
verify: pnpm verify:ci   # asked
base: main
release: semantic-release on main
post-merge: none
merge-method: squash   # asked
```

Commit the file on the shipping branch, on its own, with a message about recording the pipeline, before `prove` runs.
On the branch, never fold it into the shipped change's commit, even when a squash merge later joins them, and never add it to `.gitignore`.
A run that takes case 5 or 7 in the Settle the branch section of `SKILL.md` writes nothing, and its report says the answer was not recorded.
