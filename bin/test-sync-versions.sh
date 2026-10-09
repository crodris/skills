#!/usr/bin/env bash
# test-sync-versions.sh - run bin/sync-versions.sh in a scratch repository and
# check that plugin versions reach README headings and claimed SKILL.md
# frontmatter, that standalone SKILL.md versions reach their README headings,
# and that a skill with no version line or no frontmatter fails. Then run
# bin/hooks/pre-commit in a scratch git repository and check that it stages
# only the SKILL.md files the sync wrote.
set -euo pipefail

BIN="$(cd "$(dirname "$0")" && pwd)"
failures=0

check() {
  name=$1 file=$2 line=$3
  if grep -qxF -- "$line" "$dir/$file"; then echo "ok: $name"; else echo "FAIL: $name ($file has no line '$line')"; failures=$((failures + 1)); fi
}

skill() {
  mkdir -p "$dir/skills/$1"
  printf -- '---\nname: %s\ndescription: Demo.\n%b---\n\n# %s\n' "$1" "$2" "$1" > "$dir/skills/$1/SKILL.md"
}

fails() {
  name=$1 file=$2 got=0
  out=$("$dir/bin/sync-versions.sh" 2>&1) || got=$?
  if [ "$got" = 1 ] && [[ $out == *"$file has no version: line"* ]]; then echo "ok: $name"; else echo "FAIL: $name (exit $got)"; failures=$((failures + 1)); fi
}

marketplace() {
  printf -- '{"plugins": [{"name": "kit", "version": "%s", "skills": ["./skills/build"]}]}\n' "$1" > "$dir/.claude-plugin/marketplace.json"
}

fixture() {
  mkdir -p "$dir/bin" "$dir/.claude-plugin"
  cp "$BIN/sync-versions.sh" "$dir/bin/sync-versions.sh"
  marketplace 2.3.0
  cat > "$dir/README.md" <<'MD'
# Demo

## Available Plugins

### kit (v2.2.0)

## Standalone Skills

### lint (v0.9.0)

## License
MD
  skill build 'version: 1.0.0\n'
  skill lint 'version: 1.4.2\n'
}

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

dir="$root/sync"
fixture

"$dir/bin/sync-versions.sh" > /dev/null
check "plugin heading takes the marketplace version" README.md '### kit (v2.3.0)'
check "claimed skill frontmatter takes the plugin version" skills/build/SKILL.md 'version: 2.3.0'
check "standalone heading takes the SKILL.md version" README.md '### lint (v1.4.2)'
check "standalone frontmatter is left alone" skills/lint/SKILL.md 'version: 1.4.2'

out=$("$dir/bin/sync-versions.sh")
if [[ $out == *"All versions already up to date."* ]]; then echo "ok: a second run changes nothing"; else echo "FAIL: a second run changed something"; failures=$((failures + 1)); fi

skill build ''
fails "a claimed skill with no version line fails" skills/build/SKILL.md
skill build 'version: 2.3.0\n'

skill lint ''
fails "a standalone skill with no version line fails" skills/lint/SKILL.md
skill lint 'version: 1.4.2\n'

printf -- '# build\n' > "$dir/skills/build/SKILL.md"
fails "a claimed skill with no frontmatter fails" skills/build/SKILL.md
skill build 'version: 2.3.0\n'

dir="$root/hook"
fixture
mkdir -p "$dir/bin/hooks"
cp "$BIN/hooks/pre-commit" "$dir/bin/hooks/pre-commit"
"$dir/bin/sync-versions.sh" > /dev/null
git -C "$dir" init -q
git -C "$dir" config user.name test
git -C "$dir" config user.email test@example.com
git -C "$dir" add -A
git -C "$dir" commit -q --no-verify --no-gpg-sign -m fixture
marketplace 2.4.0
printf -- 'Unrelated edit.\n' >> "$dir/skills/lint/SKILL.md"
got=0
"$dir/bin/hooks/pre-commit" > /dev/null 2>&1 || got=$?
staged=$(git -C "$dir" diff --cached --name-only)
if [ "$got" = 0 ]; then echo "ok: the hook exits 0"; else echo "FAIL: the hook exited $got"; failures=$((failures + 1)); fi
if grep -qxF skills/build/SKILL.md <<< "$staged"; then echo "ok: the hook stages the SKILL.md the sync wrote"; else echo "FAIL: the hook did not stage skills/build/SKILL.md"; failures=$((failures + 1)); fi
if ! grep -qxF skills/lint/SKILL.md <<< "$staged"; then echo "ok: the hook leaves an unrelated SKILL.md edit unstaged"; else echo "FAIL: the hook staged skills/lint/SKILL.md"; failures=$((failures + 1)); fi

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
echo "all passed"
