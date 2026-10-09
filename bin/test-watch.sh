#!/usr/bin/env bash
# test-watch.sh - run skills/ship/watch.sh against a fake gh that replays
# fixture responses in order, one per poll with the last one repeating, and
# logs every call. A poll's fixture is N.json, or N.err to fail with that
# stderr text, and comment.err makes every `gh pr comment` fail the same way.
# Each case checks the exit code and, where it matters, stdout or the gh call log.
set -euo pipefail

WATCH="$(cd "$(dirname "$0")/.." && pwd)/skills/ship/watch.sh"
SHA=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
# shellcheck disable=SC2016 # the backticks are part of Greptile's notice text.
CREDIT='`crodris` has reached the 50-credit limit for trial accounts. Upgrade to keep reviewing.'
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FIXTURES/gh.log"
if [ "$1 $2" = "pr comment" ] && [ -e "$FIXTURES/comment.err" ]; then cat "$FIXTURES/comment.err" >&2; exit 1; fi
[ "$1 $2" = "api graphql" ] || exit 0
n=$(( $(cat "$FIXTURES/polls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FIXTURES/polls"
while [ "$n" -gt 1 ] && [ ! -e "$FIXTURES/$n.json" ] && [ ! -e "$FIXTURES/$n.err" ]; do n=$((n - 1)); done
if [ -e "$FIXTURES/$n.err" ]; then cat "$FIXTURES/$n.err" >&2; exit 1; fi
cat "$FIXTURES/$n.json"
STUB
chmod +x "$tmp/bin/gh"
PATH="$tmp/bin:$PATH"

check_run() { jq -cn --arg n "$1" --arg s "$2" --arg c "${3:-}" \
  '{__typename: "CheckRun", name: $n, status: $s, conclusion: (if $c == "" then null else $c end)}'; }
status() { jq -cn --arg c "$1" --arg s "$2" --arg d "$3" --arg t "${4:-2020-01-01T00:05:00Z}" \
  '{__typename: "StatusContext", context: $c, state: $s, description: $d, createdAt: $t}'; }
review() { jq -cn --arg l "$1" --arg o "$2" --arg b "$3" \
  '{author: {login: $l}, commit: {oid: $o}, submittedAt: "2020-01-01T00:05:00Z", body: $b}'; }
# suite <slug> <status> [workflow-name] [conclusion] [check-run-count]
# A COMPLETED suite defaults to SUCCESS with 1 check run.
suite() { jq -cn --arg a "$1" --arg s "$2" --arg w "${3:-}" --arg c "${4:-}" --arg r "${5:-}" \
  '{status: $s, app: {slug: $a}, workflowRun: (if $w == "" then null else {workflow: {name: $w}} end),
    conclusion: (if $c != "" then $c elif $s == "COMPLETED" then "SUCCESS" else null end),
    checkRuns: {totalCount: (if $r != "" then ($r | tonumber) elif $s == "COMPLETED" then 1 else 0 end)}}'; }

# response <state> <headRefOid> [reviews] <check>...
# The check suites come from $SUITES, by default one completed CI workflow.
response() {
  local state=$1 head=$2 reviews=$3 ci_done='[{"status":"COMPLETED","conclusion":"SUCCESS","app":{"slug":"github-actions"},"workflowRun":{"workflow":{"name":"CI"}},"checkRuns":{"totalCount":1}}]'
  shift 3
  printf '%s\n' "$@" | jq -s --arg state "$state" --arg head "$head" --argjson reviews "$reviews" \
    --argjson suites "${SUITES:-$ci_done}" '{data: {repository: {
    pullRequest: {state: $state, headRefOid: $head, reviews: {nodes: $reviews}, comments: {nodes: []}},
    object: {committedDate: "2020-01-01T00:00:00Z",
      statusCheckRollup: (if . == [] then null else {contexts: {nodes: .}} end),
      checkSuites: {nodes: $suites}}}}}'
}

case_dir() { dir=$(mktemp -d "$tmp/case.XXXX"); }

# A case still running after this many seconds is killed and gets exit 124, so
# a broken deadline fails the suite instead of hanging CI.
CASE_TIMEOUT=30

