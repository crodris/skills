#!/usr/bin/env bash
# Checks skills/worktree-setup/setup.sh against a scratch repo and a stub pnpm
# that records each install and fails when STUB_FAIL=1.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
setup="$repo_root/skills/worktree-setup/setup.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/bin"
cat > "$tmp/bin/pnpm" <<'STUB'
#!/usr/bin/env bash
echo "$PWD $*" >> "$STUB_LOG"
[ "${STUB_FAIL:-0}" = 1 ] && { echo "ERR_PNPM_STUB"; exit 1; }
mkdir -p node_modules
STUB
chmod +x "$tmp/bin/pnpm"
export STUB_LOG="$tmp/installs" PATH="$tmp/bin:$PATH"
: > "$STUB_LOG"

main="$tmp/main"
mkdir -p "$main/apps/web/certificates" "$main/.claude" "$main/node_modules/dep" "$main/worktrees/old"
git -C "$main" init -q -b main
printf 'node_modules\n.env*\n!.env.example\ncertificates\n.claude/settings.local.json\nworktrees\n' > "$main/.gitignore"
echo '{}' > "$main/package.json"
touch "$main/pnpm-lock.yaml"
echo "EXAMPLE=1" > "$main/.env.example"
git -C "$main" add -A && git -C "$main" -c user.name=t -c user.email=t@t commit -qm init
echo "ROOT=1" > "$main/.env.local"
echo "WEB=1" > "$main/apps/web/.env.test.local"
echo "pem" > "$main/apps/web/certificates/localhost.pem"
echo '{}' > "$main/.claude/settings.local.json"
echo "DEP=1" > "$main/node_modules/dep/.env"
echo "OLD=1" > "$main/worktrees/old/.env"
echo "SAMPLE=1" > "$main/.env.sample"

wt="$tmp/wt"
git -C "$main" worktree add -q "$wt" -b feature
mkdir -p "$wt/apps/web"
echo "MINE=1" > "$wt/apps/web/.env.test.local"

fail=0
check() {
  if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (got '$2', want '$3')"; fail=1; fi
}
run() { "$setup" "$@" 2>&1 && echo "exit=0" || echo "exit=$?"; }

check "main checkout is a no-op" "$(run "$main")" "exit=0"

out="$(export STUB_FAIL=1; run "$wt")"
check "failed install exits 1" "$(printf '%s' "$out" | tail -n 1)" "exit=1"
check "failed install shows the tool output" "$(printf '%s' "$out" | grep -c ERR_PNPM_STUB)" "1"

out="$(run "$wt")"
check "retry after a failed install runs it again" "$(wc -l < "$STUB_LOG" | tr -d ' ')" "2"
check "retry succeeds" "$(printf '%s' "$out" | tail -n 1)" "exit=0"
check "copies a root env file" "$(cat "$wt/.env.local")" "ROOT=1"
check "copies a nested cert" "$(cat "$wt/apps/web/certificates/localhost.pem")" "pem"
check "copies local Claude settings" "$(cat "$wt/.claude/settings.local.json")" "{}"
check "keeps a file the worktree already has" "$(cat "$wt/apps/web/.env.test.local")" "MINE=1"
check "skips env files inside node_modules" "$([ -e "$wt/node_modules/dep/.env" ] && echo copied || echo skipped)" "skipped"
check "skips env files in nested worktrees" "$([ -e "$wt/worktrees/old/.env" ] && echo copied || echo skipped)" "skipped"
check "skips sample env files" "$([ -e "$wt/.env.sample" ] && echo copied || echo skipped)" "skipped"
check "installs in the worktree without prompting" "$(tail -n 1 "$STUB_LOG")" "$(cd "$wt" && pwd -P) install --config.confirm-modules-purge=false"

check "second run is silent" "$(run "$wt")" "exit=0"
check "second run does not reinstall" "$(wc -l < "$STUB_LOG" | tr -d ' ')" "2"

rm "$wt/.env.local"
check "restores a deleted env file" "$(run "$wt" >/dev/null; cat "$wt/.env.local")" "ROOT=1"

git clone -q --bare "$main" "$tmp/bare.git"
git -C "$tmp/bare.git" worktree add -q "$tmp/bare-wt" -b bare-feature
run "$tmp/bare-wt" >/dev/null
check "a bare repo's worktree copies nothing from its parent dir" "$([ -e "$tmp/bare-wt/main" ] && echo copied || echo skipped)" "skipped"
exit "$fail"
