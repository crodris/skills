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
| `post-merge` | working tree | the built-in cleanup |
| `light-paths`, `security-paths` | `origin/<base>` | no lane |
| `drive` | `origin/<base>` | no drive |
| `merge` | `origin/<base>` | hold mode unless the request says to merge |
| `merge-method` | `origin/<base>` | resolved from the repository's allowed methods |

Read an `origin/<base>` slot with `git fetch origin "$base"` and `git show "origin/$base:.ship/config.md"`, so a change cannot rewrite the policy it is shipped under.
An answer this run recorded counts as read from there too.
`light-paths`, `security-paths`, `drive`, and `merge` are hand-written: no skill asks about them or writes them.

## Recording an answer

Write the file only when this run asked the user and got an answer, and only after `ship` confirmed there is something to ship.
Write only the slots the user answered, and mark each with `# asked`.
Resolve the path against the repository root, and refuse when `.ship` or `config.md` is a symlink or resolves outside the repository.
Edit an existing file in place, line by line.
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
Never fold it into the shipped change or add it to `.gitignore`.
A run that skips to `babysit` on an already-open pull request writes nothing, and its report says the answer was not recorded.
