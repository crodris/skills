#!/usr/bin/env bash
# watch.sh - wait until a pull request's checks and review bots settle on one
# pinned head SHA, with one GraphQL call per poll, and exit with a code that
# says how it ended. babysit runs it instead of a hand-written loop.
#
# usage: watch.sh <pr-number> <head-sha> --repo <owner/name>
#          [--bot <bot>]... [--rerequest <bot>]... [--retry <bot>]...
#          [--retry-in <seconds, default 0>] [--silent-after <seconds, default 600>]
#          [--deadline <seconds, default 1800>] [--interval <seconds, default 30>]
#   <bot> is coderabbit or greptile.
#
# With no --bot it waits on the checks alone.
# A GitHub Actions workflow on the SHA that has not finished counts as a pending
# check, and one that failed before creating any check run counts as a failed
# check. When the base branch's rulesets or branch protection name required
# checks, it settles once each of them has reported and finished. Otherwise it
# never settles in its first SETTLE_GRACE seconds, so a check or workflow that
# registers late is still waited on.
# --rerequest <bot> implies --bot <bot> and posts the bot's re-request comment
# once, after a poll finds the pull request open on <head-sha> and the bot not
# settled; a notice older than that post is then ignored.
# A bot that labels its own findings (own_severity in BOTS) is re-requested only
# when one of its comments or reviews on the pull request carries its own
# Critical or Major label; otherwise --rerequest exits 2 before any poll, and a
# --bot whose notice asks for a re-request exits 2 instead of posting. It checks
# that such a label exists on the pull request, not that this push fixed that
# finding; babysit decides that.
# --retry <bot> implies --bot <bot> and asks again for a review that a rate limit
# stopped, once, no sooner than --retry-in seconds after the start, with no
# label check, since no review was spent.
#
# | Exit | Meaning                                                              |
# | ---- | -------------------------------------------------------------------- |
# | 0    | settled, every check passed                                          |
# | 1    | settled, one or more checks failed; prints each failed check's name  |
# | 2    | usage error, gh or jq missing, or a re-request the bot's own finding |
# |      | labels do not allow                                                  |
# | 3    | head moved: it is no longer <head-sha>                               |
# | 4    | deadline passed before settling; prints what is still pending        |
# | 5    | forge error: 3 consecutive failed polls, a failed re-request         |
# |      | comment, or a failed read of a bot's findings; prints the error text |
# | 6    | a bot cannot review; prints "<bot> <reason>: <notice>", where the    |
# |      | reason is rate-limited or out-of-credits only when every other bot   |
# |      | is settled or itself unavailable, no check is pending, no required   |
# |      | check is missing, and the grace window allows it, or silent (no      |
# |      | status, check, review, or comment on the SHA after --silent-after    |
# |      | seconds or at the deadline, with nothing else pending)               |
# | 7    | pull request is no longer open (MERGED or CLOSED); prints its state  |
# | 8    | settled with every check passed, but the base branch moved since the |
# |      | start and the new base commits touch files this pull request changes |
#
# stdout gets a status line on each poll whose status changed, then one verdict
# line. gh's stderr is passed through, never hidden.
# The first poll that finds the pull request open on <head-sha> appends
# "<head-sha> <UTC time>" to ship/watch.log under $XDG_STATE_HOME, or under
# ~/.local/state when that is unset or not absolute, so a push gate can tell
# that this head was watched. A failed write warns on stderr and changes no exit.
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
    unavailable) exit 6 ;;
    closed) exit 7 ;;
    base-moved) exit 8 ;;
  esac
}

{ command -v gh && command -v jq; } >/dev/null || finish usage "watch.sh needs gh and jq on PATH"

# After a fresh push, workflows register over many seconds, and a fast one can
# pass before a slow one exists, so with no required checks to wait for,
# settling waits this long. WATCH_GRACE overrides it for tests.
SETTLE_GRACE=${WATCH_GRACE:-120}
MAX_FAILED_POLLS=3

