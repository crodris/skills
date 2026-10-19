#!/usr/bin/env bash
# test-check-pipeline-skills.sh - run bin/check-pipeline-skills.sh against a scratch
# upstream repository, lock file, and install, and check that it passes a matching
# install, compares a pinned skill at its recorded ref, and fails on a changed file, a skill missing from the lock file, or a table
# with no skills in it.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-pipeline-skills.sh"
failures=0

scratch() {
  dir=$(mktemp -d)
  mkdir -p "$dir/repo/bin" "$dir/repo/skills/frontend-design-pipeline" "$dir/upstream/skills/demo" "$dir/upstream/skills/other" "$dir/installed"
  cp "$SCRIPT" "$dir/repo/bin/"
  # shellcheck disable=SC2016 # the backticks are Markdown, not command substitution
  printf '| Stage | Skill | Install |\n|---|---|---|\n| 1 | one of `demo`, `other` | `npx skills@latest add someone/demo -s demo other -g` |\n' \
    > "$dir/repo/skills/frontend-design-pipeline/SKILL.md"
  printf 'demo skill\n' > "$dir/upstream/skills/demo/SKILL.md"
  printf 'other skill\n' > "$dir/upstream/skills/other/SKILL.md"
  git -C "$dir/upstream" init -q
  git -C "$dir/upstream" add .
  git -C "$dir/upstream" -c user.name=t -c user.email=t@t commit -qm init
  cp -R "$dir/upstream/skills/demo" "$dir/upstream/skills/other" "$dir/installed/"
  printf '{"skills": {"demo": {"sourceUrl": "file://%s/upstream", "skillPath": "skills/demo/SKILL.md"}, "other": {"sourceUrl": "file://%s/upstream", "skillPath": "skills/other/SKILL.md"}}}\n' "$dir" "$dir" > "$dir/lock.json"
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
printf 'local edit\n' >> "$dir/installed/other/SKILL.md"
expect "changed file in a later skill of the row fails" 1 "$dir"

dir=$(scratch)
printf '{"skills": {}}\n' > "$dir/lock.json"
expect "skill missing from the lock file fails" 1 "$dir"

dir=$(scratch)
printf 'no table here\n' > "$dir/repo/skills/frontend-design-pipeline/SKILL.md"
expect "table with no skills fails" 1 "$dir"

dir=$(scratch)
git -C "$dir/upstream" checkout -qb pinned
printf 'pinned skill\n' > "$dir/upstream/skills/other/SKILL.md"
git -C "$dir/upstream" -c user.name=t -c user.email=t@t commit -qam pinned
git -C "$dir/upstream" checkout -q -
cp "$dir/upstream/skills/demo/SKILL.md" "$dir/installed/demo/SKILL.md"
printf 'pinned skill\n' > "$dir/installed/other/SKILL.md"
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["skills"]["other"]["ref"]="pinned"; json.dump(d,open(p,"w"))' "$dir/lock.json"
expect "pinned skill is compared at its ref" 0 "$dir"

[ "$failures" = 0 ]
