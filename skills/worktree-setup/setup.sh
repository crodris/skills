#!/usr/bin/env bash
# Makes a linked git worktree runnable: copies the main checkout's untracked
# env files, local HTTPS certificates, and .claude/settings.local.json, then
# installs dependencies when they are missing or the lockfile changed.
# Prints nothing when there is nothing to do, so a SessionStart hook can run it
# on every session.
#
# Usage: setup.sh [dir]   (default: the current directory)
set -euo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

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
# A bare repository, or a --separate-git-dir one, has no checkout to copy from.
if top=$(git -C "$main" rev-parse --show-toplevel 2>/dev/null); then
  # The find below prunes common nested-worktree folders by name, which saves a
  # git call per file there; the toplevel check catches any other nesting.
  while IFS= read -r rel; do
    dest="$wt/$rel"
    if [ -e "$dest" ] || [ -L "$dest" ]; then continue; fi
    # Only untracked files the main checkout itself owns: never one inside a
    # nested worktree or submodule.
    [ "$(git -C "$main/$(dirname "$rel")" rev-parse --show-toplevel 2>/dev/null)" = "$top" ] || continue
    [ -z "$(git -C "$main" ls-files -- "$rel")" ] || continue
    # Never write through a symlink that leads out of the worktree or nowhere.
    d=$(dirname "$dest")
    while [ ! -e "$d" ] && [ ! -L "$d" ]; do d=$(dirname "$d"); done
    case "$(cd "$d" 2>/dev/null && pwd -P)/" in "$wtp"/*) ;; *) continue ;; esac
    if mkdir -p "$(dirname "$dest")" && cp -p "$main/$rel" "$dest"; then copied="$copied $rel"
    else rm -f "$dest"; echo "worktree-setup: could not copy $rel from $main"; fi
  done < <(cd "$main" && find . \
    \( -name .git -o -name node_modules -o -name worktrees -o -name .worktrees -o -name .next -o -name .turbo \) -prune -o \
    \( -type f -o -type l \) \( -name '.env*' -o -path '*/certificates/*.pem' -o -path './.claude/settings.local.json' \) \
    -print | sed 's|^\./||')
fi

# A hook has no TTY, so an install must never wait on a prompt.
pick() {
  lock=package.json install="npm install"
  for pair in \
    "pnpm-lock.yaml:pnpm install --config.confirm-modules-purge=false" \
    "bun.lock:bun install" "bun.lockb:bun install" "yarn.lock:yarn install" \
    "package-lock.json:npm install"; do
    if [ -f "$wt/${pair%%:*}" ]; then lock=${pair%%:*} install=${pair#*:}; return; fi
  done
}
# The marker holds the lockfile checksum and whether dependencies exist, so a
# lockfile change or a deleted node_modules reinstalls. Yarn Plug'n'Play keeps
# no node_modules, only .pnp.cjs.
state() {
  pick
  cksum < "$wt/$lock"
  if [ -d "$wt/node_modules" ] || [ -f "$wt/.pnp.cjs" ]; then echo deps; fi
}

installed=""
marker="$gitdir/worktree-setup-installed"
if [ -f "$wt/package.json" ] && [ "$(cat "$marker" 2>/dev/null)" != "$(state)" ]; then
  rm -f "$marker"
  pick
  log="$gitdir/worktree-setup.log"
  # shellcheck disable=SC2086 # $install is a command plus its flags
  if (cd "$wt" && $install </dev/null) >"$log" 2>&1; then
    state > "$marker"
    installed="$install"
  else
    printf "worktree-setup: \`%s\` failed in %s. Fix it before other work, then rerun: bash %q %q\n" "$install" "$wt" "$0" "$wt"
    echo "Last lines of $log:"
    tail -n 15 "$log"
    if [ -n "$copied" ]; then echo "Copied from $main:$copied"; fi
    exit 1
  fi
fi

if [ -z "$copied$installed" ]; then exit 0; fi
echo "worktree-setup prepared this worktree ($wt)."
if [ -n "$copied" ]; then echo "Copied untracked files from $main:$copied"; fi
if [ -n "$installed" ]; then echo "Ran \`$installed\`."; fi
