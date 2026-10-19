#!/usr/bin/env bash
# check-pipeline-skills.sh - diff each installed skill that frontend-design-pipeline
# names in its Companion skills table against a fresh clone of the repository the
# skills CLI lock file says it came from, at the branch or tag it records as `ref`. Exits 1 when any skill differs or is missing.
#
# __pycache__ folders are ignored, since running a skill's Python scripts writes them.
# Needs network access. Set SKILL_LOCK and SKILLS_DIR to check another install.

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
lock=${SKILL_LOCK:-$HOME/.agents/.skill-lock.json}
installed=${SKILLS_DIR:-$HOME/.agents/skills}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 -I - "$root/skills/frontend-design-pipeline/SKILL.md" "$lock" > "$work/skills" <<'PY'
import json, os, re, sys

table, lock = sys.argv[1], sys.argv[2]
names = []
for line in open(table, encoding="utf-8"):
    cells = line.split("|")
    if len(cells) > 3 and cells[1].strip().isdigit():
        names += re.findall(r"`([^`\s]+)`", cells[2])
if not names:
    sys.exit(f"No skills found in the Companion skills table of {table}.")
entries = json.load(open(lock, encoding="utf-8")).get("skills", {})
for name in names:
    entry = entries.get(name, {})
    print(name, entry.get("sourceUrl", ""), entry.get("ref") or "", os.path.dirname(entry.get("skillPath", "")), sep="\x1f")
PY

failures=0
# \x1f, since read merges consecutive tabs and an empty ref would shift the fields.
while IFS=$'\x1f' read -r name url ref path; do
  if [ -z "$url" ]; then
    echo "MISSING: $name has no entry in $lock"
    failures=$((failures + 1))
    continue
  fi
  clone="$work/${url//[^A-Za-z0-9]/_}@${ref//[^A-Za-z0-9]/_}"
  [ -d "$clone" ] || git clone -q --depth 1 ${ref:+--branch "$ref"} "$url" "$clone"
  sha=$(git -C "$clone" rev-parse --short HEAD)
  if diff -rq -x __pycache__ -x .git "$clone/$path" "$installed/$name" > "$work/diff" 2>&1; then
    echo "ok: $name matches $url${ref:+#$ref}@$sha"
  else
    echo "DIFFERS: $name from $url${ref:+#$ref}@$sha"
    sed 's/^/  /' "$work/diff"
    failures=$((failures + 1))
  fi
done < "$work/skills"

if [ "$failures" != 0 ]; then
  echo "$failures skill(s) differ from upstream. Update each with: npx skills@latest update <name> -g" >&2
  exit 1
fi
