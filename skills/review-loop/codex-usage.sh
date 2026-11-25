#!/usr/bin/env bash
# codex-usage.sh - print the token use and Codex plan usage of the Codex
# session that ran in one worktree, such as a review-loop `sol` reviewer's
# delegate_task worktree.
#
# usage: codex-usage.sh <worktree-path>
#
# Reads Codex's own session logs under $CODEX_HOME (default ~/.codex), in
# sessions/ and archived_sessions/. A log belongs to the worktree when its first
# line is a session_meta record whose cwd equals <worktree-path>, with a trailing
# slash ignored. With several, the one whose file name sorts last wins, since
# Codex names each log rollout-<start time>-<id>.jsonl. Prints one line from
# that log's last token_count event that carries a numeric token total:
#
#   tokens=<total> 5h=<percent>% week=<percent>%
#
# Each rate-limit window is labeled by its length: 5h for 300 minutes, week for
# 10080 minutes, and <minutes>m for any other. A window with no numeric percent
# or no numeric length is left out, so a log with no rate limits prints
# tokens=<total> alone. A line that is not JSON, or an event whose fields have
# the wrong type, is skipped. The percents are read when the session ended, so
# other Codex sessions running at the same time count toward them too.
#
# | Exit | Meaning                                                        |
# | ---- | -------------------------------------------------------------- |
# | 0    | printed the usage line                                         |
# | 1    | no log for that worktree, or no usable token_count event in it |
# | 2    | usage error, or jq missing                                     |
set -euo pipefail

[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: codex-usage.sh <worktree-path>" >&2; exit 2; }
command -v jq >/dev/null || { echo "codex-usage.sh: jq is required" >&2; exit 2; }
want=${1%/}
home=${CODEX_HOME:-$HOME/.codex}

matches=""
while IFS= read -r -d '' log; do
  cwd=$({ head -n 1 "$log" | jq -R -r 'try (fromjson | select(.type == "session_meta") | .payload.cwd | strings) catch empty'; } 2>/dev/null) || continue
  [ "${cwd%/}" = "$want" ] || continue
  matches+="$(basename "$log")"$'\t'"$log"$'\n'
done < <(find "$home/sessions" "$home/archived_sessions" -name 'rollout-*.jsonl' -type f -print0 2>/dev/null || true)

[ -n "$matches" ] || { echo "codex-usage.sh: no Codex session log for that worktree" >&2; exit 1; }
newest=$(printf '%s' "$matches" | LC_ALL=C sort | tail -n 1 | cut -f 2)

line=$(jq -R -r '
  def window: if .window_minutes == 300 then "5h" elif .window_minutes == 10080 then "week" else "\(.window_minutes)m" end;
  try (
    fromjson
    | select(.type == "event_msg" and .payload.type == "token_count")
    | select((.payload.info.total_token_usage.total_tokens | type) == "number")
    | "tokens=\(.payload.info.total_token_usage.total_tokens)"
      + ([(.payload.rate_limits | objects) | .primary, .secondary
          | objects | select((.used_percent | type) == "number" and (.window_minutes | type) == "number")
          | " \(window)=\(.used_percent)%"] | join(""))
  ) catch empty' "$newest" 2>/dev/null | tail -n 1)

# Only digits, labels, and percents reach the caller, whatever a log holds.
[[ $line =~ ^tokens=[0-9]+(\ [0-9a-z]+=[0-9.]+%)*$ ]] || {
  echo "codex-usage.sh: no usable token_count in the matched log" >&2
  exit 1
}
printf '%s\n' "$line"
