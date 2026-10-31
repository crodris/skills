import { test, expect } from 'claude-code/testing'

import type { Plan, Snapshot } from '../types'
import { parseChecklist, runSourceOf, toChecklistSnapshot } from './checklist'
import { parsePlan } from './plan'
import type { Epic } from './state'

// The example memory/checklist.md in the Fathom skill gives, line for line.
const EXAMPLE = [
  '# ONC-5: Add login flow',
  '',
  '- Issue: https://linear.app/acme/issue/ONC-5',
  '- Branch: feat/onc-5-add-login',
  '- Review: (id and url, filled at open)',
  '- PR: (legacy, read but no longer written)',
  '',
  '## Plan',
  '',
  'One-paragraph approach summary.',
  'Testing notes.',
  '',
  '## Tasks',
  '',
  '- [x] 1. Create login form component -> sub-issue: https://x.test/ONC-6 (done 2026-07-28, a1b2c3d)',
  '- [>] 2. Wire auth API (deps: 1) -> sub-issue: https://x.test/ONC-7',
  '- [ ] 3. Add e2e test (deps: 2) -> sub-issue: https://x.test/ONC-8',
].join('\n')

test('the documented example reads as the issue, its links and three tasks', async () => {
  const checklist = parseChecklist(EXAMPLE)

  expect(checklist.ref).toBe('ONC-5')
  expect(checklist.title).toBe('Add login flow')
  expect(checklist.issue).toBe('https://linear.app/acme/issue/ONC-5')
  expect(checklist.branch).toBe('feat/onc-5-add-login')
  expect(checklist.tasks).toEqual([
    {
      number: 1,
      title: 'Create login form component',
      marker: 'done',
      deps: [],
      subIssue: 'https://x.test/ONC-6',
      doneOn: '2026-07-28',
      hash: 'a1b2c3d',
    },
    {
      number: 2,
      title: 'Wire auth API',
      marker: 'inProgress',
      deps: [1],
      subIssue: 'https://x.test/ONC-7',
      doneOn: null,
      hash: null,
    },
    {
      number: 3,
      title: 'Add e2e test',
      marker: 'open',
      deps: [2],
      subIssue: 'https://x.test/ONC-8',
      doneOn: null,
      hash: null,
    },
  ])
})

test('the placeholder Review line names no review, and the legacy PR line is kept apart from it', async () => {
  const checklist = parseChecklist(EXAMPLE)

  expect(checklist.review).toBeNull()
  expect(checklist.pr).toBe('(legacy, read but no longer written)')
})

test('a Review line with an id and a URL is a recorded review', async () => {
  const checklist = parseChecklist('# ONC-5: A\n\n- Review: 42 https://github.com/acme/app/pull/42\n')

  expect(checklist.review).toEqual({ kind: 'recorded', id: '42', url: 'https://github.com/acme/app/pull/42' })
})

test('a PR line with a URL and no id is a legacy record, not a review', async () => {
  const checklist = parseChecklist('# ONC-5: A\n\n- PR: https://github.com/acme/app/pull/7\n')

  expect(checklist.review).toBeNull()
  expect(checklist.pr).toBe('https://github.com/acme/app/pull/7')
})

test('several dependencies are one comma-separated list, and a task may have none, one or many', async () => {
  const text = [
    '## Tasks',
    '- [x] 1. First',
    '- [x] 2. Second',
    '- [ ] 3. Third (deps: 1, 2) -> sub-issue: ONC-9',
    '- [ ] 4. Fourth (deps: 3)',
  ].join('\n')
  // The tasks sit under the section, so the lines above it are not a header block.
  const tasks = parseChecklist(text).tasks

  expect(tasks.map(t => t.deps)).toEqual([[], [], [1, 2], [3]])
  expect(tasks[2]?.subIssue).toBe('ONC-9')
  expect(tasks[3]?.subIssue).toBeNull()
})

test('several in-progress lines are kept, which is how a parallel run reads', async () => {
  const text = ['## Tasks', '- [>] 1. One', '- [>] 2. Two', '- [ ] 3. Three (deps: 1, 2)'].join('\n')

  expect(parseChecklist(text).tasks.map(t => t.marker)).toEqual(['inProgress', 'inProgress', 'open'])
})

