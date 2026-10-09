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
# A GitHub Actions workflow on the SHA that has not finished counts as a pending
# check, and one that failed before creating any check run counts as a failed
# check. Settling waits up to NO_CHECKS_GRACE seconds for a first check and a
# first workflow.
# --rerequest <bot> implies --bot <bot> and posts the bot's re-request comment
# once, after a poll finds the pull request open on <head-sha> and the bot not
# settled; a notice older than that post is then ignored.
#
# | Exit | Meaning                                                              |
# | ---- | -------------------------------------------------------------------- |
# | 0    | settled, every check passed                                          |
# | 1    | settled, one or more checks failed; prints each failed check's name  |
# | 2    | usage error, or gh or jq missing                                     |
# | 3    | head moved: it is no longer <head-sha>                               |
# | 4    | deadline passed before settling; prints what is still pending        |
# | 5    | forge error: 3 consecutive failed polls, or a failed re-request      |
# |      | comment; prints the last error text                                  |
# | 6    | a bot will not review (trial or plan quota notice); prints the notice |
# | 7    | pull request is no longer open (MERGED or CLOSED); prints its state  |
#
# stdout gets a status line on each poll whose status changed, then one verdict
# line. gh's stderr is passed through, never hidden.
# Requires bash, gh, and jq.

# shellcheck disable=SC2016 # jq and GraphQL programs use $ for their own variables.
set -euo pipefail

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

{ command -v gh && command -v jq; } >/dev/null || finish usage "watch.sh needs gh and jq on PATH"

# A fresh push may have no checks and no GitHub Actions workflow registered yet,
# so settling waits for both or for this many seconds; a repo with no workflows,
# or whose workflows all skip by paths filters, therefore waits this long before
# settling.
NO_CHECKS_GRACE=120
MAX_FAILED_POLLS=3

# Mirrors the table in bots.md; change both together.
# login is the GraphQL login, which has no [bot] suffix.
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
 object(oid:$sha){... on Commit{committedDate statusCheckRollup{contexts(first:100){pageInfo{hasNextPage} nodes{__typename
  ... on CheckRun{name status conclusion}
  ... on StatusContext{context state description createdAt}}}}
  checkSuites(first:100){pageInfo{hasNextPage} nodes{status conclusion workflowRun{workflow{name}} checkRuns(first:1){totalCount}}}}}}}'

