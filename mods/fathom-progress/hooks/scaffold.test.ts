import { test, expect } from 'claude-code/testing'

import { advance, callEvent, elapsedText, inputOf, isCreate, isPreflight, phaseText, resultEvent, startScaffold, stepParts, stepsText } from './scaffold'
import type { ScaffoldEvent, ScaffoldState } from './scaffold'

const LINEAR = 'mcp__linear-server__'
const ASK = 'AskUserQuestion'

const call = (tool: string, input: Record<string, unknown> = {}): ScaffoldEvent => ({ kind: 'call', tool, input })
const result = (tool: string, input: Record<string, unknown> = {}, isError = false): ScaffoldEvent => ({ kind: 'result', tool, input, isError })

function run(events: ScaffoldEvent[], from: ScaffoldState = startScaffold()): ScaffoldState {
  return events.reduce(advance, from)
}

// The events of the live Linear run of 2026-10-19 (probe log, claude-mods-fathom-fbf.1.2),
// in order: lookups, the tracker verified, the sweep, the draft question, the main issue
// and four sub-issues, the hand-off question, the turn ending.
const MAIN = { title: 'Habit tracker: edit, archive and filter habits', team: 'Ruesato', project: 'Massive app', labels: ['Feature'] }
const SUB = (title: string, extra: Record<string, unknown> = {}) => ({ title, team: 'Ruesato', project: 'Massive app', parentId: 'RUE-17', ...extra })
const CREATES = [
  MAIN,
  SUB('A user can rename a habit'),
  SUB('A user can archive a habit and restore it'),
  SUB("A user can filter the list by today's progress", { blockedBy: ['RUE-19'] }),
  SUB('A user sees how many habits are done today', { blockedBy: ['RUE-19'] }),
]

const LIVE: ScaffoldEvent[] = [
  { kind: 'turn.start' },
  call('Read'),
  call('ToolSearch'),
  call(`${LINEAR}get_project`, { query: 'massive-app' }),
  call(`${LINEAR}list_teams`, { limit: 10 }),
  result(`${LINEAR}get_project`),
  call(`${LINEAR}list_issues`, { project: 'Massive app', limit: 100 }),
  call(`${LINEAR}get_user`, { query: 'me' }),
  call(`${LINEAR}get_issue`, { id: 'RUE-5' }),
  result(`${LINEAR}get_user`, { query: 'me' }),
  call(ASK),
  result(ASK),
  ...CREATES.flatMap(input => [call(`${LINEAR}save_issue`, input), result(`${LINEAR}save_issue`, input)]),
  call(ASK),
  { kind: 'turn.complete' },
]

test('a scaffold starts resolving, with nothing made', async () => {
  expect(startScaffold()).toEqual({ kind: 'scaffold', phase: 'resolving', created: 0 })
})

test('the live Linear run moves through the phases in order and ends done with five issues made', async () => {
  const seen: string[] = []
  let state = startScaffold()
  for (const event of LIVE) {
    state = advance(state, event)
    const label = `${state.phase}:${state.created}`
    if (seen[seen.length - 1] !== label) seen.push(label)
  }
  expect(seen).toEqual([
    'resolving:0',
    'drafting:0',
    'waiting:0',
    'drafting:0',
    'creating:0',
    'creating:1',
    'creating:2',
    'creating:3',
    'creating:4',
    'creating:5',
    'done:5',
  ])
})

test('the tracker lookups before verification leave the run resolving', async () => {
  const state = run([call('Read'), call(`${LINEAR}get_project`), call(`${LINEAR}list_teams`), call(`${LINEAR}list_issues`)])
  expect(state.phase).toBe('resolving')
})

test('verifying the tracker moves resolving to drafting, and a later verification moves nothing', async () => {
  const drafting = run([call(`${LINEAR}get_user`, { query: 'me' })])
  expect(drafting.phase).toBe('drafting')
  expect(advance({ ...drafting, phase: 'creating', created: 2 }, call(`${LINEAR}get_user`))).toEqual({ kind: 'scaffold', phase: 'creating', created: 2 })
})