test('a closed task whose hash is not written yet has a date and no hash', async () => {
  const task = parseChecklist('## Tasks\n- [x] 1. Done (done 2026-10-20)\n').tasks[0]

  expect(task?.doneOn).toBe('2026-10-20')
  expect(task?.hash).toBeNull()
})

test('the Closed footer an older sweep appended is not a task and changes no count', async () => {
  const text = `${EXAMPLE}\n- Closed: 2026-07-30\n`

  expect(parseChecklist(text).tasks.map(t => t.number)).toEqual([1, 2, 3])
})

test('task lines outside the Tasks section are not tasks', async () => {
  const text = [
    '# ONC-5: A',
    '',
    '## Plan',
    '- [ ] 9. A step the plan lists',
    '',
    '## Tasks',
    '- [ ] 1. The only task',
    '',
    '## Notes',
    '- [ ] 8. A follow-up note',
  ].join('\n')

  expect(parseChecklist(text).tasks.map(t => t.number)).toEqual([1])
})

test('links count in the header block only, so a Plan that quotes them does not change them', async () => {
  const text = [
    '# ONC-5: A',
    '- Branch: feat/onc-5-real',
    '',
    '## Plan',
    '- Branch: feat/onc-5-quoted',
    '',
    '## Tasks',
    '- [ ] 1. T',
  ].join('\n')

  expect(parseChecklist(text).branch).toBe('feat/onc-5-real')
})

test('lines inside a code fence are skipped', async () => {
  const text = ['# ONC-5: A', '', '## Tasks', '```', '- [x] 1. Quoted from the docs', '```', '- [ ] 2. Real'].join('\n')

  expect(parseChecklist(text).tasks.map(t => t.title)).toEqual(['Real'])
})

test('tasks come out in task-number order, and the first of two lines with a number wins', async () => {
  const text = ['## Tasks', '- [ ] 3. Third', '- [x] 1. First', '- [ ] 1. First again', '- [ ] 2. Second'].join('\n')
  const tasks = parseChecklist(text).tasks

  expect(tasks.map(t => t.number)).toEqual([1, 2, 3])
  expect(tasks[0]).toMatchObject({ title: 'First', marker: 'done' })
})

test('a task line too broken to name a number and a title is skipped, not an error', async () => {
  const text = [
    '## Tasks',
    '- [?] 1. Unknown marker',
    '- [ ] two. No number',
    '- [ ] 3.',
    '- [ ] 4. (deps: 1)',
    '- [ ] 5. Fine',
  ].join('\n')

  expect(parseChecklist(text).tasks.map(t => t.number)).toEqual([5])
})

test('a header with no title still names the ref', async () => {
  const checklist = parseChecklist('# ONC-5\n\n## Tasks\n')

  expect(checklist.ref).toBe('ONC-5')
  expect(checklist.title).toBeNull()
})

test('text that is not a checklist reads as an empty one', async () => {
  for (const text of ['', 'hello\nworld', '# Just a note\n\nNo tasks here.', '{"not": "a checklist"}']) {
    const checklist = parseChecklist(text)

    expect(checklist.ref).toBeNull()
    expect(checklist.tasks).toEqual([])
  }
})

test('Windows line endings read the same as Unix ones', async () => {
  expect(parseChecklist(EXAMPLE.replace(/\n/g, '\r\n'))).toEqual(parseChecklist(EXAMPLE))
})

// A checklist with the given task lines, under the header every file has.
function listOf(...tasks: string[]): string {
  return ['# ONC-5: Add login flow', '', '## Tasks', ...tasks].join('\n')
}

// The snapshot of a checklist, with the plan document's presence as the lifecycle sees it.
function snapshotOf(text: string, plan: Plan | null = parsePlan('- Ref: ONC-5\n')): Snapshot {
  return toChecklistSnapshot({ ref: 'ONC-5', checklist: parseChecklist(text), plan })
}

