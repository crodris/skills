import { test, expect } from 'claude-code/testing'

import type { Plan } from '../types'
import * as fx from './fixtures'
import { parsePlan } from './plan'
import { currentOf, parseEpics, pickRun, progressOf, toSnapshot } from './state'

type Stage = { epics: unknown; tasks: unknown; ready: unknown }

// The lifecycle's two steps on one captured stage: pick the run from the epics, then
// read that run's tasks. Null when no run is found.
function snapshotOf(stage: Stage, plan: Plan | null, armedAt = 0) {
  const epics = parseEpics(stage.epics)
  const epic = epics === null ? null : pickRun(epics, armedAt)
  return epic === null ? null : toSnapshot({ epic, tasks: stage.tasks, ready: stage.ready, plan })
}

// A plan document exists once the breakdown is done; its contents do not matter to
// most of these tests.
const PLAN = parsePlan('- Ref: SLU-123\n')
const PLAN_2 = parsePlan('- Ref: SLU-124\n')

const TITLES = [
  'Draft the plan doc',
  'Capture the fixtures',
  'Wire the lifecycle hooks',
  'Draw the executing view',
  'Verify in a live session',
]

function tasksOf(snapshot: ReturnType<typeof snapshotOf>) {
  if (snapshot === null || !('tasks' in snapshot)) throw new Error('snapshot has no tasks')
  return snapshot.tasks
}

test('no run is found before the epic exists, and the epic alone is a run with no tasks yet', async () => {
  expect(snapshotOf(fx.idle, null)).toBeNull()
  expect(snapshotOf(fx.epicOnly, null)).toEqual({ kind: 'creating', ref: 'SLU-123', created: 0 })
})

test('while tasks are being made, with no plan document, the run is creating and counts them', async () => {
  expect(snapshotOf(fx.created1, null)).toEqual({ kind: 'creating', ref: 'SLU-123', created: 1 })
  expect(snapshotOf(fx.created3, null)).toEqual({ kind: 'creating', ref: 'SLU-123', created: 3 })
  expect(snapshotOf(fx.created5, null)).toEqual({ kind: 'creating', ref: 'SLU-123', created: 5 })
})

test('once the plan document exists the total is known: the first task is next and the rest wait', async () => {
  const snapshot = snapshotOf(fx.nextReady, PLAN)

  expect(snapshot?.kind).toBe('executing')
  expect(tasksOf(snapshot).map(t => t.state)).toEqual(['next', 'waiting', 'waiting', 'waiting', 'waiting'])
  expect(tasksOf(snapshot).map(t => t.title)).toEqual(TITLES)
})

test('tasks come out in chain order whatever order bd listed them in, with the issue ref dropped from each title', async () => {
  const shuffled = { ...fx.created5, tasks: [...fx.created5.tasks].reverse() }

  expect(tasksOf(snapshotOf(fx.created5, PLAN)).map(t => t.title)).toEqual(TITLES)
  expect(tasksOf(snapshotOf(shuffled, PLAN)).map(t => t.title)).toEqual(TITLES)
})

test('a claimed task is in progress and starts the run even with no plan document', async () => {
  const snapshot = snapshotOf(fx.claimedFirst, null)

  expect(snapshot?.kind).toBe('executing')
  expect(tasksOf(snapshot).map(t => t.state)).toEqual(['inProgress', 'waiting', 'waiting', 'waiting', 'waiting'])
})

test('mid-run: two done, one in progress, two waiting', async () => {
  const snapshot = snapshotOf(fx.claimedThird, PLAN)

  expect(tasksOf(snapshot).map(t => t.state)).toEqual(['done', 'done', 'inProgress', 'waiting', 'waiting'])
  expect(currentOf(tasksOf(snapshot))).toEqual({ index: 2, state: 'inProgress' })
  expect(progressOf(tasksOf(snapshot))).toEqual({ done: 2, total: 5, percent: 40 })
})

