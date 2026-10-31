import type { Plan, RunTask, Snapshot, TaskState } from '../types'

// Everything here is a pure function over what bd printed, parsed, and the parsed
// plan document, so the lifecycle can test it without a session. `unknown` goes in
// and is narrowed here: a bd upgrade that changes a key is read as a missing field,
// not trusted.

// One epic bd lists, narrowed to what picking a run needs.
export type Epic = { id: string; ref: string; status: string; createdAt: number; updatedAt: number }

type Task = {
  id: string
  ref: string | null
  title: string
  status: string
  createdAt: number
  blockers: string[]
}

const NOT_A_LIST = 'bd did not return a JSON list'

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function text(value: unknown): string {
  return typeof value === 'string' ? value : ''
}

// bd's timestamps are ISO strings with second resolution. One that does not parse
// reads as the epoch, which sorts it first.
function time(value: unknown): number {
  const parsed = typeof value === 'string' ? Date.parse(value) : Number.NaN
  return Number.isNaN(parsed) ? 0 : parsed
}

// The Fathom epics in `bd list --type epic --all`. Fathom makes its epic with the
// issue ref as both the external ref and a label, so an epic without that pair is
// someone else's and is not a run. Null when bd did not return a list.
export function parseEpics(value: unknown): Epic[] | null {
  if (!Array.isArray(value)) return null
  const epics: Epic[] = []
  for (const item of value) {
    if (!isRecord(item)) continue
    const id = text(item.id)
    const ref = text(item.external_ref)
    const labels: unknown[] = Array.isArray(item.labels) ? item.labels : []
    if (id && ref && labels.includes(ref)) {
      epics.push({
        id,
        ref,
        status: text(item.status),
        createdAt: time(item.created_at),
        updatedAt: time(item.updated_at),
      })
    }
  }
  return epics
}

function newest(epics: readonly Epic[], key: 'createdAt' | 'updatedAt'): Epic | null {
  let best: Epic | null = null
  for (const epic of epics) {
    // bd lists in no order worth trusting, so a tie in the second goes to the id.
    if (best === null || epic[key] > best[key] || (epic[key] === best[key] && epic.id > best.id)) {
      best = epic
    }
  }
  return best
}

// What names the issue of the invocation, when something does: its upper-cased refs, and
// whether a person typed them (`isExact`) or only the branch is named for them.
export type RunHint = { refs: readonly string[]; isExact: boolean }

// The run the band shows: the newest epic created since the latest Fathom
// invocation, otherwise the open epic with the most recent activity (a resumed
// issue, whose epic is older than this invocation). A closed epic is only picked
// by the first rule, so a finished run stays up until the next one starts.
// `armedAt` is that invocation's time in ms.
//
// Without a hint, a resumed run whose old epic is still open is shown from the moment of
// the invocation, since nothing says which issue the invocation named.
//
// A `hint` settles what that guess cannot. The named run is shown open or closed, so a
// finished run is shown as finished, not left waiting for an epic that will not come.
// - A typed ref is the issue: only its epic is shown, and until it has one the band
//   waits, never showing some other open run.
// - A branch's ref is a better guess than the latest activity, and no more: an epic made
//   since the invocation still wins (the person may be starting another issue than the
//   one the branch is for), and with no epic for the ref the old guess stands.
export function pickRun(epics: readonly Epic[], armedAt: number, hint?: RunHint): Epic | null {
  // Epics are stamped to the second, so one made in the invocation's own second
  // counts as made after it.
  const since = Math.floor(armedAt / 1000) * 1000
  const made = newest(
    epics.filter(e => e.createdAt >= since),
    'createdAt',
  )
  const latest = newest(
    epics.filter(e => e.status !== 'closed'),
    'updatedAt',
  )

  const refs = hint?.refs ?? []
  if (refs.length === 0) return made ?? latest

  const named = epics.filter(e => refs.includes(e.ref.toUpperCase()))
  const pick =
    newest(
      named.filter(e => e.createdAt >= since),
      'createdAt',
    ) ??
    newest(
      named.filter(e => e.status !== 'closed'),
      'updatedAt',
    ) ??
    newest(named, 'updatedAt')
  return hint?.isExact ? pick : (made ?? pick ?? latest)
}

function parseTasks(value: unknown): Task[] | null {
  if (!Array.isArray(value)) return null
  const tasks: Task[] = []
  for (const item of value) {
    if (!isRecord(item)) continue
    const id = text(item.id)
    if (!id) continue
    const dependencies: unknown[] = Array.isArray(item.dependencies) ? item.dependencies : []
    tasks.push({
      id,
      ref: text(item.external_ref) || null,
      title: text(item.title),
      status: text(item.status),
      createdAt: time(item.created_at),
      // Only `blocks` edges order the chain; a parent-child edge does not.
      blockers: dependencies.flatMap(d =>
        isRecord(d) && d.type === 'blocks' && text(d.depends_on_id) ? [text(d.depends_on_id)] : [],
      ),
    })
  }
  return tasks
}

function earlier(a: Task, b: Task): number {
  return a.createdAt - b.createdAt || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
}

