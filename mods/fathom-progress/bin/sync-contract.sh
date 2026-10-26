#!/usr/bin/env bash
# sync-contract.sh - copy the Fathom formats the band reads, as the Fathom skills
# state them, into hooks/contract.fixtures.ts, where contract.test.ts parses them.
# A test cannot read a file from disk, so the formats travel as a module.
# skills/fathom-shared/progress.md lists what is copied.
#
#   bash mods/fathom-progress/bin/sync-contract.sh
#
# CI runs it and fails when the module it writes differs from the committed one.
# Fails when a format it copies is missing from the skill files.
# Requires python3 (ships with macOS).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

python3 - "$ROOT" <<'PY'
import json, os, re, sys

root = sys.argv[1]
shared = os.path.join(root, 'skills', 'fathom-shared')

def read(*parts):
    return open(os.path.join(root, *parts), encoding='utf-8').read()

def die(message):
    print('sync-contract: %s' % message, file=sys.stderr)
    sys.exit(1)

def section(text, heading):
    match = re.search(r'^%s\n(.*?)(?=^## |\Z)' % re.escape(heading), text, re.S | re.M)
    if not match:
        die('no "%s" section' % heading)
    return match.group(1)

def spans(text):
    return re.findall(r'`([^`\n]+)`', text)

# A whole line has a label and a value; a bare `- Review:` in prose names the label only.
plan = []
for s in spans(section(read('skills', 'fathom-shared', 'conventions.md'), '## The plan document')):
    if s.startswith(('# ', '- ')) and ': ' in s and s not in plan:
        plan.append(s)
if not plan:
    die('conventions.md states no plan document lines')

# The example holds ## headings of its own, so it is the first fence after the heading.
block = re.search(r'^## File format\n+```markdown\n(.*?)^```', read('skills', 'fathom-shared', 'memory', 'checklist.md'), re.S | re.M)
if not block:
    die('memory/checklist.md has no example checklist')
checklist = block.group(1)

beads = [s for s in spans(read('skills', 'fathom-shared', 'memory', 'beads.md')) if s.startswith('bd create ')]
if not beads:
    die('memory/beads.md states no bd create commands')

marketplace = json.load(open(os.path.join(root, '.claude-plugin', 'marketplace.json')))
skills = []
for wanted in ('execute', 'scaffold'):
    owners = [p for p in marketplace.get('plugins', []) if './skills/%s' % wanted in (p.get('skills') or [])]
    if len(owners) != 1:
        die('no single plugin claims ./skills/%s' % wanted)
    name = re.search(r'^name:[ \t]*(\S+)', read('skills', wanted, 'SKILL.md'), re.M)
    if not name:
        die('skills/%s/SKILL.md has no name' % wanted)
    skills.append('%s:%s' % (owners[0]['name'], name.group(1)))

def lines(values):
    return '[\n' + ''.join('  %s,\n' % json.dumps(v, ensure_ascii=False) for v in values) + ']'

out = os.path.join(root, 'mods', 'fathom-progress', 'hooks', 'contract.fixtures.ts')
open(out, 'w', encoding='utf-8').write(
    '// Written by mods/fathom-progress/bin/sync-contract.sh from the Fathom skills. Do not edit:\n'
    '// run the script again.\n'
    '\n'
    '// The plan document lines conventions.md states, placeholders included.\n'
    'export const planLines: readonly string[] = %s\n'
    '\n'
    '// The example checklist in memory/checklist.md.\n'
    'export const checklistExample = %s\n'
    '\n'
    '// The bd create commands memory/beads.md states, placeholders included.\n'
    'export const beadsCreates: readonly string[] = %s\n'
    '\n'
    '// The Skill tool names of the Fathom skills the band arms on.\n'
    'export const skillNames: readonly string[] = %s\n'
    % (lines(plan), json.dumps(checklist, ensure_ascii=False), lines(beads), lines(skills))
)
PY
