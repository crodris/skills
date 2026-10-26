# Approval modes

Both skills run in `ask` or `auto` mode.
The mode decides which questions get asked, never which conditions stop a run.

## Resolving the mode

Resolve it once at the start of a run, first match winning:

1. The invocation, for this run only.
   "Auto approve", "no need to ask", "just do it", or "run it through" mean `auto`.
   "Ask me first", "check with me", or "gated" mean `ask`, even when the profile says `auto`.
2. The `approval` field of `.fathom/config.md`, read on its own since the profile may not be loaded yet.
3. `ask`.

When first-run setup records a mode later in the same run, that mode governs the rest of the run.
State the resolved mode and the source that decided it.

## What auto mode skips

- The issue draft in `scaffold`: create the scaffold and report what was created.
- The approach choice in `scaffold`, when the requirements leave it open: take the recommended approach and name it in the report.
- The handoff question after scaffolding: continue into `execute` on the new issue.
- A tracker or destination tie that the documented precedence settles: resolve it and report the choice.
- Two first-run setup answers, each only when unambiguous: the destination when exactly one is available, and the state mapping when tracker state names match the three phases exactly.
  Record each with a note that it was auto-accepted, such as `default-destination: Prototypes (1209000000000001) # auto-accepted, only option`.
- The subagent model question in `execute`: resolve it as Subagent models in the agent file `agents.md` routes to says for auto mode, and report the choice.
- The bundle-split proposal in `execute`: apply the split and report the bundles.
  This applies only when the profile's `stacking` field reads `propose`.

## What auto mode never skips

Each of these stops fires in both modes.

- **An unverified tracker MCP.** Refuse and deliver setup instructions.
  An unverified forge is not a stop: it selects a capability tier per `forges.md`.
- **A test failure that cannot be fixed.** Stop and hold, and never push broken work or open a review.
- **A conflict while updating from the base branch.** Stop and hold, naming the conflicting files.
- **A review closed without merging.** Report it and ask whether to retry, rescope, or drop the work.
  It fires once per abandoned review when the tracker can list comments, and on every run otherwise.
- **Accepting a forge CLI found by the tier-2 probe.** Ask, per Adapter or nothing in `forges.md`.
- **A phase with no matching tracker state.** Ask.
- **The other first-run setup questions.** Ask the forge, base branch, and approval mode questions, and the merge-closer question whenever `trackers.md` offers it, offering any detected or current default only as a suggestion.
- **An ambiguous first-run setup answer.** Ask that question.
- **A reply whose target is unclear.** Ask which question it answered.
- **An issue ref that disagrees with the current branch.** Ask which one to work.
- **An issue already in the `done` phase.** Ask whether to reopen it or pick another.
- **Requirements too thin to break down.** Ask the targeted questions, and never invent a breakdown the requirements do not support.

Stops unrelated to approval, such as an unreadable contract file or a failed commit reconciliation, live in their procedures and also fire in both modes.
Place every new stop in the skip list, this list, or its defining procedure.

## Recording it

First-run setup asks for the mode as its own question, after the tracker questions, and records `approval: auto` or `approval: ask` in `.fathom/config.md`.
Editing that field changes the mode for every later run, and an invocation phrase changes it for one run.
When one skill hands off to the other, carry the resolved mode across and say which mode the handed-off run uses.

The `stacking` field decides whether `execute` may split one issue into a stack of reviews.
`propose` lets it propose a split when the breakdown crosses the threshold in `execute`, with `approval` deciding whether the proposal is a question or a report.
`never` means one review per issue in both modes.
An absent field means `never`, so a repository gets stacking only by writing `stacking: propose`.
