#!/usr/bin/env bash
# Plays a timeline into a bench repo: it rewrites .fathom/tasks/<ref>.md and
# .fathom/plans/<ref>.md step by step, the way a Fathom run on the checklist backend
# would, so the band can be watched with no Fathom run and no model tokens.
#
#   bash mods/fathom-progress/bench/play-checklist.sh --bench <work> [--timeline chain] [--ref BENCH-1]
#        [--step N | --pause 15 | --clean]
#
#   --step N     write step N and stop (watch-band.sh drives it this way)
#   --pause S    write every step, S seconds apart (the default is 15; the band polls
#                every 10)
#   --clean      remove the ref's checklist and plan, and stop
#
# It refuses a folder with no .fathom/config.md and this repository itself.
set -euo pipefail
PROG=play-checklist
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BENCH="" TIMELINE=chain REF=BENCH-1 STEP="" PAUSE=15 CLEAN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --bench) BENCH="$2"; shift 2 ;;
    --timeline) TIMELINE="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --step) STEP="$2"; shift 2 ;;
    --pause) PAUSE="$2"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    -h | --help) sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$BENCH" ] || die "--bench <work folder> is required"
case "$REF" in *[!A-Za-z0-9-]*) die "ref '$REF' must be letters, digits and hyphens" ;; esac
check_bench "$BENCH"

if [ "$CLEAN" -eq 1 ]; then
  rm -f "$BENCH_WORK/.fathom/tasks/$REF.md" "$BENCH_WORK/.fathom/plans/$REF.md"
  echo "removed $REF's checklist and plan"
  exit 0
fi

load_timeline "$TIMELINE"

if [ -n "$STEP" ]; then
  write_step "$BENCH_WORK" "$REF" "$(index_of_step "$STEP")"
  echo "step $STEP of $TL_FILE written for $REF"
  exit 0
fi

i=0
while [ "$i" -lt "$TL_N" ]; do
  write_step "$BENCH_WORK" "$REF" "$i"
  echo "step ${TL_STEP[$i]}: tasks '${TL_TASKS[$i]}', ${TL_PLAN[$i]}, expect: ${TL_EXPECT[$i]}"
  i=$((i + 1))
  if [ "$i" -lt "$TL_N" ]; then sleep "$PAUSE"; fi
done
