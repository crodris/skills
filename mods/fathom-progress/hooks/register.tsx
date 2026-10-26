import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Plan, Snapshot } from '../types'
import { readBd } from './bd'
import { runSourceOf, toChecklistSnapshot } from './checklist'
import { NONE, barLabelOn, cmuxEntries, isOurBar, meterValue, pillKeyFor } from './cmux'
import type { CmuxEntries } from './cmux'
import { paletteFor } from './desktop'
import { drawBand } from './draw'
import {
  POLL_MS,
  beadsPath,
  checklistPath,
  planPath,
  refsOfBranch,
  refsOfPrompt,
  snapshotOnStart,
  startOf,
  startOfPrompt,
  touchesRun,
} from './lifecycle'
import { parsePlan } from './plan'
import { advance, callEvent, inputOf, resultEvent } from './scaffold'
import type { ScaffoldEvent } from './scaffold'
import { parseEpics, pickRun, toSnapshot } from './state'
import type { Epic } from './state'

const armedAt = atom({ plugin: 'fathom-progress', key: 'armedAt' } as const, null)
const armedRefs = atom({ plugin: 'fathom-progress', key: 'refs' } as const, [])
const snapshot = atom({ plugin: 'fathom-progress', key: 'snapshot' } as const, { kind: 'idle' })
const isHidden = atom({ plugin: 'fathom-progress', key: 'isHidden' } as const, false)
const tick = atom({ plugin: 'fathom-progress', key: 'tick' } as const, 0)

// When the scaffold run began and, once it is done, ended, in ms, for the time the band
// shows. Kept here and not in the snapshot: it is not what the run is doing, and a module
// that reloads loses it, which the band takes as an elapsed time it does not know and leaves
// off. The tick moves each second while the run is going, which is what redraws the time.
let scaffoldRun: { startedAt: number; endedAt: number | null } | null = null
const TICK_MS = 1000

async function bd($: EngineInterface, root: string, args: string[]): Promise<unknown> {
  return readBd(args[0] ?? '', await $.process.run(['bd', ...args], { cwd: root }))
}

// The run's plan document, parsed; null when there is none yet or it cannot be read.
async function readPlan($: EngineInterface, root: string, ref: string): Promise<Plan | null> {
  const path = planPath(root, ref)
  if (path === null) return null
  try {
    return parsePlan(await $.fs.read(path))
  } catch {
    return null
  }
}

// The Fathom epics bd lists, or why it could not be read. A bd that is missing or fails is
// no reason to stop here: the issue may be on the checklist backend, which needs no bd.
// With no epic and no checklist, the reason is what the band shows.
async function epicsOf($: EngineInterface, root: string): Promise<{ epics: Epic[]; error: string | null }> {
  try {
    const epics = parseEpics(await bd($, root, ['list', '--type', 'epic', '--all', '--limit', '0', '--json']))
    return epics === null ? { epics: [], error: 'bd did not return a JSON list' } : { epics, error: null }
  } catch (error) {
    return { epics: [], error: error instanceof Error ? error.message : String(error) }
  }
}

// The checklist of the first of `refs` that has one, read from the working tree (its
// in-progress marker is never committed), by ref; empty when none can be read.
async function checklistsOf($: EngineInterface, root: string, refs: readonly string[]): Promise<Map<string, string>> {
  const files = new Map<string, string>()
  for (const ref of refs) {
    const path = checklistPath(root, ref)
    if (path === null) continue
    try {
      files.set(ref, await $.fs.read(path))
      break
    } catch {
      // No file, or one that cannot be read: the issue is not on the checklist backend.
    }
  }
  return files
}

// The branch the session's repository is on, or '' when there is none to read. Read with
// each refresh and not when armed: Fathom makes the issue's branch after it starts.
async function branchOf($: EngineInterface, root: string): Promise<string> {
  try {
    const out = await $.process.run(['git', 'branch', '--show-current'], { cwd: root })
    return out.exitCode === 0 ? out.stdout.trim() : ''
  } catch {
    return ''
  }
}

// What the debug log last said the band follows, so it says it once per change.
let lastFollowed = ''

