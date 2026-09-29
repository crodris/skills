---
name: worktree-setup
description: Use right after creating a git worktree (git worktree add, or a tool's new-worktree option), or when working inside a linked git worktree whose dependencies are not installed or whose gitignored env files are missing. Copies the main checkout's env files, local HTTPS certificates, and .claude/settings.local.json into the worktree, then installs dependencies with the package manager its lockfile names. Not for the main checkout.
user-invocable: false
version: 1.0.0
---

# Worktree setup

Run the bundled script on the worktree before any other work there:

```bash
bash <this skill's directory>/setup.sh <worktree path>
```

It copies only files the worktree is missing, never overwrites one it has, and installs once per worktree.
It prints nothing when there is nothing to do.
When it reports a failed install, fix the cause it shows and run it again.
