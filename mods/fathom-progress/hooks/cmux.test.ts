import { test, expect } from 'claude-code/testing'

import type { RunTask, Snapshot, TaskState } from '../types'
import { DARK } from './desktop'
import { MAX_PILL_TEXT, NONE, PILL_KEY, barLabelOn, clip, cmuxEntries, isOurBar, meterValue, pillKeyFor } from './cmux'

function task(i: number, state: TaskState, isInReview = false): RunTask {
  return { id: `t${i}`, ref: `SLU-${i}`, title: `Task ${i}`, state, isInReview }
}

// Five tasks: the first `done` closed, then one in progress (or next), the rest waiting.
function executing(done: number, running: 'inProgress' | 'next' | null, reviews = 0): Snapshot {
  const tasks: RunTask[] = []
  for (let i = 0; i < 5; i++) {
    if (i < done) tasks.push(task(i, 'done', i < reviews))
    else if (i === done && running) tasks.push(task(i, running))
    else tasks.push(task(i, 'waiting'))
  }
  return { kind: 'executing', ref: 'PHA-352', tasks }
}

test('idle puts nothing on the row', async () => {
  expect(cmuxEntries({ kind: 'idle' })).toEqual(NONE)
})

test('starting is a pill and no bar', async () => {
  const { pill, meter } = cmuxEntries({ kind: 'starting' })
  expect(pill?.text).toBe('starting…')
  expect(meter).toBeNull()
})

test('creating counts the tasks made so far, and has no bar since there is no total', async () => {
  expect(cmuxEntries({ kind: 'creating', ref: 'SLU-1', created: 0 }).pill?.text).toBe('planning')
  expect(cmuxEntries({ kind: 'creating', ref: 'SLU-1', created: 1 }).pill?.text).toBe('planning · 1 task')
  expect(cmuxEntries({ kind: 'creating', ref: 'SLU-1', created: 3 }).pill?.text).toBe('planning · 3 tasks')
  expect(cmuxEntries({ kind: 'creating', ref: 'SLU-1', created: 3 }).meter).toBeNull()
})

