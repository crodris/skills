#!/usr/bin/env bash
# test-land.sh - run skills/land/release-watch.sh against a fake gh that replays
# run listings in order, one per call with the last one repeating, and
# skills/land/cleanup.sh in scratch repositories with a bare remote and a fake
# gh that reports the pull request's state.
# shellcheck disable=SC2016 # check takes its condition in single quotes and evals it.
set -euo pipefail

LAND="$(cd "$(dirname "$0")/.." && pwd)/skills/land"
SHA=1111111111111111111111111111111111111111
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
# shellcheck disable=SC2016 # check takes its condition in single quotes and evals it.
set -euo pipefail
printf '%s\n' "$*" >> "$FIXTURES/gh.log"
if [ "$1 $2" = "pr view" ]; then cat "$FIXTURES/pr.json"; exit 0; fi
[ "$1 $2" = "run list" ] || exit 0
n=$(( $(cat "$FIXTURES/calls" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FIXTURES/calls"
while [ "$n" -gt 1 ] && [ ! -e "$FIXTURES/$n.json" ] && [ ! -e "$FIXTURES/$n.err" ]; do n=$((n - 1)); done
if [ -e "$FIXTURES/$n.err" ]; then cat "$FIXTURES/$n.err" >&2; exit 1; fi
cat "$FIXTURES/$n.json"
STUB
chmod +x "$tmp/bin/gh"
PATH="$tmp/bin:$PATH"

case_dir() { dir=$(mktemp -d "$tmp/case.XXXX"); }
expect() {
  if [ "$got" = "$2" ]; then echo "ok: $1"; else
    echo "FAIL: $1 (exit $got, want $2)"; sed 's/^/  | /' "$dir/out"; failures=$((failures + 1)); fi
}
expect_in() {
  if grep -qF -- "$2" "$dir/out"; then echo "ok: $1"; else
    echo "FAIL: $1 (output lacks '$2')"; sed 's/^/  | /' "$dir/out"; failures=$((failures + 1)); fi
}
check() { if eval "$2"; then echo "ok: $1"; else echo "FAIL: $1"; failures=$((failures + 1)); fi; }

watch() { got=0; FIXTURES=$dir bash "$LAND/release-watch.sh" "$SHA" --repo o/r --base main --interval 0 --settle 0 "$@" > "$dir/out" 2>&1 || got=$?; }
run_json() { jq -cn --arg n "$1" --arg s "$2" --arg c "${3:-}" '{name: $n, status: $s, conclusion: $c}'; }

case_dir
echo "[$(run_json CI completed success),$(run_json Release completed skipped)]" > "$dir/1.json"
watch
expect "every run on the commit passed exits 0" 0
expect_in "the passed runs are named" "verdict: passed: CI, Release"

case_dir
echo '[]' > "$dir/1.json"
echo "[$(run_json Release in_progress)]" > "$dir/2.json"
echo "[$(run_json Release completed failure)]" > "$dir/3.json"
watch
expect "a run that appears late and fails exits 1" 1
expect_in "the failed run is named" "verdict: failed: Release"

case_dir
echo '[]' > "$dir/1.json"
watch --start-timeout 0
expect "no run on the commit exits 3" 3

case_dir
echo "[$(run_json Release in_progress)]" > "$dir/1.json"
watch --deadline 0
expect "a run still going at the deadline exits 4" 4
expect_in "the run still going is named" "still going: Release"

case_dir
echo '[]' > "$dir/1.json"
watch --deadline 0 --start-timeout 30
expect "no run yet at a deadline inside the start timeout exits 4" 4
expect_in "a deadline with no run says no run yet" "verdict: deadline: no run yet"

case_dir
echo "[$(run_json CI completed success),$(run_json Release completed success)]" > "$dir/1.json"
watch --settle 30 --deadline 0
expect "finished runs inside the settle window exit 4" 4

case_dir
echo "HTTP 502" > "$dir/1.err"
watch
expect "three failed listings exit 5" 5

case_dir
watch --base 'bad name'
expect "an invalid base is a usage error" 2

# repo <dir>: a clone at $dir/work of a bare remote, with branch feat/x pushed.
repo() {
  git init -q --bare -b main "$dir/remote.git"
  git clone -q "$dir/remote.git" "$dir/work" 2>/dev/null
  git -C "$dir/work" config user.email t@example.com
  git -C "$dir/work" config user.name t
  git -C "$dir/work" commit -q --allow-empty -m base
  git -C "$dir/work" push -q origin main
  git -C "$dir/work" switch -q -c feat/x
  git -C "$dir/work" commit -q --allow-empty -m work
  git -C "$dir/work" push -q -u origin feat/x
  git -C "$dir/work" switch -q -c other
  git -C "$dir/work" switch -q feat/x
  merged_pr feat/x "$(git -C "$dir/work" rev-parse feat/x)"
}
merged_pr() { printf '{"state": "MERGED", "headRefName": "%s", "headRefOid": "%s"}\n' "$1" "$2" > "$dir/pr.json"; }
clean() { got=0; (cd "$1" && FIXTURES=$dir bash "$LAND/cleanup.sh" 7 "${@:2}" --repo o/r) > "$dir/out" 2>&1 || got=$?; }
has_local() { git -C "$dir/work" show-ref --verify --quiet "refs/heads/$1"; }
has_remote() { git -C "$dir/remote.git" show-ref --verify --quiet "refs/heads/$1"; }

case_dir
repo
clean "$dir/work" feat/x main
expect "a run without a worktree cleans up" 0
check "it switches the checkout to the base" '[ "$(git -C "$dir/work" branch --show-current)" = main ]'
check "it deletes the local branch" '! has_local feat/x'
check "it deletes the remote branch" '! has_remote feat/x'
check "it leaves other branches alone" 'has_local other'

case_dir
repo
git -C "$dir/work" switch -q main
git -C "$dir/work" worktree add -q "$dir/wt" feat/x
clean "$dir/work" feat/x main --worktree "$dir/wt"
expect "a worktree run cleans up" 0
check "it removes the worktree" '[ ! -d "$dir/wt" ]'
check "it deletes the branch after the worktree" '! has_local feat/x && ! has_remote feat/x'

case_dir
repo
echo '{"state": "OPEN", "headRefName": "feat/x"}' > "$dir/pr.json"
clean "$dir/work" feat/x main
expect "an unmerged pull request is refused" 3
check "an unmerged pull request's branch stays" 'has_local feat/x && has_remote feat/x'

case_dir
repo
merged_pr feat/y "$(git -C "$dir/work" rev-parse feat/x)"
clean "$dir/work" feat/x main
expect "a pull request merged from another branch is refused" 3

case_dir
repo
git -C "$dir/work" commit -q --allow-empty -m "after the merge"
clean "$dir/work" feat/x main
expect "a local commit past the merged head is refused" 3
check "a local commit past the merged head keeps its branch" 'has_local feat/x && has_remote feat/x'

case_dir
repo
git -C "$dir/work" switch -q main
git -C "$dir/work" worktree add -q "$dir/wt" feat/x
git -C "$dir/wt" commit -q --allow-empty -m "after the merge"
git -C "$dir/wt" push -q
clean "$dir/work" feat/x main --worktree "$dir/wt"
expect "a pushed commit past the merged head is refused" 3
check "the refusal comes before the worktree is removed" '[ -d "$dir/wt" ]'

case_dir
repo
git -C "$dir/work" switch -q main
git -C "$dir/work" worktree add -q "$dir/wt" feat/x
touch "$dir/wt/stray"
clean "$dir/work" feat/x main --worktree "$dir/wt"
expect "a dirty worktree is refused" 3
check "a dirty worktree stays" '[ -e "$dir/wt/stray" ]'

case_dir
repo
git -C "$dir/work" switch -q main
git -C "$dir/work" worktree add -q "$dir/wt" feat/x
clean "$dir/wt" feat/x main --worktree "$dir/wt"
expect "running inside the worktree it removes is refused" 3

case_dir
repo
merged_pr main "$(git -C "$dir/work" rev-parse main)"
clean "$dir/work" main main
expect "the base branch is refused" 3
check "the base branch stays" 'has_local main && has_remote main'

case_dir
repo
git clone -q "$dir/remote.git" "$dir/other"
git -C "$dir/other" config user.email t@example.com
git -C "$dir/other" config user.name t
git -C "$dir/other" switch -q feat/x
git -C "$dir/other" commit -q --allow-empty -m "after the merge"
git -C "$dir/other" push -q
git -C "$dir/work" config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
git -C "$dir/work" update-ref -d refs/remotes/origin/feat/x
clean "$dir/work" feat/x main
expect "a remote commit past the merged head is refused when origin/<branch> is not fetched" 3
check "a remote commit past the merged head keeps its branch" 'has_remote feat/x'

case_dir
repo
cat > "$dir/work/.git/hooks/post-checkout" <<EOF
#!/usr/bin/env bash
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
if [ -e "$dir/pushed" ]; then exit 0; fi
touch "$dir/pushed"
git clone -q "$dir/remote.git" "$dir/late"
git -C "$dir/late" config user.email t@example.com
git -C "$dir/late" config user.name t
git -C "$dir/late" switch -q feat/x
git -C "$dir/late" commit -q --allow-empty -m "after the check"
git -C "$dir/late" push -q origin HEAD:feat/x
EOF
chmod +x "$dir/work/.git/hooks/post-checkout"
clean "$dir/work" feat/x main
check "a push after the check survives the delete" '[ "$got" != 0 ]'
check "the late push is still the remote tip" 'has_remote feat/x && [ "$(git -C "$dir/remote.git" rev-parse feat/x)" = "$(git -C "$dir/late" rev-parse HEAD)" ]'

case_dir
repo
git clone -q "$dir/remote.git" "$dir/ahead"
git -C "$dir/ahead" config user.email t@example.com
git -C "$dir/ahead" config user.name t
git -C "$dir/ahead" commit -q --allow-empty -m "base moved"
git -C "$dir/ahead" push -q origin main
git -C "$dir/work" config remote.origin.fetch '+refs/heads/feat/x:refs/remotes/origin/feat/x'
clean "$dir/work" feat/x main
expect "a narrowed fetch refspec still fast-forwards the local base" 0
check "the local base matches the remote base" '[ "$(git -C "$dir/work" rev-parse main)" = "$(git -C "$dir/remote.git" rev-parse main)" ]'

case_dir
repo
git -C "$dir/work" switch -q -c fix
git -C "$dir/work" push -q origin fix:x/fix
merged_pr fix "$(git -C "$dir/work" rev-parse fix)"
clean "$dir/work" fix main
expect "a branch already deleted on the remote is cleaned up beside a remote branch that ends in its name" 0
check "it deletes the local branch beside a remote branch that ends in its name" '! has_local fix'
check "it leaves the remote branch that ends in its name" 'has_remote x/fix'

case_dir
repo
cat > "$dir/work/.git/hooks/post-checkout" <<EOF
#!/usr/bin/env bash
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
git -C "$dir/work" config remote.origin.url "$dir/missing.git"
EOF
chmod +x "$dir/work/.git/hooks/post-checkout"
clean "$dir/work" feat/x main
expect "a remote lookup that fails is refused" 3
check "a failed remote lookup does not report a cleanup" '! grep -qF "cleaned up" "$dir/out"'

case_dir
repo
git -C "$dir/work" switch -q main
git -C "$dir/work" worktree add -q "$dir/wt" feat/x
clean "$dir/work" feat/x main
expect "a branch another worktree holds still cleans up" 0
check "the worktree that holds the branch keeps it" 'has_local feat/x && [ -d "$dir/wt" ]'
check "the remote branch is still deleted when another worktree holds the branch" '! has_remote feat/x'

if [ "$failures" != 0 ]; then echo "$failures case(s) failed"; exit 1; fi
echo "all land script cases passed"
