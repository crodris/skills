import type { On } from 'claude-code'
import { test, expect } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import type { RunTask, Snapshot, TaskState } from '../types'
import { DARK } from './desktop'
import type { Palette } from './desktop'
import { drawBand } from './draw'

/**
 * Draws `drawBand` through the test kit, on each surface the mod claims, to read the
 * tree it returns: the text of each row. The kit exercises the tree under that
 * surface's element table, never its paint, so colors, the heavy line and the icon
 * glyphs still need a look at the live band, in the terminal and in the desktop app.
 *
 * The plugin's own `ui.render` hook reads state atoms, which are empty in the test
 * environment, so it does not answer; the stub beneath it draws `drawBand` with the
 * snapshot the test chooses.
 */

type Surface = 'terminal' | 'desktop'

const PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 4,
  bodyColumns: 80,
  scroll: { offset: 0, bodyRows: 4 },
  view: {},
}

const TITLES = [
  'Draft the plan doc',
  'Capture the fixtures',
  'Wire the lifecycle hooks',
  'Draw the executing view',
  'Verify in a live session',
]

function runOf(states: TaskState[], reviewed: number[] = []): RunTask[] {
  return states.map((state, i) => ({
    id: `fx-${i + 1}`,
    ref: `SLU-123-${i + 1}`,
    title: TITLES[i] ?? `Task ${i + 1}`,
    state,
    isInReview: reviewed.includes(i),
  }))
}

// The frames of the design: planned, executing, done and creating.
const PLANNED: Snapshot = { kind: 'executing', ref: 'SLU-123', tasks: runOf(['next', 'waiting', 'waiting', 'waiting', 'waiting']) }
const EXECUTING: Snapshot = {
  kind: 'executing',
  ref: 'SLU-123',
  title: 'Add the progress band',
  tasks: runOf(['done', 'done', 'inProgress', 'waiting', 'waiting'], [1]),
}
const DONE: Snapshot = { kind: 'finished', ref: 'SLU-123', title: 'Add the progress band', tasks: runOf(['done', 'done', 'done', 'done', 'done']) }

// The terminal's bar: heavy lines, each segment but the last ending in a heavy half line,
// which is the gap. At 80 columns the bar has 74 cells, of which 70 divide among five tasks:
// fourteen wide each. Three made so far fill three of five slots of fourteen.
const seg = (n: number, hasNext = true) => '━'.repeat(hasNext ? n - 1 : n) + (hasNext ? '╸' : '')
const BAR_OF_FIVE = seg(14).repeat(4) + seg(14, false)
const BAR_OF_THREE_SLOTS = seg(14) + seg(14) + seg(14, false)

type Node = string | { type?: string; props?: Record<string, unknown>; children?: readonly Node[] }

// The text a node draws, nested Text and Box children joined as they are laid out.
function textOf(node: Node): string {
  return typeof node === 'string' ? node : (node.children ?? []).map(textOf).join('')
}

// The Boxes under a node that have a background, in drawing order: a segment of the
// desktop's theme-following bar is one.
function filledBoxes(node: unknown): { color: unknown; width: unknown }[] {
  const n = node as { type?: string; props?: Record<string, unknown>; children?: unknown[] } | string | null | undefined
  if (!n || typeof n === 'string') return []
  const own = n.type === 'Box' && n.props?.backgroundColor ? [{ color: n.props.backgroundColor, width: n.props.width }] : []
  return [...own, ...(n.children ?? []).flatMap(filledBoxes)]
}

// The runs of the terminal's bar under a node, in drawing order: each colored Text of
// heavy lines and the color it is drawn in. Neighboring segments of one color are one run,
// since nothing separates them. The Text that wraps the whole bar has no color of its own,
// so a bar of one unbroken run is not counted twice.
function barRuns(node: unknown): { text: string; color: unknown }[] {
  const n = node as { type?: string; props?: Record<string, unknown>; children?: Node[] } | string | null | undefined
  if (!n || typeof n === 'string') return []
  const own = n.type === 'Text' && n.props?.color !== undefined && /^[━╸]+$/.test(textOf(n)) ? [{ text: textOf(n), color: n.props.color }] : []
  return [...own, ...(n.children ?? []).flatMap(barRuns)]
}

