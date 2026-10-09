#!/usr/bin/env bash
# test-sync-versions.sh - run bin/sync-versions.sh in a scratch repository and
# check that plugin versions reach README headings and claimed SKILL.md
# frontmatter, that standalone SKILL.md versions reach their README headings,
# and that a skill with no version line or no frontmatter fails.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/sync-versions.sh"
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

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/bin" "$dir/.claude-plugin"
cp "$SCRIPT" "$dir/bin/sync-versions.sh"
cat > "$dir/.claude-plugin/marketplace.json" <<'JSON'
{"plugins": [{"name": "kit", "version": "2.3.0", "skills": ["./skills/build"]}]}
JSON
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

[ "$failures" -eq 0 ] || { echo "$failures failure(s)"; exit 1; }
echo "all passed"
