// What one sub-task is doing. `waiting` is blocked behind a task it depends on; `next`
// is a task with nothing left to wait for, which bd ready offers (or, in a checklist,
// an open task whose deps are all done). Several tasks can be next or in progress at
// once when a run goes in parallel. In review is not a task state: it is an overlay for
// a done task whose bundle's review is open.
export type TaskState = 'waiting' | 'next' | 'inProgress' | 'done'

// What the plan document (.fathom/plans/<ref>.md) records about one review. Only a
// `recorded` review names an id; `pending` (a run reached openReview and wrote no
// outcome) and `none` (the user confirmed there is none) both count as no record.
export type PlanReview =
  | { kind: 'recorded'; id: string; url: string }
  | { kind: 'pending' }
  | { kind: 'none' }

// One `- Bundle k/N: <branch> - <refs>` line: bundle `index` of `of`, the branch it
// is built on, the sub-issue refs it carries, and the review line beneath it.
export type PlanBundle = {
  index: number
  of: number
  branch: string
  refs: string[]
  review: PlanReview | null
}

// The plan document read back as data. `bundles` is empty when the issue was not
// split into a stack, and `review` is then the issue's own review line, if any.
export type Plan = {
  issue: string | null
  ref: string | null
  branch: string | null
  // The issue's title, read from the first heading, `# <ref>: <title>`. Fathom's
  // conventions fix the labels of the Issue, Ref and Branch lines but not the heading, so
  // a plan whose heading names no title (`# PHA-186 plan`) has none.
  title: string | null
  bundles: PlanBundle[]
  review: PlanReview | null
  isFinalized: boolean
}

// One sub-task of the run, in the order the chain runs it.
export type RunTask = {
  id: string
  // The sub-issue ref the task was created for (bd's external_ref). It names the
  // task's bundle in the plan document.
  ref: string | null
  title: string
  state: TaskState
  // A done task whose bundle has a recorded review, while the run is still executing.
  // The plan document does not say whether that review merged, so a recorded review
  // counts as open. A finished run has none.
  isInReview: boolean
}

// One task line of a checklist file (.fathom/tasks/<ref>.md), the memory backend Fathom
// uses when the base branch does not track beads. `number` is the task's permanent id,
// the one `deps` name. `doneOn` and `hash` are on a closed task only, and `hash` may be
// missing for a while: it is written after the commit and rides the next one.
export type ChecklistTask = {
  number: number
  title: string
  marker: 'open' | 'inProgress' | 'done'
  deps: number[]
  subIssue: string | null
  doneOn: string | null
  hash: string | null
}

// A checklist file read back as data. Every field is null or empty when the file does
// not say it, so a file that is not a checklist reads as an empty one. `review` is the
// Review line once it names an id; the placeholder Fathom writes before a review exists,
// and the legacy `PR` line (a URL and no id), leave it null, and the latter is `pr`.
export type Checklist = {
  ref: string | null
  title: string | null
  issue: string | null
  branch: string | null
  review: PlanReview | null
  pr: string | null
  tasks: ChecklistTask[]
}

// Where a `/fathom:scaffold` run stands, worked out from the events a mod sees (the
// tracker's MCP calls, the questions it asks, the turn ending), since scaffold records
// nothing a mod can read. `resolving` is the lookups before the tracker is verified;
// `drafting` is after, until the person is asked; `waiting` is the run waiting on the
// person (a question, or the draft's approval); `creating` is the tracker issues being
// made; `done` is created and handed off, or handed to execute.
export type ScaffoldPhase = 'resolving' | 'drafting' | 'waiting' | 'creating' | 'done'

// What the band shows. `idle` is not armed, so the band yields. `starting` is armed
// with no run found yet. `scaffold` is a scaffold run: its phase, and how many tracker
// issues it has made so far (the main issue and its sub-issues), with no total: the draft
// the person approves is text, so the count is known only as the issues appear. `creating`
// has an epic and the tasks made so far, with no total: the plan document that fixes it
// is written after the last task. `executing` and `finished` carry every task, and the
// issue's `title` when the plan document names one. `creating` has no title because the
// plan is written after the tasks, and bd holds none: Fathom makes the epic with the bare
// ref as its title (a checklist carries its title, so one from a checklist may have it).
// `unavailable` carries why neither bd nor a checklist could be read, so the band can
// say so instead of showing zeros.
export type Snapshot =
  | { kind: 'idle' }
  | { kind: 'starting' }
  | { kind: 'scaffold'; phase: ScaffoldPhase; created: number }
  | { kind: 'creating'; ref: string; created: number }
  | { kind: 'executing'; ref: string; title?: string; tasks: RunTask[] }
  | { kind: 'finished'; ref: string; title?: string; tasks: RunTask[] }
  | { kind: 'unavailable'; reason: string }

declare module 'claude-code' {
  interface PluginState {
    'fathom-progress': {
      // When the latest Fathom invocation of the session happened, in ms; null until
      // the first one and again after the session ends. While it is null the band
      // yields and nothing polls.
      armedAt: number | null
      // The issue refs the person typed after the Fathom command that armed the band,
      // upper-cased; empty when none, and again after the session ends.
      refs: string[]
      // What the band draws, rebuilt from bd or the run's checklist while armed.
      snapshot: Snapshot
      // The person's toggle, like beads-status has.
      isHidden: boolean
      // The time of the last tick, in ms, which a scaffold run's elapsed time is drawn from.
      // It moves each second while a scaffold run is going, and that is what redraws the band.
      tick: number
    }
  }
}