// The kit takes one `on` per test, before the first mount, so the stub is registered
// once and the snapshot it draws is swapped between mounts.
function band($: Engine, on: On) {
  let current: Snapshot = { kind: 'idle' }
  let palette: Palette | null = null
  let elapsedMs: number | null = null
  let isNull = false
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const tree = drawBand($.ui.resolve(e), e.props.bodyColumns, current, { surface: e.surface, palette, elapsedMs })
    isNull = tree === null
    return tree ?? next(e)
  })

  // Mounts the band on `surface` and reads its rows. Both surfaces draw three: the bar with
  // the percent, the title row (the dot, the label and the reviews open), and the line beneath.
  return {
    wasNull: () => isNull,
    async show(snapshot: Snapshot, surface: Surface, bodyColumns = 80, withPalette: Palette | null = null, withElapsedMs: number | null = null) {
      current = snapshot
      palette = withPalette
      elapsedMs = withElapsedMs
      const ui = await $.ui.mount({
        plugin: 'fathom-progress',
        surface,
        component: 'AbovePrompt',
        requestId: 'r',
        props: { ...PROPS, bodyColumns },
      })
      const tree = (await ui.drawn()) as unknown as { props?: Record<string, unknown>; children?: Node[] } | null
      const row = (i: number) => {
        const node = tree?.children?.[i]
        return node === undefined ? '' : textOf(node)
      }
      return { ui, head: row(0), title: row(1), line: row(2), tree }
    },
  }
}

test('terminal planned: five grey segments, 0% at the end of the bar row, the dot and label, and the next task named beneath', async ($, on) => {
  const { show } = band($, on)
  const { ui, head, title, line, tree } = await show(PLANNED, 'terminal')

  expect(head).toBe(`${BAR_OF_FIVE}0%`)
  // The plan names no title here, so the ref stands alone.
  expect(title).toBe('●SLU-123')
  expect(line).toBe('▸ next 1/5  Draft the plan doc')
  // Five grey segments are one run: nothing separates neighbors of a color.
  expect(barRuns(tree)).toEqual([{ text: BAR_OF_FIVE, color: 'subtle' }])
  // The bar row is the band's first row: there is no row of padding above it.
  expect(tree?.props?.paddingTop).toBeUndefined()
  await ui.unmount()
})

test('terminal executing: the bar in each state\'s color, 40%, the reviews open beside the label, and the task in progress beneath', async ($, on) => {
  const { show } = band($, on)
  const { ui, head, title, line, tree } = await show(EXECUTING, 'terminal')

  expect(head).toBe(`${BAR_OF_FIVE}40%`)
  expect(barRuns(tree)).toEqual([
    { text: seg(14), color: 'success' },
    { text: seg(14), color: 'claude' },
    { text: seg(14), color: 'warning' },
    { text: seg(14) + seg(14, false), color: 'subtle' },
  ])
  expect(title).toBe('●SLU-123 Add the progress band· 1 in review')
  // The note is its own dim Text on the title row, and the line beneath no longer carries it.
  const note = (await ui.find({ type: 'Text', text: '· 1 in review' })) as unknown as { props?: { dimColor?: boolean } } | undefined
  expect(note?.props?.dimColor).toBe(true)
  expect(line).toBe('▸ now 3/5  Wire the lifecycle hooks')
  expect(await ui.find({ type: 'Text', text: '▸ now 3/5  Wire the lifecycle hooks' })).toBeDefined()
  await ui.unmount()
})

test('terminal between tasks: the next task is named and the reviews open are counted beside the label', async ($, on) => {
  const { show } = band($, on)
  const between: Snapshot = {
    kind: 'executing',
    ref: 'SLU-123',
    title: 'Add the progress band',
    tasks: runOf(['done', 'done', 'next', 'waiting', 'waiting'], [0, 1]),
  }
  const { ui, head, title, line } = await show(between, 'terminal')

  expect(head).toBe(`${BAR_OF_FIVE}40%`)
  expect(title).toBe('●SLU-123 Add the progress band· 2 in review')
  expect(line).toBe('▸ next 3/5  Wire the lifecycle hooks')
  await ui.unmount()
})

test('terminal done: a full green bar, 100%, no reviews, and the count beneath', async ($, on) => {
  const { show } = band($, on)
  const { ui, head, title, line, tree } = await show(DONE, 'terminal')

  expect(head).toBe(`${BAR_OF_FIVE}100%`)
  expect(barRuns(tree)).toEqual([{ text: BAR_OF_FIVE, color: 'success' }])
  expect(title).toBe('●SLU-123 Add the progress band')
  expect(line).toBe('✓ 5/5 done')
  await ui.unmount()
})