# Mirrors the table in bots.md; change both together.
# login is the GraphQL login, which has no [bot] suffix.
# A bot settles on whichever of status, check_run, or review_on_sha it defines.
# own_severity matches the bot's own Critical or Major label in a comment body,
# in each CodeRabbit format: "</picture> Major**", "**🟠 Major**", and "_🟠 Major_".
# A status's skipped pattern is a notice that asks for a re-request.
# A skipped check run is a re-request notice, not a settle.
# A check run whose title is a rate-limit or out-of-credits notice is that notice, not a settle.
# CodeRabbit reports a check run on newer installs and a commit status on older ones.
# Either one settles it apart from a skipped check run or a notice title.
BOTS='{
  "coderabbit": {
    "login": "coderabbitai",
    "rerequest": "@coderabbitai review",
    "own_severity": "(</picture>|🔴|🟠) (Critical|Major)(\\*\\*|_)",
    "check_run": "CodeRabbit",
    "status": {"context": "CodeRabbit", "settled": "Review completed", "skipped": "Review skipped"}
  },
  "greptile": {
    "login": "greptile-apps",
    "rerequest": "@greptileai",
    "check_run": "Greptile Review",
    "review_on_sha": true
  }
}'

QUERY='query($owner:String!,$repo:String!,$n:Int!,$sha:GitObjectID!){repository(owner:$owner,name:$repo){
 pullRequest(number:$n){state headRefOid baseRefName baseRef{target{oid}}
  files(first:100){pageInfo{hasNextPage} nodes{path}}
  reviews(last:30){nodes{author{login} commit{oid} submittedAt body}}
  comments(last:30){nodes{author{login} updatedAt body}}}
 object(oid:$sha){... on Commit{committedDate statusCheckRollup{contexts(first:100){pageInfo{hasNextPage} nodes{__typename
  ... on CheckRun{name status conclusion title completedAt}
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
# $posting (ids this run posts a re-request for on its own: --rerequest and --retry),
# $required (required check names, empty when none were found), and
# $grace_over (whether SETTLE_GRACE has passed).
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
def notice($skipped):
  if test("reached the [0-9]+-credit limit|trial (has )?(ended|expired)|upgrade (your|to a paid) plan"; "i") then "out-of-credits"
  elif test("rate limit(ed\\b| exceeded)"; "i") then "rate-limited"
  elif $skipped != null and test($skipped; "i") then "rerequest"
  else null end;
# Only the first line: a real notice opens with its phrase, and a summary below it may quote code.
def body_notice: (split("\n")[0] // "") | notice(null);

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
| def bot($b; $since; $posts):
    ([$checks[] | select($b.status != null and .context == $b.status.context)] | last) as $status
    | [$pr.reviews.nodes // [] | .[] | select(author == $b.login and .commit.oid == $sha)] as $reviews
    | [$pr.comments.nodes // [] | .[]
       | select(author == $b.login and $committed != null and (.updatedAt | epoch) >= ($committed | epoch))] as $comments
    # A bot with a status gives no notices in comments or reviews, since its walkthrough comments quote code.
    # A check run has no timestamp, so a skip counts only before this run posts its re-request.
    | [ ($status | select(. != null and (.createdAt | fresh($since)))
         | {kind: (.description // "" | notice($b.status.skipped)), text: .description}),
        ($reviews[], $comments[] | select($b.status == null and (.submittedAt // .updatedAt | fresh($since)))
         | {kind: (.body // "" | body_notice), text: .body}),
        ($checks[] | select($since == null and $b.check_run != null and .name == $b.check_run
           and .status == "COMPLETED" and .conclusion == "SKIPPED")
         | {kind: "rerequest", text: "\(.name) check run skipped"}),
        ($checks[] | select($b.check_run != null and .name == $b.check_run and .status == "COMPLETED"
           and (.title // "" | notice(null)) != null and (.completedAt | fresh($since)))
         | {kind: (.title | notice(null)), text: .title})
      | select(.kind != null) ] as $notices
    | ( ($status != null and $status.state == "SUCCESS"
         and ($status.description // "" | contains($b.status.settled)))
        or ($b.check_run != null and any($checks[]; .name == $b.check_run and .status == "COMPLETED"
           and .conclusion != "SKIPPED" and (.title // "" | notice(null)) == null))
        or ($b.review_on_sha == true and any($reviews[]; .body // "" | body_notice == null))
      ) as $settled
    | ($status != null or ($reviews | length) > 0 or ($comments | length) > 0
       or ($b.check_run != null and any($checks[]; .name == $b.check_run))) as $seen
    | ([$notices[] | select(.kind == "out-of-credits")] | first) as $credits
    | ([$notices[] | select(.kind == "rate-limited")] | first) as $limited
    | ([$notices[] | select(.kind == "rerequest")] | first) as $rerequest
    # A rate limit this run will re-request on its own waits for that post instead of ending the run.
    | if $credits then {state: "out-of-credits", notice: $credits.text}
      elif $settled then {state: "settled"}
      elif $limited and $posts and $since == null then {state: "rerequest", notice: $limited.text}
      elif $limited then {state: "rate-limited", notice: $limited.text}
      elif $rerequest then {state: "rerequest", notice: $rerequest.text}
      else {state: "pending"} end
    | . + {seen: $seen};
  [$bots[] as $id | {id: $id} + bot($registry[$id]; $rerequested[$id] // null; $id | IN($posting[]))] as $botstates
| [$required[] | . as $name | select(any($checks[]; .label == $name) | not)] as $missing
| ($grace_over or ($required | length) > 0) as $may_settle
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
    may_settle: $may_settle,
    missing_required: $missing,
    base: ($pr.baseRef.target.oid // null),
    files: [$pr.files.nodes // [] | .[].path],
    files_truncated: ($pr.files.pageInfo.hasNextPage == true),
    bots: ($botstates | map({(.id): .state}) | add // {}),
    seen: ($botstates | map({(.id): .seen}) | add // {}),
    notices: ($botstates | map(select(.notice != null) | {(.id): .notice}) | add // {})
  }
| .outcome = (
    if .pr != "open" then .pr
    # Unavailable only when a bot is rate-limited or out of credits, every
    # other bot is settled or itself unavailable, no check is pending, no
    # required check is missing, and the grace window allows settling.
    elif any(.bots[]; . == "out-of-credits" or . == "rate-limited")
      and all(.bots[]; . == "settled" or . == "out-of-credits" or . == "rate-limited")
      and .checks.pending == 0 and ($missing | length) == 0 and $may_settle then "unavailable"
    elif all(.bots[]; . == "settled") and .checks.pending == 0 and ($missing | length) == 0 and $may_settle
    then (if .checks.failed > 0 then "failed" else "passed" end)
    else "waiting" end)'

STATUS_LINE='"checks \(.checks.passed) passed \(.checks.failed) failed \(.checks.pending) pending"
  + (.bots | to_entries | map(" | \(.key) \(.value)") | join(""))'

STILL_PENDING='[
  (if .checks.pending > 0 then "checks \(.checks.pending_names | join(", "))"
   elif .checks.passed + .checks.failed == 0 then "no checks registered"
   else empty end),
  (if (.missing_required | length) > 0 then "required checks not reported: \(.missing_required | join(", "))" else empty end),
  (if .may_settle | not then "the \($grace)-second wait for late checks" else empty end),
  (.bots | to_entries[] | select(.value != "settled") | "\(.key) \(.value)")
] | join("; ")'

usage() {
  echo "usage: watch.sh <pr-number> <head-sha> --repo <owner/name> [--bot coderabbit|greptile]... [--rerequest coderabbit|greptile]... [--retry coderabbit|greptile]... [--retry-in <seconds>] [--silent-after <seconds>] [--deadline <seconds>] [--interval <seconds>]" >&2
  echo "  --rerequest <bot> implies --bot <bot> and posts its re-request comment once, after a poll finds the pull request open on <head-sha> and the bot not settled" >&2
  echo "  a bot that labels its own findings is re-requested only when it labeled one Critical or Major on the pull request; otherwise it exits 2" >&2
  echo "  --retry <bot> implies --bot <bot> and asks again, once, for a rate-limited review no sooner than --retry-in seconds after the start" >&2
  finish usage "$1"
}

add() { jq -c --arg b "$1" 'if any(.[]; . == $b) then . else . + [$b] end'; }

pr='' sha='' repo='' deadline=1800 interval=30 retry_in=0 silent_after=600 bots='[]' forced='[]' retry='[]'
while [ $# -gt 0 ]; do
  case $1 in
    --repo | --bot | --rerequest | --retry | --retry-in | --silent-after | --deadline | --interval)
      [ $# -ge 2 ] || usage "$1 needs a value"
      case $1 in
        --repo) repo=$2 ;;
        --deadline) deadline=$2 ;;
        --interval) interval=$2 ;;
        --retry-in) retry_in=$2 ;;
        --silent-after) silent_after=$2 ;;
        --bot | --rerequest | --retry)
          jq -e --arg b "$2" 'has($b)' <<<"$BOTS" >/dev/null || usage "unknown bot $2"
          bots=$(add "$2" <<<"$bots")
          [ "$1" != --rerequest ] || forced=$(add "$2" <<<"$forced")
          [ "$1" != --retry ] || retry=$(add "$2" <<<"$retry")
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
[[ $retry_in =~ ^[0-9]+$ ]] || usage "--retry-in must be whole seconds"
[[ $silent_after =~ ^[0-9]+$ ]] || usage "--silent-after must be whole seconds"
[[ $SETTLE_GRACE =~ ^[0-9]+$ ]] || usage "WATCH_GRACE must be whole seconds"

errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT

# Succeeds when one of the bot's review comments or reviews on the pull request
# carries its own Critical or Major label (own_severity), or when the bot has no
# own_severity. babysit's triage may grade a finding higher than the bot did, but
# only the bot's label spends a re-review (bots.md, Which pass waits on which bot).
labeled() {
  local login pattern path out rc
  pattern=$(jq -r --arg b "$1" '.[$b].own_severity // empty' <<<"$BOTS")
  [ -n "$pattern" ] || return 0
  login=$(jq -r --arg b "$1" '.[$b].login' <<<"$BOTS")
  for path in "pulls/$pr/comments" "pulls/$pr/reviews"; do
    rc=0
    out=$(gh api --paginate "repos/$repo/$path" 2>"$errfile") || rc=$?
    [ "$rc" = 0 ] || finish forge "reading $1 findings failed: $(tr '\n' ' ' <"$errfile")"
    jq -se --arg l "$login" --arg p "$pattern" 'add // [] | any(.[];
      (.user.login // "" | sub("\\[bot\\]$"; "")) == $l and (.body // "" | test($p)))' \
      <<<"$out" >/dev/null && return 0
  done
  return 1
}

for bot in $(jq -r '.[]' <<<"$forced"); do
  labeled "$bot" ||
    finish usage "--rerequest $bot: no $bot finding on pull request $pr carries its own Critical or Major label"
done

member() { jq -e --arg b "$1" 'any(.[]; . == $b)' <<<"$2" >/dev/null; }

# Prints the base branch's required check names as a JSON array, from its
# rulesets and its branch protection. A read that fails, such as protection
# that needs admin access, adds nothing, so the grace period applies instead.
required_checks() {
  local rules protection
  rules=$(gh api "repos/$repo/rules/branches/$1" 2>/dev/null |
    jq -c '[.[]? | select(.type == "required_status_checks") | .parameters.required_status_checks[]?.context]' 2>/dev/null) ||
    rules='[]'
  protection=$(gh api "repos/$repo/branches/$1/protection/required_status_checks" 2>/dev/null |
    jq -c '[(.contexts // [])[], (.checks // [])[].context]' 2>/dev/null) || protection='[]'
  jq -cn --argjson a "${rules:-[]}" --argjson b "${protection:-[]}" '$a + $b | unique'
}

# Sets $verdict on success; sets $error and returns 1 on a failed poll.
poll() {
  local out rc=0 grace_over=false reduced base_name
  [ $((SECONDS - start)) -lt "$SETTLE_GRACE" ] || grace_over=true
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
  if [ -z "$required" ]; then
    base_name=$(jq -r '.data.repository.pullRequest.baseRefName // empty' <<<"$out")
    if [ -n "$base_name" ]; then required=$(required_checks "$base_name"); else required='[]'; fi
  fi
  reduced=$(jq -c --arg sha "$sha" --argjson bots "$bots" --argjson registry "$BOTS" \
    --argjson rerequested "$rerequested" --argjson posting "$(jq -cn --argjson a "$forced" --argjson b "$retry" '$a + $b')" \
    --argjson required "$required" --argjson grace_over "$grace_over" "$REDUCE" <<<"$out" 2>&1) ||
    { error="unreadable response: $reduced"; return 1; }
  verdict=$reduced
}

v() { jq -r "$@" <<<"$verdict"; }

# Posts the re-request comment of each bot in the JSON array $1 that this run
# has not re-requested yet. A failed post ends the run, because a post that may
# have landed must not be retried. A --bot whose notice asks for a re-request
# gets the same label check as --rerequest. A --retry bot gets none, since a
# rate limit means no review was spent, and posts only after --retry-in.
rerequest() {
  local bot comment rc
  for bot in $(jq -r '.[]' <<<"$1"); do
    [ "$(jq --arg b "$bot" 'has($b)' <<<"$rerequested")" = false ] || continue
    if member "$bot" "$retry"; then
      [ $((SECONDS - start)) -ge "$retry_in" ] || continue
    elif ! member "$bot" "$forced" && ! labeled "$bot"; then
      finish usage "--bot $bot: its notice asks for a re-request, but no $bot finding on pull request $pr carries its own Critical or Major label"
    fi
    rerequested=$(jq -c --arg b "$bot" --argjson t "$(date +%s)" '.[$b] = $t' <<<"$rerequested")
    comment=$(jq -r --arg b "$bot" '.[$b].rerequest' <<<"$BOTS")
    rc=0
    gh pr comment "$pr" --repo "$repo" --body "$comment" >&2 2>"$errfile" || rc=$?
    cat "$errfile" >&2
    [ "$rc" = 0 ] || finish forge "re-request for $bot failed: $(tr '\n' ' ' <"$errfile")"
  done
}

record_watch() {
  local state=${HOME:-}/.local/state log
  case ${XDG_STATE_HOME:-} in /*) state=$XDG_STATE_HOME ;; esac
  log=$state/ship/watch.log
  { mkdir -p "$(dirname "$log")" && printf '%s %s\n' "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$log"; } ||
    echo "could not record this watch in $log" >&2
}

failed_poll() {
  failures=$((failures + 1))
  echo "poll failed ($failures of $MAX_FAILED_POLLS): $error" >&2
}

# Prints "base moved: <old>..<new> touches <files>" and succeeds when the base
# branch moved since the first poll and its new commits touch a file this pull
# request changes. Every move counts when the pull request has over 100 files.
# A compare that lists 300 or more files counts as touching too, since GitHub caps the list there.
base_moved() {
  local now out rc=0 touched
  now=$(v '.base // ""')
  [ -n "$first_base" ] && [ -n "$now" ] && [ "$now" != "$first_base" ] || return 1
  if [ "$(v .files_truncated)" = true ]; then
    touched="this pull request's files (more than 100)"
  else
    out=$(gh api "repos/$repo/compare/$first_base...$now" 2>"$errfile") || rc=$?
    [ "$rc" = 0 ] || finish forge "comparing the moved base failed: $(tr '\n' ' ' <"$errfile")"
    touched=$(jq -r --argjson files "$(v -c .files)" '[.files[]?.filename | select(IN($files[]))] | join(", ")' <<<"$out")
    if [ -z "$touched" ] && [ "$(jq '.files | length' <<<"$out")" -ge 300 ]; then
      touched="this pull request's files (the base changed 300 or more files)"
    fi
  fi
  [ -n "$touched" ] || return 1
  echo "base moved: ${first_base:0:7}..${now:0:7} touches $touched"
}

# Prints "<bot> <reason>: <notice>" for every rate-limited or out-of-credits bot.
unavailable_bots() {
  v '. as $v | [.bots | to_entries[] | select(.value == "out-of-credits" or .value == "rate-limited") | .key]
    | map("\(.) \($v.bots[.]): \($v.notices[.] // "" | gsub("\\s+"; " ") | .[0:200])") | join("; ")'
}

# Prints the bots that never showed a status, check, review, or comment on the
# SHA, when nothing else is still pending. A rate-limited or out-of-credits bot
# is not still pending.
silent_bots() {
  v '[.seen | to_entries[] | select(.value == false) | .key] as $silent
    | if ($silent | length) > 0 and .checks.pending == 0 and (.missing_required | length) == 0
         and all(.bots | to_entries[]; .value == "settled" or .value == "rate-limited" or .value == "out-of-credits" or (.key | IN($silent[])))
      then $silent | join(", ") else "" end'
}

# Names the silent bots. An unavailable bot beside them is named too.
silent_verdict() {
  local text extra
  text="$(silent_bots) silent: no status, check, review, or comment on $sha within ${1}s"
  extra=$(unavailable_bots)
  if [ -n "$extra" ]; then echo "$extra; $text"; else echo "$text"; fi
}

start=$SECONDS failures=0 shown='' verdict='' error='' rerequested='{}' required='' first_base='' recorded=''
while :; do
  if poll; then
    failures=0
    [ -n "$first_base" ] || first_base=$(v '.base // ""')
    if [ -z "$recorded" ] && [ "$(v .pr)" = open ]; then
      record_watch
      recorded=1
    fi
    line=$(v "$STATUS_LINE")
    [ "$line" = "$shown" ] || { echo "$line"; shown=$line; }
    case $(v .outcome) in
      moved) finish moved "head is $(v .head), not $sha" ;;
      closed) finish closed "pull request is $(v .state), not OPEN" ;;
      unavailable) finish unavailable "$(unavailable_bots)" ;;
      failed)
        base_moved || true
        finish failed "$(v '.checks.failed_names | join(", ")')"
        ;;
      passed)
        if base_moved; then finish base-moved "$(v '"\(.checks.passed) checks passed"')"; fi
        finish passed "$(v '"\(.checks.passed) checks passed"')"
        ;;
      waiting) rerequest "$(v --argjson forced "$forced" '[.bots | to_entries[]
        | select(.value == "rerequest" or (.value != "settled" and (.key | IN($forced[])))) | .key]')" ;;
    esac
  else
    failed_poll
  fi
  [ "$failures" -lt "$MAX_FAILED_POLLS" ] || finish forge "${error//$'\n'/ }"
  if [ -n "$verdict" ] && [ $((SECONDS - start)) -ge "$silent_after" ] && [ -n "$(silent_bots)" ]; then
    finish unavailable "$(silent_verdict "$silent_after")"
  fi
  if [ $((SECONDS - start)) -ge "$deadline" ]; then
    [ -z "$verdict" ] || [ -z "$(silent_bots)" ] ||
      finish unavailable "$(silent_verdict "$deadline")"
    if [ -n "$verdict" ]; then finish deadline "still pending: $(v --argjson grace "$SETTLE_GRACE" "$STILL_PENDING")"; fi
    finish deadline "no poll succeeded"
  fi
  sleep "$interval"
done