function tasksOf(snapshot: Snapshot) {
  if (!('tasks' in snapshot)) throw new Error(`snapshot has no tasks: ${snapshot.kind}`)
  return snapshot.tasks
}

test('a run in a line: done, in progress, then the rest waiting behind it', async () => {
  const snapshot = snapshotOf(
    listOf('- [x] 1. One (done 2026-10-20)', '- [>] 2. Two (deps: 1)', '- [ ] 3. Three (deps: 2)'),
  )

  expect(snapshot.kind).toBe('executing')
  expect(tasksOf(snapshot).map(t => t.state)).toEqual(['done', 'inProgress', 'waiting'])
})

test('the open task whose dependencies are all closed is next', async () => {
  const snapshot = snapshotOf(listOf('- [x] 1. One', '- [x] 2. Two', '- [ ] 3. Three (deps: 1, 2)', '- [ ] 4. Four (deps: 3)'))

  expect(tasksOf(snapshot).map(t => t.state)).toEqual(['done', 'done', 'next', 'waiting'])
})

test('a task with no dependencies is next, and so is every other such task: they can run together', async () => {
  const snapshot = snapshotOf(listOf('- [ ] 1. One', '- [ ] 2. Two', '- [ ] 3. Three (deps: 1, 2)'))

  expect(tasksOf(snapshot).map(t => t.state)).toEqual(['next', 'next', 'waiting'])
})

test('a parallel run: several in progress at once, and the task behind them waits', async () => {
  const snapshot = snapshotOf(listOf('- [>] 1. One', '- [>] 2. Two', '- [ ] 3. Three (deps: 1, 2)'))

  expect(tasksOf(snapshot).map(t => t.state)).toEqual(['inProgress', 'inProgress', 'waiting'])
})

test('a dependency on a task the file does not list is met, so one lost line does not stall the run', async () => {
  const snapshot = snapshotOf(listOf('- [ ] 2. Two (deps: 1)'))

  expect(tasksOf(snapshot).map(t => t.state)).toEqual(['next'])
})

test('with every task closed the run is finished, and it shows no review marks', async () => {
  const plan = parsePlan(
    ['- Ref: ONC-5', '- Bundle 1/1: feat/onc-5-a - ONC-6', '- Review: 7 https://x.test/pull/7 (bundle 1/1)'].join('\n'),
  )
  const snapshot = snapshotOf(listOf('- [x] 1. One -> sub-issue: ONC-6 (done 2026-10-20, a1b2c3d)'), plan)

  expect(snapshot.kind).toBe('finished')
  expect(tasksOf(snapshot).map(t => t.isInReview)).toEqual([false])
})

test('a done task is in review while its bundle has a recorded review and the run goes on', async () => {
  const plan = parsePlan(
    [
      '- Ref: ONC-5',
      '- Bundle 1/2: feat/onc-5-a - ONC-6',
      '- Review: 7 https://x.test/pull/7 (bundle 1/2)',
      '- Bundle 2/2: feat/onc-5-b - ONC-7',
    ].join('\n'),
  )
  const snapshot = snapshotOf(listOf('- [x] 1. One -> sub-issue: ONC-6', '- [>] 2. Two -> sub-issue: ONC-7'), plan)

  expect(tasksOf(snapshot).map(t => t.isInReview)).toEqual([true, false])
})

test('tasks made but no plan document yet is a run being created, and counts the tasks', async () => {
  expect(snapshotOf(listOf('- [ ] 1. One', '- [ ] 2. Two'), null)).toEqual({ kind: 'creating', ref: 'ONC-5', created: 2 })
  expect(snapshotOf(listOf('- [ ] 1. One', '- [ ] 2. Two'), parsePlan('- Breakdown: pending\n'))).toEqual({ kind: 'creating', ref: 'ONC-5', created: 2 })
})

test('once the plan document exists the run is executing, whatever the markers', async () => {
  const snapshot = snapshotOf(listOf('- [ ] 1. One', '- [ ] 2. Two (deps: 1)'))

  expect(snapshot.kind).toBe('executing')
  expect(tasksOf(snapshot).map(t => t.state)).toEqual(['next', 'waiting'])
})