test('the dot is grey until a task starts, the band\'s color while it runs, and green when done', async ($, on) => {
  const { show } = band($, on)
  const colorOfDot = async (snapshot: Snapshot) => {
    const { ui } = await show(snapshot, 'terminal')
    const dot = await ui.find({ type: 'Text', text: '●' })
    await ui.unmount()
    return (dot as unknown as { props?: { color?: string } } | undefined)?.props?.color
  }

  expect(await colorOfDot(PLANNED)).toBe('inactive')
  expect(await colorOfDot(EXECUTING)).toBe('claude')
  expect(await colorOfDot(DONE)).toBe('success')
  expect(await colorOfDot({ kind: 'creating', ref: 'SLU-123', created: 3 })).toBe('claude')
})

test('terminal creating: the tasks made so far fill slots of the bar, 0% where the percent goes, and no total', async ($, on) => {
  const { show } = band($, on)

  const three = await show({ kind: 'creating', ref: 'SLU-123', created: 3 }, 'terminal')
  expect(three.head).toBe(`${BAR_OF_THREE_SLOTS}0%`)
  // The plan is written after the tasks, so a run being created has no title yet.
  expect(three.title).toBe('●SLU-123')
  expect(three.line).toBe('▸ planning  3 tasks so far')
  expect(barRuns(three.tree)).toEqual([{ text: BAR_OF_THREE_SLOTS, color: 'subtle' }])
  await three.ui.unmount()

  const none = await show({ kind: 'creating', ref: 'SLU-123', created: 0 }, 'terminal')
  expect(none.head).toBe('0%')
  expect(none.line).toBe('▸ planning  no tasks yet')
  await none.ui.unmount()

  const one = await show({ kind: 'creating', ref: 'SLU-123', created: 1 }, 'terminal')
  expect(one.line).toBe('▸ planning  1 task so far')
  await one.ui.unmount()
})

test('desktop creating shows the tasks made so far, 0% where the percent goes, and no total', async ($, on) => {
  const { show } = band($, on)
  const { ui, head, title, line } = await show({ kind: 'creating', ref: 'SLU-123', created: 3 }, 'desktop')

  expect(head.endsWith('0%')).toBe(true)
  expect(title).toBe('●SLU-123 Progress band')
  // The design's Creating frame has no arrow before the line, as the terminal's does.
  expect(line).toBe('planning  3 tasks so far')
  await ui.unmount()
})

const SCAFFOLD = (phase: 'resolving' | 'drafting' | 'waiting' | 'creating' | 'done', created = 0): Snapshot => ({ kind: 'scaffold', phase, created })

test('a scaffold is two rows on both surfaces: the dot and what the run is doing, then the steps with the finished ones checked', async ($, on) => {
  const { show } = band($, on)
  const frames: [Snapshot, string, string][] = [
    [SCAFFOLD('resolving'), 'Scaffold · Checking the tracker', '○ Resolve  Draft  Create  Done'],
    [SCAFFOLD('drafting'), 'Scaffold · Drafting the issues', '● Resolve  ○ Draft  Create  Done'],
    [SCAFFOLD('waiting'), 'Scaffold · ● Waiting on you', '● Resolve  ○ Draft  Create  Done'],
    [SCAFFOLD('creating', 0), 'Scaffold · Creating issues', '● Resolve  ● Draft  ○ Create  Done'],
    [SCAFFOLD('creating', 3), 'Scaffold · Creating, 3 issues made', '● Resolve  ● Draft  ○ Create  Done'],
    [SCAFFOLD('done', 5), 'Scaffold · Done, 5 issues made', '● Resolve  ● Draft  ● Create  ● Done'],
  ]
  for (const surface of ['terminal', 'desktop'] as const) {
    for (const [snapshot, label, steps] of frames) {
      const { ui, head, title, tree } = await show(snapshot, surface)
      // The first row is the label and the second the steps. No bar, no percent.
      expect(head).toBe(label)
      expect(title).toBe(steps)
      expect(tree?.children).toHaveLength(2)
      expect(head).not.toContain('%')
      await ui.unmount()
    }
  }
})

test('a scaffold on the desktop has a row of padding above it for the engine\'s [-], and on the terminal none', async ($, on) => {
  const { show } = band($, on)
  const desktop = await show(SCAFFOLD('drafting'), 'desktop')
  expect(desktop.tree?.props?.paddingTop).toBe(1)
  await desktop.ui.unmount()
  const terminal = await show(SCAFFOLD('drafting'), 'terminal')
  expect(terminal.tree?.props?.paddingTop).toBeUndefined()
  await terminal.ui.unmount()
})

