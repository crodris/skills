#!/usr/bin/env bash
# Plays a timeline into a bench repo one step at a time and checks that the band, read off
# a tmux pane, shows what the step should look like. No model tokens go to the run itself.
#
#   bash mods/fathom-progress/bench/watch-band.sh --bench <work> --target <tmux target>
#        [--timeline chain] [--ref BENCH-1] [--arm] [--timeout 30] [--out <dir>]
#
#   --target     a tmux session or pane running Claude Code in the bench repo
#                (start-session.sh starts one)
#   --arm        first type /fathom:execute <ref> into the pane and press Esc, so the
#                band is armed. Without it, arm the band yourself before running this.
#   --timeout S  how long a step may take to show (default 30; the band polls every 10)
#   --out DIR    where each step's screen is saved (default: a new folder next to the bench)
#   --screens D  test the checks without tmux: read D/step-N.txt for each step
#
# Each step passes when every pattern in the timeline matches the screen; the screen is
# read every 2 seconds until then. It exits 1 if any step fails.
set -euo pipefail
PROG=watch-band
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BENCH="" TARGET="" TIMELINE=chain REF=BENCH-1 ARM=0 TIMEOUT=30 OUT="" SCREENS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bench) BENCH="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --timeline) TIMELINE="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --arm) ARM=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --screens) SCREENS="$2"; shift 2 ;;
    -h | --help) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$BENCH" ] || die "--bench <work folder> is required"
if [ -z "$SCREENS" ]; then
  [ -n "$TARGET" ] || die "--target <tmux target> is required"
  command -v tmux > /dev/null || die "tmux is not installed"
  tmux has-session -t "$TARGET" 2> /dev/null || die "no tmux session or pane '$TARGET'"
fi
check_bench "$BENCH"
load_timeline "$TIMELINE"

if [ -z "$OUT" ]; then OUT="$(dirname "$BENCH_WORK")/out/$(date +%Y%m%d-%H%M%S)-$TIMELINE"; fi
mkdir -p "$OUT"

# Leave no checklist behind from an earlier run, so step 0 starts clean.
bash "$BENCH_DIR/play-checklist.sh" --bench "$BENCH_WORK" --ref "$REF" --clean > /dev/null

if [ "$ARM" -eq 1 ] && [ -z "$SCREENS" ]; then
  tmux send-keys -t "$TARGET" "/fathom:execute $REF" Enter
  sleep 3
  tmux send-keys -t "$TARGET" Escape
  sleep 1
fi

read_screen() { # step number -> file
  local file="$OUT/step-$1.txt"
  if [ -n "$SCREENS" ]; then
    [ -f "$SCREENS/step-$1.txt" ] || die "no $SCREENS/step-$1.txt"
    cp "$SCREENS/step-$1.txt" "$file"
  else
    tmux capture-pane -p -t "$TARGET" > "$file"
  fi
}

# Sets MISSING to the patterns that did not hold on the screen file $1.
check_screen() {
  local screen="$1" patterns="$2" p
  MISSING=""
  patterns="${patterns// ~~ /$'\n'}"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "${p:0:1}" = "!" ]; then
      if grep -Eq -- "${p:1}" "$screen"; then MISSING="$MISSING [should not match] ${p:1};"; fi
    else
      if ! grep -Eq -- "$p" "$screen"; then MISSING="$MISSING [no match] $p;"; fi
    fi
  done <<< "$patterns"
}

failed=0
i=0
while [ "$i" -lt "$TL_N" ]; do
  step="${TL_STEP[$i]}"
  bash "$BENCH_DIR/play-checklist.sh" --bench "$BENCH_WORK" --timeline "$TL_FILE" --ref "$REF" --step "$step" > /dev/null
  start=$SECONDS
  while :; do
    read_screen "$step"
    check_screen "$OUT/step-$step.txt" "${TL_EXPECT[$i]//\{ref\}/$REF}"
    if [ -z "$MISSING" ]; then
      echo "PASS step $step after $((SECONDS - start))s: tasks '${TL_TASKS[$i]}'"
      break
    fi
    if [ -n "$SCREENS" ] || [ $((SECONDS - start)) -ge "$TIMEOUT" ]; then
      echo "FAIL step $step after $((SECONDS - start))s: tasks '${TL_TASKS[$i]}'$MISSING"
      echo "     screen saved in $OUT/step-$step.txt"
      failed=$((failed + 1))
      break
    fi
    sleep 2
  done
  i=$((i + 1))
done

bash "$BENCH_DIR/play-checklist.sh" --bench "$BENCH_WORK" --ref "$REF" --clean > /dev/null
if [ "$failed" -gt 0 ]; then
  echo "$failed of $TL_N steps failed. Screens: $OUT"
  exit 1
fi
echo "all $TL_N steps passed. Screens: $OUT"
