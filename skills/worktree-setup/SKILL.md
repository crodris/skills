---
name: worktree-setup
description: Use right after creating a git worktree on a branch (git worktree add -b, or a tool's new-worktree option), or when working inside a linked git worktree whose dependencies are not installed or whose local env files are missing. Copies the main checkout's untracked env files (never production .env.prod* files or Sentry's .env.sentry-build-plugin token), local HTTPS certificates, and .claude/settings.local.json into the worktree, then installs dependencies with the package manager its lockfile names. Not for the main checkout, and not for a worktree of a branch you do not trust, such as a pull request under review.
user-invocable: false
version: 1.0.1
---

# Worktree setup

Run the bundled script on the worktree before any other work there:

```bash
bash <this skill's directory>/setup.sh <worktree path>
```

It copies only untracked files the worktree is missing, never overwrites one the worktree has, and installs when dependencies are missing or the lockfile changed.
It never copies a file named for production credentials, a `.env.prod*` file or Sentry's `.env.sentry-build-plugin`, or a symlink that points at one.
Secrets inside other env files, such as `.env.local`, still copy.
It skips a worktree on a detached HEAD, which is how a pull request gets checked out for review, and treats any branch checkout as yours.
It prints nothing when there is nothing to do.
When it reports a failed install, fix the cause it shows and run the command it prints.
