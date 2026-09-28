#!/usr/bin/env bash
# Checks bin/scan-skills.sh against a stub skillspector that mimics v2.12.0's exit
# codes: 1 means the risk score is over threshold with a complete report, 2 means
# the scan failed.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
stub_dir="$(mktemp -d)"
trap 'rm -rf "$stub_dir"' EXIT

cat > "$stub_dir/skillspector" <<'STUB'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = --output ] && out="$2"; shift; done
issues='[]'
[ "$STUB_ACTIVE" = 1 ] && issues='[{"id":"X1","pattern":"p","severity":"HIGH","location":{"file":"SKILL.md","start_line":1}}]'
[ "$STUB_NOREPORT" = 1 ] || printf '{"risk_assessment":{"score":65,"severity":"HIGH","recommendation":"DO_NOT_INSTALL"},"issues":%s,"suppressed_count":3}' "$issues" > "$out"
exit "$STUB_EXIT"
STUB
chmod +x "$stub_dir/skillspector"

run() {
  STUB_EXIT="$1" STUB_ACTIVE="$2" STUB_NOREPORT="${3:-0}" PATH="$stub_dir:$PATH" "$repo_root/bin/scan-skills.sh" 2>&1 && echo "exit=0" || echo "exit=$?"
}

fail=0
check() {
  if printf '%s' "$2" | grep -q "$3"; then echo "ok: $1"; else echo "FAIL: $1"; printf '%s\n' "$2"; fail=1; fi
}

check "over threshold, all suppressed passes" "$(run 1 0)" "PASS: all scanned skills are clean"
check "over threshold, active findings fail as findings" "$(run 1 1)" "have non-suppressed findings"
check "exit 2 fails as a crash" "$(run 2 0)" "the scanner crashed on"
check "missing report fails as a crash" "$(run 1 0 1)" "the scanner crashed on"
exit "$fail"