test('a claimed task starts the run even with no plan document', async () => {
  expect(snapshotOf(listOf('- [>] 1. One', '- [ ] 2. Two (deps: 1)'), null).kind).toBe('executing')
})

test('a checklist with a header and no task yet is a run being created, with none made', async () => {
  expect(snapshotOf('# ONC-5: Add login flow\n\n## Tasks\n')).toEqual({ kind: 'creating', ref: 'ONC-5', created: 0 })
})

test('a file that is not a checklist is unavailable and says so, never an empty run', async () => {
  for (const text of ['', 'hello', '## Tasks\n- [ ] x\n']) {
    const snapshot = snapshotOf(text)

    expect(snapshot.kind).toBe('unavailable')
    expect('reason' in snapshot && snapshot.reason).toContain('.fathom/tasks/ONC-5.md')
  }
})

test("the title is the checklist header's, then the plan document's, and may be absent", async () => {
  const plan = parsePlan('# ONC-5: The plan title\n- Ref: ONC-5\n')

  expect(snapshotOf(listOf('- [ ] 1. One'), plan)).toMatchObject({ title: 'Add login flow' })
  expect(snapshotOf('# ONC-5\n\n## Tasks\n- [ ] 1. One', plan)).toMatchObject({ title: 'The plan title' })
  expect('title' in snapshotOf('# ONC-5\n\n## Tasks\n- [ ] 1. One')).toBe(false)
})

test('a task is titled without the issue ref in front, and carries its number and sub-issue', async () => {
  const task = tasksOf(snapshotOf(listOf('- [ ] 7. ONC-5: Wire auth API -> sub-issue: ONC-9')))[0]

  expect(task).toEqual({ id: '7', ref: 'ONC-9', title: 'Wire auth API', state: 'next', isInReview: false })
})

const EPIC: Epic = { id: 'e1', ref: 'ONC-5', status: 'open', createdAt: 0, updatedAt: 0 }
const FILES = new Map([['ONC-5', listOf('- [ ] 1. One')]])

test('beads wins when it has an epic, even if a checklist for the ref also exists', async () => {
  const source = runSourceOf({ epic: EPIC, bdError: null, hasBeads: true, refs: ['ONC-5'], files: FILES })

  expect(source).toEqual({ kind: 'beads', epic: EPIC })
})

test('with no epic the checklist for the ref is used', async () => {
  const source = runSourceOf({ epic: null, bdError: null, hasBeads: true, refs: ['ONC-5'], files: FILES })

  expect(source.kind).toBe('checklist')
  expect(source.kind === 'checklist' && source.ref).toBe('ONC-5')
  expect(source.kind === 'checklist' && source.checklist.tasks.length).toBe(1)
})

test('a bd that failed does not hide a readable checklist', async () => {
  const source = runSourceOf({ epic: null, bdError: 'bd list exited 127: command not found', hasBeads: true, refs: ['ONC-5'], files: FILES })

  expect(source.kind).toBe('checklist')
})

test('the first ref that has a checklist is the one followed', async () => {
  const files = new Map([['ONC-6', listOf('- [ ] 1. Six')]])
  const source = runSourceOf({ epic: null, bdError: null, hasBeads: true, refs: ['ONC-5', 'ONC-6'], files })

  expect(source.kind === 'checklist' && source.ref).toBe('ONC-6')
})

test('no epic and no checklist is a run that has not begun, when bd could be read', async () => {
  expect(runSourceOf({ epic: null, bdError: null, hasBeads: true, refs: ['ONC-5'], files: new Map() })).toEqual({ kind: 'starting' })
})

test('no epic and no checklist shows why bd could not be read, never a run that has not begun', async () => {
  const source = runSourceOf({ epic: null, bdError: 'bd list did not print JSON', hasBeads: true, refs: ['ONC-5'], files: new Map() })

  expect(source).toEqual({ kind: 'unavailable', reason: 'bd list did not print JSON' })
})

