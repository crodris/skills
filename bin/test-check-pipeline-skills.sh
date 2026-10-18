#!/usr/bin/env bash
# test-check-pipeline-skills.sh - run bin/check-pipeline-skills.sh against a scratch
# upstream repository, lock file, and install, and check that it passes a matching
# install and fails on a changed file or a skill missing from the lock file.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-pipeline-skills.sh"
failures=0

scratch() {
  dir=$(mktemp -d)
  mkdir -p "$dir/repo/bin" "$dir/repo/skills/frontend-design-pipeline" "$dir/upstream/skills/demo" "$dir/installed"
  cp "$SCRIPT" "$dir/repo/bin/"
  # shellcheck disable=SC2016 # the backticks are Markdown, not command substitution
  printf '| Stage | Skill | Install |\n|---|---|---|\n| 1 | `demo` | `npx skills@latest add someone/demo -s demo -g` |\n' \
    > "$dir/repo/skills/frontend-design-pipeline/SKILL.md"
  printf 'demo skill\n' > "$dir/upstream/skills/demo/SKILL.md"
  git -C "$dir/upstream" init -q
  git -C "$dir/upstream" add .
  git -C "$dir/upstream" -c user.name=t -c user.email=t@t commit -qm init
  cp -R "$dir/upstream/skills/demo" "$dir/installed/demo"
  printf '{"skills": {"demo": {"sourceUrl": "file://%s/upstream", "skillPath": "skills/demo/SKILL.md"}}}\n' "$dir" > "$dir/lock.json"
  echo "$dir"
}

expect() {
  name=$1 want=$2 dir=$3
  if SKILL_LOCK="$dir/lock.json" SKILLS_DIR="$dir/installed" "$dir/repo/bin/check-pipeline-skills.sh" >/dev/null 2>&1; then got=0; else got=1; fi
  if [ "$got" = "$want" ]; then echo "ok: $name"; else echo "FAIL: $name (exit $got, want $want)"; failures=$((failures + 1)); fi
  rm -rf "$dir"
}

dir=$(scratch)
expect "matching install passes" 0 "$dir"

dir=$(scratch)
mkdir -p "$dir/installed/demo/__pycache__"
printf 'bytecode\n' > "$dir/installed/demo/__pycache__/x.pyc"
expect "__pycache__ is ignored" 0 "$dir"

dir=$(scratch)
printf 'local edit\n' >> "$dir/installed/demo/SKILL.md"
expect "changed file fails" 1 "$dir"

dir=$(scratch)
printf '{"skills": {}}\n' > "$dir/lock.json"
expect "skill missing from the lock file fails" 1 "$dir"

[ "$failures" = 0 ]