// The colors of the pieces of text under a node that read `text`, in drawing order.
function colorsOf(node: unknown, text: string): (string | undefined)[] {
  const n = node as { type?: string; props?: { color?: string }; children?: unknown[] } | string | null
  if (!n || typeof n === 'string') return []
  const own = n.type === 'Text' && textOf(n as Node) === text ? [n.props?.color] : []
  return [...own, ...(n.children ?? []).flatMap(c => colorsOf(c, text))]
}

test('the steps are marked with a green filled circle when finished and an outlined one in the band\'s color for the current step, on both surfaces', async ($, on) => {
  const { show } = band($, on)
  for (const surface of ['terminal', 'desktop'] as const) {
    const running = await show(SCAFFOLD('creating', 1), surface)
    expect(colorsOf(running.tree, '\u25cb')).toEqual(['claude'])
    expect(colorsOf(running.tree, '\u25cf')).toEqual(['success', 'success'])
    await running.ui.unmount()
    const done = await show(SCAFFOLD('done', 5), surface)
    expect(colorsOf(done.tree, '\u25cb')).toEqual([])
    expect(colorsOf(done.tree, '\u25cf')).toEqual(['success', 'success', 'success', 'success'])
    await done.ui.unmount()
  }
})

test('only waiting on you has an icon on the first row, and it is yellow; the other phases have none', async ($, on) => {
  const { show } = band($, on)
  for (const surface of ['terminal', 'desktop'] as const) {
    for (const phase of ['resolving', 'drafting', 'waiting', 'creating', 'done'] as const) {
      const { ui, head } = await show(SCAFFOLD(phase, 2), surface)
      const icon = head.includes('\u25cf')
      expect(icon).toBe(phase === 'waiting')
      expect(head.startsWith('Scaffold \u00b7 ')).toBe(true)
      await ui.unmount()
    }
    const waiting = await show(SCAFFOLD('waiting'), surface)
    expect(colorsOf(waiting.tree?.children?.[0], '\u25cf ')).toEqual(['warning'])
    await waiting.ui.unmount()
  }
})

test('the first row ends with the time the run has gone on, dim, and has none when it is not known', async ($, on) => {
  const { show } = band($, on)
  for (const surface of ['terminal', 'desktop'] as const) {
    const known = await show(SCAFFOLD('waiting'), surface, 80, null, 235_000)
    expect(known.head).toBe('Scaffold \u00b7 \u25cf Waiting on you (3m 55s)')
    expect(colorsOf(known.tree, ' (3m 55s)')).toEqual([undefined])
    await known.ui.unmount()
    const unknown = await show(SCAFFOLD('done', 5), surface, 80, null, null)
    expect(unknown.head).toBe('Scaffold \u00b7 Done, 5 issues made')
    await unknown.ui.unmount()
  }
})

test('the first row\'s words and the steps start with a capital', async ($, on) => {
  const { show } = band($, on)
  const { ui, head, title } = await show(SCAFFOLD('drafting'), 'terminal')
  expect(head).toBe('Scaffold \u00b7 Drafting the issues')
  expect(title).toBe('\u25cf Resolve  \u25cb Draft  Create  Done')
  await ui.unmount()
})

// The Svg elements under a node, in drawing order, as their markup.
function svgsOf(node: unknown): string[] {
  const n = node as { type?: string; props?: { source?: string }; children?: unknown[] } | string | null
  if (!n || typeof n === 'string') return []
  const own = n.type === 'Svg' && n.props?.source ? [n.props.source] : []
  return [...own, ...(n.children ?? []).flatMap(svgsOf)]
}

test('on the desktop with a palette the marks are Svg circles: a ring for the current step, filled for finished ones and the waiting dot', async ($, on) => {
  const { show } = band($, on)
  const creating = await show(SCAFFOLD('creating', 3), 'desktop', 80, DARK)
  const marks = svgsOf(creating.tree)
  expect(marks).toHaveLength(3)
  expect(marks.filter(m => m.includes('fill="none"'))).toHaveLength(1)
  expect(marks.filter(m => m.includes(`fill="${DARK.done}"`))).toHaveLength(2)
  // The glyphs are not drawn beside them, and the labels are.
  expect(textOf(creating.tree as Node)).not.toMatch(/[\u25cb\u25cf]/)
  expect(textOf(creating.tree as Node)).toContain('Create')
  await creating.ui.unmount()

  const waiting = await show(SCAFFOLD('waiting'), 'desktop', 80, DARK)
  // One for the waiting dot on the first row, one for Resolve done, one for Draft current.
  expect(svgsOf(waiting.tree)).toHaveLength(3)
  expect(svgsOf(waiting.tree?.children?.[0])).toEqual([expect.stringContaining(`fill="${DARK.inProgress}"`)])
  await waiting.ui.unmount()

  const drafting = await show(SCAFFOLD('drafting'), 'desktop', 80, DARK)
  expect(svgsOf(drafting.tree?.children?.[0])).toEqual([])
  await drafting.ui.unmount()

  const done = await show(SCAFFOLD('done', 5), 'desktop', 80, DARK)
  expect(svgsOf(done.tree).filter(m => m.includes('fill="none"'))).toEqual([])
  expect(svgsOf(done.tree)).toHaveLength(4)
  await done.ui.unmount()
})