// Reads bd and the plan document and builds what the band shows. Three bd calls, one
// after the other: they are reads, but they share one embedded database. `typed` is
// what the person typed after the command; with none, the branch's ref stands in.
// When bd has no epic for that ref, the issue may be on the checklist backend: its
// .fathom/tasks/<ref>.md is read instead, and bd being missing or failing hides neither.
async function build($: EngineInterface, since: number, typed: readonly string[]): Promise<Snapshot> {
  try {
    const root = await $.session.root()
    const { epics, error } = await epicsOf($, root)

    const branch = typed.length > 0 ? [] : refsOfBranch(await branchOf($, root))
    const refs = typed.length > 0 ? typed : branch
    const epic = pickRun(epics, since, { refs, isExact: typed.length > 0 })
    // Beads wins, so the checklist files are read only when bd has no epic to follow.
    const files = epic === null ? await checklistsOf($, root, refs) : new Map<string, string>()
    // Whether bd failing means anything is asked only when it could matter: no run to follow.
    const hasBeads = epic === null && error !== null && files.size === 0 ? await $.fs.exists(beadsPath(root)) : true
    const source = runSourceOf({ epic, bdError: error, hasBeads, refs, files })

    const run = source.kind === 'beads' ? source.epic.ref : source.kind === 'checklist' ? `${source.ref} (checklist)` : 'nothing'
    const followed = `${run} (typed ${typed.join(',') || '-'}, branch ${branch.join(',') || '-'})`
    if (followed !== lastFollowed) {
      lastFollowed = followed
      $.ui.log(`fathom-progress: following ${followed}`, { to: 'debug' })
    }
    if (source.kind === 'starting') return { kind: 'starting' }
    if (source.kind === 'unavailable') return source
    if (source.kind === 'checklist') {
      const plan = await readPlan($, root, source.ref)
      return toChecklistSnapshot({ ref: source.ref, checklist: source.checklist, plan })
    }

    const ref = source.epic.ref
    const tasks = await bd($, root, ['list', '-l', ref, '--type', 'task', '--all', '--limit', '0', '--json'])
    const ready = await bd($, root, ['ready', '-l', ref, '--type', 'task', '--limit', '50', '--json'])
    return toSnapshot({ epic: source.epic, tasks, ready, plan: await readPlan($, root, ref) })
  } catch (error) {
    // Unlike a count, a failure is kept and shown ("unavailable"), never zeros.
    const reason = error instanceof Error ? error.message : String(error)
    $.ui.log(`fathom-progress: refresh failed: ${reason}`, { to: 'debug' })
    return { kind: 'unavailable', reason }
  }
}

// The person's theme, as `/config` holds it, for the desktop bar's colors. Read with each
// refresh and not with each draw, since it rarely changes and a draw must stay quick.
let theme: string | null = null

async function readTheme($: EngineInterface) {
  try {
    const row = (await $.config.list()).find(r => r.key === 'theme')
    theme = typeof row?.value === 'string' ? row.value : null
  } catch {
    theme = null
  }
}

// The cmux sidebar row. Inside cmux the snapshot the band draws also goes onto the
// workspace's row, as a status pill and a progress bar, through cmux's own command line.
// Outside cmux (the desktop app, any other terminal) there is no CMUX_WORKSPACE_ID and
// nothing happens. All of it is best effort: a cmux that is missing, stopped or slow must
// never touch the band.
const CMUX_TIMEOUT_MS = 3000

// What the row last got, as the text it was made from, so an unchanged snapshot (every
// poll) sends nothing; and the label of the bar we put on it, if any. cmux has one bar per
// workspace, and another pane's run may take it over, so ours is cleared only while the
// row still shows it, never someone else's.
let sentToCmux: string | null = null
let ownBar: string | null = null

// Runs one cmux command. Returns what it printed, or null when it did not work.
async function cmux($: EngineInterface, args: string[]): Promise<string | null> {
  try {
    const out = await $.process.run(['cmux', ...args], { timeoutMs: CMUX_TIMEOUT_MS })
    if (out.exitCode !== 0) {
      $.ui.log(`fathom-progress: cmux ${args[0]} exited ${out.exitCode}: ${out.stderr.trim().split('\n')[0] ?? ''}`, { to: 'debug' })
      return null
    }
    return out.stdout
  } catch (error) {
    $.ui.log(`fathom-progress: cmux ${args[0]} failed: ${error instanceof Error ? error.message : String(error)}`, { to: 'debug' })
    return null
  }
}

// Puts `entries` on the row, or takes ours off when there are none. `isForced` sends
// even when nothing changed: session.start uses it to remove a pill that a session which
// ended badly left behind.
async function syncCmux($: EngineInterface, entries: CmuxEntries, isForced: boolean): Promise<void> {
  if ((await $.env.get('CMUX_WORKSPACE_ID')) === undefined) return
  const key = JSON.stringify(entries)
  if (!isForced && key === sentToCmux) return
  sentToCmux = key

  // A key for this pane, so a second run in the workspace has a pill of its own and ending
  // one run leaves the other's.
  const pillKey = pillKeyFor(await $.env.get('CMUX_SURFACE_ID'))
  const { pill, meter } = entries
  if (pill) await cmux($, ['set-status', pillKey, pill.text, '--icon', pill.icon, '--color', pill.color])
  else await cmux($, ['clear-status', pillKey])

  if (meter) {
    ownBar = meter.label
    await cmux($, ['set-progress', meterValue(meter.value), '--label', meter.label])
  } else if (ownBar !== null) {
    const label = ownBar
    ownBar = null
    // The bar may be another run's by now: leave it. When cmux can't say, clear it, as the
    // mod always did; a cmux that fails to answer is unlikely to take the clear either.
    const row = await cmux($, ['sidebar-state'])
    if (row === null || isOurBar(barLabelOn(row), label)) await cmux($, ['clear-progress'])
  }
}