# Prints the failure text of a response that counts as a failed poll, else nothing.
ERRORS='
if .errors then [.errors[]? | .message // tojson] | join("; ") | if . == "" then "GraphQL errors field" else . end
elif (.data.repository.pullRequest | type) != "object" then "response has no pull request"
elif .data.repository.object.statusCheckRollup.contexts.pageInfo.hasNextPage == true
then "more than 100 checks on the SHA; watch.sh reads only the first 100"
elif .data.repository.object.checkSuites.pageInfo.hasNextPage == true
then "more than 100 check suites on the SHA; watch.sh reads only the first 100"
else empty end'

# Reduces one GraphQL response to a verdict. Inputs: $sha, $bots (ids in order),
# $registry, $rerequested (bot id -> epoch seconds of this run's re-request),
# and $grace_over (whether NO_CHECKS_GRACE has passed, so settling no longer
# needs a first check and a first workflow).
REDUCE='
def epoch: sub("\\.[0-9]+"; "") | fromdateiso8601;
def fresh($since): $since == null or (. != null and epoch >= $since);
def author: .author.login // "" | sub("\\[bot\\]$"; "");
# A status passes on SUCCESS and waits on PENDING or EXPECTED; a check run waits until COMPLETED and passes on SUCCESS, NEUTRAL, or SKIPPED; anything else failed.
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
# Only the first line: a real notice opens with its phrase, and a summary below it may quote code.
def body_notice: split("\n")[0] | notice("rate limit exceeded");

.data.repository as $repo
| $repo.pullRequest as $pr
| ($repo.object.committedDate // null) as $committed
# Only a GitHub Actions suite has a workflow run; other apps leave theirs QUEUED forever.
# A finished workflow fails through its check runs, or as itself when it failed before creating any.
| [$repo.object.checkSuites.nodes // [] | .[] | select(.workflowRun != null)] as $workflows
| [ ($repo.object.statusCheckRollup.contexts.nodes // [] | .[] | . + {kind: kind, label: (.name // .context)}),
    ($workflows[] | "workflow \(.workflowRun.workflow.name)" as $label
     | if .status != "COMPLETED" then {kind: "pending", label: $label}
       elif .checkRuns.totalCount == 0 and (.conclusion | IN("SUCCESS", "NEUTRAL", "SKIPPED") | not)
       then {kind: "failed", label: $label}
       else empty end)
  ] as $checks
| def bot($b; $since):
    ([$checks[] | select($b.status != null and .context == $b.status.context)] | last) as $status
    | [$pr.reviews.nodes // [] | .[] | select(author == $b.login and .commit.oid == $sha)] as $reviews
    | [$pr.comments.nodes // [] | .[]
       | select(author == $b.login and $committed != null and (.updatedAt | epoch) >= ($committed | epoch))] as $comments
    # A bot with a status gives notices only there, since its walkthrough comments quote code.
    | [ ($status | select(. != null and (.createdAt | fresh($since)))
         | {kind: (.description // "" | notice($b.status.notice)), text: .description}),
        ($reviews[], $comments[] | select($b.status == null and (.submittedAt // .updatedAt | fresh($since)))
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
    no_workflow: ($workflows == [] and ($grace_over | not)),
    bots: ($botstates | map({(.id): .state}) | add // {}),
    notices: ($botstates | map(select(.notice != null) | {(.id): .notice}) | add // {})
  }
| .outcome = (
    if .pr != "open" then .pr
    elif any(.bots[]; . == "refused") then "refused"
    elif all(.bots[]; . == "settled") and .checks.pending == 0
         and (.checks.passed + .checks.failed > 0 or $grace_over) and (.no_workflow | not)
    then (if .checks.failed > 0 then "failed" else "passed" end)
    else "waiting" end)'

STATUS_LINE='"checks \(.checks.passed) passed \(.checks.failed) failed \(.checks.pending) pending"
  + (.bots | to_entries | map(" | \(.key) \(.value)") | join(""))'

STILL_PENDING='[
  (if .checks.pending > 0 then "checks \(.checks.pending_names | join(", "))"
   elif .checks.passed + .checks.failed == 0 then "no checks registered"
   else empty end),
  (if .no_workflow and (.checks.pending > 0 or .checks.passed + .checks.failed > 0)
   then "no GitHub Actions workflow registered" else empty end),
  (.bots | to_entries[] | select(.value != "settled") | "\(.key) \(.value)")
] | join("; ")'

usage() {
  echo "usage: watch.sh <pr-number> <head-sha> --repo <owner/name> [--bot coderabbit|greptile]... [--rerequest coderabbit|greptile]... [--deadline <seconds>] [--interval <seconds>]" >&2
  echo "  --rerequest <bot> implies --bot <bot> and posts its re-request comment once, after a poll finds the pull request open on <head-sha> and the bot not settled" >&2
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
  local out rc=0 grace_over=false reduced
  [ $((SECONDS - start)) -lt "$NO_CHECKS_GRACE" ] || grace_over=true
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
    --argjson rerequested "$rerequested" --argjson grace_over "$grace_over" "$REDUCE" <<<"$out" 2>&1) ||
    { error="unreadable response: $reduced"; return 1; }
  verdict=$reduced
}

v() { jq -r "$@" <<<"$verdict"; }

# Posts the re-request comment of each bot in the JSON array $1 that this run
# has not re-requested yet. A failed post ends the run, because a post that may
# have landed must not be retried.
rerequest() {
  local bot comment rc
  for bot in $(jq -r '.[]' <<<"$1"); do
    [ "$(jq --arg b "$bot" 'has($b)' <<<"$rerequested")" = false ] || continue
    rerequested=$(jq -c --arg b "$bot" --argjson t "$(date +%s)" '.[$b] = $t' <<<"$rerequested")
    comment=$(jq -r --arg b "$bot" '.[$b].rerequest' <<<"$BOTS")
    rc=0
    gh pr comment "$pr" --repo "$repo" --body "$comment" >&2 2>"$errfile" || rc=$?
    cat "$errfile" >&2
    [ "$rc" = 0 ] || finish forge "re-request for $bot failed: $(tr '\n' ' ' <"$errfile")"
  done
}

failed_poll() {
  failures=$((failures + 1))
  echo "poll failed ($failures of $MAX_FAILED_POLLS): $error" >&2
}

start=$SECONDS failures=0 shown='' verdict='' error='' rerequested='{}'
while :; do
  if poll; then
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
      waiting) rerequest "$(v --argjson forced "$forced" '[.bots | to_entries[]
        | select(.value == "rerequest" or (.value != "settled" and (.key | IN($forced[])))) | .key]')" ;;
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
