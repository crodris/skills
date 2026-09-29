---
name: worktree-setup
description: Use right after creating a git worktree on a branch (git worktree add -b, or a tool's new-worktree option), or when working inside a linked git worktree whose dependencies are not installed or whose gitignored env files are missing. Copies the main checkout's gitignored env files, local HTTPS certificates, and .claude/settings.local.json into the worktree, then installs dependencies with the package manager its lockfile names. Not for the main checkout, and not for a worktree of a branch you do not trust, such as a pull request under review.
user-invocable: false
version: 1.0.0
---

# Worktree setup

Run the bundled script on the worktree before any other work there:

```bash
bash <this skill's directory>/setup.sh <worktree path>
```

It copies only files the main checkout ignores and the worktree is missing, never overwrites one the worktree has, and installs when dependencies are missing or the lockfile changed.
It skips a worktree on a detached HEAD, which is how a pull request gets checked out for review.
It prints nothing when there is nothing to do.
When it reports a failed install, fix the cause it shows and run the command it prints.
