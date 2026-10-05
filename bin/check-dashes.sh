#!/usr/bin/env bash
# check-dashes.sh - fail when an em or en dash appears in skills/, bin/, the
# README, CODING_STANDARDS.md, or docs/fathom.md. Write a plain hyphen instead.
# Untracked files count too, so verify catches a new file before it is committed.
#
# docs/plans/ and docs/superpowers/ hold dated records and are not checked.
# Requires python3 for UTF-8 matching (ships with macOS).

set -euo pipefail

cd "$(dirname "$0")/.."

git ls-files -z --cached --others --exclude-standard -- skills bin README.md CODING_STANDARDS.md docs/fathom.md |
  python3 -c '
import sys
hits = 0
for path in sys.stdin.read().split("\0"):
    if not path:
        continue
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except (UnicodeDecodeError, FileNotFoundError):
        continue
    for number, line in enumerate(lines, 1):
        if chr(0x2014) in line or chr(0x2013) in line:
            print(f"{path}:{number}: {line.strip()[:100]}")
            hits += 1
if hits:
    print(f"{hits} line(s) with an em or en dash. Use a plain hyphen instead.", file=sys.stderr)
    sys.exit(1)
'
