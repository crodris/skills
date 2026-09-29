#!/usr/bin/env bash
# Makes a linked git worktree runnable: copies the main checkout's gitignored
# env files, local HTTPS certificates, and .claude/settings.local.json, then
# installs dependencies when they are missing or the lockfile changed.
# Prints nothing when there is nothing to do, so a SessionStart hook can run it
# on every session.
#
# Usage: setup.sh [dir]   (default: the current directory)
set -euo pipefail

wt=$(git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)
gitdir=$(git -C "$wt" rev-parse --path-format=absolute --git-dir)
# A main checkout or a submodule owns its git dir; only linked worktrees share one.
[ "$gitdir" != "$common" ] || exit 0
# A pull request checked out for review sits on a detached HEAD. Its install
# scripts are someone else's code, so it gets neither secrets nor an install.
git -C "$wt" symbolic-ref -q HEAD >/dev/null || exit 0

main=$(git -C "$wt" worktree list --porcelain | sed -n '1s/^worktree //p')
wtp=$(cd "$wt" && pwd -P)
copied=""
# A bare repository has no checkout to copy from.
if [ "$(git -C "$main" rev-parse --is-bare-repository 2>/dev/null)" = false ]; then
  top=$(git -C "$main" rev-parse --show-toplevel)
  while IFS= read -r rel; do
    dest="$wt/$rel"
    if [ -e "$dest" ] || [ -L "$dest" ]; then continue; fi
    # Only files the main checkout itself ignores: never a tracked file, and
    # never one that belongs to a nested worktree or submodule.
    [ "$(git -C "$main/$(dirname "$rel")" rev-parse --show-toplevel)" = "$top" ] || continue
    git -C "$main" check-ignore -q -- "$rel" || continue
    # Never write through a symlink that leads out of the worktree.
    d=$(dirname "$dest")
    while [ ! -e "$d" ]; do d=$(dirname "$d"); done
    case "$(cd "$d" && pwd -P)/" in "$wtp"/*) ;; *) continue ;; esac
    mkdir -p "$(dirname "$dest")"
    if cp -p "$main/$rel" "$dest"; then copied="$copied $rel"
    else echo "worktree-setup: could not copy $rel from $main"; fi
  done < <(cd "$main" && find . \
    \( -name .git -o -name node_modules -o -name worktrees -o -name .worktrees -o -name .next -o -name .turbo \) -prune -o \
    \( -type f -o -type l \) \( -name '.env*' -o -path '*/certificates/*.pem' -o -path './.claude/settings.local.json' \) \
    -print | sed 's|^\./||')
fi

installed=""
if [ -f "$wt/package.json" ]; then
  # A hook has no TTY, so an install must never wait on a prompt.
  lock=package.json install="npm install"
  for pair in \
    "pnpm-lock.yaml:pnpm install --config.confirm-modules-purge=false" \
    "bun.lock:bun install" "bun.lockb:bun install" "yarn.lock:yarn install" \
    "package-lock.json:npm install"; do
    if [ -f "$wt/${pair%%:*}" ]; then lock=${pair%%:*} install=${pair#*:}; break; fi
  done
  marker="$gitdir/worktree-setup-installed"
  if { [ ! -d "$wt/node_modules" ] && [ ! -f "$wt/.pnp.cjs" ]; } ||
    [ "$(cat "$marker" 2>/dev/null)" != "$(cksum < "$wt/$lock")" ]; then
    log="$gitdir/worktree-setup.log"
    # shellcheck disable=SC2086 # $install is a command plus its flags
    if (cd "$wt" && $install </dev/null) >"$log" 2>&1; then
      cksum < "$wt/$lock" > "$marker"
      installed="$install"
    else
      echo "worktree-setup: \`$install\` failed in $wt. Fix it before other work, then rerun: bash $0 $wt"
      echo "Last lines of $log:"
      tail -n 15 "$log"
      if [ -n "$copied" ]; then echo "Copied from $main:$copied"; fi
      exit 1
    fi
  fi
fi

if [ -z "$copied$installed" ]; then exit 0; fi
echo "worktree-setup prepared this worktree ($wt)."
if [ -n "$copied" ]; then echo "Copied gitignored files from $main:$copied"; fi
if [ -n "$installed" ]; then echo "Ran \`$installed\`."; fi