test('with no ref there is no checklist to look for', async () => {
  expect(runSourceOf({ epic: null, bdError: null, hasBeads: true, refs: [], files: FILES })).toEqual({ kind: 'starting' })
  expect(runSourceOf({ epic: null, bdError: 'no bd', hasBeads: true, refs: [], files: FILES })).toEqual({ kind: 'unavailable', reason: 'no bd' })
})

test('a file that is not a checklist is followed as one, and the band says so instead of going blank', async () => {
  const source = runSourceOf({ epic: null, bdError: null, hasBeads: true, refs: ['ONC-5'], files: new Map([['ONC-5', 'hello']]) })

  expect(source.kind === 'checklist' && toChecklistSnapshot({ ref: 'ONC-5', checklist: source.checklist, plan: null }).kind).toBe(
    'unavailable',
  )
})

// The text mods/fathom-progress/bench/play-checklist.sh writes, step 6 of the chain timeline and step 4 of
// the parallel one, copied as it is. The band's live checks lean on these reading as the run
// they stand for, so a change to the parser that broke them would fail here first.
const BENCH_CHAIN_6 = [
  '# BENCH-1: Bench run',
  '',
  '- Issue: https://example.test/BENCH-1',
  '- Branch: feat/bench-1-bench-run',
  '- Review: (id and url, filled at open)',
  '',
  '## Plan',
  '',
  'Written by mods/fathom-progress/bench/play-checklist.sh, not by Fathom.',
  '',
  '## Tasks',
  '',
  '- [x] 1. Create bench/a.txt -> sub-issue: SUB-1 (done 2026-10-20, a1b2c31)',
  '- [x] 2. Create bench/b.txt (deps: 1) -> sub-issue: SUB-2 (done 2026-10-20)',
  '- [>] 3. Create bench/c.txt (deps: 2) -> sub-issue: SUB-3',
].join('\n')

const BENCH_PARALLEL_4 = [
  '## Tasks',
  '',
  '- [>] 1. Create bench/a.txt -> sub-issue: SUB-1',
  '- [>] 2. Create bench/b.txt -> sub-issue: SUB-2',
  '- [ ] 3. Create bench/c.txt (deps: 1, 2) -> sub-issue: SUB-3',
].join('\n')

test('what the bench harness writes reads as the run it stands for', async () => {
  const chain = parseChecklist(BENCH_CHAIN_6)

  expect(chain.title).toBe('Bench run')
  expect(chain.tasks.map(t => t.hash)).toEqual(['a1b2c31', null, null])
  expect(tasksOf(snapshotOf(BENCH_CHAIN_6)).map(t => t.state)).toEqual(['done', 'done', 'inProgress'])
  expect(tasksOf(snapshotOf(BENCH_PARALLEL_4)).map(t => t.state)).toEqual(['inProgress', 'inProgress', 'waiting'])
})

test('where there is no .beads/, a bd that cannot be read is the normal state: the band waits instead of failing', async () => {
  for (const bdError of ['bd list exited 1: Error: no beads database found', 'bd list exited 127: bd: command not found']) {
    const source = runSourceOf({ epic: null, bdError, hasBeads: false, refs: ['ONC-5'], files: new Map() })

    expect(source).toEqual({ kind: 'starting' })
  }
})

test('where there is a .beads/, a bd that cannot be read is still unavailable', async () => {
  const source = runSourceOf({
    epic: null,
    bdError: 'bd list exited 1: Error: no beads database found',
    hasBeads: true,
    refs: ['ONC-5'],
    files: new Map(),
  })

  expect(source).toEqual({ kind: 'unavailable', reason: 'bd list exited 1: Error: no beads database found' })
})

test('having no .beads/ changes nothing when there is an epic or a checklist to follow', async () => {
  const bdError = 'bd list exited 1: Error: no beads database found'

  expect(runSourceOf({ epic: EPIC, bdError: null, hasBeads: false, refs: ['ONC-5'], files: new Map() }).kind).toBe('beads')
  expect(runSourceOf({ epic: null, bdError, hasBeads: false, refs: ['ONC-5'], files: FILES }).kind).toBe('checklist')
})