test('a question before anything is made is the person being asked, and answering it resumes the draft', async () => {
  const waiting = run([call(`${LINEAR}get_user`), call(ASK)])
  expect(waiting.phase).toBe('waiting')
  expect(advance(waiting, result(ASK)).phase).toBe('drafting')
})

test('a question after issues were made is the hand-off, and the run is done', async () => {
  const state = run([call(`${LINEAR}save_issue`, MAIN), result(`${LINEAR}save_issue`, MAIN), call(ASK)])
  expect(state).toEqual({ kind: 'scaffold', phase: 'done', created: 1 })
})

test('an issue counts when the tracker accepts it, not when it is asked for', async () => {
  const asked = run([call(`${LINEAR}save_issue`, MAIN)])
  expect(asked).toEqual({ kind: 'scaffold', phase: 'creating', created: 0 })
  expect(advance(asked, result(`${LINEAR}save_issue`, MAIN, true))).toEqual(asked)
  expect(advance(asked, result(`${LINEAR}save_issue`, MAIN)).created).toBe(1)
})

test('a save_issue with an id is an update, as the sweep makes, and is not an issue made', async () => {
  const update = { id: 'RUE-5', state: 'Done' }
  expect(isCreate(`${LINEAR}save_issue`, update)).toBe(false)
  expect(run([call(`${LINEAR}get_user`), call(`${LINEAR}save_issue`, update), result(`${LINEAR}save_issue`, update)])).toEqual({
    kind: 'scaffold',
    phase: 'drafting',
    created: 0,
  })
})

test('only the tracker\'s create and verify calls are read as such, whatever else carries the name', async () => {
  expect(isCreate(`${LINEAR}save_issue`, MAIN)).toBe(true)
  expect(isCreate(`${LINEAR}save_issue`, SUB('x'))).toBe(true)
  expect(isCreate(`${LINEAR}get_issue`, {})).toBe(false)
  expect(isCreate('mcp__other-server__save_issue', MAIN)).toBe(false)
  expect(isCreate('save_issue', MAIN)).toBe(false)
  expect(isPreflight(`${LINEAR}get_user`)).toBe(true)
  expect(isPreflight(`${LINEAR}list_teams`)).toBe(false)
  expect(isPreflight('get_user')).toBe(false)
})

test('the turn ending after issues were made ends the run; before any, the run is left waiting, never done', async () => {
  expect(run([call(`${LINEAR}save_issue`, MAIN), result(`${LINEAR}save_issue`, MAIN), { kind: 'turn.complete' }]).phase).toBe('done')
  expect(run([call(`${LINEAR}get_user`), { kind: 'turn.complete' }]).phase).toBe('waiting')
  expect(run([{ kind: 'turn.complete' }]).phase).toBe('waiting')
})

test('a reply to a question that ended the turn resumes the draft', async () => {
  const waiting = run([call(`${LINEAR}get_user`), { kind: 'turn.complete' }])
  expect(waiting.phase).toBe('waiting')
  expect(advance(waiting, { kind: 'turn.start' }).phase).toBe('drafting')
})

test('handing off to execute ends the run, with or without the plugin prefix, and another skill does not', async () => {
  expect(run([call('Skill', { skill: 'fathom:execute' })]).phase).toBe('done')
  expect(run([call('Skill', { skill: 'execute' })]).phase).toBe('done')
  expect(run([call('Skill', { skill: 'fathom:review' })]).phase).toBe('resolving')
  expect(run([call('Skill', {})]).phase).toBe('resolving')
})

test('done is final: nothing after it moves the run', async () => {
  const done: ScaffoldState = { kind: 'scaffold', phase: 'done', created: 5 }
  for (const event of [{ kind: 'turn.start' }, { kind: 'turn.complete' }, call(`${LINEAR}save_issue`, MAIN), call(ASK), result(`${LINEAR}save_issue`, MAIN)] as ScaffoldEvent[]) {
    expect(advance(done, event)).toBe(done)
  }
})

test('an event that changes nothing returns the same state', async () => {
  const state = startScaffold()
  expect(advance(state, call('Read'))).toBe(state)
})

