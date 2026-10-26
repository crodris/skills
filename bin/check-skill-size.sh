#!/usr/bin/env bash
# check-skill-size.sh - fail when a Markdown file in skills/ has more words than
# its budget in bin/skill-budgets.txt, when it has no budget line, or when a
# budget line names a file that no longer exists. Words are whitespace-separated,
# as Python's str.split() counts them. A path may contain spaces, since the word
# count is the last field on its line.
# Untracked files count too, so verify catches a new file before it is committed.
# Requires python3 (ships with macOS).

set -euo pipefail

cd "$(dirname "$0")/.."

git ls-files -z --cached --others --exclude-standard -- 'skills/*.md' |
  python3 -c '
import sys

budget_file = "bin/skill-budgets.txt"
budgets = {}
problems = []
for number, line in enumerate(open(budget_file, encoding="utf-8"), 1):
    fields = line.split("#", 1)[0].strip().rsplit(None, 1)
    if not fields:
        continue
    if len(fields) != 2 or not fields[1].isdigit():
        problems.append(f"{budget_file}:{number}: expected \"<path> <words>\", got {line.strip()!r}")
        continue
    if fields[0] in budgets:
        problems.append(f"{budget_file}:{number}: {fields[0]} already has a budget. Keep one line per file.")
        continue
    budgets[fields[0]] = int(fields[1])

present = set()
for path in sorted(p for p in sys.stdin.read().split("\0") if p):
    try:
        words = len(open(path, encoding="utf-8").read().split())
    except FileNotFoundError:
        continue
    except UnicodeDecodeError:
        present.add(path)
        problems.append(f"{path}: not valid UTF-8.")
        continue
    present.add(path)
    if path not in budgets:
        problems.append(f"{path}: {words} words and no budget. Add \"{path} {words}\" to {budget_file}.")
    elif words > budgets[path]:
        problems.append(f"{path}: {words} words, over its budget of {budgets[path]}. Cut words, or raise the budget in {budget_file} and say why in the pull request.")

for path in sorted(set(budgets) - present):
    problems.append(f"{budget_file}: {path} has a budget but no file. Remove its line.")

for problem in problems:
    print(problem)
if problems:
    sys.exit(1)
'
