#!/usr/bin/env bash
# test-resolve-verify.sh - run skills/prove/resolve-verify.sh against scratch
# repositories and check the candidates it prints.
set -euo pipefail

RESOLVE="$(cd "$(dirname "$0")/.." && pwd)/skills/prove/resolve-verify.sh"
failures=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

case_dir() { dir=$(mktemp -d "$tmp/case.XXXX"); }
run() { got=0; bash "$RESOLVE" "$dir" > "$dir/.out" 2>&1 || got=$?; }

# expect <name> <exact expected output, tab-separated lines>
expect() {
  if [ "$(cat "$dir/.out")" = "$(printf '%b' "$2")" ]; then echo "ok: $1"; else
    echo "FAIL: $1"; echo "  want:"; printf '%b\n' "$2" | sed 's/^/  | /'; echo "  got:"; sed 's/^/  | /' "$dir/.out"
    failures=$((failures + 1)); fi
}

case_dir
echo '{"scripts": {"test": "vitest", "check": "tsc", "verify:ci": "run-s lint test"}}' > "$dir/package.json"
touch "$dir/pnpm-lock.yaml"
run
expect "aggregate scripts print in aggregate order with the lockfile's runner, before the composed fallback" \
  'aggregate\tpackage.json\tpnpm run verify:ci\naggregate\tpackage.json\tpnpm run check\ncompose\tpackage.json\tpnpm run test'

case_dir
echo '{"packageManager": "yarn@4.1.0", "scripts": {"ci": "x"}}' > "$dir/package.json"
touch "$dir/package-lock.json"
run
expect "a packageManager field outranks the lockfile" 'aggregate\tpackage.json\tyarn run ci'

case_dir
echo '{"packageManager": "npm; curl x | sh@1", "scripts": {"verify": "x"}}' > "$dir/package.json"
touch "$dir/pnpm-lock.yaml"
run
expect "an unrecognized packageManager name falls through to the lockfile" \
  'aggregate\tpackage.json\tpnpm run verify'

case_dir
printf 'CI ?= 1\nverify: lint test\n\t./run\nall:\n\ttrue\n' > "$dir/Makefile"
run
expect "Makefile targets, not variable assignments" 'aggregate\tMakefile\tmake verify\naggregate\tMakefile\tmake all'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on:
  pull_request:
jobs:
  test:
    steps:
      - uses: actions/checkout@v6
      - run: bin/lint.sh
      - name: Test
        run: |
          # a comment
          bin/test.sh
          bin/build.sh
YML
cat > "$dir/.github/workflows/release.yml" <<'YML'
on:
  push:
    branches: [main]
jobs:
  release:
    steps:
      - run: bin/release.sh
YML
run
expect "run steps of pull_request workflows only, with a block scalar as one command" \
  'ci\t.github/workflows/ci.yml\tbin/lint.sh\nci\t.github/workflows/ci.yml\tbin/test.sh && bin/build.sh'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on:
  pull_request:
jobs:
  test:
    steps:
      - run: |
          bin/a.sh
          bin/b.sh
        env:
          FOO: bar
YML
run
expect "a block scalar stops before a sibling key" \
  'ci\t.github/workflows/ci.yml\tbin/a.sh && bin/b.sh'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on: pull_request
jobs:
  ci:
    steps:
      - run: |
          if [ -f Makefile ]; then
            make test
          fi
YML
run
expect "a block scalar of shell control flow is an instruction" \
  'ci\t.github/workflows/ci.yml\tread the multi-line run step at line 5'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on: pull_request
jobs:
  ci:
    steps:
      - run: |
          npm ci &&
            npm test
YML
run
expect "a block scalar of shell operator line ends is an instruction" \
  'ci\t.github/workflows/ci.yml\tread the multi-line run step at line 5'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on: pull_request
jobs:
  ci:
    steps:
      - run: |
          python - <<'PY'
          print(1)
          PY
YML
run
expect "a block scalar with a heredoc is an instruction" \
  'ci\t.github/workflows/ci.yml\tread the multi-line run step at line 5'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on: pull_request
jobs:
  ci:
    steps:
      - run: >
          npm run lint
          --max-warnings 0
YML
run
expect "a folded block scalar is an instruction" \
  'ci\t.github/workflows/ci.yml\tread the multi-line run step at line 5'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on: pull_request
jobs:
  ci:
    defaults:
      run:
        shell: bash
    steps:
      - run: bin/check.sh
YML
run
expect "an empty run value does not start a block" \
  'ci\t.github/workflows/ci.yml\tbin/check.sh'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on: pull_request
jobs:
  ci:
    steps:
      - run: npm test
        working-directory: packages/api
YML
run
expect "a run step with working-directory is an instruction" \
  'ci\t.github/workflows/ci.yml\tread the run step at line 5, since this workflow sets working-directory'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on: pull_request
defaults:
  run:
    working-directory: packages/api
jobs:
  ci:
    steps:
      - run: npm test
YML
run
expect "a workflow defaults working-directory makes a run step an instruction" \
  'ci\t.github/workflows/ci.yml\tread the run step at line 8, since this workflow sets working-directory'

case_dir
mkdir -p "$dir/.github/workflows"
cat > "$dir/.github/workflows/ci.yml" <<'YML'
on: pull_request
jobs:
  ci:
    steps:
      - run: |
          npm ci
          npm test
        working-directory: packages/api
YML
run
expect "a block scalar with working-directory is an instruction" \
  'ci\t.github/workflows/ci.yml\tread the run step at line 5, since this workflow sets working-directory'

case_dir
echo '{"scripts": {"lint": "eslint .", "type-check": "tsc", "test": "vitest", "build": "vite build"}}' > "$dir/package.json"
touch "$dir/bun.lockb"
run
expect "compose runs lint, type check, test, then build" \
  'compose\tpackage.json\tbun run lint && bun run type-check && bun run test && bun run build'

case_dir
printf '[tool.ruff]\n[tool.pytest.ini_options]\n' > "$dir/pyproject.toml"
run
expect "compose from the Python tools pyproject.toml configures" 'compose\tpyproject.toml\truff check . && pytest'

case_dir
echo '{"scripts": {"prepare": "husky"}}' > "$dir/package.json"
printf 'module example.com/m\n' > "$dir/go.mod"
run
expect "a package.json whose scripts compose nothing falls through to go.mod" \
  'compose\tgo.mod\tgo vet ./... && go test ./...'

case_dir
touch "$dir/README.md"
run
if [ "$got" = 1 ] && [ ! -s "$dir/.out" ]; then echo "ok: no candidates exits 1 with no output"; else
  echo "FAIL: no candidates (exit $got)"; failures=$((failures + 1)); fi

if [ "$failures" != 0 ]; then echo "$failures case(s) failed"; exit 1; fi
echo "all resolve-verify.sh cases passed"