test('with every task closed the run is finished, whether or not its epic is closed yet', async () => {
  for (const stage of [fx.allClosed, fx.finished]) {
    const snapshot = snapshotOf(stage, PLAN)

    expect(snapshot?.kind).toBe('finished')
    expect(tasksOf(snapshot).every(t => t.state === 'done')).toBe(true)
    expect(currentOf(tasksOf(snapshot))).toBeNull()
    expect(progressOf(tasksOf(snapshot))).toEqual({ done: 5, total: 5, percent: 100 })
  }
})

test('the current task is the one in progress, else the next one offered', async () => {
  expect(currentOf(tasksOf(snapshotOf(fx.nextReady, PLAN)))).toEqual({ index: 0, state: 'next' })
  expect(progressOf(tasksOf(snapshotOf(fx.nextReady, PLAN)))).toEqual({ done: 0, total: 5, percent: 0 })
  expect(currentOf([])).toBeNull()
  expect(progressOf([])).toEqual({ done: 0, total: 0, percent: 0 })
})

test('a finished run stays up until the next one starts, then the new run takes over', async () => {
  const [finished] = parseEpics(fx.finished.epics) ?? []
  const second = parseEpics(fx.stacked.epics)?.find(e => e.ref === 'SLU-124')

  expect(finished?.ref).toBe('SLU-123')
  expect(snapshotOf(fx.finished, PLAN)?.kind).toBe('finished')

  // The second run's epic is newer, so it wins from the first invocation on.
  expect(snapshotOf(fx.stacked, null)).toEqual({ kind: 'creating', ref: 'SLU-124', created: 2 })
  expect(tasksOf(snapshotOf(fx.stacked, PLAN_2)).map(t => t.state)).toEqual(['next', 'waiting'])
  expect(snapshotOf(fx.stacked, PLAN_2, second?.createdAt ?? 0)?.kind).toBe('executing')
})

test('an invocation after every epic was made picks the open epic with the most recent activity, never a closed one', async () => {
  const later = Date.now() + 60_000

  expect(snapshotOf(fx.stacked, PLAN_2, later)).toMatchObject({ kind: 'executing', ref: 'SLU-124' })
  expect(snapshotOf(fx.finished, PLAN, later)).toBeNull()
})

test('a done task is in review while its bundle has a recorded review and the plan is not final', async () => {
  const stack = [
    '- Ref: SLU-123',
    '- Bundle 1/2: feat/a - SLU-123-1, SLU-123-2',
    '  - Review: 90 https://example.com/90 (bundle 1/2)',
    '- Bundle 2/2: feat/b - SLU-123-3, SLU-123-4, SLU-123-5',
  ].join('\n')
  const reviewed = (plan: string) => tasksOf(snapshotOf(fx.claimedThird, parsePlan(plan))).map(t => t.isInReview)

  expect(reviewed(stack)).toEqual([true, true, false, false, false])
  expect(reviewed(`${stack}\n- Finalization: complete`)).toEqual([false, false, false, false, false])
  expect(reviewed(stack.replace('90 https://example.com/90', 'pending'))).toEqual([false, false, false, false, false])
  expect(reviewed('- Ref: SLU-123')).toEqual([false, false, false, false, false])
})

test('a finished run shows no review marks, whether or not the plan is final', async () => {
  const stack = [
    '- Ref: SLU-123',
    '- Bundle 1/2: feat/a - SLU-123-1, SLU-123-2',
    '  - Review: 90 https://example.com/90 (bundle 1/2)',
    '- Bundle 2/2: feat/b - SLU-123-3, SLU-123-4, SLU-123-5',
  ].join('\n')

  for (const plan of [stack, `${stack}\n- Finalization: complete`]) {
    const snapshot = snapshotOf(fx.allClosed, parsePlan(plan))

    expect(snapshot?.kind).toBe('finished')
    expect(tasksOf(snapshot).map(t => t.isInReview)).toEqual([false, false, false, false, false])
  }
})