test('with no palette, and on the terminal, the marks are the glyphs, whatever the palette', async ($, on) => {
  const { show } = band($, on)
  const bare = await show(SCAFFOLD('creating', 3), 'desktop', 80, null)
  expect(svgsOf(bare.tree)).toEqual([])
  expect(bare.title).toBe('\u25cf Resolve  \u25cf Draft  \u25cb Create  Done')
  await bare.ui.unmount()
  const terminal = await show(SCAFFOLD('creating', 3), 'terminal', 80, DARK)
  expect(svgsOf(terminal.tree)).toEqual([])
  expect(terminal.title).toBe('\u25cf Resolve  \u25cf Draft  \u25cb Create  Done')
  await terminal.ui.unmount()
})

test('a scaffold draws the same two rows at 50, 80 and 100 columns', async ($, on) => {
  const { show } = band($, on)
  for (const surface of ['terminal', 'desktop'] as const) {
    for (const columns of [50, 80, 100]) {
      const { ui, head, title, tree } = await show(SCAFFOLD('creating', 4), surface, columns)
      expect(head).toBe('Scaffold · Creating, 4 issues made')
      expect(title).toBe('● Resolve  ● Draft  ○ Create  Done')
      expect(tree?.children).toHaveLength(2)
      await ui.unmount()
    }
  }
})

test('a narrow window drops the time first, then cuts the scaffold phase, instead of wrapping them', async ($, on) => {
  const { show } = band($, on)
  const tight = await show(SCAFFOLD('creating', 12), 'terminal', 40, null, 322_000)
  // 40 columns less the cell of padding is 39: the phase fits (`Scaffold · Creating, 12 issues made`
  // is 35) but the time after it does not.
  expect(tight.head).toBe('Scaffold \u00b7 Creating, 12 issues made')
  await tight.ui.unmount()
  const { ui, head, title } = await show(SCAFFOLD('creating', 12), 'terminal', 24, null, 322_000)
  expect(head.length).toBeLessThanOrEqual(24 - 1)
  expect(head.endsWith('\u2026')).toBe(true)
  expect(head.startsWith('Scaffold \u00b7 Creating')).toBe(true)
  expect(title.length).toBeGreaterThan(0)
  await ui.unmount()
})

test('terminal starting and unavailable say so in one dim line, without the brackets the desktop keeps', async ($, on) => {
  const { show } = band($, on)
  const reason = 'bd list exited 1: Error: no beads database found'

  const starting = await show({ kind: 'starting' }, 'terminal')
  expect(await starting.ui.find({ type: 'Text', text: 'fathom starting…' })).toBeDefined()
  expect(starting.tree?.props?.paddingTop).toBeUndefined()
  await starting.ui.unmount()

  const down = await show({ kind: 'unavailable', reason }, 'terminal')
  expect(await down.ui.find({ type: 'Text', text: `fathom unavailable: ${reason}` })).toBeDefined()
  await down.ui.unmount()

  const desktopStarting = await show({ kind: 'starting' }, 'desktop')
  expect(await desktopStarting.ui.find({ type: 'Text', text: '[fathom] starting…' })).toBeDefined()
  await desktopStarting.ui.unmount()

  const desktopDown = await show({ kind: 'unavailable', reason }, 'desktop')
  expect(await desktopDown.ui.find({ type: 'Text', text: /^\[fathom\] unavailable: bd list exited 1/ })).toBeDefined()
  await desktopDown.ui.unmount()
})

test('idle draws nothing, so the event passes on and beads-status can draw', async ($, on) => {
  const { show, wasNull } = band($, on)

  // With nothing beneath this mod to answer, the kit refuses to mount: the band yielded.
  await expect(show({ kind: 'idle' }, 'terminal')).rejects.toThrow(/no implementation for ui\.render/)
  expect(wasNull()).toBe(true)
})