// Until the breakdown finishes, tasks may still be added, so the total is not known. A
// plan document written by an older Fathom has no pending line and exists only once the
// breakdown is done, so a plan without the line counts as finished.
export function isBreakdownOpen(plan: Plan | null): boolean {
  return plan === null || plan.isBreakdownPending
}

// The tasks in the order the chain runs them. bd lists in no useful order and
// created_at ties within a second, so the order comes from the blocks edges: a task
// follows every task that blocks it, and tasks that are free at the same time go
// oldest first. Fathom chains its tasks, so in practice this is a line. A cycle,
// which bd does not allow, would stall it, so what is left then goes oldest first.
function inChainOrder(tasks: readonly Task[]): Task[] {
  const ids = new Set(tasks.map(t => t.id))
  const left = new Map(tasks.map(t => [t.id, t]))
  const ordered: Task[] = []
  while (left.size > 0) {
    const pending = [...left.values()]
    const free = pending.filter(t => t.blockers.every(b => !ids.has(b) || !left.has(b)))
    const next = [...(free.length > 0 ? free : pending)].sort(earlier)[0]
    if (!next) break
    ordered.push(next)
    left.delete(next.id)
  }
  return ordered
}

// Fathom titles a task `<issue ref>: <task title>`; the band already shows the ref.
export function shortTitle(title: string, ref: string): string {
  const prefix = `${ref}: `
  const bare = title.startsWith(prefix) ? title.slice(prefix.length) : title
  return bare.replace(/\s+/g, ' ').trim()
}

// The sub-issue refs of every bundle whose review is recorded, while the plan is
// not final. A single-review issue opens its review as the last step, so it has no
// task to mark.
export function reviewedRefs(plan: Plan | null): Set<string> {
  const refs = new Set<string>()
  if (plan === null || plan.isFinalized) return refs
  for (const bundle of plan.bundles) {
    if (bundle.review?.kind === 'recorded') bundle.refs.forEach(ref => refs.add(ref))
  }
  return refs
}

// Closed is done, claimed is in progress, and an open task is next only when bd
// ready offers it, since bd keeps an open task with an unmet blocker at `open`.
// Everything else waits. bd 1.1.0 leaves a claimed task out of `ready`; 0.49.0 kept
// it in, so the stored status is read first.
function stateOf(status: string, isReady: boolean): TaskState {
  if (status === 'closed') return 'done'
  if (status === 'in_progress') return 'inProgress'
  return isReady ? 'next' : 'waiting'
}

// The snapshot for the picked run. `tasks` and `ready` are what `bd list -l <ref>
// --type task --all` and `bd ready -l <ref> --type task` printed; `plan` is the
// parsed plan document, or null when there is none to read.
//
// A run with an open breakdown and no task started is still being created. Once the
// breakdown is done, or any task has been claimed, the total is known and the run is
// executing, until every task is closed.
export function toSnapshot(input: {
  epic: Epic
  tasks: unknown
  ready: unknown
  plan: Plan | null
}): Snapshot {
  const tasks = parseTasks(input.tasks)
  if (tasks === null || !Array.isArray(input.ready)) {
    return { kind: 'unavailable', reason: NOT_A_LIST }
  }
  const { ref } = input.epic

  if (isBreakdownOpen(input.plan) && tasks.every(t => t.status === 'open')) {
    return { kind: 'creating', ref, created: tasks.length }
  }

  const readyIds = new Set(
    input.ready.flatMap(item => (isRecord(item) && text(item.id) ? [text(item.id)] : [])),
  )
  const reviewed = reviewedRefs(input.plan)
  const run: RunTask[] = inChainOrder(tasks).map(t => {
    const state = stateOf(t.status, readyIds.has(t.id))
    return {
      id: t.id,
      ref: t.ref,
      title: shortTitle(t.title, ref),
      state,
      isInReview: state === 'done' && t.ref !== null && reviewed.has(t.ref),
    }
  })

  // A finished run shows no review marks: the design's done state is all green, and
  // the plan's Finalization line can land after the last task closes, so nothing here
  // could know when to take the marks off.
  // The issue's title comes from the plan document's heading, since bd's epic is titled
  // with the bare ref. A plan with no title leaves it out.
  const title = input.plan?.title ? { title: input.plan.title } : {}
  const isFinished = run.length > 0 && run.every(t => t.state === 'done')
  if (isFinished) return { kind: 'finished', ref, ...title, tasks: run.map(t => ({ ...t, isInReview: false })) }
  return { kind: 'executing', ref, ...title, tasks: run }
}

// The task the line under the bar names: the one in progress, else the next one bd
// offers. Null when neither exists, as when every task is done.
export function currentOf(
  tasks: readonly RunTask[],
): { index: number; state: 'inProgress' | 'next' } | null {
  for (const state of ['inProgress', 'next'] as const) {
    const index = tasks.findIndex(t => t.state === state)
    if (index !== -1) return { index, state }
  }
  return null
}

// Done over total, by count: a task counts when it is closed, whether or not its
// review is still open. The percent follows the count, not the width of the
// segments, so it does not move when the widths do.
export function progressOf(tasks: readonly RunTask[]): { done: number; total: number; percent: number } {
  const done = tasks.filter(t => t.state === 'done').length
  const total = tasks.length
  return { done, total, percent: total === 0 ? 0 : Math.round((done / total) * 100) }
}