run() {
  local pid watchdog
  got=0
  FIXTURES=$dir "$WATCH" "$@" > "$dir/out" 2> "$dir/err" &
  pid=$!
  # The trap kills the sleep too, so a finished case leaves no stray process.
  (
    trap 'kill "$timer" 2>/dev/null; exit 0' TERM
    sleep "$CASE_TIMEOUT" &
    timer=$!
    wait "$timer"
    kill "$pid" 2>/dev/null && touch "$dir/timed-out"
  ) &
  watchdog=$!
  wait "$pid" || got=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  [ ! -e "$dir/timed-out" ] || got=124
  touch "$dir/gh.log"
}

expect_exit() {
  if [ "$got" = "$2" ]; then echo "ok: $1"; else
    echo "FAIL: $1 (exit $got, want $2)"; sed 's/^/  | /' "$dir/out" "$dir/err"; failures=$((failures + 1)); fi
}

expect_in() {
  if grep -qF -- "$3" "$dir/$2"; then echo "ok: $1"; else
    echo "FAIL: $1 ($2 lacks '$3')"; sed 's/^/  | /' "$dir/$2"; failures=$((failures + 1)); fi
}

expect_count() {
  local n
  n=$(grep -cF -- "$3" "$dir/$2" || true)
  if [ "$n" = "$4" ]; then echo "ok: $1"; else echo "FAIL: $1 ($n lines with '$3' in $2, want $4)"; failures=$((failures + 1)); fi
}

BUILD=$(check_run build COMPLETED SUCCESS)
CR_DONE=$(status CodeRabbit SUCCESS "Review completed")

case_dir
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "checks passed and CodeRabbit review completed exits 0" 0
expect_in "status line names every check state and bot" out "checks 2 passed 0 failed 0 pending | coderabbit settled"

case_dir
response OPEN $SHA '[]' "$BUILD" "$(check_run lint COMPLETED FAILURE)" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a failed check run exits 1" 1
expect_in "the failed check's name is printed" out "verdict: failed: lint"

case_dir
response OPEN $OLD '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a moved head exits 3" 3
expect_in "the moved head is printed" out "head is $OLD"

case_dir
response MERGED $SHA '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a merged pull request exits 7" 7
expect_in "the merged state is printed" out "pull request is MERGED"

case_dir
response CLOSED $SHA '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a closed pull request exits 7" 7
expect_in "the closed state is printed" out "pull request is CLOSED"

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review paused")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 1
expect_exit "a CodeRabbit success without Review completed never settles" 4
expect_in "CodeRabbit is reported pending" out "still pending: coderabbit pending"

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited")" > "$dir/1.json"
cp "$dir/1.json" "$dir/2.json"
cp "$dir/1.json" "$dir/3.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/4.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "a rate-limited CodeRabbit success is re-requested, then settles" 0
expect_count "exactly one re-request comment is posted" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1
expect_count "no other comment is posted" gh.log "pr comment" 1
expect_in "a notice older than the re-request reads as pending" out "| coderabbit pending"

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited" 2099-01-01T00:00:00Z)" > "$dir/2.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/3.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "a second rate limit after the re-request still settles" 0
expect_count "a second rate limit is never re-requested" gh.log "pr comment" 1

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review skipped: incremental reviews are disabled")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/2.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest waits on the bot and settles past an older skipped notice" 0
expect_count "--rerequest posts exactly one re-request comment" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1
expect_count "--rerequest posts no other comment" gh.log "pr comment" 1
if head -1 "$dir/gh.log" | grep -q '^api graphql'; then echo "ok: --rerequest posts after the first poll"; else
  echo "FAIL: --rerequest posts after the first poll (first gh call: $(head -1 "$dir/gh.log" | cut -c1-40))"; failures=$((failures + 1)); fi

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit PENDING "Review in progress")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/2.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest settles a bot that showed no notice" 0
expect_count "--rerequest posts for a bot that showed no notice" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1

case_dir
response MERGED $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review skipped")" > "$dir/1.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest on a merged pull request exits 7" 7
expect_count "--rerequest posts nothing on a merged pull request" gh.log "pr comment" 0

