#!/usr/bin/env bash
# watch.sh - wait until a pull request's checks and review bots settle on one
# pinned head SHA, with one GraphQL call per poll, and exit with a code that
# says how it ended. Ship's stage 3 runs it instead of a hand-written loop.
#
# usage: watch.sh <pr-number> <head-sha> --repo <owner/name>
#          [--bot coderabbit|greptile]... [--rerequest coderabbit|greptile]...
#          [--deadline <seconds, default 1800>] [--interval <seconds, default 30>]
#
# With no --bot it waits on the checks alone.
# --rerequest <bot> implies --bot <bot> and posts the bot's re-request comment
# once before the first poll; a notice older than that post is then ignored.
#
# | Exit | Meaning                                                              |
# | ---- | -------------------------------------------------------------------- |
# | 0    | settled, every check passed                                          |
# | 1    | settled, one or more checks failed; prints each failed check's name  |
# | 2    | usage error                                                          |
# | 3    | head moved: it is no longer <head-sha>                               |
# | 4    | deadline passed before settling; prints what is still pending        |
# | 5    | forge error: 3 consecutive failed polls; prints the last error text  |
# | 6    | a bot will not review (trial or plan quota notice); prints the notice |
# | 7    | pull request is no longer open (MERGED or CLOSED); prints its state  |
#
# stdout gets a status line on each poll whose status changed, then one verdict
# line. gh's stderr is passed through, never hidden.
# Requires bash, gh, and jq.

# shellcheck disable=SC2016 # jq and GraphQL programs use $ for their own variables.
set -euo pipefail

# A fresh push has no checks registered yet, so an empty rollup settles only after this many seconds.
NO_CHECKS_GRACE=120
MAX_FAILED_POLLS=3

# Every bot rule lives here. login is the GraphQL login, which has no [bot] suffix.
# A bot settles on whichever of status, check_run, or review_on_sha it defines.
BOTS='{
  "coderabbit": {
    "login": "coderabbitai",
    "rerequest": "@coderabbitai review",
    "status": {"context": "CodeRabbit", "settled": "Review completed", "notice": "rate limit(ed)?|Review skipped"}
  },
  "greptile": {
    "login": "greptile-apps",
    "rerequest": "@greptileai",
    "check_run": "Greptile Review",
    "review_on_sha": true
  }
}'

QUERY='query($owner:String!,$repo:String!,$n:Int!,$sha:GitObjectID!){repository(owner:$owner,name:$repo){
 pullRequest(number:$n){state headRefOid
  reviews(last:30){nodes{author{login} commit{oid} submittedAt body}}
  comments(last:30){nodes{author{login} updatedAt body}}}
 object(oid:$sha){... on Commit{committedDate statusCheckRollup{contexts(first:100){nodes{__typename
  ... on CheckRun{name status conclusion}
  ... on StatusContext{context state description createdAt}}}}}}}}'

