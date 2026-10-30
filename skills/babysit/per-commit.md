# Per-commit verify

Read by babysit's Result step 2 when `merge-method` is `rebase` and `origin/$base..HEAD` holds more than one commit, since a rebase merge puts each commit on the base on its own.

Resolve the verify command as the Resolve verify section of `../prove/SKILL.md` says, and hold it in `$verify`.
For each commit in `origin/$base..HEAD`, read the `verify:` line of its `.ship/config.md` with `git show <sha>:.ship/config.md`, dropping a trailing comment.
A missing file, no `verify:` line, an empty value, or `none` means that commit runs `$verify`.
Return `BLOCKED` naming the commit and the command when the value is a review tool or a skill that wraps one, as the Resolve verify section of `../prove/SKILL.md` describes, or falls outside the Command shape section of `../ship/boundary.md`.
Then run `bash <this skill's directory>/../prove/verify-each.sh "$(git rev-parse --show-toplevel)" "origin/$base..HEAD" "$verify"`.
Exit 0 goes on to Result step 3.
On exit 1, when every commit fails, the worktree may lack something verify needs, so say in the run section that the per-commit check could not judge these commits and go on to Result step 3.
On exit 1 with any other set of failing commits, return `BLOCKED` naming the first failing commit, since a commit that passed shows the worktree has what verify needs.
Any other exit is `BLOCKED`, quoting the script's output.
