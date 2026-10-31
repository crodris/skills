import type { Checklist, ChecklistTask, Plan, RunTask, Snapshot, TaskState } from '../types'
import { isBreakdownOpen, reviewedRefs, shortTitle } from './state'
import type { Epic } from './state'

// The checklist file at .fathom/tasks/<ref>.md, read back as data: the memory backend
// Fathom uses when the base branch does not track beads (memory/checklist.md in the
// Fathom skill). The file in the working tree is the truth, not the last commit, since
// the in-progress marker is left uncommitted. Everything here is pure over the text, so
// it can be tested without a session.
const FENCE = /^\s*(```|~~~)/
// The header, `# <ref>: <title>`. The title may be missing in a file `init` just made.
const HEADING = /^# +([A-Za-z][A-Za-z0-9]*-\d+)(?:: +(\S.*?))?\s*$/
const SECTION = /^## +(.+?)\s*$/
const LINK = /^\s*- (Issue|Branch|Review|PR): (.+?)\s*$/
const TASK = /^\s*- \[( |>|x)\] (\d+)\. (.+?)\s*$/
// The tail close writes: `(done YYYY-MM-DD)`, then the hash once the commit exists.
const DONE = /\s*\(done (\d{4}-\d{2}-\d{2})(?:, ([0-9a-f]{4,40}))?\)\s*$/
const SUB_ISSUE = /\s*->\s*sub-issue:\s*(\S+)\s*$/
const DEPS = /\s*\(deps:\s*(\d+(?:\s*,\s*\d+)*)\s*\)/

const MARKERS = { ' ': 'open', '>': 'inProgress', x: 'done' } as const

// One line under `## Tasks`, or null for any other line: a blank, the `Closed` footer an
// older sweep appended, prose, or a task line too broken to name a number and a title.
function taskOf(line: string): ChecklistTask | null {
  const match = TASK.exec(line)
  if (!match) return null
  const marker = MARKERS[(match[1] ?? ' ') as keyof typeof MARKERS]

  let rest = match[3] ?? ''
  const done = DONE.exec(rest)
  if (done) rest = rest.slice(0, done.index)
  const sub = SUB_ISSUE.exec(rest)
  if (sub) rest = rest.slice(0, sub.index)
  const deps = DEPS.exec(rest)
  if (deps) rest = rest.replace(DEPS, '')

  const title = rest.replace(/\s+/g, ' ').trim()
  if (title === '') return null
  return {
    number: Number(match[2]),
    title,
    marker,
    deps: deps ? (deps[1] ?? '').split(',').map(n => Number(n.trim())) : [],
    subIssue: sub?.[1] ?? null,
    doneOn: done?.[1] ?? null,
    hash: done?.[2] ?? null,
  }
}

// What follows `- Review: `: an id and a URL once the review exists. The placeholder
// before that (`(id and url, filled at open)`) names nothing.
function reviewOf(value: string): Checklist['review'] {
  const [id, url, ...rest] = value.split(/\s+/)
  return id && url && rest.length === 0 && !value.startsWith('(') ? { kind: 'recorded', id, url } : null
}

// Lines inside a code fence are skipped, so a file that quotes Fathom's own format in an
// example does not read as a record. The Issue, Branch and Review lines count only in the
// header block above the first `##` section, where Fathom writes them. A task line counts
// only under `## Tasks`, and the first of two lines with one number wins.
export function parseChecklist(text: string): Checklist {
  const checklist: Checklist = {
    ref: null,
    title: null,
    issue: null,
    branch: null,
    review: null,
    pr: null,
    tasks: [],
  }
  let isFenced = false
  let hasHeading = false
  let section: string | null = null

  for (const line of text.split(/\r?\n/)) {
    if (FENCE.test(line)) {
      isFenced = !isFenced
      continue
    }
    if (isFenced) continue

    if (!hasHeading && /^# /.test(line)) {
      hasHeading = true
      const heading = HEADING.exec(line)
      if (heading) {
        checklist.ref = heading[1] ?? null
        checklist.title = heading[2] ? heading[2].replace(/\s+/g, ' ') : null
      }
      continue
    }

    const named = SECTION.exec(line)
    if (named) {
      section = (named[1] ?? '').toLowerCase()
      continue
    }

    if (section === null) {
      const link = LINK.exec(line)
      if (!link) continue
      const value = link[2] ?? ''
      if (link[1] === 'Issue') checklist.issue ??= value
      else if (link[1] === 'Branch') checklist.branch ??= value
      else if (link[1] === 'Review') checklist.review ??= reviewOf(value)
      else checklist.pr ??= value
      continue
    }

    if (section === 'tasks') {
      const task = taskOf(line)
      if (task && !checklist.tasks.some(t => t.number === task.number)) checklist.tasks.push(task)
    }
  }

  checklist.tasks.sort((a, b) => a.number - b.number)
  return checklist
}

// A closed task is done, a claimed one is in progress, and an open one is next when every
// task it depends on is closed, else it waits. Several tasks can be next at once and
// several in progress, which is how a parallel run reads. A dependency on a task the file
// does not list is met, as in the beads reader: one lost line must not stall the run.
function stateOf(task: ChecklistTask, tasks: readonly ChecklistTask[]): TaskState {
  if (task.marker === 'done') return 'done'
  if (task.marker === 'inProgress') return 'inProgress'
  const isMet = (n: number) => {
    const dep = tasks.find(t => t.number === n)
    return dep === undefined || dep.marker === 'done'
  }
  return task.deps.every(isMet) ? 'next' : 'waiting'
}

// The snapshot for a checklist run, the counterpart of `toSnapshot` for beads. `ref` is
// the issue the band follows. A checklist has no epic to tell when the tasks are all made,
// so the plan document stands in as it does for beads: while its breakdown is open, a run
// whose tasks are all still open is being created.
//
// - A file that names no issue and holds no task is not a checklist at all: unavailable,
//   with the reason, not an empty run.
// - A checklist with a header and no task yet is a run being created.
export function toChecklistSnapshot(input: { ref: string; checklist: Checklist; plan: Plan | null }): Snapshot {
  const { ref, checklist, plan } = input
  const { tasks } = checklist

  if (tasks.length === 0) {
    return checklist.ref === null
      ? { kind: 'unavailable', reason: `.fathom/tasks/${ref}.md is not a Fathom checklist` }
      : { kind: 'creating', ref, created: 0 }
  }
  if (isBreakdownOpen(plan) && tasks.every(t => t.marker === 'open')) {
    return { kind: 'creating', ref, created: tasks.length }
  }

  const reviewed = reviewedRefs(plan)
  const run: RunTask[] = tasks.map(t => {
    const state = stateOf(t, tasks)
    return {
      id: String(t.number),
      ref: t.subIssue,
      title: shortTitle(t.title, ref),
      state,
      isInReview: state === 'done' && t.subIssue !== null && reviewed.has(t.subIssue),
    }
  })

  // The checklist's own header is the freshest title; the plan's heading is the fallback.
  const name = checklist.title ?? plan?.title
  const title = name ? { title: name } : {}
  const isFinished = run.every(t => t.state === 'done')
  if (isFinished) return { kind: 'finished', ref, ...title, tasks: run.map(t => ({ ...t, isInReview: false })) }
  return { kind: 'executing', ref, ...title, tasks: run }
}

// Where a run's tasks are read from, decided from what was found. Beads and the checklist
// are two backends for the same thing and an issue has exactly one, so beads wins when it
// has an epic, as the no-dual-truth rule has it; the checklist is for the issue beads knows
// nothing about. `bdError` is why bd could not be read, or null when it was and found no
// epic. `files` holds the text of each checklist that could be read, by ref; a ref with no
// entry has none, whether the file is missing or not readable.
export type RunSource =
  | { kind: 'beads'; epic: Epic }
  | { kind: 'checklist'; ref: string; checklist: Checklist }
  | { kind: 'starting' }
  | { kind: 'unavailable'; reason: string }

//
// `hasBeads` is whether the repository has a `.beads/` folder. It matters only when bd could
// not be read and there is no run to follow: in a repository with no `.beads/`, bd failing
// (`no beads database found`, or no bd at all) is the normal state, and the run has simply
// not written its checklist yet.
export function runSourceOf(input: {
  epic: Epic | null
  bdError: string | null
  hasBeads: boolean
  refs: readonly string[]
  files: ReadonlyMap<string, string>
}): RunSource {
  if (input.epic !== null) return { kind: 'beads', epic: input.epic }
  for (const ref of input.refs) {
    const text = input.files.get(ref)
    if (text !== undefined) return { kind: 'checklist', ref, checklist: parseChecklist(text) }
  }
  // A bd that could not be read must not look like a run that has not begun, where the
  // repository uses beads. A checklist, when there is one, has already been preferred.
  return input.bdError === null || !input.hasBeads
    ? { kind: 'starting' }
    : { kind: 'unavailable', reason: input.bdError }
}