test('a narrower terminal shortens the bar, and a row with no room for one shows the count instead', async ($, on) => {
  const { show } = band($, on)

  // 40 columns: 33 cells for the bar, of which 30 divide into five segments of six. The two
  // grey ones are one run of twelve.
  const shorter = await show(EXECUTING, 'terminal', 40)
  expect(barRuns(shorter.tree).map(r => r.text.length)).toEqual([6, 6, 6, 12])
  expect(shorter.head.endsWith('40%')).toBe(true)
  await shorter.ui.unmount()

  // 17 columns leave 11 cells, under the 12 a bar is worth.
  const narrow = await show(EXECUTING, 'terminal', 17)
  expect(narrow.head).toContain('2 of 5')
  expect(narrow.head).not.toContain('━')
  expect(narrow.head.endsWith('40%')).toBe(true)
  await narrow.ui.unmount()

  // More tasks than cells does too.
  const many: Snapshot = { kind: 'executing', ref: 'SLU-123', tasks: runOf(Array.from({ length: 80 }, () => 'waiting' as const)) }
  const crowded = await show(many, 'terminal', 80)
  expect(crowded.head).toContain('0 of 80')
  expect(crowded.head).not.toContain('━')
  await crowded.ui.unmount()
})

test('the second row is the ref and the issue\'s title, with the reviews open after it', async ($, on) => {
  const { show } = band($, on)
  const home: Snapshot = {
    kind: 'executing',
    ref: 'PHA-368',
    title: 'Home page: Restrict actions and CTAs, add video',
    tasks: runOf(['done', 'done', 'inProgress', 'waiting', 'waiting'], [1]),
  }

  const wide = await show(home, 'terminal', 100)
  expect(wide.title).toBe('●PHA-368 Home page: Restrict actions and CTAs, add video· 1 in review')
  // The label and the note are separate Texts, the note dim, and the dot keeps its color.
  expect(await wide.ui.find({ type: 'Text', text: 'PHA-368 Home page: Restrict actions and CTAs, add video' })).toBeDefined()
  expect(await wide.ui.find({ type: 'Text', text: '· 1 in review' })).toBeDefined()
  await wide.ui.unmount()

  // The desktop's band keeps its own label, with the reviews open after it as well.
  const desktop = await show(home, 'desktop', 100)
  expect(desktop.title).toBe('●PHA-368 Progress band· 1 in review')
  await desktop.ui.unmount()
})

test('a title too long for the row is cut with an ellipsis, the reviews open stay while they fit, and the ref stays whole', async ($, on) => {
  const { show } = band($, on)
  const home: Snapshot = {
    kind: 'executing',
    ref: 'PHA-368',
    title: 'Home page: Restrict actions and CTAs, add video',
    tasks: runOf(['done', 'done', 'inProgress', 'waiting', 'waiting'], [1]),
  }

  // 40 columns: a cell in, the dot and its gap, leave 37. The note takes 14 with its gap, so the label gets 23.
  const medium = await show(home, 'terminal', 40)
  expect(medium.title).toBe('●PHA-368 Home page: Res…· 1 in review')
  await medium.ui.unmount()

  // 24 columns leave 21: the ref, a gap and the note need exactly that, so the note stays and the title has no room.
  const tight = await show(home, 'terminal', 24)
  expect(tight.title).toBe('●PHA-368· 1 in review')
  await tight.ui.unmount()

  // One column less and the note cannot fit beside the ref, so it goes and the label gets the row.
  const narrow = await show(home, 'terminal', 23)
  expect(narrow.title).toBe('●PHA-368 Home page:…')
  expect(narrow.title).not.toContain('review')
  await narrow.ui.unmount()

  // Without a note a long title still fits the row.
  const plain: Snapshot = { ...home, tasks: runOf(['done', 'done', 'inProgress', 'waiting', 'waiting']) }
  const noReviews = await show(plain, 'terminal', 40)
  expect(noReviews.title).toBe('●PHA-368 Home page: Restrict actions…')
  await noReviews.ui.unmount()
})

// Whether any Box under a node sets `prop`: the head row is laid out by what its parts
// measure, so the percent follows the bar and is not pushed to the end of the row.
function anyBoxSets(node: unknown, prop: string): boolean {
  const n = node as { type?: string; props?: Record<string, unknown>; children?: unknown[] } | string | null | undefined
  if (!n || typeof n === 'string') return false
  return (n.type === 'Box' && n.props?.[prop] !== undefined) || (n.children ?? []).some(child => anyBoxSets(child, prop))
}

