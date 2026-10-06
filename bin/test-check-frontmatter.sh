#!/usr/bin/env bash
# test-check-frontmatter.sh - run bin/check-frontmatter.sh in scratch repositories
# and check that it passes clean frontmatter and fails on a parse error or a
# description cut short by a comment.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-frontmatter.sh"
failures=0

scratch() {
  dir=$(mktemp -d)
  git -C "$dir" init -q
  mkdir -p "$dir/bin" "$dir/skills/demo"
  cp "$SCRIPT" "$dir/bin/check-frontmatter.sh"
  printf -- '---\nname: demo\ndescription: %b\n---\n\n# Demo\n' "$1" > "$dir/skills/demo/SKILL.md"
  git -C "$dir" add bin skills
  echo "$dir"
}

expect() {
  name=$1 want=$2 dir=$3 says=${4:-}
  got=0
  out=$("$dir/bin/check-frontmatter.sh" 2>&1) || got=$?
  if [ "$got" = "$want" ] && [[ $out == *"$says"* ]]; then echo "ok: $name"; else echo "FAIL: $name (exit $got, want $want)"; failures=$((failures + 1)); fi
  rm -rf "$dir"
}

dir=$(scratch 'Use when the user says "demo it".')
expect "clean frontmatter passes" 0 "$dir"

dir=$(scratch 'Merge needs `merge: yes` in the config.')
expect "an unquoted colon fails as a parse error" 1 "$dir" "Nested mappings"

dir=$(scratch 'Use when the user says "review #107" or "review this".')
expect "a description cut short by a comment fails" 1 "$dir"

dir=$(scratch '"Use when the user says \"review #107\"."')
expect "a quoted description with a hash passes" 0 "$dir"

dir=$(scratch '>\n  Use when the user says "review #107".')
expect "a block scalar with a hash passes" 0 "$dir"

dir=$(scratch 'Use when the user says\n  "demo it" or "show it".')
expect "a plain description wrapped onto the next line passes" 0 "$dir"

dir=$(scratch 'Use when the user says "demo it"\n  # or "show it".')
expect "a wrapped description cut short by a comment line fails" 1 "$dir"

dir=$(scratch 'Use when the user says "demo it".')
printf -- '---\r\nname: demo\r\ndescription: Use when the user says "demo it".\r\n---' > "$dir/skills/demo/SKILL.md"
expect "CRLF frontmatter with no final newline passes" 0 "$dir"

dir=$(scratch 'Use when the user says\n\n  "demo it" #or "show it".')
expect "a comment after a blank line in a wrapped description fails" 1 "$dir"

dir=$(scratch 'Use when\xc2\xa0#1 is asked.')
expect "a hash after a non-breaking space passes" 0 "$dir"

dir=$(scratch 'Use when the user says "demo it".')
printf '\xef\xbb\xbf%s' "$(cat "$dir/skills/demo/SKILL.md")" > "$dir/skills/demo/SKILL.md"
expect "a byte order mark fails, since the skills CLI cannot read it" 1 "$dir" "no frontmatter"

dir=$(scratch 'Use when the user says "demo it".')
mkdir -p "$dir/stub" && printf '#!/usr/bin/env bash\nexit 1\n' > "$dir/stub/npm" && chmod +x "$dir/stub/npm"
PATH="$dir/stub:$PATH" expect "a failed yaml install exits 2 and says so" 2 "$dir" "could not install yaml"

dir=$(scratch 'Use when the user says "demo it".')
mkdir -p "$dir/skills/gone" && printf -- '---\nname: gone\ndescription: Gone.\n---\n' > "$dir/skills/gone/SKILL.md"
git -C "$dir" add skills/gone && rm "$dir/skills/gone/SKILL.md"
expect "a tracked skill deleted from the tree is skipped" 0 "$dir"

dir=$(scratch 'Use when the user says "demo it".')
mkdir -p "$dir/skills/bare" && printf -- '---\nname: bare\n---\n' > "$dir/skills/bare/SKILL.md"
expect "an untracked skill with no description fails" 1 "$dir"

[ "$failures" = 0 ]
