# First-run tracker profile

Read this when the working tree has no `.fathom/config.md`, or when Tracker profile in `trackers.md` says to re-run setup.
Read Committing the profile alone when `SKILL.md` or `trackers.md` names it.

## Reusing an existing profile

Run each command below on its own, as the Permissions section of `agents.md` says.

1. Look for a local branch for this issue with `git branch --list --ignore-case '*/<issue-ref>-*'`, using the issue ref the run was given.
   When one exists and tracks `.fathom/config.md`, load the profile with `git show <branch>:.fathom/config.md`, and skip the offer and the setup questions below, since the run switches to that branch.
2. Otherwise list commits on other local branches that added or changed the profile, newest first, with `git log --branches --not HEAD --diff-filter=AM --format='%h %cI %s' -- .fathom/config.md`.
   Name the branches that carry each commit with `git branch --contains <commit>`.
   Read each branch's current profile with `git show <branch>:.fathom/config.md`, and skip a branch where that fails, since its tip deleted the profile.
   Before any setup question, offer each branch that still has a profile once, ordered by its newest listed commit.
   When the user accepts an offer, write that branch's profile, as `git show <branch>:.fathom/config.md` prints it, to `.fathom/config.md`, and skip the setup questions.
3. When no profile is found, or the user declines every offer, ask the setup questions.

## Setup questions

Ask the six questions in order, one at a time, and get each answer before the next question starts.
Never show a later question, or any other pending question such as scaffold's issue draft, beside an unanswered one.
Use the structured question mechanism named in the agent file that `agents.md` routes to.
When a reply could answer more than one pending question, or its target is unclear, ask which question it answered.
Never treat an ambiguous or negative reply as approval to create anything.
Auto mode may answer the destination and the state mapping itself, only as `approval.md` allows, and every other question goes to the user.

1. Destination.
   Call `listDestinations`, list the destinations, and let the user pick the profile's default.
2. State mapping.
   Read what the tracker offers, as the adapter file says: a Linear team's workflow states, or an Asana project's board sections and status custom fields.
   Propose a mapping onto `inProgress`, `inReview`, and `done`, and let the user confirm or correct it.
   When a phase has no matching state, which is common for `inReview`, say so, and never pick the nearest state or invent one.
   Offer three choices: the user adds a state in the tracker and you re-read the states, the phase maps onto another state with the lost distinction stated, or the phase stays unmapped and its transition is skipped.
   Record an unmapped phase as `unmapped` rather than omitting its line.
   No adapter operation creates a workflow state, so never claim to have added one.
3. Forge.
   Ask the first-run forge question in `forges.md`, and record the answer as `forge`.
   Ask it before question 4, since question 4 depends on the forge's declared capabilities.
4. Merge closer.
   Run the tracker adapter's merge-closer question under the forge rules in Tracker profile in `trackers.md`, and record the answer as `merge-closer`.
5. Base branch.
   Offer the repository's current branch as the default and its default branch as the alternative.
   When the current branch is a Fathom feature branch, meaning its name carries an issue ref and a branch prefix, offer the default branch instead and say why the current one was excluded.
   A base recorded on one issue's branch would make every later issue, for every teammate, build on that issue's unmerged work.
   Record the answer as `base-branch`.
6. Approval mode.
   Ask whether runs should stop for approval at the usual points or run straight through.
   Record `approval: ask` or `approval: auto` per `approval.md`, and say that the safety stops listed there fire in both modes.

Write `.fathom/config.md` only after all six questions have answers, including the default destination.
A profile is written only after every question has an answer, from the user or from an auto-accept that `approval.md` allows, never after setup was merely announced.
Neither ask about `stacking` nor write it; a repository opts into stacking by adding `stacking: propose` itself, per `approval.md`.

## Profile format

```markdown
# fathom tracker profile
tracker: asana
forge: github          # a bundled adapter name, "local" for .fathom/forge.md, or "none"
default-destination: Prototypes (1209000000000001)  # add "# auto-accepted" when auto mode chose it
base-branch: main
approval: ask
stacking: propose      # setup never writes this; a repository adds it by hand to allow stacks, per approval.md
merge-closer: native   # "none (forge has no hooks)" when the forge declares no ciHooks
state-mapping:
  inProgress: section "In Progress"
  inReview: section "Review"
  done: section "Done" + completed
```

## Committing the profile

Commit the profile on the issue branch, as the first commit the run makes there, so it reaches the base branch through review.
Never commit it on the base branch, since the issue branch is created from `origin/<base>` and would leave that commit behind.
A run that ends before an issue branch exists leaves the profile, and any merge-closer workflow written with it, uncommitted, and the next run that reaches an issue branch commits them there.
Commit a reused profile, and any edit a run makes to a tracked profile, the same way.

After fetching the base branch as the Base branch resolution section of `forges.md` says, and before switching to or creating the issue branch, handle an uncommitted `.fathom/config.md` against the target ref:
- When it is untracked or only staged and the target ref tracks it, compare the two with `git show <ref>:.fathom/config.md`.
  When they match, remove the copy, since git refuses to switch over an untracked file the target tracks: use `git clean --force -- .fathom/config.md` for an untracked copy and `git rm --force -- .fathom/config.md` for a staged one.
  When they differ, ask the user which profile to keep.
- When it is a modified tracked copy, leave it alone when `git diff --quiet HEAD <ref> -- .fathom/config.md` succeeds, since it then carries over the switch.
  Otherwise git refuses the switch.
  Discard the copy with `git restore --source=HEAD --staged --worktree -- .fathom/config.md` only when `git diff --quiet <ref> -- .fathom/config.md` succeeds and the index holds nothing else, meaning `git diff --cached --quiet <ref> -- .fathom/config.md` or `git diff --cached --quiet HEAD -- .fathom/config.md` succeeds, so a staged edit is never lost.
  Otherwise ask the user which profile to keep.

Never use `git checkout -f`, which also discards tracked changes.
