#!/usr/bin/env bash
# release-watch.sh - wait for every GitHub Actions run on the base branch at
# one commit, such as the commit a merge put at the base's tip, and exit with a
# code that says how they ended.
#
# usage: release-watch.sh <commit-sha> --repo <owner/name> --base <branch>
#          [--deadline <seconds, default 540>] [--start-timeout <seconds, default 300>]
#          [--interval <seconds, default 15>] [--settle <seconds, default 30>]
#
# A run that concluded success, skipped, or neutral passed. --deadline bounds
# one call, so a caller whose tool times out calls again on exit 4.
# --start-timeout bounds the wait for the first run to appear.
# --settle holds a passed or failed verdict until that many seconds have passed
# since the start, and keeps polling until then.
#
# | Exit | Meaning                                                     |
# | ---- | ----------------------------------------------------------- |
# | 0    | every run passed; prints each run's name                    |
# | 1    | a run finished and failed; prints each failed run's name    |
# | 2    | usage error, or gh or jq missing                            |
# | 3    | no run appeared on the commit within --start-timeout        |
# | 4    | deadline passed with runs still going, or with no run yet   |
# | 5    | forge error: 3 consecutive failed listings; prints the text |
set -euo pipefail

finish() {
  echo "verdict: $1: $2"
  case $1 in
    passed) exit 0 ;;
    failed) exit 1 ;;
    usage) exit 2 ;;
    no-run) exit 3 ;;
    deadline) exit 4 ;;
    forge) exit 5 ;;
  esac
}

{ command -v gh && command -v jq; } >/dev/null || finish usage "release-watch.sh needs gh and jq on PATH"

sha='' repo='' base='' deadline=540 start_timeout=300 interval=15 settle=30
while [ $# -gt 0 ]; do
  case $1 in
    --repo | --base | --deadline | --start-timeout | --interval | --settle)
      [ $# -ge 2 ] || finish usage "$1 needs a value"
      case $1 in
        --repo) repo=$2 ;;
        --base) base=$2 ;;
        --deadline) deadline=$2 ;;
        --start-timeout) start_timeout=$2 ;;
        --interval) interval=$2 ;;
        --settle) settle=$2 ;;
      esac
      shift 2
      ;;
    -*) finish usage "unknown option $1" ;;
    *)
      [ -z "$sha" ] || finish usage "unexpected argument $1"
      sha=$1
      shift
      ;;
  esac
done

[[ $sha =~ ^[0-9a-f]{40}$ ]] || finish usage "commit-sha must be a full 40-hex SHA"
[[ $repo =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || finish usage "--repo <owner/name> is required"
git check-ref-format --branch "$base" >/dev/null 2>&1 || finish usage "--base <branch> is required"
for n in "$deadline" "$start_timeout" "$interval" "$settle"; do [[ $n =~ ^[0-9]+$ ]] || finish usage "times must be whole seconds"; done

errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT
start=$SECONDS failures=0 shown='' summary='{"going": []}'
while :; do
  if runs=$(gh run list --repo "$repo" --branch "$base" --commit "$sha" --limit 100 \
    --json name,status,conclusion 2>"$errfile"); then
    failures=0
    summary=$(jq -c '{
      total: length,
      going: [.[] | select(.status != "completed") | .name],
      failed: [.[] | select(.status == "completed" and (.conclusion | IN("success", "skipped", "neutral") | not)) | .name],
      names: [.[].name]}' <<<"$runs")
    line=$(jq -r '"runs \(.total), still going \(.going | length), failed \(.failed | length)"' <<<"$summary")
    [ "$line" = "$shown" ] || { echo "$line"; shown=$line; }
    if [ "$(jq .total <<<"$summary")" = 0 ]; then
      [ $((SECONDS - start)) -lt "$start_timeout" ] || finish no-run "no run on $base at $sha within ${start_timeout}s"
    elif [ "$(jq '.going | length' <<<"$summary")" = 0 ] && [ $((SECONDS - start)) -ge "$settle" ]; then
      [ "$(jq '.failed | length' <<<"$summary")" = 0 ] || finish failed "$(jq -r '.failed | join(", ")' <<<"$summary")"
      finish passed "$(jq -r '.names | join(", ")' <<<"$summary")"
    fi
  else
    failures=$((failures + 1))
    echo "listing failed ($failures of 3): $(tr '\n' ' ' <"$errfile")" >&2
    [ "$failures" -lt 3 ] || finish forge "$(tr '\n' ' ' <"$errfile")"
  fi
  if [ $((SECONDS - start)) -ge "$deadline" ]; then
    if [ "$(jq '.total // 0' <<<"$summary")" = 0 ]; then
      finish deadline "no run yet"
    fi
    finish deadline "still going: $(jq -r '.going | join(", ")' <<<"$summary")"
  fi
  sleep "$interval"
done