test('the pills use the band\'s own colors, never an undefined one', async () => {
  for (const snapshot of [{ kind: 'starting' }, { kind: 'creating', ref: 'SLU-1', created: 1 }, { kind: 'scaffold', phase: 'resolving', created: 0 }, { kind: 'scaffold', phase: 'waiting', created: 0 }] as Snapshot[]) {
    expect(cmuxEntries(snapshot).pill?.color).toMatch(/^#[0-9A-F]{6}$/i)
  }
})

test('a scaffold run is a pill per phase, with the issues made so far, and never a bar', async () => {
  const pill = (phase: 'resolving' | 'drafting' | 'waiting' | 'creating' | 'done', created: number) => cmuxEntries({ kind: 'scaffold', phase, created }).pill
  expect(pill('resolving', 0)?.text).toBe('Scaffold · Checking tracker')
  expect(pill('drafting', 0)?.text).toBe('Scaffold · Drafting')
  expect(pill('waiting', 0)?.text).toBe('Scaffold · Waiting on you')
  expect(pill('creating', 0)?.text).toBe('Scaffold · Creating')
  expect(pill('creating', 1)?.text).toBe('Scaffold · 1 issue made')
  expect(pill('creating', 12)?.text).toBe('Scaffold · 12 issues made')
  expect(pill('done', 5)?.text).toBe('Scaffold · Done, 5 issues made')
  expect(pill('done', 0)?.text).toBe('Scaffold · Done')
  expect(cmuxEntries({ kind: 'scaffold', phase: 'creating', created: 3 }).meter).toBeNull()
})

test('a scaffold pill fits the row, waiting is yellow like the band\'s dot, and done is green', async () => {
  for (const phase of ['resolving', 'drafting', 'waiting', 'creating', 'done'] as const) {
    expect((cmuxEntries({ kind: 'scaffold', phase, created: 99 }).pill?.text ?? '').length).toBeLessThanOrEqual(MAX_PILL_TEXT)
  }
  expect(cmuxEntries({ kind: 'scaffold', phase: 'waiting', created: 0 }).pill?.color).toBe(DARK.inProgress)
  expect(cmuxEntries({ kind: 'scaffold', phase: 'done', created: 5 }).pill?.color).toBe(DARK.done)
})

test('executing shows the count, the task in progress, and a bar of done over total', async () => {
  const { pill, meter } = cmuxEntries(executing(2, 'inProgress'))
  expect(pill?.text).toBe('2/5 · now 3')
  expect(pill?.color).toBe(DARK.inProgress)
  expect(meter).toEqual({ value: 0.4, label: 'PHA-352 · 2 of 5' })
})

test('between tasks the pill names the next one', async () => {
  expect(cmuxEntries(executing(2, 'next')).pill?.text).toBe('2/5 · next 3')
})

test('with no task in progress or next, the pill only counts', async () => {
  expect(cmuxEntries(executing(2, null)).pill?.text).toBe('2/5')
})

test('tasks in review are counted in the pill', async () => {
  expect(cmuxEntries(executing(3, 'inProgress', 2)).pill?.text).toBe('3/5 · now 4 · 2 in review')
})

test('a bar that has not started is empty', async () => {
  expect(cmuxEntries(executing(0, 'next')).meter).toEqual({ value: 0, label: 'PHA-352 · 0 of 5' })
})

test('finished is green with a full bar', async () => {
  const tasks = [task(0, 'done'), task(1, 'done'), task(2, 'done')]
  const { pill, meter } = cmuxEntries({ kind: 'finished', ref: 'PHA-352', tasks })
  expect(pill).toEqual({ text: 'done 3/3', icon: 'checkmark.circle', color: DARK.done })
  expect(meter).toEqual({ value: 1, label: 'PHA-352 · done' })
})

test('unavailable is a pill and no bar, and never carries the reason', async () => {
  const { pill, meter } = cmuxEntries({ kind: 'unavailable', reason: 'bd exited 1: a very long reason that would be cut off by the row anyway' })
  expect(pill?.text).toBe('bd unavailable')
  expect(meter).toBeNull()
})

test('no pill is longer than the row takes, whatever the run', async () => {
  const tasks = Array.from({ length: 12 }, (_, i) => task(i, i < 9 ? 'done' : i === 9 ? 'inProgress' : 'waiting', true))
  const snapshots: Snapshot[] = [
    { kind: 'starting' },
    { kind: 'creating', ref: 'SLU-1', created: 120 },
    { kind: 'executing', ref: 'ABCDEFGHIJ-1234', tasks },
    { kind: 'finished', ref: 'ABCDEFGHIJ-1234', tasks },
    { kind: 'unavailable', reason: 'x'.repeat(200) },
  ]
  for (const snapshot of snapshots) {
    const text = cmuxEntries(snapshot).pill?.text ?? ''
    expect(text.length).toBeLessThanOrEqual(MAX_PILL_TEXT)
  }
})

test('clip leaves a short text alone and ends a long one with an ellipsis at the limit', async () => {
  expect(clip('short')).toBe('short')
  expect(clip('x'.repeat(MAX_PILL_TEXT))).toBe('x'.repeat(MAX_PILL_TEXT))
  const cut = clip('x'.repeat(MAX_PILL_TEXT + 5))
  expect(cut.length).toBe(MAX_PILL_TEXT)
  expect(cut.endsWith('…')).toBe(true)
})

test('meterValue is what cmux set-progress takes: 0 to 1, two places', async () => {
  expect(meterValue(0)).toBe('0')
  expect(meterValue(0.4)).toBe('0.4')
  expect(meterValue(2 / 3)).toBe('0.67')
  expect(meterValue(1)).toBe('1')
  expect(meterValue(-1)).toBe('0')
  expect(meterValue(7)).toBe('1')
})

test('our pill key is not the one cmux uses for Claude Code', async () => {
  expect(PILL_KEY).toBe('fathom')
  expect(PILL_KEY).not.toBe('claude_code')
})

test('each pane gets its own pill key, from the first eight characters of its surface id', async () => {
  expect(pillKeyFor('025A8E08-1DFB-4109-9998-0D0F6A74FCB3')).toBe('fathom-025a8e08')
  expect(pillKeyFor('7C1F0B22-AAAA-4000-8000-000000000001')).toBe('fathom-7c1f0b22')
  expect(pillKeyFor('025A8E08-1DFB-4109-9998-0D0F6A74FCB3')).not.toBe(pillKeyFor('7C1F0B22-AAAA-4000-8000-000000000001'))
})

test('without a surface id the plain pill key stands, and no key is cmux\'s own', async () => {
  expect(pillKeyFor(undefined)).toBe(PILL_KEY)
  expect(pillKeyFor('')).toBe(PILL_KEY)
  expect(pillKeyFor('--------')).toBe(PILL_KEY)
  expect(pillKeyFor('025A8E08-1DFB')).not.toBe('claude_code')
})

test('the bar on the row is the label after the value in the progress line of sidebar-state', async () => {
  const state = (progress: string) => `tab=FB598B8C\ncolor=none\nprogress=${progress}\nstatus_count=1\n  claude_code=Running`
  expect(barLabelOn(state('0.40 PHA-352 · 2 of 5'))).toBe('PHA-352 · 2 of 5')
  expect(barLabelOn(state('1.00 PHA-352 · done'))).toBe('PHA-352 · done')
  expect(barLabelOn(state('0.40'))).toBe('')
  expect(barLabelOn(state('none'))).toBeNull()
  expect(barLabelOn('tab=FB598B8C\ncolor=none')).toBeNull()
})

test('a run takes its bar off only while the row still shows its reference', async () => {
  expect(isOurBar('PHA-352 · 3 of 5', 'PHA-352 · 2 of 5')).toBe(true)
  expect(isOurBar('PHA-352 · done', 'PHA-352 · 4 of 5')).toBe(true)
  // Another run's bar, and a bar with no label: not ours.
  expect(isOurBar('SLU-124 · 1 of 3', 'PHA-352 · 2 of 5')).toBe(false)
  expect(isOurBar('', 'PHA-352 · 2 of 5')).toBe(false)
  // Nothing on the row: nothing to clear.
  expect(isOurBar(null, 'PHA-352 · 2 of 5')).toBe(false)
  // A reference that only begins the same is not the same reference.
  expect(isOurBar('PHA-3520 · 1 of 2', 'PHA-352 · 2 of 5')).toBe(false)
})
