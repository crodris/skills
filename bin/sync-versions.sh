#!/usr/bin/env bash
# sync-versions.sh - marketplace.json is the source of truth for plugin
# versions; this syncs those versions into README.md, into the SKILL.md
# frontmatter of each skill the plugin claims, and into the plugin.json of a
# plugin with its own source folder, and checks that every skill directory is
# claimed by exactly one plugin entry, so each skill installs from the
# marketplace, including in Claude Code cloud sessions.
#
# Several plugins share one source folder (source "./skills"), so each entry
# scopes itself with a "skills" array, whose paths are relative to its source.
# The shared folder is skills/ and not the repo root, because the claude.ai
# marketplace sync rejects a plugin folder that holds another plugin's
# .claude-plugin/plugin.json, such as a mod's under mods/. There is
# deliberately no skills/.claude-plugin/plugin.json: a manifest in a shared
# source folder would apply to every entry and its version would silently win
# over each entry's own.
#
# Compatible with Bash 3.2 (macOS default).
# Requires python3 for JSON parsing and the file edits (ships with macOS).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
README="$REPO_ROOT/README.md"

if [ ! -f "$MARKETPLACE" ]; then
  echo "No marketplace manifest found at $MARKETPLACE" >&2
  exit 1
fi

if [ ! -f "$README" ]; then
  echo "No README found at $README" >&2
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
    python3 - "$README" "$name" "$version" <<'PY'
import re, sys
path, name, version = sys.argv[1:]
text = open(path).read()
open(path, 'w').write(re.sub(r'^### %s \(v[^)]*\)' % re.escape(name), '### %s (v%s)' % (name, version), text, flags=re.M))
PY
    changed=1
  else
    echo "  WARNING: README.md has no section header for '$name' - add it manually"
    problems=$((problems + 1))
  fi
done < <(python3 -c "
import json, sys
data = json.load(sys.stdin)
for p in data.get('plugins', []):
    print('%s\t%s' % (p.get('name', ''), p.get('version', '')))
" < "$MARKETPLACE")

# --- Sync SKILL.md frontmatter and plugin.json versions ---
#
# A plugin skill's frontmatter takes its plugin's version from marketplace.json.
# A plugin with its own source folder, such as a mod under mods/, keeps a
# plugin.json there, and its "version" takes the marketplace version too.

skill_report=$(python3 - "$MARKETPLACE" "$REPO_ROOT" <<'PY'
import json, os, re, sys

marketplace, repo_root = sys.argv[1], sys.argv[2]
data = json.load(open(marketplace))
VERSION = re.compile(r'^version:[ \t]*(\S*)[ \t]*$', re.M)

def frontmatter(text):
    return re.match(r'---\n(.*?\n)---\n', text, re.S)

MANIFEST_VERSION = re.compile(r'("version"[ \t]*:[ \t]*")([^"]*)(")')

for plugin in data.get('plugins', []):
    version = plugin.get('version')
    if not version:
        continue
    source = plugin.get('source')
    if isinstance(source, str):
        manifest = os.path.join(repo_root, os.path.normpath(source), '.claude-plugin', 'plugin.json')
        if os.path.isfile(manifest):
            text = open(manifest).read()
            found = MANIFEST_VERSION.search(text)
            if not found:
                print('nomanifestversion\t%s' % os.path.relpath(manifest, repo_root))
            elif found.group(2) != version:
                open(manifest, 'w').write(text[:found.start(2)] + version + text[found.end(2):])
                print('synced\t%s\t%s' % (os.path.relpath(manifest, repo_root), version))
    for path in plugin.get('skills', []) or []:
        skill_md = os.path.join(repo_root, os.path.normpath(os.path.join(source if isinstance(source, str) else '.', path)), 'SKILL.md')
        if not os.path.isfile(skill_md):
            continue
        text = open(skill_md).read()
        fm = frontmatter(text)
        found = fm and VERSION.search(fm.group(1))
        if not found:
            print('noversion\t%s' % os.path.relpath(skill_md, repo_root))
        elif found.group(1) != version:
            start = fm.start(1) + found.start(1)
            open(skill_md, 'w').write(text[:start] + version + text[fm.start(1) + found.end(1):])
            print('synced\t%s\t%s' % (os.path.relpath(skill_md, repo_root), version))
PY
)

if [ -n "$skill_report" ]; then
  while IFS='	' read -r kind path version; do
    case "$kind" in
      synced)    echo "  $path -> version $version"; changed=1 ;;
      noversion) echo "  WARNING: $path has no version: line in its frontmatter"; problems=$((problems + 1)) ;;
      nomanifestversion) echo "  WARNING: $path has no \"version\" field"; problems=$((problems + 1)) ;;
    esac
  done <<< "$skill_report"
fi

# --- Check every skill directory is claimed by exactly one plugin entry ---
#
# An unclaimed skill never reaches the plugin marketplace, so Claude Code
# cloud sessions, which skip skills.sh installs, cannot install it from there.

claim_report=$(python3 - "$MARKETPLACE" "$REPO_ROOT" <<'PY'
import json, os, sys

marketplace, repo_root = sys.argv[1], sys.argv[2]
data = json.load(open(marketplace))

claims = {}
for plugin in data.get('plugins', []):
    name = plugin.get('name', '?')
    source = plugin.get('source')
    for path in plugin.get('skills', []) or []:
        claims.setdefault(os.path.normpath(os.path.join(source if isinstance(source, str) else '.', path)), []).append(name)

skills_dir = os.path.join(repo_root, 'skills')
on_disk = set()
if os.path.isdir(skills_dir):
    for entry in sorted(os.listdir(skills_dir)):
        if os.path.isfile(os.path.join(skills_dir, entry, 'SKILL.md')):
            on_disk.add(os.path.join('skills', entry))

for path in sorted(on_disk - set(claims)):
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
      unclaimed) echo "  WARNING: $path is in no plugin entry's \"skills\" list - add an entry for it to .claude-plugin/marketplace.json" ;;
      missing)   echo "  WARNING: $path is claimed by $owners but has no SKILL.md on disk" ;;
      shared)    echo "  WARNING: $path is claimed by more than one plugin ($owners)" ;;
    esac
    problems=$((problems + 1))
  done <<< "$claim_report"
else
  echo "  skills/: every skill is claimed by exactly one plugin"
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
