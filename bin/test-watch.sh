#!/usr/bin/env bash
# test-watch.sh - run skills/babysit/watch.sh against a fake gh that replays
# fixture responses in order, one per poll with the last one repeating, and
# logs every call. A poll's fixture is N.json, or N.err to fail with that
# stderr text, and comment.err makes every `gh pr comment` fail the same way.
# `gh api --paginate` of a pull request's review comments or reviews prints
# pr-comments.json or pr-reviews.json, else an empty list, and pr-comments.err
# makes it fail with that stderr text.
# `gh api` of the base's rulesets prints rules.json, else an empty list; of its
# branch protection prints protection.json, else fails with HTTP 404; and of a
# compare prints compare.json, else no files.
# Each case checks the exit code and, where it matters, stdout or the gh call log.
# WATCH_GRACE is 0 unless a case sets it, so a case settles on its first poll.
set -euo pipefail
export WATCH_GRACE=0

WATCH="$(cd "$(dirname "$0")/.." && pwd)/skills/babysit/watch.sh"
SHA=1111111111111111111111111111111111111111
OLD=2222222222222222222222222222222222222222
BASE_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
BASE_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
# shellcheck disable=SC2016 # the backticks are part of Greptile's notice text.
CREDIT='`crodris` has reached the 50-credit limit for trial accounts. Upgrade to keep reviewing.'
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_STATE_HOME="$tmp/state"

mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FIXTURES/gh.log"
if [ "$1 $2" = "pr comment" ] && [ -e "$FIXTURES/comment.err" ]; then cat "$FIXTURES/comment.err" >&2; exit 1; fi
if [ "$1 $2" = "api --paginate" ]; then
  if [ -e "$FIXTURES/pr-comments.err" ]; then cat "$FIXTURES/pr-comments.err" >&2; exit 1; fi
  case $3 in */comments) f=pr-comments.json ;; */reviews) f=pr-reviews.json ;; *) f=none ;; esac
  if [ -e "$FIXTURES/$f" ]; then cat "$FIXTURES/$f"; else echo '[]'; fi
  exit 0