test('a wide window stretches the bar to fill it, and the percent stays with the bar', async ($, on) => {
  const { show } = band($, on)

  // 150 columns leave 144 cells, of which 140 divide into five segments of 28. The two grey
  // ones are one run of 56. There is no limit: 200 columns give segments of 38.
  const wide = await show(EXECUTING, 'terminal', 150)
  expect(barRuns(wide.tree).map(r => r.text.length)).toEqual([28, 28, 28, 56])
  expect(wide.head.endsWith('40%')).toBe(true)
  // Nothing in the row grows or aligns to push the percent to the end.
  expect(anyBoxSets(wide.tree, 'flexGrow')).toBe(false)
  expect(anyBoxSets(wide.tree, 'justifyContent')).toBe(false)
  await wide.ui.unmount()

  const wider = await show(EXECUTING, 'terminal', 200)
  expect(barRuns(wider.tree).map(r => r.text.length)).toEqual([38, 38, 38, 76])
  await wider.ui.unmount()
})

test('the line beneath is cut to the row, a cell in from the left', async ($, on) => {
  const { show } = band($, on)
  const { ui, line } = await show(EXECUTING, 'terminal', 24)

  // 24 columns less the cell of padding: the lead, then the title cut with an ellipsis.
  expect(line).toHaveLength(23)
  expect(line.startsWith('▸ now 3/5  Wire')).toBe(true)
  expect(line.endsWith('…')).toBe(true)
  await ui.unmount()
})

test('nine tasks, the over-seven case, still draw a bar with every task in it', async ($, on) => {
  const { show } = band($, on)
  const nine: Snapshot = {
    kind: 'executing',
    ref: 'SLU-123',
    tasks: runOf(['done', 'done', 'done', 'inProgress', 'waiting', 'waiting', 'waiting', 'waiting', 'waiting']),
  }
  // 74 cells, of which 72 divide into nine segments of eight, with eight half lines between them.
  // The three done are one run, the one in progress is a run, and the five waiting are a run.
  const terminal = await show(nine, 'terminal')
  expect(barRuns(terminal.tree).map(r => [r.color, r.text.length])).toEqual([['success', 24], ['warning', 8], ['subtle', 40]])
  expect([...terminal.head].filter(c => c === '━' || c === '╸')).toHaveLength(72)
  expect([...terminal.head].filter(c => c === '╸')).toHaveLength(8)
  expect(terminal.head.endsWith('33%')).toBe(true)
  expect(terminal.line).toContain('now 4/9')
  await terminal.ui.unmount()

  // On the desktop the bar has a row of its own with the percent, so the theme-following
  // boxes are seven cells each: every task has its own box and icon, and the last has room
  // for the step text.
  const desktop = await show(nine, 'desktop')
  expect(filledBoxes(desktop.tree)).toHaveLength(9)
  expect(new Set(filledBoxes(desktop.tree).map(b => b.width))).toEqual(new Set([7]))
  expect([...desktop.head].filter(c => c === '✓')).toHaveLength(3)
  expect(desktop.head).toContain('3 of 9')
  expect(desktop.head).not.toContain('━')
  expect(desktop.line).toContain('now 4/9')
  await desktop.ui.unmount()
})

test('desktop planned, executing and done draw three rows: the bar with its percent, the label with the reviews open, and the line beneath', async ($, on) => {
  const { show } = band($, on)

  const planned = await show(PLANNED, 'desktop')
  expect(planned.head).toContain('0 of 5')
  expect(planned.head.endsWith('  0%')).toBe(true)
  expect(planned.title).toBe('●SLU-123 Progress band')
  expect(planned.line).toBe('next 1/5  Draft the plan doc')
  await planned.ui.unmount()

  const executing = await show(EXECUTING, 'desktop')
  expect(executing.head).toContain('2 of 5')
  expect(executing.head).toContain('◐')
  expect(executing.head).toContain('●')
  expect(executing.head.endsWith(' 40%')).toBe(true)
  expect(executing.title).toBe('●SLU-123 Progress band· 1 in review')
  expect(executing.line).toBe('now 3/5  Wire the lifecycle hooks')
  await executing.ui.unmount()

  const done = await show(DONE, 'desktop')
  expect(done.head).toContain('5 of 5')
  expect(done.head.endsWith('100%')).toBe(true)
  expect(done.title).toBe('●SLU-123 Progress band')
  expect(done.line).toBe('✓ 5/5 done')
  await done.ui.unmount()
})