# Prints the failure text of a response that counts as a failed poll, else nothing.
ERRORS='
if .errors then [.errors[]? | .message // tojson] | join("; ") | if . == "" then "GraphQL errors field" else . end
elif (.data.repository.pullRequest | type) != "object" then "response has no pull request"
else empty end'

# Reduces one GraphQL response to a verdict. Inputs: $sha, $bots (ids in order),
# $registry, $rerequested (bot id -> epoch seconds of this run's re-request),
# and $allow_empty (whether an empty rollup may settle).
REDUCE='
def epoch: sub("\\.[0-9]+"; "") | fromdateiso8601;
def fresh($since): $since == null or (. != null and epoch >= $since);
def author: .author.login // "" | sub("\\[bot\\]$"; "");
# Mirrors checkKind in pr-watch (~/.claude-config/mods/pr-watch/hooks/pr.ts).
def kind:
  if (.state | type) == "string" then
    if .state == "SUCCESS" then "passed"
    elif .state == "PENDING" or .state == "EXPECTED" then "pending"
    else "failed" end
  elif .status != "COMPLETED" then "pending"
  elif .conclusion == "SUCCESS" or .conclusion == "NEUTRAL" or .conclusion == "SKIPPED" then "passed"
  else "failed" end;
# Phrases, never loose words, because review bodies discuss code.
def notice($rerequest):
  if test("reached the [0-9]+-credit limit|trial (has )?(ended|expired)|upgrade (your|to a paid) plan"; "i") then "refused"
  elif test($rerequest; "i") then "rerequest"
  else null end;
def body_notice: notice("rate limit exceeded");

.data.repository as $repo
| $repo.pullRequest as $pr
| ($repo.object.committedDate // null) as $committed
| [$repo.object.statusCheckRollup.contexts.nodes // [] | .[] | . + {kind: kind, label: (.name // .context)}] as $checks
| def bot($b; $since):
    ([$checks[] | select($b.status != null and .context == $b.status.context)] | last) as $status
    | [$pr.reviews.nodes // [] | .[] | select(author == $b.login and .commit.oid == $sha)] as $reviews
    | [$pr.comments.nodes // [] | .[]
       | select(author == $b.login and $committed != null and (.updatedAt | epoch) >= ($committed | epoch))] as $comments
    | [ ($status | select(. != null and (.createdAt | fresh($since)))
         | {kind: (.description // "" | notice($b.status.notice)), text: .description}),
        ($reviews[], $comments[] | select(.submittedAt // .updatedAt | fresh($since))
         | {kind: (.body // "" | body_notice), text: .body})
      | select(.kind != null) ] as $notices
    | ( ($status != null and $status.state == "SUCCESS"
         and ($status.description // "" | contains($b.status.settled)))
        or ($b.check_run != null and any($checks[]; .name == $b.check_run and .status == "COMPLETED"))
        or ($b.review_on_sha == true and any($reviews[]; .body // "" | body_notice == null))
      ) as $settled
    | ([$notices[] | select(.kind == "refused")] | first) as $refused
    | ([$notices[] | select(.kind == "rerequest")] | first) as $rerequest
    | if $refused then {state: "refused", notice: $refused.text}
      elif $settled then {state: "settled"}
      elif $rerequest then {state: "rerequest", notice: $rerequest.text}
      else {state: "pending"} end;
  [$bots[] as $id | {id: $id} + bot($registry[$id]; $rerequested[$id] // null)] as $botstates
| {
    pr: (if $pr.state != "OPEN" then "closed" elif $pr.headRefOid != $sha then "moved" else "open" end),
    state: $pr.state,
    head: $pr.headRefOid,
    checks: {
      passed: ($checks | map(select(.kind == "passed")) | length),
      failed: ($checks | map(select(.kind == "failed")) | length),
      pending: ($checks | map(select(.kind == "pending")) | length),
      failed_names: [$checks[] | select(.kind == "failed") | .label],
      pending_names: [$checks[] | select(.kind == "pending") | .label]
    },
    bots: ($botstates | map({(.id): .state}) | add // {}),
    notices: ($botstates | map(select(.notice != null) | {(.id): .notice}) | add // {})
  }
| .outcome = (
    if .pr != "open" then .pr
    elif any(.bots[]; . == "refused") then "refused"
    elif all(.bots[]; . == "settled") and .checks.pending == 0
         and (.checks.passed + .checks.failed > 0 or $allow_empty)
    then (if .checks.failed > 0 then "failed" else "passed" end)
    else "waiting" end)'

STATUS_LINE='"checks \(.checks.passed) passed \(.checks.failed) failed \(.checks.pending) pending"
  + (.bots | to_entries | map(" | \(.key) \(.value)") | join(""))'

STILL_PENDING='[
  (if .checks.pending > 0 then "checks \(.checks.pending_names | join(", "))"
   elif .checks.passed + .checks.failed == 0 then "no checks registered"
   else empty end),
  (.bots | to_entries[] | select(.value != "settled") | "\(.key) \(.value)")
] | join("; ")'

finish() {
  echo "verdict: $1: $2"
  case $1 in
    passed) exit 0 ;;
    failed) exit 1 ;;
    usage) exit 2 ;;
    moved) exit 3 ;;
    deadline) exit 4 ;;
    forge) exit 5 ;;
    refused) exit 6 ;;
    closed) exit 7 ;;
  esac
}

usage() {
  echo "usage: watch.sh <pr-number> <head-sha> --repo <owner/name> [--bot coderabbit|greptile]... [--rerequest coderabbit|greptile]... [--deadline <seconds>] [--interval <seconds>]" >&2
  echo "  --rerequest <bot> implies --bot <bot> and posts its re-request comment once before the first poll" >&2
  finish usage "$1"
}

add() { jq -c --arg b "$1" 'if any(.[]; . == $b) then . else . + [$b] end'; }

pr='' sha='' repo='' deadline=1800 interval=30 bots='[]' forced='[]'
while [ $# -gt 0 ]; do
  case $1 in
    --repo | --bot | --rerequest | --deadline | --interval)
      [ $# -ge 2 ] || usage "$1 needs a value"
      case $1 in
        --repo) repo=$2 ;;
        --deadline) deadline=$2 ;;
        --interval) interval=$2 ;;
        --bot | --rerequest)
          jq -e --arg b "$2" 'has($b)' <<<"$BOTS" >/dev/null || usage "unknown bot $2"
          bots=$(add "$2" <<<"$bots")
          [ "$1" = --bot ] || forced=$(add "$2" <<<"$forced")
          ;;
      esac
      shift 2
      ;;
    -*) usage "unknown option $1" ;;
    *)
      if [ -z "$pr" ]; then pr=$1; elif [ -z "$sha" ]; then sha=$1; else usage "unexpected argument $1"; fi
      shift
      ;;
  esac
done

[[ $pr =~ ^[1-9][0-9]*$ ]] || usage "pr-number must be a positive integer"
[[ $sha =~ ^[0-9a-f]{40}$ ]] || usage "head-sha must be a full 40-hex SHA"
[[ $repo =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || usage "--repo <owner/name> is required"
[[ $deadline =~ ^[0-9]+$ ]] || usage "--deadline must be whole seconds"
[[ $interval =~ ^[0-9]+$ ]] || usage "--interval must be whole seconds"

errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT

# Sets $verdict on success; sets $error and returns 1 on a failed poll.
poll() {
  local out rc=0 allow_empty=false reduced
  [ $((SECONDS - start)) -lt "$NO_CHECKS_GRACE" ] || allow_empty=true
  out=$(gh api graphql -f query="$QUERY" -f owner="${repo%%/*}" -f repo="${repo#*/}" -F n="$pr" -f sha="$sha" 2>"$errfile") || rc=$?
  if [ "$rc" != 0 ]; then
    error=$(cat "$errfile")
    [ -n "$error" ] || error="gh exited $rc"
    return 1
  fi
  cat "$errfile" >&2
  [ -n "$out" ] || { error="gh returned no output"; return 1; }
  error=$(jq -r "$ERRORS" <<<"$out" 2>&1) || { error="unreadable response: $error"; return 1; }
  [ -z "$error" ] || return 1
  reduced=$(jq -c --arg sha "$sha" --argjson bots "$bots" --argjson registry "$BOTS" \
    --argjson rerequested "$rerequested" --argjson allow_empty "$allow_empty" "$REDUCE" <<<"$out" 2>&1) ||
    { error="unreadable response: $reduced"; return 1; }
  verdict=$reduced
}

v() { jq -r "$@" <<<"$verdict"; }

# Posts the re-request comment of each bot in the JSON array $1 that this run
# has not re-requested yet. Sets $error and returns 1 when a post fails.
rerequest() {
  local bot comment rc
  for bot in $(jq -r '.[]' <<<"$1"); do
    [ "$(jq --arg b "$bot" 'has($b)' <<<"$rerequested")" = false ] || continue
    comment=$(jq -r --arg b "$bot" '.[$b].rerequest' <<<"$BOTS")
    rc=0
    gh pr comment "$pr" --repo "$repo" --body "$comment" >&2 2>"$errfile" || rc=$?
    cat "$errfile" >&2
    if [ "$rc" != 0 ]; then
      error="re-request for $bot failed: $(cat "$errfile")"
      return 1
    fi
    rerequested=$(jq -c --arg b "$bot" --argjson t "$(date +%s)" '.[$b] = $t' <<<"$rerequested")
  done
}

failed_poll() {
  failures=$((failures + 1))
  echo "poll failed ($failures of $MAX_FAILED_POLLS): $error" >&2
}

start=$SECONDS failures=0 shown='' verdict='' error='' rerequested='{}'
while :; do
  if rerequest "$forced" && poll; then
    failures=0
    line=$(v "$STATUS_LINE")
    [ "$line" = "$shown" ] || { echo "$line"; shown=$line; }
    case $(v .outcome) in
      moved) finish moved "head is $(v .head), not $sha" ;;
      closed) finish closed "pull request is $(v .state), not OPEN" ;;
      refused) finish refused "$(v '[.bots | to_entries[] | select(.value == "refused") | .key][0] as $b
        | "\($b): \(.notices[$b] | gsub("\\s+"; " ") | .[0:200])"')" ;;
      failed) finish failed "$(v '.checks.failed_names | join(", ")')" ;;
      passed) finish passed "$(v '"\(.checks.passed) checks passed"')" ;;
      waiting) rerequest "$(v '[.bots | to_entries[] | select(.value == "rerequest") | .key]')" || failed_poll ;;
    esac
  else
    failed_poll
  fi
  [ "$failures" -lt "$MAX_FAILED_POLLS" ] || finish forge "${error//$'\n'/ }"
  if [ $((SECONDS - start)) -ge "$deadline" ]; then
    if [ -n "$verdict" ]; then finish deadline "still pending: $(v "$STILL_PENDING")"; fi
    finish deadline "no poll succeeded"
  fi
  sleep "$interval"
done
