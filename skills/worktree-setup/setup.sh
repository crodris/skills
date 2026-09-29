#!/usr/bin/env bash
# Makes a fresh linked git worktree runnable: copies the main checkout's local
# files that git leaves behind, then installs dependencies once.
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
main=$(dirname "$common")

copied=""
# A bare-repo layout has no main checkout to copy from.
if [ "$(basename "$common")" = .git ]; then
  while IFS= read -r rel; do
    [ -e "$wt/$rel" ] && continue
    mkdir -p "$wt/$(dirname "$rel")"
    cp -p "$main/$rel" "$wt/$rel"
    copied="$copied $rel"
  done < <(cd "$main" && find . \
    \( -name .git -o -name node_modules -o -name worktrees -o -name .next -o -name .turbo \) -prune -o \
    -type f \( \
      \( -name '.env*' ! -name '*.example' ! -name '*.sample' ! -name '*.template' \) \
      -o -path '*/certificates/*.pem' \
      -o -path './.claude/settings.local.json' \
    \) -print | sed 's|^\./||')
fi

installed=""
marker="$gitdir/worktree-setup-installed"
if [ -f "$wt/package.json" ] && [ ! -f "$marker" ]; then
  # A hook has no TTY, so an install must never wait on a prompt.
  install="npm install"
  for pair in \
    "pnpm-lock.yaml:pnpm install --config.confirm-modules-purge=false" \
    "bun.lock:bun install" "bun.lockb:bun install" "yarn.lock:yarn install"; do
    if [ -f "$wt/${pair%%:*}" ]; then install=${pair#*:}; break; fi
  done
  log="$gitdir/worktree-setup.log"
  # shellcheck disable=SC2086 # $install is a command plus its flags
  if (cd "$wt" && $install </dev/null) >"$log" 2>&1; then
    touch "$marker"
    installed="$install"
  else
    echo "worktree-setup: \`$install\` failed in $wt. Fix it before other work, then rerun $0. Last lines of $log:"
    tail -n 15 "$log"
    if [ -n "$copied" ]; then echo "Copied from $main:$copied"; fi
    exit 1
  fi
fi

if [ -z "$copied$installed" ]; then exit 0; fi
echo "worktree-setup prepared this worktree ($wt) from $main."
if [ -n "$copied" ]; then echo "Copied local files git does not track:$copied"; fi
if [ -n "$installed" ]; then echo "Ran \`$installed\`."; fi
