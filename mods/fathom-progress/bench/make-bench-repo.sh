#!/usr/bin/env bash
# Makes a scratch git repo for testing Fathom and fathom-progress without Beads: a bare
# `origin`, a working copy on `main` with a Fathom profile already committed (so Fathom
# asks no first-run questions), and a tiny test that costs a model nothing to satisfy.
#
#   bash scripts/bench/make-bench-repo.sh [dir] [--destination "<default-destination line>"]
#        [--config-from <path to a .fathom/config.md>]
#
# dir      must not exist or be empty, and must be outside this repository. The default is
#          a new mktemp folder, which the OS reaps. Nothing is ever deleted.
# --destination / --config-from
#          where the profile's default-destination and state-mapping come from. The default
#          copies them from this repository's .fathom/config.md.
#
# The last line printed is the working folder, so `WORK=$(... | tail -n 1)` works.
set -euo pipefail
PROG=make-bench-repo
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DIR="" DEST="" CONFIG_FROM="$BENCH_ROOT/.fathom/config.md"
while [ $# -gt 0 ]; do
  case "$1" in
    --destination) DEST="$2"; shift 2 ;;
    --config-from) CONFIG_FROM="$2"; shift 2 ;;
    -h | --help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown argument: $1" ;;
    *) DIR="$1"; shift ;;
  esac
done

command -v git > /dev/null || die "git is not installed"
if [ -z "$DIR" ]; then DIR="$(mktemp -d "${TMPDIR:-/tmp}/fathom-bench.XXXXXX")"; fi
mkdir -p "$DIR"
DIR="$(cd "$DIR" && pwd -P)"
case "$DIR/" in "$BENCH_ROOT"/*) die "$DIR is inside $BENCH_ROOT" ;; esac
[ -z "$(ls -A "$DIR")" ] || die "$DIR is not empty"

# The profile's destination and state mapping come from a real profile, since they name this
# workspace's tracker. Everything else is fixed for the bench.
if [ -z "$DEST" ]; then
  [ -f "$CONFIG_FROM" ] || die "no $CONFIG_FROM to take the destination from; pass --destination"
  DEST="$(grep '^default-destination:' "$CONFIG_FROM" | head -n 1 || true)"
  [ -n "$DEST" ] || die "$CONFIG_FROM has no default-destination line; pass --destination"
fi
case "$DEST" in default-destination:*) ;; *) DEST="default-destination: $DEST" ;; esac
MAPPING=""
if [ -f "$CONFIG_FROM" ]; then MAPPING="$(awk '/^state-mapping:/{p=1} p' "$CONFIG_FROM")"; fi
if [ -z "$MAPPING" ]; then
  MAPPING='state-mapping:
  inProgress: "In Progress"
  inReview: "In Review"
  done: "Done"'
fi

ORIGIN="$DIR/origin.git"
WORK="$DIR/work"
git init -q --bare -b main "$ORIGIN"
git init -q -b main "$WORK"
cd "$WORK"
git config user.name "Fathom Bench"
git config user.email "bench@example.com"

mkdir -p .fathom bench test
{
  echo "# fathom tracker profile"
  echo "tracker: linear"
  echo "forge: none   # manual tier: no review can be observed, so closing an issue is a manual step"
  echo "$DEST"
  echo "base-branch: main"
  echo "approval: auto"
  echo "merge-closer: none (forge has no hooks)"
  echo "$MAPPING"
} > .fathom/config.md

cat > README.md << 'EOF'
# fathom-bench

A scratch repository for testing Fathom and the fathom-progress band without Beads.
Fathom's tasks here create `bench/<name>.txt` containing the single line `<name>`.
`npm test` passes for any set of those files, so a task never needs to write a test.
EOF
cat > package.json << 'EOF'
{
  "name": "fathom-bench",
  "private": true,
  "type": "module",
  "scripts": { "test": "node --test" }
}
EOF
cat > test/bench.test.js << 'EOF'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, readdirSync, readFileSync } from 'node:fs'

const dir = new URL('../bench/', import.meta.url)

test('the bench folder exists', () => {
  assert.ok(existsSync(dir))
})

for (const file of readdirSync(dir).filter(f => f.endsWith('.txt'))) {
  test(`bench/${file} holds its own name`, () => {
    assert.equal(readFileSync(new URL(file, dir), 'utf8'), `${file.slice(0, -4)}\n`)
  })
}
EOF
touch bench/.gitkeep
printf '.DS_Store\n' > .gitignore

git add .fathom/config.md README.md package.json test/bench.test.js bench/.gitkeep .gitignore
git commit -q -m "chore: seed the fathom bench"
git remote add origin "$ORIGIN"
git push -q -u origin main

# The backend Fathom picks depends on whether the base branch tracks beads.
if git cat-file -e origin/main:.beads/metadata.json 2> /dev/null; then
  die "origin/main tracks .beads/metadata.json, so Fathom would use beads here"
fi
if command -v node > /dev/null; then
  node --test > /dev/null 2>&1 || die "the bench's own test fails; run 'node --test' in $WORK"
  tests="its test passes"
else
  tests="node is not installed, so its test was not run"
fi

echo "bench repo ready in $DIR"
echo "  origin: $ORIGIN"
echo "  base branch main does not track .beads/, so Fathom will use the checklist backend; $tests"
echo "$WORK"