// One send at a time, in the order asked: two overlapping ones could leave the older
// pill on the row. Each reads the snapshot when its turn comes, so the last one wins.
let cmuxQueue: Promise<void> = Promise.resolve()

// The row follows the band: what the band shows, and nothing while it is hidden or idle.
function publish($: EngineInterface, isForced = false): Promise<void> {
  cmuxQueue = cmuxQueue.then(async () => {
    try {
      const entries = (await read($, isHidden)) ? NONE : cmuxEntries(await read($, snapshot))
      await syncCmux($, entries, isForced)
    } catch (error) {
      $.ui.log(`fathom-progress: cmux sync failed: ${error instanceof Error ? error.message : String(error)}`, { to: 'debug' })
    }
  })
  return cmuxQueue
}

// One refresh at a time. A call that arrives during one asks for another straight
// after it, so the last change is never missed and the calls never pile up.
let isRefreshing = false
let isStale = false

async function refresh($: EngineInterface) {
  if (isRefreshing) {
    isStale = true
    return
  }
  isRefreshing = true
  try {
    do {
      isStale = false
      const since = await read($, armedAt)
      // Not armed: nothing to show and nothing to poll.
      if (since === null) return
      await readTheme($)
      const fresh = await build($, since, await read($, armedRefs))
      // A new invocation, or the session ending, during the fetch makes it stale.
      if ((await read($, armedAt)) === since) {
        await update($, snapshot, () => fresh)
        void publish($)
      }
    } while (isStale)
  } finally {
    isRefreshing = false
  }
}

// One event at a time, in the order they came: two overlapping ones could read the same
// state and lose a count. Only a scaffold run is moved; for anything else the state is left
// as it is, so an execute run never sees these events. Not awaited by the hooks, so Claude
// gets its tool's result and its turn at once, and a failure here is only logged.
let scaffoldQueue: Promise<void> = Promise.resolve()

function feedScaffold($: EngineInterface, event: ScaffoldEvent): void {
  scaffoldQueue = scaffoldQueue.then(async () => {
    try {
      const current = await read($, snapshot)
      if (current.kind !== 'scaffold') return
      const next = advance(current, event)
      if (next === current) return
      if (next.phase === 'done' && scaffoldRun !== null && scaffoldRun.endedAt === null) {
        scaffoldRun = { ...scaffoldRun, endedAt: await $.clock.now() }
      }
      await update($, snapshot, () => next)
      void publish($)
    } catch (error) {
      $.ui.log(`fathom-progress: scaffold event failed: ${error instanceof Error ? error.message : String(error)}`, { to: 'debug' })
    }
  })
}

// One start reaches arm by more than one signal within about this long.
const SAME_START_MS = 3000

// A Fathom skill started. Execute arms the band: it shows `starting` until the epic
// exists, then follows the run. Scaffold writes no beads, so there is no run to follow: it
// disarms, which also stops the poll, and shows its first phase, which the events of the run
// move on (feedScaffold).
// When the last scaffold started, so the second signal of one start (a typed command is a
// `skill.prompt` and a `prompt.submit`) does not put a run already moving back on its
// first phase.
let lastScaffoldAt = Number.NEGATIVE_INFINITY

