# Per-commit verify

Read by babysit's Result step 2 when `merge-method` is `rebase` and `origin/$base..HEAD` holds more than one commit, since a rebase merge puts each commit on the base on its own.

Resolve the verify command as the Resolve verify section of `../prove/SKILL.md` says, and hold it in `$verify`.
Run `bash <this skill's directory>/../prove/verify-each.sh --print "$(git rev-parse --show-toplevel)" "origin/$base..HEAD" "$verify"`, which runs nothing and prints each commit's short SHA and the exact command a run gives it.
The script decides that command, and a commit with a missing or symlinked config, or no usable verify line, prints `$verify`.
Return `BLOCKED` quoting the output when `--print` exits nonzero, and naming the commit and the command when a printed command is a review tool or a skill that wraps one, as the Resolve verify section of `../prove/SKILL.md` describes, or falls outside the Command shape section of `../ship/boundary.md`.
Then run the same command without `--print`.
Exit 0 goes on to Result step 3.
On exit 1, when every commit fails, the worktree may lack something verify needs, so say in the run section that the per-commit check could not judge these commits and go on to Result step 3.
On exit 1 with any other set of failing commits, return `BLOCKED` naming the first failing commit, since a commit that passed shows the worktree has what verify needs.
Any other exit is `BLOCKED`, quoting the script's output.
