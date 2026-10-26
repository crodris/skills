#!/usr/bin/env bash
# Starts Claude Code in a detached tmux session inside a bench repo, ready for
# watch-band.sh. It does not type anything into Claude.
#
#   bash scripts/bench/start-session.sh --bench <work> [--session fathom-bench]
#        [--bd real|shim] [--trust] [--width 140] [--height 42] [-- <extra claude args>]
#
#   --bd shim   put a fake bd first on PATH that fails with "command not found" (exit
#               127). Use it to show the band works without Beads. The default is the
#               real bd, which in a bench repo with no .beads/ also errors on every read.
#
# The first time Claude Code opens a folder it asks whether to trust it. Pass --trust to
# answer yes for this bench folder, or attach once with `tmux attach -t <session>`, answer
# it, and detach with ctrl-b d. Stop the session with `tmux kill-session -t <session>`.
#
# The mod must already be installed and on the branch under test (it loads from the
# working tree of whatever marketplace you installed it from); run /reload-plugins in
# the session after switching branches.
set -euo pipefail
PROG=start-session
# shellcheck source=common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BENCH="" SESSION=fathom-bench BD=real WIDTH=140 HEIGHT=42 TRUST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --bench) BENCH="$2"; shift 2 ;;
    --session) SESSION="$2"; shift 2 ;;
    --bd) BD="$2"; shift 2 ;;
    --width) WIDTH="$2"; shift 2 ;;
    --height) HEIGHT="$2"; shift 2 ;;
    --trust) TRUST=1; shift ;;
    --) shift; break ;;
    -h | --help) sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$BENCH" ] || die "--bench <work folder> is required"
case "$BD" in real | shim) ;; *) die "--bd must be real or shim" ;; esac
command -v tmux > /dev/null || die "tmux is not installed"
command -v claude > /dev/null || die "claude is not on PATH"
check_bench "$BENCH"
if tmux has-session -t "$SESSION" 2> /dev/null; then die "tmux session '$SESSION' already exists; kill it or pick another name"; fi

OUT="$(dirname "$BENCH_WORK")/out"
mkdir -p "$OUT"
LOG="$OUT/claude-debug-$SESSION.log"

cmd="claude --debug-file $(printf '%q' "$LOG")"
for arg in "$@"; do cmd="$cmd $(printf '%q' "$arg")"; done
if [ "$BD" = shim ]; then
  SHIM="$OUT/shim-bin"
  mkdir -p "$SHIM"
  printf '#!/bin/sh\necho "bd: command not found" >&2\nexit 127\n' > "$SHIM/bd"
  chmod +x "$SHIM/bd"
  cmd="env PATH=$(printf '%q' "$SHIM:$PATH") $cmd"
fi

tmux new-session -d -s "$SESSION" -x "$WIDTH" -y "$HEIGHT" -c "$BENCH_WORK" "$cmd"

# Claude Code asks once per folder whether to trust it, with "No, exit" selected. --trust
# answers yes for this bench folder only, after checking the dialog is the one it expects.
if [ "$TRUST" -eq 1 ]; then
  waited=0
  until tmux capture-pane -p -t "$SESSION" | grep -q "Quick safety check"; do
    sleep 1
    waited=$((waited + 1))
    if [ "$waited" -ge 30 ]; then
      echo "start-session: no trust dialog after 30s; attach and check ($SESSION)" >&2
      break
    fi
  done
  if [ "$waited" -lt 30 ]; then
    tmux send-keys -t "$SESSION" Down
    sleep 1
    tmux send-keys -t "$SESSION" Enter
    sleep 2
  fi
fi
echo "started tmux session '$SESSION' in $BENCH_WORK (bd: $BD)"
echo "debug log: $LOG"
echo "attach:    tmux attach -t $SESSION"
echo "then:      bash scripts/bench/watch-band.sh --bench $BENCH_WORK --target $SESSION --arm"
