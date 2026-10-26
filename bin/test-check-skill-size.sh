#!/usr/bin/env bash
# test-check-skill-size.sh - run bin/check-skill-size.sh in scratch repositories
# and check each way it passes or fails.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-skill-size.sh"
failures=0

scratch() {
  dir=$(mktemp -d)
  git -C "$dir" init -q
  mkdir -p "$dir/bin" "$dir/skills/demo"
  cp "$SCRIPT" "$dir/bin/check-skill-size.sh"
  printf 'one two three\n' > "$dir/skills/demo/SKILL.md"
  printf '# budgets\nskills/demo/SKILL.md 3\n' > "$dir/bin/skill-budgets.txt"
  git -C "$dir" add bin skills
  echo "$dir"
}

# expect <name> <exit> <dir> [text the output must contain]
expect() {
  name=$1 want=$2 dir=$3 text=${4:-}
  if out=$("$dir/bin/check-skill-size.sh" 2>&1); then got=0; else got=1; fi
  if [ "$got" != "$want" ]; then
    echo "FAIL: $name (exit $got, want $want)"; failures=$((failures + 1))
  elif [ -n "$text" ] && ! printf '%s' "$out" | grep -qF "$text"; then
    echo "FAIL: $name (output lacks: $text)"; failures=$((failures + 1))
  else
    echo "ok: $name"
  fi
  rm -rf "$dir"
}

dir=$(scratch)
expect "a file at its budget passes" 0 "$dir"

dir=$(scratch)
printf 'four\n' >> "$dir/skills/demo/SKILL.md"
expect "a file over its budget fails" 1 "$dir" "4 words, over its budget of 3"

dir=$(scratch)
printf 'new file\n' > "$dir/skills/demo/extra.md"
expect "an untracked file with no budget fails" 1 "$dir" "skills/demo/extra.md: 2 words and no budget"

dir=$(scratch)
printf 'skills/demo/gone.md 10\n' >> "$dir/bin/skill-budgets.txt"
expect "a budget for a missing file fails" 1 "$dir" "skills/demo/gone.md has a budget but no file"

dir=$(scratch)
printf 'skills/demo/SKILL.md lots\n' > "$dir/bin/skill-budgets.txt"
expect "a malformed budget line fails" 1 "$dir" "expected \"<path> <words>\""

dir=$(scratch)
printf 'skills/demo/SKILL.md 3 extra\n' > "$dir/bin/skill-budgets.txt"
expect "a budget line with three fields fails" 1 "$dir" "expected \"<path> <words>\""

dir=$(scratch)
printf 'skills/demo/SKILL.md\n' > "$dir/bin/skill-budgets.txt"
expect "a budget line with only a path fails" 1 "$dir" "expected \"<path> <words>\""

dir=$(scratch)
printf 'skills/demo/SKILL.md 9\n' >> "$dir/bin/skill-budgets.txt"
expect "a duplicate budget line fails" 1 "$dir" "skills/demo/SKILL.md already has a budget"

dir=$(scratch)
mkdir -p "$dir/skills/demo/deep dir"
printf 'two words\n' > "$dir/skills/demo/deep dir/my file.md"
printf 'skills/demo/deep dir/my file.md 2\n' >> "$dir/bin/skill-budgets.txt"
expect "a nested path with spaces takes its budget" 0 "$dir"

dir=$(scratch)
printf 'skills/demo/ignored.md\n' > "$dir/.gitignore"
printf 'ignored notes\n' > "$dir/skills/demo/ignored.md"
expect "a git-ignored file is not checked" 0 "$dir"

dir=$(scratch)
rm "$dir/skills/demo/SKILL.md"
printf '# budgets\n' > "$dir/bin/skill-budgets.txt"
expect "a tracked file deleted from the tree is skipped" 0 "$dir"

dir=$(scratch)
printf 'skills/demo/setup.sh has many words but is not Markdown\n' > "$dir/skills/demo/setup.sh"
expect "a file that is not Markdown is not checked" 0 "$dir"

[ "$failures" = 0 ]
