import type { ScaffoldPhase, Snapshot } from '../types'

// Where a /fathom:scaffold run stands, worked out from the events a mod sees. Scaffold
// writes no beads and no plan document, so there is nothing to read back as there is for
// execute: the phases are inferred from the tracker's MCP calls, the questions Fathom asks
// and the turn ending. Pure: register.tsx raises the events and keeps the state, and this
// file only says what each event does to it, so it has tests.
//
// What the rules rest on was seen once, in a live run against Linear on 2026-10-19
// (claude-mods-fathom-fbf.1.2): `tool.call` fires for MCP tools, named
// `mcp__<server>__<tool>`; the tracker was verified with `get_user` before any question;
// each issue was made with `save_issue`, the main issue with no `parentId` and every
// sub-issue with one, and none of the creates carried an `id`; the questions were
// AskUserQuestion calls inside one turn; and `turn.complete` fired once, at the very
// end. Asana, a Team organization account and a `save_issue` that updates were not seen
// (claude-mods-fathom-fbf.1.7), so only Linear has entries below.
export type ScaffoldState = Extract<Snapshot, { kind: 'scaffold' }>

export type ScaffoldEvent =
  // A tool is about to run. `input` is the call's arguments.
  | { kind: 'call'; tool: string; input: Readonly<Record<string, unknown>> }
  // The same call came back.
  | { kind: 'result'; tool: string; input: Readonly<Record<string, unknown>>; isError: boolean }
  | { kind: 'turn.start' }
  | { kind: 'turn.complete' }

// The tools of a tracker, by server name. The server's name is the person's own
// configuration (`linear-server` here, a claude.ai connector elsewhere), so it is matched
// by what it contains, not by an exact name: that is a guess beyond the one run.
const TRACKERS = [
  // `save_issue` creates and updates alike, so a create is a call with no `id`.
  { server: /linear/i, preflight: ['get_user'], create: ['save_issue'] },
]

function parse(tool: string): { server: string; name: string } | null {
  const match = /^mcp__(.+?)__(.+)$/.exec(tool)
  return match ? { server: match[1] ?? '', name: match[2] ?? '' } : null
}

// The tracker's call that verifies it: the first sign that scaffold got past the lookups.
export function isPreflight(tool: string): boolean {
  const parsed = parse(tool)
  return !!parsed && TRACKERS.some(t => t.server.test(parsed.server) && t.preflight.includes(parsed.name))
}

// A call that makes a tracker issue, the main one or a sub-issue. A `save_issue` with an
// `id` updates one, as the done-on-merge sweep does, and is not a create.
export function isCreate(tool: string, input: Readonly<Record<string, unknown>>): boolean {
  const parsed = parse(tool)
  const hasId = input.id !== undefined && input.id !== null && input.id !== ''
  return !!parsed && !hasId && TRACKERS.some(t => t.server.test(parsed.server) && t.create.includes(parsed.name))
}

const ASK = 'AskUserQuestion'

// A tool.call event as the arguments it carried: everything but the engine's own `tool`
// and `tool_use_id` fields.
export function inputOf(e: Readonly<Record<string, unknown>>): Record<string, unknown> {
  const { tool: _tool, tool_use_id: _id, ...input } = e
  return input
}

export function callEvent(tool: string, input: Readonly<Record<string, unknown>>): ScaffoldEvent {
  return { kind: 'call', tool, input }
}

// The same call once it came back. A call the engine refused (`deny`) did not make
// anything, so it counts as an error like one the tool reported.
export function resultEvent(tool: string, input: Readonly<Record<string, unknown>>, result: unknown): ScaffoldEvent {
  const r = (result ?? {}) as { isError?: unknown; deny?: unknown }
  return { kind: 'result', tool, input, isError: r.isError === true || typeof r.deny === 'string' }
}

// Whether the skill the Skill tool was asked for is execute, which is what scaffold hands
// off to. The engine reports a skill as `fathom:execute`, and a bare name is accepted too.
function isExecute(input: Readonly<Record<string, unknown>>): boolean {
  return typeof input.skill === 'string' && /^(fathom:)?execute$/.test(input.skill)
}

export function startScaffold(): ScaffoldState {
  return { kind: 'scaffold', phase: 'resolving', created: 0 }
}

function at(state: ScaffoldState, phase: ScaffoldPhase, created = state.created): ScaffoldState {
  return phase === state.phase && created === state.created ? state : { kind: 'scaffold', phase, created }
}