case_dir
response OPEN $OLD '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review skipped")" > "$dir/1.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest on a moved head exits 3" 3
expect_count "--rerequest posts nothing on a moved head" gh.log "pr comment" 0

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited")" > "$dir/1.json"
echo "HTTP 502: Bad Gateway" > "$dir/comment.err"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "a failed re-request comment exits 5" 5
expect_in "the failed comment's stderr is printed" out "re-request for coderabbit failed: HTTP 502"
expect_count "a failed re-request comment is never retried" gh.log "pr comment" 1

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit PENDING "Review in progress")" |
  jq '.data.repository.pullRequest.comments.nodes = [{author: {login: "coderabbitai"}, updatedAt: "2020-01-01T00:05:00Z",
    body: "<!-- This is an auto-generated comment: summarize by coderabbit.ai -->\n## Walkthrough\nReturns 429 with \"Rate limit exceeded\" and shows \"Upgrade your plan\" for free users."}]' > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/2.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "notice phrases in a CodeRabbit walkthrough are not notices" 0
expect_count "a CodeRabbit walkthrough triggers no re-request" gh.log "pr comment" 0

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit PENDING "Review in progress")" |
  jq '.data.repository.pullRequest.comments.nodes = [{author: {login: "coderabbitai"}, updatedAt: "2020-01-01T00:05:00Z",
    body: "Upgrade your plan is now shown to free users once they hit rate limit exceeded."}]' > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/2.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "CodeRabbit comments are never read as notices, even on their first line" 0
expect_count "a CodeRabbit comment triggers no re-request" gh.log "pr comment" 0

case_dir
response OPEN $SHA "[$(review greptile-apps $SHA "<h3>Greptile Summary</h3>
Adds backoff when the API answers rate limit exceeded.")]" "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 5
expect_exit "a notice phrase below a Greptile summary's first line still settles" 0
expect_count "a Greptile summary triggers no re-request" gh.log "pr comment" 0

case_dir
response OPEN $SHA "[$(review greptile-apps $SHA "Rate limit exceeded, try again later.")]" "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 1
expect_exit "a Greptile rate-limit review never settles" 4
expect_count "a Greptile rate-limit review is re-requested once" gh.log "pr comment 7 --repo o/r --body @greptileai" 1

case_dir
response OPEN $SHA '[]' "$BUILD" "$(check_run "Greptile Review" COMPLETED SUCCESS)" |
  jq --arg b "$CREDIT" '.data.repository.pullRequest.comments.nodes =
    [{author: {login: "greptile-apps"}, updatedAt: "2019-12-31T00:00:00Z", body: $b}]' > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 5
expect_exit "a notice comment older than the commit is ignored" 0

case_dir
response OPEN $SHA '[]' "$BUILD" "$(check_run test IN_PROGRESS)" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 1
expect_exit "a check that stays pending exits 4 at the deadline" 4
expect_in "the pending check is printed" out "still pending: checks test"
expect_count "an unchanged status is printed once" out "checks 1 passed" 1

case_dir
response OPEN $SHA '[]' > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 1
expect_exit "an empty rollup with no bots does not settle early" 4
expect_in "the empty rollup is reported" out "no checks registered"

CR_SKIPPED=$(status CodeRabbit SUCCESS "Review skipped: 574 files exceed the limit of 150")
CI_QUEUED="[$(suite github-actions QUEUED CI)]"
CI_RUNNING="[$(suite github-actions IN_PROGRESS CI)]"
CI_DONE="[$(suite github-actions COMPLETED CI)]"

case_dir
SUITES=$CI_QUEUED response OPEN $SHA '[]' "$CR_SKIPPED" > "$dir/1.json"
SUITES=$CI_RUNNING response OPEN $SHA '[]' "$CR_SKIPPED" "$(check_run test IN_PROGRESS)" > "$dir/2.json"
SUITES=$CI_DONE response OPEN $SHA '[]' "$CR_SKIPPED" "$(check_run test COMPLETED SUCCESS)" > "$dir/3.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a queued workflow with no check runs yet waits, then passes" 0
expect_in "the queued workflow counts as pending on the first poll" out "checks 1 passed 0 failed 1 pending"
expect_count "it settles only on the third poll" gh.log "api graphql" 3

case_dir
SUITES=$CI_QUEUED response OPEN $SHA '[]' "$CR_SKIPPED" > "$dir/1.json"
SUITES=$CI_RUNNING response OPEN $SHA '[]' "$CR_SKIPPED" "$(check_run test IN_PROGRESS)" > "$dir/2.json"
SUITES=$CI_DONE response OPEN $SHA '[]' "$CR_SKIPPED" "$(check_run test COMPLETED FAILURE)" > "$dir/3.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a queued workflow whose check run later fails exits 1" 1
expect_in "the workflow's failed check is printed" out "verdict: failed: test"

