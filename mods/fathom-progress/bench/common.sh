# shellcheck shell=bash
# Shared by the scripts in this folder. Source it; do not run it.
# Written for bash 3.2, the one macOS ships: no associative arrays, no mapfile.

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BENCH_ROOT="$(cd "$BENCH_DIR/../../.." && pwd -P)"

die() { echo "${PROG:-bench}: $*" >&2; exit 1; }

# The bench repo's working folder: must hold a .fathom/config.md and must not be this
# repository, so a script can never rewrite this project's own .fathom/ records.
check_bench() {
  local work="$1"
  [ -d "$work" ] || die "$work is not a folder"
  work="$(cd "$work" && pwd -P)"
  [ "$work" != "$BENCH_ROOT" ] || die "$work is this repository, not a bench repo"
  case "$work/" in "$BENCH_ROOT"/*) die "$work is inside $BENCH_ROOT" ;; esac
  [ -f "$work/.fathom/config.md" ] || die "$work has no .fathom/config.md; make it with make-bench-repo.sh"
  BENCH_WORK="$work"
}

# A timeline file holds one run's states, one per step. See the README in this folder.
# Sets TL_TITLE, TL_TITLES, TL_DEPS and the parallel arrays TL_STEP, TL_TASKS, TL_PLAN,
# TL_EXTRAS and TL_EXPECT, with TL_N steps.
load_timeline() {
  local arg="$1" file line rest
  if [ -f "$arg" ]; then
    file="$arg"
  elif [ -f "$BENCH_DIR/timelines/$arg.tl" ]; then
    file="$BENCH_DIR/timelines/$arg.tl"
  else
    die "no timeline '$arg' (looked for it as a path and in $BENCH_DIR/timelines/)"
  fi
  TL_FILE="$file"
  TL_TITLE="Bench run"
  TL_TITLES="Create bench/a.txt; Create bench/b.txt; Create bench/c.txt"
  TL_DEPS=""
  TL_N=0
  TL_STEP=()
  TL_TASKS=()
  TL_PLAN=()
  TL_EXTRAS=()
  TL_EXPECT=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '' | '#'*) continue ;;
      '@title '*) TL_TITLE="${line#@title }"; continue ;;
      '@titles '*) TL_TITLES="${line#@titles }"; continue ;;
      '@deps '*) TL_DEPS="${line#@deps }"; continue ;;
      '@'*) die "$file: unknown directive: $line" ;;
    esac
    rest="$line"
    TL_STEP[$TL_N]="${rest%%::*}"; rest="${rest#*::}"
    TL_TASKS[$TL_N]="${rest%%::*}"; rest="${rest#*::}"
    TL_PLAN[$TL_N]="${rest%%::*}"; rest="${rest#*::}"
    TL_EXTRAS[$TL_N]="${rest%%::*}"; rest="${rest#*::}"
    TL_EXPECT[$TL_N]="$rest"
    case "${TL_PLAN[$TL_N]}" in plan | noplan) ;; *) die "$file: step ${TL_STEP[$TL_N]}: plan must be plan or noplan" ;; esac
    TL_N=$((TL_N + 1))
  done < "$file"
  [ "$TL_N" -gt 0 ] || die "$file has no steps"
}

# The index in the timeline arrays of step number $1, or an error.
index_of_step() {
  local want="$1" i=0
  while [ "$i" -lt "$TL_N" ]; do
    [ "${TL_STEP[$i]}" = "$want" ] && { echo "$i"; return 0; }
    i=$((i + 1))
  done
  die "$TL_FILE has no step $want"
}

title_of() {
  local n="$1" i=0 t old_ifs="$IFS"
  IFS=';'
  for t in $TL_TITLES; do
    i=$((i + 1))
    if [ "$i" -eq "$n" ]; then
      IFS="$old_ifs"
      echo "$t" | sed 's/^ *//; s/ *$//'
      return 0
    fi
  done
  IFS="$old_ifs"
  echo "Task $n"
}