async function arm($: EngineInterface, start: 'execute' | 'scaffold' | null, via: string, refs: readonly string[] = []) {
  if (start === null) return
  const now = await $.clock.now()
  if (start === 'scaffold') {
    if (now - lastScaffoldAt < SAME_START_MS) return
    lastScaffoldAt = now
  }
  // One start can reach here by more than one signal (a typed command is a `skill.prompt`
  // and a `prompt.submit`): the later ones, moments after the first, add nothing, except
  // the refs, which only the typed command carries and which may come second.
  const last = await read($, armedAt)
  if (start === 'execute' && last !== null && now - last < SAME_START_MS) {
    if (refs.length > 0) {
      await update($, armedRefs, () => [...refs])
      void refresh($)
    }
    return
  }
  scaffoldRun = start === 'scaffold' ? { startedAt: now, endedAt: null } : null
  await update($, tick, () => now)
  await update($, armedAt, () => (start === 'execute' ? now : null))
  await update($, armedRefs, () => [...refs])
  await update($, snapshot, () => snapshotOnStart(start))
  void publish($)
  $.ui.log(`fathom-progress: armed (${start}) by ${via}, typed refs ${refs.join(',') || '-'}`, { to: 'debug' })
  if (start === 'execute') void refresh($)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // The timer runs all session and does nothing until armed. A finished run does not
    // change, so it is not polled; the next invocation refreshes it.
    $.clock.every(POLL_MS, async () => {
      if ((await read($, snapshot)).kind !== 'finished') await refresh($)
    })

    // Moves the time a running scaffold shows. Nothing else is drawn from it.
    $.clock.every(TICK_MS, async () => {
      if (scaffoldRun === null || scaffoldRun.endedAt !== null) return
      const now = await $.clock.now()
      if ((await read($, snapshot)).kind === 'scaffold') await update($, tick, () => now)
    })

    // A taken name throws, and a hook that throws is skipped; register last.
    try {
      await $.command.register({ name: 'fathom-progress', description: 'Toggle the Fathom progress band.' })
    } catch {}

    // Forced, to take off the row a pill that a session which ended badly left there, and to
    // put the run back after /reload-plugins, which makes this module new and leaves the
    // band's state as it was.
    void publish($, true)

    return next(e)
  })

  // The module and its timer survive /clear (probed, claude-mods-fathom-5l2.2), and
  // session.start does not fire again, so the reset is here, for every reason.
  on('session.end', async ($, e, next) => {
    scaffoldRun = null
    await update($, armedAt, () => null)
    await update($, armedRefs, () => [])
    await update($, snapshot, () => ({ kind: 'idle' }))
    // Awaited: the session may be gone straight after, and the row must not keep the run.
    await publish($)
    return next(e)
  })

  // The signal that Fathom started: the engine reports the skill's own text, typed as a
  // command or called through the Skill tool. A new invocation re-arms and re-picks.
  on('skill.prompt', async ($, e, next) => {
    await arm($, startOf(e.skill), 'skill.prompt')
    return next(e)
  })

  // The same two signals where `skill.prompt` is skipped (a Team organization's built-in
  // security plugin answers it first): a typed command, and the Skill tool's call. Both
  // only read; a failure here must never hold up the prompt or the tool.
  on('prompt.submit', async ($, e, next) => {
    try {
      await arm($, startOfPrompt(e.text), 'prompt.submit', refsOfPrompt(e.text))
    } catch {}
    return next(e)
  })

  on('tool.call', { tool: 'Skill' }, async ($, e, next) => {
    try {
      if (typeof e.skill === 'string') {
        // Scaffold handing off to execute ends the scaffold run; arm then starts execute's.
        feedScaffold($, callEvent('Skill', { skill: e.skill }))
        await arm($, startOf(e.skill), 'tool.call')
      }
    } catch {}
    return next(e)
  })

  // What a scaffold run does is visible only as its calls: the tracker's MCP tools and the
  // questions it asks, which are the only ones the phases read. Each is passed on as it
  // came, and its result is returned as it came.
  on('tool.call', { tool: ['AskUserQuestion', /^mcp__/] }, async ($, e, next) => {
    const tool = String(e.tool)
    const input = inputOf(e as unknown as Record<string, unknown>)
    feedScaffold($, callEvent(tool, input))
    const result = await next(e)
    feedScaffold($, resultEvent(tool, input, result))
    return result
  })

  // A turn is the model's work for one prompt. A subagent's turns are not the run's.
  on('turn.start', async ($, e, next) => {
    if ((e as { agentId?: string }).agentId === undefined) feedScaffold($, { kind: 'turn.start' })
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if ((e as { agentId?: string }).agentId === undefined) feedScaffold($, { kind: 'turn.complete' })
    return next(e)
  })

  // A bd call or a commit may have moved the run: catch up now, not at the next poll.
  // Not awaited, so Claude gets the tool's result at once.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    if (typeof e.command === 'string' && touchesRun(e.command)) void refresh($)
    return result
  })

  on('command.run', { command: 'fathom-progress' }, async $ => {
    const current = await read($, isHidden)
    await update($, isHidden, () => !current)
    void publish($)
    return { text: current ? 'Fathom band shown.' : 'Fathom band hidden.' }
  })

  // The band answers AbovePrompt only while it has something to show; otherwise it
  // passes the event on, so beads-status can draw there.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const current = await read($, snapshot)
    if (e.props.hasSurvey || current.kind === 'idle' || (await read($, isHidden))) return next(e)
    // How long a scaffold run has gone on. The tick is read only for one, so no other band is
    // redrawn by it.
    const now = current.kind === 'scaffold' ? await read($, tick) : 0
    const elapsedMs = current.kind === 'scaffold' && scaffoldRun !== null ? (scaffoldRun.endedAt ?? now) - scaffoldRun.startedAt : null
    return drawBand($.ui.resolve(e), e.props.bodyColumns, current, { surface: e.surface, palette: paletteFor(theme), elapsedMs }) ?? next(e)
  })
}
