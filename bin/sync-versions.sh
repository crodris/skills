#!/usr/bin/env bash
# sync-versions.sh — marketplace.json is the source of truth for plugin
# versions; this syncs those versions into README.md and checks that every
# skill directory is claimed by exactly one plugin entry.
#
# The repo hosts several plugins out of one marketplace root (source "./"),
# so each entry scopes itself with a "skills" array instead of relying on the
# default skills/ scan. There is deliberately no .claude-plugin/plugin.json:
# with source "./" a single root manifest would apply to every entry and its
# version would silently win over each entry's own.
#
# Compatible with Bash 3.2 (macOS default) and BSD sed.
# Requires python3 for JSON parsing (ships with macOS).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
README="$REPO_ROOT/README.md"

if [ ! -f "$MARKETPLACE" ]; then
  echo "No marketplace manifest found at $MARKETPLACE" >&2
  exit 1
fi

changed=0
problems=0

# --- Update README.md from marketplace.json ---

while IFS='	' read -r name version; do
  [ -n "$name" ] || continue

  if [ -z "$version" ]; then
    echo "  WARNING: plugin '$name' has no version in marketplace.json"
    problems=$((problems + 1))
    continue
  fi

  if grep -q "^### $name (v$version)" "$README"; then
    echo "  README.md: $name already at v$version"
  elif grep -q "^### $name (v" "$README"; then
    echo "  README.md: $name -> v$version"
    sed -i '' "s/^### $name (v[^)]*)/### $name (v$version)/" "$README"
    changed=1
  else
    echo "  WARNING: README.md has no section header for '$name' — add it manually"
    problems=$((problems + 1))
  fi
done < <(python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data.get('plugins', []):
    print('%s\t%s' % (p.get('name', ''), p.get('version', '')))
" < "$MARKETPLACE")

# --- Check every skill directory is claimed by exactly one plugin entry ---
#
# An unclaimed skill installs for nobody: entries that scope themselves with
# "skills" replace the default skills/ scan, so a new directory reaches users
# only once some entry lists it.

claim_report=$(python3 - "$MARKETPLACE" "$REPO_ROOT" "$README" <<'PY'
import json, os, re, sys

marketplace, repo_root, readme = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(marketplace))

# A skill no plugin claims is fine when README.md declares it under
# "## Standalone Skills" (installed via skills.sh, not /plugin install).
# Anything else unclaimed is a directory that reaches nobody.
standalone = set()
text = open(readme).read()
m = re.search(r'^## Standalone Skills\n(.*?)(?=^## |\Z)', text, re.S | re.M)
if m:
    for name in re.findall(r'^### ([\w-]+) \(', m.group(1), re.M):
        standalone.add(os.path.join('skills', name))

claims = {}
for plugin in data.get('plugins', []):
    name = plugin.get('name', '?')
    for path in plugin.get('skills', []) or []:
        claims.setdefault(os.path.normpath(path.lstrip('./')), []).append(name)

skills_dir = os.path.join(repo_root, 'skills')
on_disk = set()
if os.path.isdir(skills_dir):
    for entry in sorted(os.listdir(skills_dir)):
        if os.path.isfile(os.path.join(skills_dir, entry, 'SKILL.md')):
            on_disk.add(os.path.join('skills', entry))

for path in sorted(on_disk - set(claims) - standalone):
    print('unclaimed\t%s' % path)
for path, owners in sorted(claims.items()):
    if path not in on_disk:
        print('missing\t%s\t%s' % (path, ', '.join(owners)))
    elif len(owners) > 1:
        print('shared\t%s\t%s' % (path, ', '.join(owners)))
PY
)

if [ -n "$claim_report" ]; then
  while IFS='	' read -r kind path owners; do
    case "$kind" in
      unclaimed) echo "  WARNING: $path is in no plugin entry's \"skills\" list — it installs for nobody" ;;
      missing)   echo "  WARNING: $path is claimed by $owners but has no SKILL.md on disk" ;;
      shared)    echo "  WARNING: $path is claimed by more than one plugin ($owners)" ;;
    esac
    problems=$((problems + 1))
  done <<< "$claim_report"
else
  echo "  skills/: every skill is claimed by exactly one plugin or declared standalone in README.md"
fi

# --- Summary ---

if [ "$changed" -eq 0 ]; then
  echo "All versions already up to date."
else
  echo "Versions synced."
fi

if [ "$problems" -gt 0 ]; then
  echo "$problems problem(s) need attention." >&2
  exit 1
fi

exit 0