// Whether the run has begun making issues, so a question now is the hand-off.
const hasCreated = (state: ScaffoldState) => state.phase === 'creating' || state.created > 0

// What one event does. `done` is final: the later events of the same turn (the summary,
// the hand-off's reply) move nothing, and the next Fathom command starts a new run.
export function advance(state: ScaffoldState, event: ScaffoldEvent): ScaffoldState {
  if (state.phase === 'done') return state

  switch (event.kind) {
    case 'call':
      if (isCreate(event.tool, event.input)) return at(state, 'creating')
      if (isPreflight(event.tool)) return state.phase === 'resolving' ? at(state, 'drafting') : state
      // A question before anything is made is the person being asked about the draft or
      // the requirements; one after is the hand-off ("run execute now?"), and the run is
      // done.
      if (event.tool === ASK) return at(state, hasCreated(state) ? 'done' : 'waiting')
      // Execute taking over, as when the hand-off needs no question.
      if (event.tool === 'Skill' && isExecute(event.input)) return at(state, 'done')
      return state

    case 'result':
      // An issue counts when the tracker accepted it, not when it was asked for.
      if (isCreate(event.tool, event.input)) return event.isError ? state : at(state, 'creating', state.created + 1)
      // The person answered, so the run is working again.
      if (event.tool === ASK && state.phase === 'waiting') return at(state, 'drafting')
      return state

    // The person replied to a question that ended the turn.
    case 'turn.start':
      return state.phase === 'waiting' ? at(state, 'drafting') : state

    // The turn ended. After issues were made that is the end of the run. Before, Fathom
    // stopped to ask in plain text, or stopped altogether (a missing tracker); the band
    // cannot tell those apart, and does not claim a finish that did not happen.
    case 'turn.complete':
      return at(state, hasCreated(state) ? 'done' : 'waiting')
  }
}

// The steps the band lists, in order. `waiting` is not a step: the run is waiting on the
// person inside the draft step.
export const STEPS = ['Resolve', 'Draft', 'Create', 'Done'] as const

// Which step the phase is in.
export function stepOf(phase: ScaffoldPhase): number {
  return { resolving: 0, drafting: 1, waiting: 1, creating: 2, done: 3 }[phase]
}

// What the label says the run is doing.
export function phaseText(state: ScaffoldState): string {
  switch (state.phase) {
    case 'resolving':
      return 'Checking the tracker'
    case 'drafting':
      return 'Drafting the issues'
    case 'waiting':
      return 'Waiting on you'
    case 'creating':
      return state.created === 0 ? 'Creating issues' : `Creating, ${issues(state.created)} made`
    case 'done':
      return state.created === 0 ? 'Done' : `Done, ${issues(state.created)} made`
  }
}

export function issues(count: number): string {
  return `${count} issue${count === 1 ? '' : 's'}`
}

// The steps as pieces of one line, so the state never rests on color: a filled circle
// before each finished step, an outlined one before the current step, and nothing before
// those to come. A finished run has every step filled. The marks are pieces of their own so
// the band can color them (green and the band's color, as the design does); the rest of the
// line is dim.
export const DONE_MARK = '\u25cf'
export const CURRENT_MARK = '\u25cb'

export type StepPart = { text: string; mark: 'done' | 'current' | null }

// Each step with its mark, or none for a step to come.
export function stepMarks(phase: ScaffoldPhase): { label: string; mark: 'done' | 'current' | null }[] {
  const current = stepOf(phase)
  return STEPS.map((label, i) => ({ label, mark: phase === 'done' || i < current ? 'done' : i === current ? 'current' : null }))
}

export function stepParts(phase: ScaffoldPhase): StepPart[] {
  return stepMarks(phase).flatMap(({ label, mark }, i): StepPart[] => {
    const gap: StepPart[] = i === 0 ? [] : [{ text: '  ', mark: null }]
    if (mark === null) return [...gap, { text: label, mark: null }]
    return [...gap, { text: mark === 'done' ? DONE_MARK : CURRENT_MARK, mark }, { text: ` ${label}`, mark: null }]
  })
}

export function stepsText(phase: ScaffoldPhase): string {
  return stepParts(phase)
    .map(part => part.text)
    .join('')
}

// How long the run has gone on, as the band says it: `37s`, `3m 55s`, `1h 2m`. Whole
// seconds, rounded down; nothing under a second reads as `0s`.
export function elapsedText(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000))
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const seconds = total % 60
  if (hours > 0) return `${hours}h ${minutes}m`
  return minutes > 0 ? `${minutes}m ${seconds}s` : `${seconds}s`
}