test('only a done task can be in review, and a task with no ref cannot', async () => {
  const plan = parsePlan('- Bundle 1/1: feat/a - SLU-123-1, SLU-123-3\n  - Review: 90 https://example.com/90 (bundle 1/1)')

  // Task 3 is in progress and task 1 is done: only task 1 is marked.
  expect(tasksOf(snapshotOf(fx.claimedThird, plan)).map(t => t.isInReview)).toEqual([true, false, false, false, false])
})

test('parseEpics keeps only Fathom epics: the ref is both the external ref and a label', async () => {
  const epic = { id: 'a', external_ref: 'SLU-1', labels: ['SLU-1'], status: 'open', created_at: '2026-01-01T00:00:00Z' }

  expect(parseEpics([epic, { ...epic, id: 'b', labels: [] }, { ...epic, id: 'c', external_ref: '' }, { ...epic, id: 'd', labels: ['other'] }, 3, null])).toEqual([
    { id: 'a', ref: 'SLU-1', status: 'open', createdAt: Date.parse('2026-01-01T00:00:00Z'), updatedAt: 0 },
  ])
  expect(parseEpics({ error: 'nope' })).toBeNull()
  expect(parseEpics(null)).toBeNull()
})

test('an epic made in the invocation\'s own second counts as made after it, and a tie in the second goes to the id', async () => {
  const at = Date.parse('2026-01-01T00:00:05Z')
  const epics = [
    { id: 'a', ref: 'A-1', status: 'open', createdAt: at, updatedAt: at },
    { id: 'b', ref: 'B-1', status: 'open', createdAt: at, updatedAt: at },
  ]

  expect(pickRun(epics, at + 400)?.id).toBe('b')
  expect(pickRun(epics, at + 1000)).toEqual(epics[1])
  expect(pickRun([], 0)).toBeNull()
})

// Three runs: a finished one, an open one with later activity, and one made after the
// invocation below.
const T = (s: string) => Date.parse(`2026-01-01T00:00:${s}Z`)
const RUNS = [
  { id: 'old', ref: 'PHA-352', status: 'closed', createdAt: T('01'), updatedAt: T('09') },
  { id: 'open', ref: 'PHA-400', status: 'open', createdAt: T('02'), updatedAt: T('20') },
]
const ARMED = T('30')

test('a typed ref shows its own run, finished or not, and waits when it has none', async () => {
  expect(pickRun(RUNS, ARMED)?.id).toBe('open')
  expect(pickRun(RUNS, ARMED, { refs: ['PHA-352'], isExact: true })?.id).toBe('old')
  expect(pickRun(RUNS, ARMED, { refs: ['PHA-400'], isExact: true })?.id).toBe('open')
  // No epic for the ref yet: nothing, not the other open run.
  expect(pickRun(RUNS, ARMED, { refs: ['PHA-999'], isExact: true })).toBeNull()
})

test('a ref is matched whatever its case', async () => {
  const lower = [{ ...RUNS[0]!, ref: 'pha-352' }]
  expect(pickRun(lower, ARMED, { refs: ['PHA-352'], isExact: true })?.id).toBe('old')
})

test('a typed ref picks the newest of its epics made since the invocation, then an open one', async () => {
  const again = { id: 'again', ref: 'PHA-352', status: 'open', createdAt: ARMED + 5000, updatedAt: ARMED + 5000 }
  const reopened = { id: 'reopened', ref: 'PHA-352', status: 'open', createdAt: T('03'), updatedAt: T('15') }
  const hint = { refs: ['PHA-352'], isExact: true }
  expect(pickRun([...RUNS, again], ARMED, hint)?.id).toBe('again')
  expect(pickRun([...RUNS, reopened], ARMED, hint)?.id).toBe('reopened')
})

test('several typed refs pick among their epics only', async () => {
  expect(pickRun(RUNS, ARMED, { refs: ['PHA-352', 'PHA-400'], isExact: true })?.id).toBe('open')
  expect(pickRun(RUNS, ARMED, { refs: ['PHA-777', 'PHA-352'], isExact: true })?.id).toBe('old')
})

