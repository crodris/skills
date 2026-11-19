#!/usr/bin/env bash
# Makes a linked git worktree runnable: copies the main checkout's untracked
# env files (except ones named for production credentials and .env*.bak*
# backups), local HTTPS certificates, .claude/settings.local.json, and any
# gitignored file its .worktreeinclude lists, then installs dependencies when
# they are missing or the lockfile changed.
# Prints nothing when there is nothing to do, so a SessionStart hook can run it
# on every session.
#
# Usage: setup.sh [dir]   (default: the current directory)
set -euo pipefail
# A caller such as a git hook can export GIT_DIR and friends, which would point
# every git call below at its repository instead.
# shellcheck disable=SC2046 # git prints bare variable names, one per line
unset $(git rev-parse --local-env-vars)

wt=$(git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)
gitdir=$(git -C "$wt" rev-parse --path-format=absolute --git-dir)
# A main checkout or a submodule owns its git dir; only linked worktrees share one.
[ "$gitdir" != "$common" ] || exit 0
# The review skill checks a pull request out on a detached HEAD. Its install
# scripts are someone else's code, so it gets neither secrets nor an install.
# A branch checkout, including one from gh pr checkout, is treated as the user's.
git -C "$wt" symbolic-ref -q HEAD >/dev/null || exit 0

main=$(git -C "$wt" worktree list --porcelain | sed -n '1s/^worktree //p')
wtp=$(cd "$wt" && pwd -P)
copied=""
# copy_untracked copies one untracked file of the main checkout, by its path
# relative to the checkout, into the worktree when every safety check passes.
copy_untracked() {
  local rel=$1 dest f hops l tracked d
  dest="$wt/$rel"
  if [ -e "$dest" ] || [ -L "$dest" ]; then return 0; fi
  # A .env*.bak* backup is an old snapshot, not a live env file, so it stays
  # out. Only regular files copy: git lists a nested worktree or a symlink to
  # a directory as one entry, which cp would refuse on every run.
  case "${rel##*/}" in .env*.bak*) return 0 ;; esac
  [ -f "$main/$rel" ] || return 0
  # Files named for production credentials stay in the main checkout: a
  # .env.prod* file or Sentry's .env.sentry-build-plugin token. A symlink is
  # judged by the file it finally points at, within 40 hops so a link loop
  # cannot hang it, so a link to one of those stays out too.
  f="$main/$rel" hops=0
  while [ -L "$f" ] && [ "$hops" -lt 40 ]; do
    l=$(readlink "$f")
    case $l in /*) f=$l ;; *) f="$(dirname "$f")/$l" ;; esac
    hops=$((hops + 1))
  done
  case "$(basename "$f")" in .env.prod*|.env.sentry-build-plugin) return 0 ;; esac
  # Only untracked files the main checkout itself owns: never one inside a
  # nested worktree or submodule.
  [ "$(git -C "$main/$(dirname -- "$rel")" rev-parse --show-toplevel 2>/dev/null)" = "$top" ] || return 0
  tracked=$(git -C "$main" --literal-pathspecs ls-files -- "$rel") || return 0
  [ -z "$tracked" ] || return 0
  # Never write through a symlink that leads out of the worktree or nowhere.
  d=$(dirname "$dest")
  while [ ! -e "$d" ] && [ ! -L "$d" ]; do d=$(dirname "$d"); done
  case "$(cd "$d" 2>/dev/null && pwd -P)/" in "$wtp"/*) ;; *) return 0 ;; esac
  if mkdir -p "$(dirname "$dest")" && cp -p "$main/$rel" "$dest"; then copied="$copied $rel"
  else rm -f "$dest"; echo "worktree-setup: could not copy $rel from $main"; fi
}

# A bare repository has no checkout, and git lists a --separate-git-dir
# repository's git dir in place of its checkout, so neither is copied from.
if top=$(git -C "$main" rev-parse --show-toplevel 2>/dev/null); then
  # The find prunes dependency and build folders, whose env files would pass
  # the checks in copy_untracked, and common nested-worktree folders, which
  # only saves a git call per file there; the toplevel check catches any other
  # nesting.
  while IFS= read -r rel; do copy_untracked "$rel"; done < <(cd "$main" && find . \
    \( -name .git -o -name node_modules -o -name worktrees -o -name .worktrees -o -name .next -o -name .turbo \) -prune -o \
    \( -type f -o -type l \) \( -name '.env*' -o -path '*/certificates/*.pem' -o -path './.claude/settings.local.json' \) \
    -print | sed 's|^\./||')
  # A .worktreeinclude at the main checkout's root lists more files to copy,
  # in gitignore pattern syntax. As with Claude Code's own worktrees, a match
  # copies only when the repository also gitignores it, so an uncommitted
  # source file never lands on another branch. The list is read even when it
  # is itself untracked, so a project can keep it local. check-ignore reads
  # its input as pathspecs, so each path gets a ./ prefix that keeps a name
  # starting with : from reading as pathspec magic.
  if [ -f "$main/.worktreeinclude" ]; then
    while IFS= read -r -d '' rel; do copy_untracked "${rel#./}"; done < <(
      git -C "$main" ls-files -z --others --ignored --exclude-from="$main/.worktreeinclude" |
        while IFS= read -r -d '' path; do printf './%s\0' "$path"; done |
        git -C "$main" check-ignore -z --stdin)
  fi
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
# lockfile change or a deleted node_modules reinstalls. It picks the lockfile
# again because npm writes package-lock.json on a first install. Yarn
# Plug'n'Play keeps no node_modules, only .pnp.cjs.
state() {
  local lock install
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