test('on the desktop, with a palette for the theme, the bar is one Svg of thin segments, and the step text is not drawn beside it', async ($, on) => {
  const { show } = band($, on)
  const { ui, head, title, line, tree } = await show(EXECUTING, 'desktop', 80, DARK)

  const svg = (await ui.find({ type: 'Svg' })) as unknown as { props?: { alt?: string; width?: number; height?: number; source?: string } } | undefined
  expect(svg).toBeDefined()
  expect(svg?.props?.alt).toBe('2 of 5 tasks done, 1 in review, task 3 in progress')
  // 80 cells at 7.9px, less the percent's box and the 12px before it, leaves a bar of 580;
  // the Svg's own box carries those 12px after it.
  expect([svg?.props?.width, svg?.props?.height]).toEqual([592, 6])
  expect(svg?.props?.source).toContain('viewBox="0 0 592 6"')
  // A segment for each of the five tasks, the last ending where the bar does, and no count
  // drawn inside the bar.
  expect(svg?.props?.source?.match(/class="segment"/g)).toHaveLength(5)
  const last = [...(svg?.props?.source ?? '').matchAll(/class="segment" x="([\d.]+)" width="([\d.]+)"/g)].at(-1)
  expect(Math.abs(Number(last?.[1]) + Number(last?.[2]) - 580)).toBeLessThan(0.05)
  expect(svg?.props?.source).not.toContain('<text')
  // The thin bar sits in the middle of the percent's line.
  const headRow = tree?.children?.[0] as { props?: Record<string, unknown> } | undefined
  expect(headRow?.props?.alignItems).toBe('center')
  // The percent, label and line stay Text, so they follow the theme; the bar row holds only the percent.
  expect(head).toBe(' 40%')
  expect(title).toBe('●SLU-123 Progress band· 1 in review')
  expect(head).not.toContain('━')
  expect(line).toBe('now 3/5  Wire the lifecycle hooks')
  await ui.unmount()
})

test('on the desktop with no palette for the theme the bar is boxes in the theme\'s colors, never block characters; the terminal keeps its thin bar', async ($, on) => {
  const { show } = band($, on)

  const unknownTheme = await show(EXECUTING, 'desktop', 80, null)
  expect(await unknownTheme.ui.find({ type: 'Svg' })).toBeUndefined()
  // One box per task: done, done with a review open, in progress, and two waiting.
  const boxes = filledBoxes(unknownTheme.tree)
  expect(boxes.map(b => b.color)).toEqual(['success', 'claude', 'warning', 'subtle', 'subtle'])
  expect(new Set(boxes.map(b => b.width)).size).toBe(1)
  expect(unknownTheme.head).toContain('2 of 5')
  expect(unknownTheme.head).not.toContain('━')
  await unknownTheme.ui.unmount()

  // A palette is for the desktop's Svg; the terminal ignores it and draws no filled box.
  const terminal = await show(EXECUTING, 'terminal', 80, DARK)
  expect(terminal.head).toContain('━')
  expect(terminal.head).not.toContain('of')
  expect(filledBoxes(terminal.tree)).toHaveLength(0)
  await terminal.ui.unmount()
})

test('the desktop Svg bar draws for planned and finished runs too, and while the tasks are made it is one waiting segment for each', async ($, on) => {
  const { show } = band($, on)

  for (const snapshot of [PLANNED, DONE]) {
    const { ui } = await show(snapshot, 'desktop', 80, DARK)
    expect(await ui.find({ type: 'Svg' })).toBeDefined()
    await ui.unmount()
  }
  const creating = await show({ kind: 'creating', ref: 'SLU-123', created: 3 }, 'desktop', 80, DARK)
  const svg = (await creating.ui.find({ type: 'Svg' })) as unknown as { props?: { alt?: string; width?: number; source?: string } } | undefined
  expect(svg?.props?.alt).toBe('3 tasks made so far')
  // The three made share the whole bar the row leaves, as the design's Creating frame does:
  // 580 and the 12px after it.
  expect(svg?.props?.width).toBe(592)
  expect(svg?.props?.source?.match(/class="segment"/g)).toHaveLength(3)
  expect(svg?.props?.source).not.toContain('<text')
  expect(creating.head).not.toContain('━')
  await creating.ui.unmount()

  // With no palette for the theme it is three blank boxes in the theme's grey, not blocks.
  const plain = await show({ kind: 'creating', ref: 'SLU-123', created: 3 }, 'desktop', 80, null)
  expect(await plain.ui.find({ type: 'Svg' })).toBeUndefined()
  expect(filledBoxes(plain.tree).map(b => [b.color, b.width])).toEqual([['subtle', 4], ['subtle', 4], ['subtle', 4]])
  expect(plain.head).not.toContain('━')
  await plain.ui.unmount()
})