# "1, 2" for task $1 when the timeline says `@deps 3=1,2`, else nothing.
deps_of() {
  local n="$1" w
  for w in $TL_DEPS; do
    if [ "${w%%=*}" = "$n" ]; then
      echo "${w#*=}" | sed 's/,/, /g'
      return 0
    fi
  done
  return 0
}

# The task lines for a marker string such as "x>o" (o open, > in progress, x done), in the
# format of memory/checklist.md in the Fathom skill. With `nohash` in $2 the highest done
# task has its date and no hash yet, as Fathom writes it until the next commit.
task_lines() {
  local markers="$1" extras="$2" i n ch mark title deps line last=0
  for ((i = 0; i < ${#markers}; i++)); do
    [ "${markers:$i:1}" = x ] && last=$((i + 1))
  done
  for ((i = 0; i < ${#markers}; i++)); do
    n=$((i + 1))
    ch="${markers:$i:1}"
    case "$ch" in
      o) mark=' ' ;;
      '>') mark='>' ;;
      x) mark='x' ;;
      *) die "marker '$ch' in '$markers' is not one of o > x" ;;
    esac
    title="$(title_of "$n")"
    deps="$(deps_of "$n")"
    line="- [$mark] $n. $title"
    if [ -n "$deps" ]; then line="$line (deps: $deps)"; fi
    line="$line -> sub-issue: SUB-$n"
    if [ "$ch" = x ]; then
      if [ "$n" -eq "$last" ] && [[ ",$extras," == *,nohash,* ]]; then
        line="$line (done 2026-10-20)"
      else
        line="$line (done 2026-10-20, a1b2c3$n)"
      fi
    fi
    printf '%s\n' "$line"
  done
}

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# Write $2 (a file) from stdin without ever leaving a half-written file, since the band
# may read it at any moment.
write_atomic() {
  local file="$1" tmp
  tmp="$file.tmp.$$"
  cat > "$tmp"
  mv "$tmp" "$file"
}

# Put the bench repo's records for $2 (a ref) in the state of timeline step index $3.
write_step() {
  local work="$1" ref="$2" i="$3"
  local tasks="${TL_TASKS[$i]}" plan="${TL_PLAN[$i]}" extras="${TL_EXTRAS[$i]}"
  local tdir="$work/.fathom/tasks" pdir="$work/.fathom/plans"
  local tfile="$tdir/$ref.md" pfile="$pdir/$ref.md" branch
  branch="feat/$(lower "$ref")-bench-run"
  mkdir -p "$tdir" "$pdir"

  case "$tasks" in
    -) rm -f "$tfile" ;;
    raw:*) printf '%s\n' "${tasks#raw:}" | sed "s/{ref}/$ref/g" | write_atomic "$tfile" ;;
    header | [o\>x]*)
      {
        printf '# %s: %s\n\n' "$ref" "$TL_TITLE"
        printf -- '- Issue: https://example.test/%s\n' "$ref"
        printf -- '- Branch: %s\n' "$branch"
        printf -- '- Review: (id and url, filled at open)\n\n'
        printf '## Plan\n\nWritten by mods/fathom-progress/bench/play-checklist.sh, not by Fathom.\n\n## Tasks\n\n'
        if [ "$tasks" != header ]; then task_lines "$tasks" "$extras"; fi
        if [[ ",$extras," == *,footer,* ]]; then printf -- '\n- Closed: 2026-10-20\n'; fi
      } | write_atomic "$tfile"
      ;;
    *) die "step ${TL_STEP[$i]}: tasks '$tasks' is not -, header, raw:<text> or a marker string" ;;
  esac

  if [ "$plan" = plan ]; then
    {
      printf '# %s: %s\n\n' "$ref" "$TL_TITLE"
      printf -- '- Issue: https://example.test/%s\n' "$ref"
      printf -- '- Ref: %s\n' "$ref"
      printf -- '- Branch: %s\n\n' "$branch"
      printf '## Tasks\n\nWritten by mods/fathom-progress/bench/play-checklist.sh, not by Fathom.\n'
    } | write_atomic "$pfile"
  else
    rm -f "$pfile"
  fi
}
