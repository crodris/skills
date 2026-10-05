#!/usr/bin/env bash
# Checks skills/worktree-setup/setup.sh against scratch repositories and stubs:
# pnpm and npm record each install and fail when they can read stdin (a hook's
# stdin is the session JSON, never the install's); pnpm creates node_modules
# and also fails when STUB_FAIL=1; npm writes a package-lock.json when none
# exists; cp fails partway through on any .env.partial file. Every path has a
# space in it.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
setup="$repo_root/skills/worktree-setup/setup.sh"
base="$(mktemp -d)"
tmp="$base/a b"
mkdir "$tmp"
trap 'rm -rf "$base"' EXIT

mkdir "$tmp/bin" "$tmp/outside"
cat > "$tmp/bin/pnpm" <<'STUB'
#!/usr/bin/env bash
echo "$PWD $*" >> "$STUB_LOG"
mkdir -p node_modules
if read -r _; then echo "STUB_READ_STDIN"; exit 1; fi
[ "${STUB_FAIL:-0}" = 1 ] && { echo "ERR_PNPM_STUB"; exit 1; }
exit 0
STUB
cat > "$tmp/bin/npm" <<'STUB'
#!/usr/bin/env bash
echo "$PWD $*" >> "$NPM_LOG"
if read -r _; then echo "STUB_READ_STDIN"; exit 1; fi
[ -f package-lock.json ] || echo "lock" > package-lock.json
exit 0
STUB
cat > "$tmp/bin/cp" <<'STUB'
#!/usr/bin/env bash
case "$*" in *.env.partial*) for last; do :; done; echo "PART" > "$last"; exit 1 ;; esac
exec "$REAL_CP" "$@"
STUB
chmod +x "$tmp/bin/pnpm" "$tmp/bin/npm" "$tmp/bin/cp"
REAL_CP="$(command -v cp)"
export REAL_CP STUB_LOG="$tmp/installs" NPM_LOG="$tmp/npm-installs" PATH="$tmp/bin:$PATH"
: > "$STUB_LOG"
: > "$NPM_LOG"
git() { command git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

main="$tmp/main"
mkdir -p "$main/apps/web/certificates" "$main/apps/api" "$main/apps/gone" "$main/.claude" "$main/node_modules/dep"
git -C "$main" init -q -b main
printf '%s\n' node_modules '.env*' '!.env.example' '!.env.test' '!.env.a' certificates scratch-wt > "$main/.gitignore"
echo '{}' > "$main/package.json"
echo "v1" > "$main/pnpm-lock.yaml"
echo "EXAMPLE=1" > "$main/.env.example"
echo "TRACKED=1" > "$main/.env.test"
echo "A=1" > "$main/.env.a"
git -C "$main" add -A && git -C "$main" commit -qm init
echo "ROOT=1" > "$main/.env.local"
echo "Q=1" > "$main/.env.?"
echo "API=1" > "$main/apps/api/.env.local"
echo "GONE=1" > "$main/apps/gone/.env.local"
echo "WEB=1" > "$main/apps/web/.env.test.local"
echo "SENTRY_AUTH_TOKEN=x" > "$main/apps/web/.env.sentry-build-plugin"
echo "PROD=1" > "$main/apps/web/.env.prod.local"
echo "PROD=1" > "$main/.env.production.local"
echo "pem" > "$main/apps/web/certificates/localhost.pem"
echo '{}' > "$main/.claude/settings.local.json"
echo "DEP=1" > "$main/node_modules/dep/.env"
echo "DANGLE=1" > "$main/.env.dangling"
echo "PARTIAL=1" > "$main/.env.partial"
echo "LINK=1" > "$tmp/secret.env" && ln -s "$tmp/secret.env" "$main/.env.link"
echo "LOCKED=1" > "$main/.env.locked" && chmod 000 "$main/.env.locked"
git -C "$main" worktree add -q "$main/scratch-wt" -b scratch
echo "OTHER=1" > "$main/scratch-wt/.env.other"

wt="$tmp/wt"
git -C "$main" worktree add -q "$wt" -b feature
git -C "$wt" rm -q .env.test && git -C "$wt" commit -qm "drop tracked env"
mkdir -p "$wt/apps/web"
echo "MINE=1" > "$wt/apps/web/.env.test.local"
ln -s "$tmp/outside" "$wt/apps/api"
ln -s "$tmp/gone" "$wt/apps/gone"
ln -s "$tmp/nowhere" "$wt/.env.dangling"

fail=0
check() {
  if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (got '$2', want '$3')"; fail=1; fi
}
run() { "$setup" "$@" <<< '{"hook_event_name":"SessionStart"}' 2>&1 && echo "exit=0" || echo "exit=$?"; }
has() { [ -e "$1" ] && echo copied || echo skipped; }
installs() { wc -l < "$STUB_LOG" | tr -d ' '; }
npm_installs() { wc -l < "$NPM_LOG" | tr -d ' '; }

check "main checkout is a no-op" "$(run "$main")" "exit=0"

out="$(STUB_FAIL=1 run "$wt")"
check "failed install exits 1" "$(printf '%s' "$out" | tail -n 1)" "exit=1"
check "failed install shows the tool output" "$(printf '%s' "$out" | grep -c ERR_PNPM_STUB)" "1"
check "failed install names the rerun command, quoted" "$(printf '%s' "$out" | grep -cF "$(printf 'rerun: bash %q %q' "$setup" "$(cd "$wt" && pwd -P)")")" "1"

out="$(run "$wt")"
check "retry after a failed install succeeds" "$(printf '%s' "$out" | tail -n 1)" "exit=0"
check "retry runs the install again" "$(installs)" "2"
check "an unreadable file is reported and skipped" "$(printf '%s' "$out" | grep -c "could not copy .env.locked")" "1"
check "a failed copy is reported" "$(printf '%s' "$out" | grep -c "could not copy .env.partial")" "1"
check "a failed copy leaves no partial file" "$(has "$wt/.env.partial")" "skipped"
rm -f "$main/.env.locked" "$main/.env.partial"
check "install runs without a prompt" "$(tail -n 1 "$STUB_LOG")" "$(cd "$wt" && pwd -P) install --config.confirm-modules-purge=false"
check "copies a root env file" "$(cat "$wt/.env.local")" "ROOT=1"
check "matches a file name literally, not as a glob" "$(cat "$wt/.env.?" 2>/dev/null)" "Q=1"
check "copies a nested cert" "$(cat "$wt/apps/web/certificates/localhost.pem")" "pem"
check "copies untracked local Claude settings" "$(cat "$wt/.claude/settings.local.json")" "{}"
check "copies a symlinked env file as a file" "$(cat "$wt/.env.link"; [ -L "$wt/.env.link" ] && echo " (link)")" "LINK=1"
check "keeps a file the worktree already has" "$(cat "$wt/apps/web/.env.test.local")" "MINE=1"
check "skips env files inside node_modules" "$(has "$wt/node_modules/dep/.env")" "skipped"
check "skips files from a nested worktree" "$(has "$wt/scratch-wt/.env.other")" "skipped"
check "skips a tracked env file the branch deleted" "$(has "$wt/.env.test")" "skipped"
check "never writes through a symlinked directory" "$(has "$tmp/outside/.env.local")" "skipped"
check "never writes through a dangling symlinked directory" "$(has "$tmp/gone")" "skipped"
check "never writes through a dangling symlink" "$(has "$tmp/nowhere")" "skipped"
check "never copies Sentry's build-plugin token" "$(has "$wt/apps/web/.env.sentry-build-plugin")" "skipped"
check "never copies a production env file" "$(has "$wt/apps/web/.env.prod.local")$(has "$wt/.env.production.local")" "skippedskipped"

check "second run is silent" "$(run "$wt")" "exit=0"
check "second run does not reinstall" "$(installs)" "2"

rm -rf "$wt/node_modules"
run "$wt" >/dev/null
check "reinstalls when node_modules is gone" "$(installs)" "3"
echo "v2" > "$wt/pnpm-lock.yaml"
run "$wt" >/dev/null
check "reinstalls when the lockfile changes" "$(installs)" "4"
rm -rf "$wt/node_modules" && touch "$wt/.pnp.cjs"
check "Plug'n'Play counts as installed" "$(run "$wt"; installs)" "exit=0
4"
rm "$wt/.pnp.cjs"
STUB_FAIL=1 run "$wt" >/dev/null
run "$wt" >/dev/null
check "a failed reinstall that left node_modules is retried" "$(installs)" "6"

rm "$wt/.env.local"
check "restores a deleted env file" "$(run "$wt" >/dev/null; cat "$wt/.env.local")" "ROOT=1"

git -C "$main" worktree add -q "$tmp/wt2" -b feature2
GIT_DIR="$main/.git" run "$tmp/wt2" >/dev/null
check "an inherited GIT_DIR does not redirect it" "$(cat "$tmp/wt2/.env.local" 2>/dev/null)" "ROOT=1"

git -C "$main" worktree add -q --detach "$tmp/review" main
check "a detached worktree is a no-op" "$(run "$tmp/review")" "exit=0"
check "a detached worktree gets no secrets" "$(has "$tmp/review/.env.local")" "skipped"

# No package.json in these worktrees, so only the copy path runs.
git clone -q --bare "$main" "$tmp/bare.git"
git -C "$tmp/bare.git" worktree add -q "$tmp/bare-wt" -b bare-feature
rm "$tmp/bare-wt/package.json"
check "a bare repo's worktree is a no-op" "$(run "$tmp/bare-wt")" "exit=0"
check "a bare repo's worktree copies nothing from its parent" "$(has "$tmp/bare-wt/main")" "skipped"

git clone -q --bare "$main" "$tmp/proj/.git"
git -C "$tmp/proj/.git" worktree add -q "$tmp/proj/main" main
git -C "$tmp/proj/.git" worktree add -q "$tmp/proj/feat" -b proj-feature
echo "SIBLING=1" > "$tmp/proj/main/.env.local"
rm "$tmp/proj/feat/package.json"
check "a bare repo in .git is a no-op" "$(run "$tmp/proj/feat")" "exit=0"
check "a bare repo in .git copies nothing from a sibling" "$(has "$tmp/proj/feat/main/.env.local")$(has "$tmp/proj/feat/.env.local")" "skippedskipped"

git init -q -b main --separate-git-dir "$tmp/sep.git" "$tmp/sep"
echo '{}' > "$tmp/sep/package.json"
git -C "$tmp/sep" add -A && git -C "$tmp/sep" commit -qm init
git -C "$tmp/sep" worktree add -q "$tmp/sep-wt" -b sep-feature
check "a separate-git-dir worktree still installs" "$(run "$tmp/sep-wt" | tail -n 1; npm_installs)" "exit=0
1"
check "npm's new lockfile does not trigger another install" "$(run "$tmp/sep-wt"; npm_installs)" "exit=0
1"
exit "$fail"