test('a branch ref beats the latest activity, but not an epic made since the invocation, and falls back without a match', async () => {
  const branch = (ref: string) => ({ refs: [ref], isExact: false })
  // The branch is for PHA-352, which is finished: shown as finished, not the open PHA-400.
  expect(pickRun(RUNS, ARMED, branch('PHA-352'))?.id).toBe('old')
  // Another issue was started since: it wins over the branch's.
  const started = { id: 'started', ref: 'PHA-401', status: 'open', createdAt: ARMED + 2000, updatedAt: ARMED + 2000 }
  expect(pickRun([...RUNS, started], ARMED, branch('PHA-352'))?.id).toBe('started')
  // A branch with no epic keeps the old guess.
  expect(pickRun(RUNS, ARMED, branch('PHA-999'))?.id).toBe('open')
  expect(pickRun(RUNS, ARMED, { refs: [], isExact: false })?.id).toBe('open')
})

test('toSnapshot refuses output that is not a list instead of reporting an empty run', async () => {
  const epic = { id: 'a', ref: 'SLU-1', status: 'open', createdAt: 0, updatedAt: 0 }

  expect(toSnapshot({ epic, tasks: { error: 'nope' }, ready: [], plan: null })).toEqual({
    kind: 'unavailable',
    reason: 'bd did not return a JSON list',
  })
  expect(toSnapshot({ epic, tasks: [], ready: null, plan: null }).kind).toBe('unavailable')
})

test('a task whose blocker bd did not list does not stall the chain, and a blocked or deferred task waits', async () => {
  const epic = { id: 'e', ref: 'X', status: 'open', createdAt: 0, updatedAt: 0 }
  const task = (id: string, extra: Record<string, unknown> = {}) => ({
    id,
    title: `X: ${id}`,
    status: 'open',
    external_ref: `X-${id}`,
    created_at: '2026-01-01T00:00:00Z',
    ...extra,
  })
  const blocks = (id: string) => ({ dependencies: [{ depends_on_id: id, type: 'blocks' }] })

  const snapshot = toSnapshot({
    epic,
    tasks: [task('c', { ...blocks('b'), status: 'deferred' }), task('b', blocks('gone')), task('a', { status: 'blocked' })],
    ready: [{ id: 'b' }],
    plan: PLAN,
  })

  expect(tasksOf(snapshot).map(t => `${t.id}:${t.state}`)).toEqual(['a:waiting', 'b:next', 'c:waiting'])
})

test('tasks bd lists in a free order, with no edges and one timestamp, fall back to id order', async () => {
  const epic = { id: 'e', ref: 'X', status: 'open', createdAt: 0, updatedAt: 0 }
  const task = (id: string) => ({ id, title: id, status: 'open', created_at: '2026-01-01T00:00:00Z' })
  const snapshot = toSnapshot({ epic, tasks: [task('c'), task('a'), task('b')], ready: [], plan: PLAN })

  expect(tasksOf(snapshot).map(t => t.id)).toEqual(['a', 'b', 'c'])
})

test('an executing or finished run carries the issue\'s title from the plan document, and has none when the plan names none', async () => {
  const titled = parsePlan('# SLU-123: Add the progress band\n\n- Ref: SLU-123\n')

  expect(snapshotOf(fx.claimedThird, titled)).toMatchObject({ kind: 'executing', ref: 'SLU-123', title: 'Add the progress band' })
  expect(snapshotOf(fx.allClosed, titled)).toMatchObject({ kind: 'finished', ref: 'SLU-123', title: 'Add the progress band' })

  // A plan with no title leaves the field out, so the band falls back to the ref.
  for (const plan of [PLAN, parsePlan('# SLU-123 plan\n\n- Ref: SLU-123\n')]) {
    expect(snapshotOf(fx.claimedThird, plan)).not.toHaveProperty('title')
    expect(snapshotOf(fx.allClosed, plan)).not.toHaveProperty('title')
  }
})

test('a run still being created has no title, since the plan document is written after its tasks', async () => {
  expect(snapshotOf(fx.created3, null)).toEqual({ kind: 'creating', ref: 'SLU-123', created: 3 })
})
