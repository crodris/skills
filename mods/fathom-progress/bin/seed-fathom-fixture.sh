#!/usr/bin/env bash
# Drives one Fathom run through a scratch beads repo with the commands the beads
# adapter runs (fathom 2.2.0, skills/execute/memory/beads.md), and writes what
# bd prints at each stage to mods/fathom-progress/hooks/fixtures.ts.
#
# Run it with bash, no chmod needed:
#   bash mods/fathom-progress/bin/seed-fathom-fixture.sh [scratch-dir] [out-file]
#
# The scratch repo is never this one. The script refuses a scratch dir inside this
# repo or one that is not empty, and checks that bd resolves to the scratch repo
# before it writes anything. It deletes nothing: the default scratch dir is a fresh
# mktemp dir that the OS reaps.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
SCRATCH="${1:-$(mktemp -d "${TMPDIR:-/tmp}/fathom-fixture.XXXXXX")}"
OUT="${2:-$ROOT/mods/fathom-progress/hooks/fixtures.ts}"

die() { echo "seed-fathom-fixture: $*" >&2; exit 1; }

mkdir -p "$SCRATCH"
SCRATCH="$(cd "$SCRATCH" && pwd -P)"
case "$SCRATCH/" in "$ROOT"/*) die "$SCRATCH is inside $ROOT" ;; esac
[ -z "$(ls -A "$SCRATCH")" ] || die "$SCRATCH is not empty"

# A fixed actor and git identity, so the captured owner and created_by fields do
# not carry whoever ran this.
unset BEADS_DIR BEADS_DB
export BD_NON_INTERACTIVE=1 BEADS_ACTOR=fixture
cd "$SCRATCH"
git init -q .
git config user.name Fixture
git config user.email fixture@example.com

# The adapter's init skips git hooks and takes a short prefix. On bd 1.1.0 the
# prefix is the -p flag; a positional argument is ignored.
bd init -p fx --skip-hooks --skip-agents --non-interactive -q >/dev/null
export BEADS_DIR="$SCRATCH/.beads"
[ "$(bd where | head -n 1)" = "$BEADS_DIR" ] || die "bd resolves to $(bd where | head -n 1), not $BEADS_DIR"

CAP="$SCRATCH/captured"
mkdir "$CAP"
STAGES=()

# What the mod will read at a stage. `epics` is unscoped because the mod does not
# know the issue ref until it has picked the run; the rest are scoped to the ref,
# like the adapter's claimNext and status. Closed issues are hidden by default, so
# the task and epic lists ask for all of them.
snap() { # stage ref
  local stage="$1" ref="$2"
  bd list --type epic --all --limit 0 --json >"$CAP/$stage.epics.json"
  bd list -l "$ref" --type task --all --limit 0 --json >"$CAP/$stage.tasks.json"
  bd ready -l "$ref" --type task --limit 50 --json >"$CAP/$stage.ready.json"
  bd count -l "$ref" --type task --by-status --json >"$CAP/$stage.counts.json"
  bd list -l "$ref" --type task --status in_progress --limit 1 --json >"$CAP/$stage.inProgress.json"
  STAGES+=("$stage")
}

# A command that may fail: keeps its stdout, stderr and exit code as they came.
raw() { # name command...
  local name="$1"
  shift
  set +e
  "$@" >"$CAP/$name.out" 2>"$CAP/$name.err"
  echo $? >"$CAP/$name.code"
  set -e
}

new_epic() { # ref
  bd create "$1" --type epic --external-ref "$1" -l "$1" -p 1 --silent
}

new_task() { # ref title description sub-ref blocker-id-or-empty
  local args=("$1: $2" -d "$3" -l "$1" --external-ref "$4" --silent)
  if [ -n "${5:-}" ]; then args+=(--deps "$5"); fi
  bd create "${args[@]}"
}

work() { # id: claim it, then close it, as the execute loop does
  bd update "$1" --claim >/dev/null
  bd close "$1" >/dev/null
}

REF=SLU-123
TITLES=("Draft the plan doc" "Capture the fixtures" "Wire the lifecycle hooks" "Draw the executing view" "Verify in a live session")

snap idle "$REF"

EPIC="$(new_epic "$REF")"
snap epicOnly "$REF"

IDS=()
for i in 0 1 2 3 4; do
  blocker=""
  if [ "$i" -gt 0 ]; then blocker="${IDS[$((i - 1))]}"; fi
  IDS+=("$(new_task "$REF" "${TITLES[$i]}" "Sub-task $((i + 1)) of 5." "$REF-$((i + 1))" "$blocker")")
  case "$i" in
    0) snap created1 "$REF" ;;
    2) snap created3 "$REF" ;;
    4) snap created5 "$REF" ;;
  esac
done

# The adapter's last creation step: one edge per child, parent depends on child.
# bd 1.1.0 refuses it ("epics can only block other epics, not tasks"), so the
# failure is captured as it is and the run goes on without the edges.
raw epicEdge bd dep add "$EPIC" "${IDS[0]}"
for id in "${IDS[@]:1}"; do bd dep add "$EPIC" "$id" >/dev/null 2>&1 || true; done
snap nextReady "$REF"

bd update "${IDS[0]}" --claim >/dev/null
snap claimedFirst "$REF"

work_done="${IDS[0]}"
bd close "$work_done" >/dev/null
work "${IDS[1]}"
bd update "${IDS[2]}" --claim >/dev/null
snap claimedThird "$REF"

bd close "${IDS[2]}" >/dev/null
work "${IDS[3]}"
work "${IDS[4]}"
snap allClosed "$REF"

bd close "$EPIC" >/dev/null
snap finished "$REF"

# A second run starts while the first one's epic is still listed.
REF2=SLU-124
EPIC2="$(new_epic "$REF2")"
SECOND_FIRST="$(new_task "$REF2" "Add the retry" "Sub-task 1 of 2." "$REF2-1" "")"
new_task "$REF2" "Document the retry" "Sub-task 2 of 2." "$REF2-2" "$SECOND_FIRST" >/dev/null
snap stacked "$REF2"

# What bd does when it cannot answer, and what the human output looks like.
EMPTY="$(mktemp -d "${TMPDIR:-/tmp}/fathom-fixture-empty.XXXXXX")"
raw noWorkspace env -u BEADS_DIR bash -c 'cd "$1" && bd list --json' _ "$EMPTY"
raw notJson bd list -l "$REF" --type task --all

# Write the file.
emit_stage() { # stage
  printf 'export const %s = {\n' "$1"
  for key in epics tasks ready counts inProgress; do
    printf '  %s: ' "$key"
    jq -S --indent 2 . "$CAP/$1.$key.json" | sed -e '1!s/^/  /' -e '$s/$/,/'
  done
  printf '} as const\n\n'
}

emit_run() { # name
  printf 'export const %s: Run = {\n  exitCode: %s,\n  stdout: %s,\n  stderr: %s,\n}\n\n' \
    "$1" "$(cat "$CAP/$1.code")" "$(jq -Rs . <"$CAP/$1.out")" "$(jq -Rs . <"$CAP/$1.err")"
}

{
  echo "// Captured from $(bd version | head -n 1) by mods/fathom-progress/bin/seed-fathom-fixture.sh. Do not edit:"
  echo "// run the script again. Real bd output, so ids and times differ between runs; the"
  echo "// tests lean on the shape, not on the values."
  echo "//"
  echo "// One Fathom run (SLU-123, five chained tasks) at each stage, then a second run"
  echo "// (SLU-124) started while the first one's epic is still listed. Each stage holds what"
  echo "// the mod reads: every epic, then the run's tasks, its ready tasks, its counts by"
  echo "// status and its in-progress task."
  echo
  echo "import type { Run } from './bd'"
  echo
  for stage in "${STAGES[@]}"; do emit_stage "$stage"; done
  echo "// The adapter's parent edge, which bd 1.1.0 refuses."
  emit_run epicEdge
  echo "// bd run where no .beads directory is reachable. The error is on stderr even with --json."
  emit_run noWorkspace
  echo "// The human output, for a caller that forgot --json."
  emit_run notJson
} >"$SCRATCH/fixtures.ts"

cp "$SCRATCH/fixtures.ts" "$OUT"
echo "wrote $OUT ($(wc -c <"$OUT" | tr -d ' ') bytes) from $SCRATCH"