test('the label says what the run is doing, with the issues made so far', async () => {
  expect(phaseText({ kind: 'scaffold', phase: 'resolving', created: 0 })).toBe('Checking the tracker')
  expect(phaseText({ kind: 'scaffold', phase: 'drafting', created: 0 })).toBe('Drafting the issues')
  expect(phaseText({ kind: 'scaffold', phase: 'waiting', created: 0 })).toBe('Waiting on you')
  expect(phaseText({ kind: 'scaffold', phase: 'creating', created: 0 })).toBe('Creating issues')
  expect(phaseText({ kind: 'scaffold', phase: 'creating', created: 1 })).toBe('Creating, 1 issue made')
  expect(phaseText({ kind: 'scaffold', phase: 'creating', created: 3 })).toBe('Creating, 3 issues made')
  expect(phaseText({ kind: 'scaffold', phase: 'done', created: 5 })).toBe('Done, 5 issues made')
  expect(phaseText({ kind: 'scaffold', phase: 'done', created: 0 })).toBe('Done')
})

test('the steps line fills a circle before what is finished and outlines the current step, with waiting inside the draft', async () => {
  expect(stepsText('resolving')).toBe('○ Resolve  Draft  Create  Done')
  expect(stepsText('drafting')).toBe('● Resolve  ○ Draft  Create  Done')
  expect(stepsText('waiting')).toBe('● Resolve  ○ Draft  Create  Done')
  expect(stepsText('creating')).toBe('● Resolve  ● Draft  ○ Create  Done')
  expect(stepsText('done')).toBe('● Resolve  ● Draft  ● Create  ● Done')
})

test('a tool.call event becomes a call event with the engine\'s own fields taken off', async () => {
  const e = { tool: `${LINEAR}save_issue`, tool_use_id: 'toolu_1', title: 'x', parentId: 'RUE-17' }
  expect(inputOf(e)).toEqual({ title: 'x', parentId: 'RUE-17' })
  expect(callEvent(e.tool, inputOf(e))).toEqual({ kind: 'call', tool: `${LINEAR}save_issue`, input: { title: 'x', parentId: 'RUE-17' } })
})

test('a result is an error when the tool said so or the engine refused the call, and not otherwise', async () => {
  const input = { title: 'x' }
  const isError = (result: unknown) => (resultEvent(`${LINEAR}save_issue`, input, result) as { isError: boolean }).isError
  expect(isError({ result: {}, text: 'ok' })).toBe(false)
  expect(isError({ result: {}, text: 'no', isError: true })).toBe(true)
  expect(isError({ deny: 'blocked' })).toBe(true)
  expect(isError(undefined)).toBe(false)
})

test('a create refused by the engine is not counted', async () => {
  const asked = run([callEvent(`${LINEAR}save_issue`, MAIN)])
  expect(advance(asked, resultEvent(`${LINEAR}save_issue`, MAIN, { deny: 'blocked' })).created).toBe(0)
})

test('the marks are pieces of their own, one cell wide, so the band can color them: filled for done, outlined for the current step', async () => {
  const marks = (phase: Parameters<typeof stepParts>[0]) => stepParts(phase).filter(part => part.mark !== null)
  expect(marks('creating')).toEqual([
    { text: '\u25cf', mark: 'done' },
    { text: '\u25cf', mark: 'done' },
    { text: '\u25cb', mark: 'current' },
  ])
  expect(marks('resolving')).toEqual([{ text: '\u25cb', mark: 'current' }])
  expect(marks('waiting').map(part => part.mark)).toEqual(['done', 'current'])
  expect(marks('done').map(part => part.mark)).toEqual(['done', 'done', 'done', 'done'])
})

test('the elapsed time reads in seconds, then minutes and seconds, then hours and minutes', async () => {
  expect(elapsedText(0)).toBe('0s')
  expect(elapsedText(999)).toBe('0s')
  expect(elapsedText(37_000)).toBe('37s')
  expect(elapsedText(60_000)).toBe('1m 0s')
  expect(elapsedText(235_900)).toBe('3m 55s')
  expect(elapsedText(3_600_000)).toBe('1h 0m')
  expect(elapsedText(3_725_000)).toBe('1h 2m')
  expect(elapsedText(-5)).toBe('0s')
})
