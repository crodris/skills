---
name: scaffold
description: This skill should be used when the user asks to "scaffold these requirements", "scaffold an issue from this PRD or spec", "turn these requirements into an issue", "create an issue and sub-issues", or "break these requirements into tickets" for Asana or Linear. Creates a main issue plus linked sub-issues, then offers to hand off to the execute skill.
version: 3.0.1
---

# Scaffold

## Absolute boundary

Treat the connected tracker MCP as the only channel for tracker work.
When it is absent or disabled, refuse and stop, naming the missing MCP and saying the user must connect it, even when a bypass looks possible and helpful.
Never search for credentials in files, environment variables, or token caches, never call tracker HTTP APIs, and never edit MCP or agent configuration.
A disabled server is the user's decision and a stop condition.

This skill never writes task-memory or checklist files.

## Read first

Before any tracker work, read these files.
Their paths are relative to this SKILL.md's directory and point into the `execute` skill installed beside it.

- `../execute/trackers.md` for the tracker contract and the profile's default destination.
- `../execute/agents.md` for the per-agent notes and the structured question mechanism every question here uses.
- `../execute/approval.md` for the two approval modes and the stops that hold in both.

When `../execute/` does not exist, stop first and give its install command for the user to run, never running it yourself.
That is `npx skills@latest add crodris/skills -s execute file-pr -g` for a global install, without `-g` for a project install, with the install's `-a <agent>` flag, such as `-a kiro-cli`, and `/plugin install fathom@crodris` for a Claude Code plugin install.
When any of these files cannot be read, stop and report which paths were tried, never improvising its contract.

## Procedure

1. Resolve the approval mode per `../execute/approval.md` and state it.
   When the precedence in Preflight verification in `../execute/trackers.md` settles the tracker, run preflight against it, and stop when its MCP does not verify.
   The forge never gates this skill.
   When that precedence leaves two connected tracker MCPs to choose between, defer preflight to step 3.
2. Run the done-on-merge sweep per `../execute/trackers.md` once preflight has verified the MCP; when preflight was deferred, defer the sweep with it.
3. Resolve the tracker, then the destination.
   - Use the tracker step 1 settled.
     When it deferred preflight, ask once which tracker to use, then run preflight and the sweep against the answer.
     When no tracker MCP is connected, stop and name both supported trackers, Asana and Linear.
   - When the repository has no tracker profile, run first-run setup from `../execute/first-run.md` to completion first, so the destination below resolves from the profile it writes.
   - Resolve the destination per Destination resolution in `../execute/trackers.md`, passing an explicit destination hint to `resolveDestination`.
4. Gather the requirements.
   Take them from the invocation text, or read the file it names or points at, such as a PRD, spec, or design doc.
   Otherwise, or when the user names this conversation as the source, synthesize them from the conversation instead of interviewing the user.
   Summarize them in one or two sentences.
5. Read the files the requirements would touch, and name real files and functions in the sub-issue drafts.
   When nothing related exists yet, say so.
6. When the requirements are too thin to split, unclear in scope, or open to two incompatible readings, ask targeted questions about what is missing, one at a time, and wait for the answers before drafting.
   When they leave the approach open, propose two or three approaches with their trade-offs and recommend one.
   In ask mode, ask for the choice on its own, after every targeted question is answered, and wait; in auto mode, take the recommended one and say so.
7. Draft the scaffold.
   - The main issue: a title, a type (feature, bug, chore, or docs, defaulting to feature), and a description in four parts: the problem and the solution from the user's side, numbered user stories as "As a <actor>, I want <feature>, so that <benefit>", and the test seams, preferring the highest existing seam for each behavior.
   - Sub-issue drafts from the chosen approach, as many as the unit rule in `../execute/SKILL.md` step 8 allows, each a tracer-bullet vertical slice through every layer the change touches, demoable on its own.
   - Each draft's blocking edges, the drafts that must land before it or none, with the drafts ordered so every blocker comes before what it blocks.

   In ask mode, show the full draft as the only open question in that turn, apply any requested edits and show it again, and create nothing until the user approves it explicitly and unambiguously.
   An ambiguous or negative reply, such as a bare "decline", is not approval.
   In auto mode, create the scaffold at once and report the draft as what was created.
   When a reply could answer more than one open question, or its target is unclear, ask which question it answered.
8. Create the scaffold.
   - Call `createIssue` with the title, description, type, and resolved destination.
   - Call `createSubIssue` once per sub-issue draft, in order, linked to the main issue, and end each description with a `Blocked by:` line listing each blocker's Linear key or full Asana task URL, or `none`.
   - Report a compact block: the tracker, the main issue's ref, title, and URL, then one line per sub-issue with its ref and URL.
     Write each ref in the adapter's issue ref scheme, which for Asana is `asana-<last six digits of the GID>`.
   - In auto mode, put that block in the run's final reply beside execute's final summary.
9. Write `default-destination` into the profile only when it has none or the user asks to change it; a destination hint applies only to this issue.
10. Hand off with a reference `getIssue` can resolve in a fresh session: the Linear key, or the full Asana task URL, keeping the short Asana ref for display.
    In ask mode, ask "run execute on <ref> now?"; on yes, invoke execute on that reference, as Invoking another skill in `../execute/agents.md` says, and on no, stop.
    In auto mode, invoke execute on that reference the same way without asking, and say so.