case_dir
SUITES="[$(suite vercel QUEUED),$(suite github-actions QUEUED),$(suite github-actions COMPLETED CI)]" response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a queued suite from another app or with no workflow run is ignored" 0

case_dir
SUITES="[$(suite github-actions COMPLETED CI STARTUP_FAILURE 0)]" response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a workflow that fails before creating check runs exits 1" 1
expect_in "the failed workflow is printed" out "verdict: failed: workflow CI"

case_dir
SUITES="[$(suite github-actions COMPLETED CI SKIPPED 0)]" response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a skipped workflow with no check runs passes" 0

case_dir
SUITES='[]' response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 1
expect_exit "a passed check with no workflow registered does not settle early" 4
expect_in "the missing workflow is reported" out "no GitHub Actions workflow registered"

case_dir
SUITES=$CI_QUEUED response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 1
expect_exit "a workflow that stays queued exits 4 at the deadline" 4
expect_in "the queued workflow is printed" out "workflow CI"

case_dir
echo "HTTP 502: Bad Gateway (https://api.github.com/graphql)" > "$dir/1.err"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "three failed gh calls exit 5" 5
expect_in "gh's stderr text is printed" out "HTTP 502: Bad Gateway"
expect_count "it gives up after exactly three polls" gh.log "api graphql" 3

case_dir
echo "HTTP 502: Bad Gateway" > "$dir/1.err"
cp "$dir/1.err" "$dir/2.err"
response OPEN $SHA '[]' "$BUILD" "$(check_run test IN_PROGRESS)" > "$dir/3.json"
cp "$dir/1.err" "$dir/4.err"
cp "$dir/1.err" "$dir/5.err"
response OPEN $SHA '[]' "$BUILD" "$(check_run test COMPLETED SUCCESS)" > "$dir/6.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a successful poll resets the failed-poll count" 0

case_dir
response OPEN $SHA '[]' "$BUILD" | jq '.data.repository.object.statusCheckRollup.contexts.pageInfo.hasNextPage = true' > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "more than 100 checks is a failed poll" 5
expect_in "the check limit is printed" out "more than 100 checks on the SHA; watch.sh reads only the first 100"

case_dir
response OPEN $SHA '[]' "$BUILD" | jq '.data.repository.object.checkSuites.pageInfo.hasNextPage = true' > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "more than 100 check suites is a failed poll" 5
expect_in "the check suite limit is printed" out "more than 100 check suites on the SHA; watch.sh reads only the first 100"

case_dir
echo '{"errors": [{"type": "RATE_LIMITED", "message": "API rate limit exceeded for user ID 1."}]}' > "$dir/1.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a GraphQL errors field counts as a failed poll" 5
expect_in "the GraphQL error message is printed" out "API rate limit exceeded for user ID 1."

case_dir
response OPEN $SHA "[$(review greptile-apps $SHA "$CREDIT")]" "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 5
expect_exit "a Greptile credit-limit review on the SHA exits 6" 6
expect_in "the bot and its notice are printed" out "greptile: \`crodris\` has reached the 50-credit limit"

case_dir
response OPEN $SHA "[$(review greptile-apps $OLD "$CREDIT")]" "$BUILD" "$(check_run "Greptile Review" COMPLETED SUCCESS)" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 5
expect_exit "a credit-limit review on an older commit is ignored" 0

case_dir
response OPEN $SHA "[$(review greptile-apps $SHA "Looks good. One rate limiter comment inline.")]" "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 5
expect_exit "Greptile settles on a review of the SHA with no check run" 0

case_dir
run 7 abc123 --repo o/r --interval 0
expect_exit "a short SHA is a usage error" 2
expect_count "a usage error never calls gh" gh.log "api graphql" 0

case_dir
run 7 $SHA --interval 0
expect_exit "a missing --repo is a usage error" 2

case_dir
run 7 $SHA --repo o/r --bot coderabbitai
expect_exit "an unknown bot is a usage error" 2

case_dir
got=0
PATH="$tmp/bin" FIXTURES=$dir "$BASH" "$WATCH" 7 $SHA --repo o/r --interval 0 --deadline 1 > "$dir/out" 2> "$dir/err" || got=$?
expect_exit "a missing jq is a usage error" 2
expect_in "the missing tools are named" out "needs gh and jq"

[ "$failures" = 0 ]
