// Written by mods/fathom-progress/bin/sync-contract.sh from the Fathom skills. Do not edit:
// run the script again.

// The plan document lines conventions.md states, placeholders included.
export const planLines: readonly string[] = [
  "# <ISSUE-REF>: <title>",
  "- Issue: <tracker url>",
  "- Ref: <issue ref>",
  "- Branch: <branch>",
  "- Unit <n>: <title> -> sub-issue: pending",
  "- Bundle <k>/<N>: <branch> - <sub-issue refs, comma separated>",
  "- Review: pending (bundle k/N)",
  "- Review: <id> <url> (bundle k/N)",
  "- Review: none confirmed (bundle k/N)",
  "- Merge-closer: suppressed",
  "- Breakdown: pending",
  "- Finalization: complete",
]

// The example checklist in memory/checklist.md.
export const checklistExample = "# ONC-5: Add login flow\n\n- Issue: https://linear.app/acme/issue/ONC-5\n- Branch: feat/onc-5-add-login\n- Review: (id and url, filled at open)\n- PR: (legacy, read but no longer written)\n\n## Plan\n\nOne-paragraph approach summary.\nTesting notes.\n\n## Tasks\n\n- [x] 1. Create login form component -> sub-issue: https://... (done 2026-07-28, a1b2c3d)\n- [>] 2. Wire auth API (deps: 1) -> sub-issue: https://...\n- [ ] 3. Add e2e test (deps: 2) -> sub-issue: https://...\n"

// The bd create commands memory/beads.md states, placeholders included.
export const beadsCreates: readonly string[] = [
  "bd create \"<title>\" -d \"<description>\" -l \"<issueRef>\" --external-ref \"<subIssueRef>\" --deps \"<comma-separated blocker ids>\" --silent",
  "bd create \"<issueRef>\" --type epic --external-ref \"<issueRef>\" -l \"<issueRef>\" -p 1 --silent",
]

// The Skill tool names of the Fathom skills the band arms on.
export const skillNames: readonly string[] = [
  "fathom:execute",
  "fathom:scaffold",
]