fi
if [ "$1" = api ]; then
  case $2 in
    repos/*/rules/branches/*) if [ -e "$FIXTURES/rules.json" ]; then cat "$FIXTURES/rules.json"; else echo '[]'; fi; exit 0 ;;
    repos/*/protection/required_status_checks)
      if [ -e "$FIXTURES/protection.json" ]; then cat "$FIXTURES/protection.json"; exit 0; fi
      echo "HTTP 404: Branch not protected" >&2; exit 1 ;;
    repos/*/compare/*) if [ -e "$FIXTURES/compare.json" ]; then cat "$FIXTURES/compare.json"; else echo '{"files": []}'; fi; exit 0 ;;
  esac
fi
[ "$1 $2" = "api graphql" ] || exit 0
n=$(( $(cat "$FIXTURES/polls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FIXTURES/polls"
while [ "$n" -gt 1 ] && [ ! -e "$FIXTURES/$n.json" ] && [ ! -e "$FIXTURES/$n.err" ]; do n=$((n - 1)); done
if [ -e "$FIXTURES/$n.err" ]; then cat "$FIXTURES/$n.err" >&2; exit 1; fi
cat "$FIXTURES/$n.json"
STUB
chmod +x "$tmp/bin/gh"
PATH="$tmp/bin:$PATH"

check_run() { jq -cn --arg n "$1" --arg s "$2" --arg c "${3:-}" --arg title "${4:-}" --arg at "${5:-2020-01-01T00:05:00Z}" \
  '{__typename: "CheckRun", name: $n, status: $s, conclusion: (if $c == "" then null else $c end),
    title: (if $title == "" then null else $title end), completedAt: $at}'; }
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
# The base branch main is at $BASE, by default BASE_A, and the pull request
# changes the paths in the JSON array $FILES, by default none.
response() {
  local state=$1 head=$2 reviews=$3 ci_done='[{"status":"COMPLETED","conclusion":"SUCCESS","app":{"slug":"github-actions"},"workflowRun":{"workflow":{"name":"CI"}},"checkRuns":{"totalCount":1}}]'
  shift 3
  printf '%s\n' "$@" | jq -s --arg state "$state" --arg head "$head" --argjson reviews "$reviews" \
    --argjson suites "${SUITES:-$ci_done}" --arg base "${BASE:-$BASE_A}" --argjson files "${FILES:-[]}" '{data: {repository: {
    pullRequest: {state: $state, headRefOid: $head, baseRefName: "main", baseRef: {target: {oid: $base}},
      files: {pageInfo: {hasNextPage: false}, nodes: [$files[] | {path: .}]},
      reviews: {nodes: $reviews}, comments: {nodes: []}},
    object: {committedDate: "2020-01-01T00:00:00Z",
      statusCheckRollup: (if . == [] then null else {contexts: {nodes: .}} end),
      checkSuites: {nodes: $suites}}}}}'
}

case_dir() { dir=$(mktemp -d "$tmp/case.XXXX"); }

# finding <file> <login> <label line>: one comment or review by <login> whose body opens with <label line>.
finding() { jq -n --arg l "$2" --arg b "$3" '[{user: {login: $l}, body: ($b + "\n\n**Fix the thing.**")}]' > "$dir/$1"; }
CR_MAJOR='**<picture><img src="x.svg" alt=""></picture> Major** · **Functional Correctness**'
CR_MINOR='**<picture><img src="x.svg" alt=""></picture> Minor** · **Functional Correctness**'

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
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED SUCCESS)" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "a completed CodeRabbit check run settles with no status" 0

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MAJOR"
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED SKIPPED)" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED SUCCESS)" > "$dir/2.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "a skipped CodeRabbit check run is re-requested, then a success settles" 0
expect_count "a skipped CodeRabbit check run posts one re-request" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MINOR"
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED SKIPPED)" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "a skipped CodeRabbit check run asks for a re-request and exits 2 when nothing is Critical or Major" 2

case_dir
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit IN_PROGRESS)" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 1
expect_exit "an in-progress CodeRabbit check run does not settle" 4

case_dir
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "a rate-limited CodeRabbit check run exits 6" 6
expect_in "a rate-limited check run names the bot, the reason, and the notice" out "verdict: unavailable: coderabbit rate-limited: Review rate limited"
expect_count "a rate-limited check run under --bot posts nothing" gh.log "pr comment" 0

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MAJOR"
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" > "$dir/1.json"
cp "$dir/1.json" "$dir/2.json"
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED SUCCESS "Review completed")" > "$dir/3.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "a rate limit from before the re-request is ignored, then a completed review settles" 0
expect_count "a rate-limited check run posts one re-request" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MAJOR"
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited" 2099-01-01T00:00:00Z)" > "$dir/2.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "a fresh rate-limited CodeRabbit check run after the re-request exits 6" 6
expect_count "a fresh rate limit after the re-request posts one re-request" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review paused")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 1
expect_exit "a CodeRabbit success without Review completed never settles" 4
expect_in "CodeRabbit is reported pending" out "still pending: coderabbit pending"

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "a rate-limited CodeRabbit exits 6 at once" 6
expect_in "the bot, the reason, and the notice are printed" out "verdict: unavailable: coderabbit rate-limited: Review rate limited"
expect_count "a rate limit under --bot posts nothing" gh.log "pr comment" 0

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited")" > "$dir/1.json"
cp "$dir/1.json" "$dir/2.json"
cp "$dir/1.json" "$dir/3.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/4.json"
run 7 $SHA --repo o/r --retry coderabbit --interval 0 --deadline 5
expect_exit "--retry re-requests a rate-limited CodeRabbit, then settles" 0
expect_count "--retry posts exactly one re-request comment" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1
expect_count "--retry posts no other comment" gh.log "pr comment" 1
expect_in "a notice older than the re-request reads as pending" out "| coderabbit pending"

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited" 2099-01-01T00:00:00Z)" > "$dir/2.json"
run 7 $SHA --repo o/r --retry coderabbit --interval 0 --deadline 5
expect_exit "a second rate limit after the --retry post exits 6" 6
expect_count "a second rate limit is never re-requested" gh.log "pr comment" 1

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited")" > "$dir/1.json"
run 7 $SHA --repo o/r --retry coderabbit --retry-in 30 --interval 0 --deadline 1
expect_exit "--retry waits out --retry-in before posting" 4
expect_count "--retry posts nothing before --retry-in" gh.log "pr comment" 0

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MAJOR"
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review skipped: incremental reviews are disabled")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/2.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest waits on the bot and settles past an older skipped notice" 0
expect_count "--rerequest posts exactly one re-request comment" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1
expect_count "--rerequest posts no other comment" gh.log "pr comment" 1
first_poll=$(grep -n '^api graphql' "$dir/gh.log" | head -1 | cut -d: -f1)
first_post=$(grep -n '^pr comment' "$dir/gh.log" | head -1 | cut -d: -f1)
if [ -n "$first_poll" ] && [ -n "$first_post" ] && [ "$first_poll" -lt "$first_post" ]; then echo "ok: --rerequest posts after the first poll"; else
  echo "FAIL: --rerequest posts after the first poll (poll line ${first_poll:-none}, post line ${first_post:-none})"; failures=$((failures + 1)); fi

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MINOR"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/1.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest refuses a bot whose findings it labeled Minor at most" 2
expect_in "the refusal names the missing label" out "carries its own Critical or Major label"
expect_count "a refused --rerequest posts nothing" gh.log "pr comment" 0
expect_count "a refused --rerequest never polls" gh.log "api graphql" 0

case_dir
finding pr-comments.json "someone-else" "$CR_MAJOR"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/1.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest ignores a Major label in another author's comment" 2

case_dir
finding pr-reviews.json "coderabbitai" "**🟠 Major** | **⚡ Quick win**"
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit PENDING "Review in progress")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/2.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest accepts the older emoji Major label in a review body" 0
expect_count "the emoji-labelled re-request posts once" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1

case_dir
finding pr-comments.json "coderabbitai[bot]" "_⚠️ Potential issue_ | _🟠 Major_"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/1.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest accepts the italic Major label" 0

case_dir
finding pr-comments.json "coderabbitai[bot]" "_🟡 Minor_ | _⚡ Quick win_"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/1.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest refuses the italic Minor label" 2

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MINOR"
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review skipped: incremental reviews are disabled")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "--bot refuses a skipped notice's re-request when the bot labeled Minor at most" 2
expect_count "a refused --bot re-request posts nothing" gh.log "pr comment" 0

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MAJOR"
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review skipped: incremental reviews are disabled")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/2.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "--bot re-requests a skipped notice when the bot labeled a Major" 0
expect_count "the labelled --bot re-request posts once" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1

case_dir
response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$(check_run "Greptile Review" COMPLETED SUCCESS)" > "$dir/2.json"
run 7 $SHA --repo o/r --rerequest greptile --interval 0 --deadline 5
expect_exit "--rerequest greptile needs no label, since Greptile labels nothing" 0
expect_count "--rerequest greptile posts once" gh.log "pr comment 7 --repo o/r --body @greptileai" 1

case_dir
echo "HTTP 502: Bad Gateway" > "$dir/pr-comments.err"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/1.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "a failed read of the bot's findings exits 5" 5
expect_in "the failed read's stderr is printed" out "reading coderabbit findings failed: HTTP 502"

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MAJOR"
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit PENDING "Review in progress")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$CR_DONE" > "$dir/2.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest settles a bot that showed no notice" 0
expect_count "--rerequest posts for a bot that showed no notice" gh.log "pr comment 7 --repo o/r --body @coderabbitai review" 1

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MAJOR"
response MERGED $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review skipped")" > "$dir/1.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest on a merged pull request exits 7" 7
expect_count "--rerequest posts nothing on a merged pull request" gh.log "pr comment" 0

case_dir
finding pr-comments.json "coderabbitai[bot]" "$CR_MAJOR"
response OPEN $OLD '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review skipped")" > "$dir/1.json"
run 7 $SHA --repo o/r --rerequest coderabbit --interval 0 --deadline 5
expect_exit "--rerequest on a moved head exits 3" 3
expect_count "--rerequest posts nothing on a moved head" gh.log "pr comment" 0

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited")" > "$dir/1.json"
echo "HTTP 502: Bad Gateway" > "$dir/comment.err"
run 7 $SHA --repo o/r --retry coderabbit --interval 0 --deadline 5
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
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 5
expect_exit "a Greptile rate-limit review exits 6" 6
expect_in "the Greptile rate limit is printed" out "verdict: unavailable: greptile rate-limited: Rate limit exceeded"
expect_count "a Greptile rate limit under --bot posts nothing" gh.log "pr comment" 0

case_dir
response OPEN $SHA "[$(review greptile-apps $SHA "<h3>Greptile Summary</h3>
The new rate limiter looks right.")]" "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 5
expect_exit "a review that names a rate limiter is not a rate limit" 0

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
SUITES='[]' response OPEN $SHA '[]' > "$dir/1.json"
WATCH_GRACE=60 run 7 $SHA --repo o/r --interval 0 --deadline 1
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
WATCH_GRACE=60 run 7 $SHA --repo o/r --interval 0 --deadline 1
expect_exit "a passed check with no workflow registered does not settle early" 4
expect_in "the grace window is reported" out "60-second wait for late checks"

GUARD_DONE=$(suite github-actions COMPLETED Guard)
case_dir
SUITES="[$GUARD_DONE]" response OPEN $SHA '[]' "$(check_run guard COMPLETED SUCCESS)" > "$dir/1.json"
SUITES="[$GUARD_DONE,$CI_QUEUED]" response OPEN $SHA '[]' "$(check_run guard COMPLETED SUCCESS)" > "$dir/2.json"
SUITES="[$GUARD_DONE,$(suite github-actions COMPLETED CI)]" response OPEN $SHA '[]' \
  "$(check_run guard COMPLETED SUCCESS)" "$(check_run test COMPLETED FAILURE)" > "$dir/3.json"
WATCH_GRACE=2 run 7 $SHA --repo o/r --interval 0 --deadline 10
expect_exit "a workflow that registers after another one passed is still waited on" 1
expect_in "the late workflow's failed check is printed" out "verdict: failed: test"

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
expect_in "the bot, the reason, and its notice are printed" out "greptile out-of-credits: \`crodris\` has reached the 50-credit limit"

case_dir
response OPEN $SHA "[$(review greptile-apps $SHA "$CREDIT")]" "$BUILD" "$(status CodeRabbit SUCCESS "Review rate limited")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --bot greptile --interval 0 --deadline 5
expect_exit "two unavailable bots exit 6" 6
expect_in "the first unavailable bot is named" out "coderabbit rate-limited: Review rate limited"
expect_in "the second unavailable bot is named too" out "greptile out-of-credits:"

case_dir
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --bot greptile --interval 0 --deadline 1
expect_exit "a rate-limited CodeRabbit beside a Greptile that never posts exits 6" 6
expect_in "the verdict names the rate-limited CodeRabbit" out "coderabbit rate-limited: Review rate limited"
expect_in "the verdict names the silent Greptile" out "greptile silent: no status, check, review, or comment on $SHA within 1s"

case_dir
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --bot greptile --silent-after 0 --interval 0 --deadline 30
expect_exit "a rate-limited CodeRabbit beside a silent Greptile exits 6" 6
expect_in "the verdict names the rate-limited CodeRabbit" out "coderabbit rate-limited: Review rate limited"
expect_in "the verdict names the silent Greptile" out "greptile silent: no status, check, review, or comment on $SHA within 0s"
expect_count "it ends on the first poll" gh.log "api graphql" 1

case_dir
SUITES='[]' response OPEN $SHA "[$(review greptile-apps $SHA "Rate limit exceeded")]" > "$dir/1.json"
WATCH_GRACE=60 run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 1
expect_exit "a rate-limited bot inside the grace window with no checks registered does not exit 6" 4
expect_in "no checks are registered" out "no checks registered"
expect_in "the grace window is still open" out "60-second wait for late checks"

case_dir
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" > "$dir/1.json"
response OPEN $SHA '[]' "$BUILD" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" \
  "$(check_run "Greptile Review" COMPLETED SUCCESS)" > "$dir/2.json"
run 7 $SHA --repo o/r --bot coderabbit --bot greptile --interval 0 --deadline 5
expect_exit "a rate-limited CodeRabbit exits 6 once Greptile settles" 6
expect_count "it waits out the pending Greptile before exit 6" gh.log "api graphql" 2
expect_in "the rate-limited CodeRabbit is named once Greptile settles" out "verdict: unavailable: coderabbit rate-limited: Review rate limited"

case_dir
response OPEN $SHA '[]' "$(check_run test IN_PROGRESS)" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 1
expect_exit "a rate-limited bot with a check in progress does not exit 6 before the deadline" 4
expect_in "the check in progress reaches the deadline" out "verdict: deadline:"

case_dir
response OPEN $SHA '[]' "$(check_run test IN_PROGRESS)" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" > "$dir/1.json"
response OPEN $SHA '[]' "$(check_run test COMPLETED SUCCESS)" "$(check_run CodeRabbit COMPLETED NEUTRAL "Review rate limited")" > "$dir/2.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 5
expect_exit "a rate-limited bot exits 6 once the check finishes" 6
expect_count "it waits until the check finishes before exit 6" gh.log "api graphql" 2

case_dir
response OPEN $SHA "[$(review greptile-apps $OLD "$CREDIT")]" "$BUILD" "$(check_run "Greptile Review" COMPLETED SUCCESS)" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 5
expect_exit "a credit-limit review on an older commit is ignored" 0

case_dir
response OPEN $SHA "[$(review greptile-apps $SHA "Looks good. One rate limiter comment inline.")]" "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 5
expect_exit "Greptile settles on a review of the SHA with no check run" 0

case_dir
response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 1
expect_exit "a bot that shows nothing on the SHA by the deadline exits 6" 6
expect_in "the silent bot is named" out "verdict: unavailable: greptile silent: no status, check, review, or comment on $SHA"

case_dir
response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --silent-after 0 --interval 0 --deadline 30
expect_exit "a bot that shows nothing by --silent-after exits 6 before the deadline" 6
expect_in "the silent wait is named" out "greptile silent: no status, check, review, or comment on $SHA within 0s"
expect_count "it ends on the first poll" gh.log "api graphql" 1

case_dir
response OPEN $SHA '[]' "$BUILD" "$(check_run test IN_PROGRESS)" > "$dir/1.json"
run 7 $SHA --repo o/r --bot greptile --interval 0 --deadline 1
expect_exit "a silent bot beside a pending check is a plain deadline" 4

case_dir
response OPEN $SHA '[]' "$BUILD" "$(status CodeRabbit PENDING "Review in progress")" > "$dir/1.json"
run 7 $SHA --repo o/r --bot coderabbit --interval 0 --deadline 1
expect_exit "a bot whose review is in progress is not silent" 4

case_dir
echo '[{"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "lint"}]}}]' > "$dir/rules.json"
response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
WATCH_GRACE=60 run 7 $SHA --repo o/r --interval 0 --deadline 1
expect_exit "a required check that never reports keeps it waiting" 4
expect_in "the missing required check is printed" out "required checks not reported: lint"

case_dir
echo '[{"type": "required_status_checks", "parameters": {"required_status_checks": [{"context": "lint"}]}}]' > "$dir/rules.json"
response OPEN $SHA '[]' "$BUILD" "$(check_run lint COMPLETED SUCCESS)" > "$dir/1.json"
WATCH_GRACE=60 run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "every required check finished settles without the grace period" 0
expect_count "it settles on the first poll" gh.log "api graphql" 1

case_dir
echo '{"contexts": ["build"], "checks": [{"context": "e2e"}]}' > "$dir/protection.json"
response OPEN $SHA '[]' "$BUILD" > "$dir/1.json"
WATCH_GRACE=60 run 7 $SHA --repo o/r --interval 0 --deadline 1
expect_exit "branch protection's required checks count too" 4
expect_in "a protection check that never reports is printed" out "required checks not reported: e2e"

case_dir
FILES='["src/a.ts"]' response OPEN $SHA '[]' "$BUILD" "$(check_run test IN_PROGRESS)" > "$dir/1.json"
FILES='["src/a.ts"]' BASE=$BASE_B response OPEN $SHA '[]' "$BUILD" > "$dir/2.json"
echo '{"files": [{"filename": "README.md"}, {"filename": "src/a.ts"}]}' > "$dir/compare.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a base that moved onto this pull request's files exits 8" 8
expect_in "the moved base and the shared file are printed" out "base moved: aaaaaaa..bbbbbbb touches src/a.ts"
expect_in "it compares the first base with the new one" gh.log "api repos/o/r/compare/$BASE_A...$BASE_B"

case_dir
FILES='["src/a.ts"]' response OPEN $SHA '[]' "$BUILD" "$(check_run test IN_PROGRESS)" > "$dir/1.json"
FILES='["src/a.ts"]' BASE=$BASE_B response OPEN $SHA '[]' "$BUILD" > "$dir/2.json"
echo '{"files": [{"filename": "README.md"}]}' > "$dir/compare.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a base that moved elsewhere still passes" 0

case_dir
FILES='["src/a.ts"]' response OPEN $SHA '[]' "$BUILD" "$(check_run test IN_PROGRESS)" > "$dir/1.json"
FILES='["src/a.ts"]' BASE=$BASE_B response OPEN $SHA '[]' "$BUILD" > "$dir/2.json"
jq -n '{files: [range(300) | {filename: "other/\(.).ts"}]}' > "$dir/compare.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a moved base at the compare file limit counts as touching" 8
expect_in "a capped compare names the file limit" out "the base changed 300 or more files"

case_dir
FILES='["src/a.ts"]' response OPEN $SHA '[]' "$BUILD" "$(check_run test IN_PROGRESS)" > "$dir/1.json"
FILES='["src/a.ts"]' BASE=$BASE_B response OPEN $SHA '[]' "$(check_run test COMPLETED FAILURE)" > "$dir/2.json"
echo '{"files": [{"filename": "src/a.ts"}]}' > "$dir/compare.json"
run 7 $SHA --repo o/r --interval 0 --deadline 5
expect_exit "a failed check beside a moved base still exits 1" 1
expect_in "the moved base is printed beside the failure" out "base moved: aaaaaaa..bbbbbbb touches src/a.ts"

case_dir
run 7 abc123 --repo o/r --interval 0
expect_exit "a short SHA is a usage error" 2
expect_count "a usage error never calls gh" gh.log "api graphql" 0

case_dir
run 7 $SHA --interval 0
expect_exit "a missing --repo is a usage error" 2

case_dir
WATCH_GRACE=soon run 7 $SHA --repo o/r --interval 0
expect_exit "a WATCH_GRACE that is not whole seconds is a usage error" 2

case_dir
run 7 $SHA --repo o/r --bot coderabbitai
expect_exit "an unknown bot is a usage error" 2

case_dir
got=0
PATH="$tmp/bin" FIXTURES=$dir "$BASH" "$WATCH" 7 $SHA --repo o/r --interval 0 --deadline 1 > "$dir/out" 2> "$dir/err" || got=$?
expect_exit "a missing jq is a usage error" 2
expect_in "the missing tools are named" out "needs gh and jq"

case_dir
response OPEN "$SHA" '[]' "$(status CI PENDING running)" > "$dir/1.json"
response OPEN "$SHA" '[]' "$(status CI SUCCESS done)" > "$dir/2.json"
XDG_STATE_HOME="$dir/state" run 7 $SHA --repo o/r --interval 0
expect_exit "a watched head passes" 0
expect_count "a watched head is recorded once" state/ship/watch.log "$SHA " 1

case_dir
response OPEN "$OLD" '[]' "$(status CI SUCCESS done)" > "$dir/1.json"
mkdir -p "$dir/state/ship"
touch "$dir/state/ship/watch.log"
XDG_STATE_HOME="$dir/state" run 7 $SHA --repo o/r --interval 0
expect_exit "a head that moved exits 3" 3
expect_count "a head that moved is not recorded" state/ship/watch.log "$SHA " 0

case_dir
response CLOSED "$SHA" '[]' "$(status CI SUCCESS done)" > "$dir/1.json"
mkdir -p "$dir/state/ship"
touch "$dir/state/ship/watch.log"
XDG_STATE_HOME="$dir/state" run 7 $SHA --repo o/r --interval 0
expect_exit "a closed pull request exits 7" 7
expect_count "a closed pull request is not recorded" state/ship/watch.log "$SHA " 0

case_dir
response OPEN "$SHA" '[]' "$(status CI SUCCESS done)" > "$dir/1.json"
XDG_STATE_HOME=/dev/null run 7 $SHA --repo o/r --interval 0
expect_exit "a log that cannot be written does not change the exit" 0
expect_in "a log that cannot be written is named" err "could not record this watch"

case_dir
response OPEN "$SHA" '[]' "$(status CI SUCCESS done)" > "$dir/1.json"
HOME="$dir/home" XDG_STATE_HOME=relative run 7 $SHA --repo o/r --interval 0
expect_count "a relative XDG_STATE_HOME falls back to the home directory" home/.local/state/ship/watch.log "$SHA " 1

case_dir
response OPEN "$SHA" '[]' "$(status CI SUCCESS done)" > "$dir/1.json"
(
  unset HOME XDG_STATE_HOME
  run 7 $SHA --repo o/r --interval 0
  echo "$got" > "$dir/got"
)
got=$(cat "$dir/got")
expect_exit "an unset HOME does not change the exit" 0

[ "$failures" = 0 ]
