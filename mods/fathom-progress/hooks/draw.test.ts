import { test, expect } from 'claude-code/testing'

import type { RunTask, TaskState } from '../types'
import { allocate } from './bar'
import { barCells, barWidth, desktopSegments, equalWidth, growingCells, growingSegments, lineText, lookOf, stepText, titleParts, toSpans } from './draw'
import type { Cell } from './draw'

const task = (state: TaskState, isInReview = false): RunTask => ({
  id: state,
  ref: null,
  title: `${state} task`,
  state,
  isInReview,
})

const chars = (cells: readonly Cell[]) => cells.map(c => c.char).join('')
const five = (state: TaskState) => Array.from({ length: 5 }, () => task(state))

// A segment of n cells: heavy lines, and the last a heavy half line when another segment
// follows. The widths of the segments in a bar's text, read from where the half lines fall.
const seg = (n: number, hasNext = true) => '━'.repeat(hasNext ? n - 1 : n) + (hasNext ? '╸' : '')
const widthsOf = (text: string) => text.split('╸').map((part, i, parts) => part.length + (i < parts.length - 1 ? 1 : 0))

// These draw a bar 55 cells wide, the room a window 61 columns wide leaves. Five tasks
// divide it into segments of eleven, and there is no blank cell between them: each segment
// but the last ends in a half line.

test('planned: five equal grey segments, each but the last ending in a half line, and nothing written in them', async () => {
  const cells = barCells([task('next'), task('waiting'), task('waiting'), task('waiting'), task('waiting')], 55)

  expect(chars(cells)).toBe(seg(11).repeat(4) + seg(11, false))
  expect(cells).toHaveLength(55)
  expect(new Set(cells.map(c => c.color))).toEqual(new Set(['subtle']))
})

test('executing: each segment is its state\'s color, and its closing half line is the same color', async () => {
  const cells = barCells([task('done'), task('done', true), task('inProgress'), task('waiting'), task('waiting')], 55)
  const colorAt = (i: number) => cells[i]?.color

  expect([0, 11, 22, 33, 44].map(colorAt)).toEqual(['success', 'claude', 'warning', 'subtle', 'subtle'])
  // The half line that closes a segment is that segment's, not the next one's.
  for (const [edge, color] of [[10, 'success'], [21, 'claude'], [32, 'warning'], [43, 'subtle']] as const) {
    expect(cells[edge]).toEqual({ char: '╸', color })
  }
})

test('finished: every segment is the done green', async () => {
  const cells = barCells(five('done'), 55)

  expect(chars(cells)).toBe(seg(11).repeat(4) + seg(11, false))
  expect(new Set(cells.map(c => c.color))).toEqual(new Set(['success']))
})

test('a segment is a color and nothing else: no icon, no step text, no fill behind it, no blank cell', async () => {
  const cells = barCells([task('done'), task('done', true), task('inProgress'), task('waiting'), task('waiting')], 55)

  expect(new Set(chars(cells))).toEqual(new Set(['━', '╸']))
  for (const c of cells) {
    expect(Object.keys(c).sort()).toEqual(['char', 'color'])
  }
})

test('stepText says how many are closed out of how many', async () => {
  expect(stepText(0, 5)).toBe('0 of 5')
  expect(stepText(12, 12)).toBe('12 of 12')
})

test('done, in review, in progress and not started each have a color of their own, and next and waiting are the same plain dark grey', async () => {
  const color = (state: TaskState, isInReview = false) => barCells([task(state, isInReview)], 8)[0]?.color

  expect(color('waiting')).toBe('subtle')
  expect(color('next')).toBe('subtle')
  expect(color('inProgress')).toBe('warning')
  expect(color('done')).toBe('success')
  expect(color('done', true)).toBe('claude')

  // The desktop's segments still carry a mark for each, so the states do not rest on color alone there.
  const marked = [lookOf(task('inProgress')), lookOf(task('done')), lookOf(task('done', true))].map(l => l.icon)
  expect(new Set(marked).size).toBe(3)
  expect(lookOf(task('waiting')).icon).toBe('')
  expect(lookOf(task('next')).icon).toBe('')
})

test('segments are as equal as whole cells allow, for any number of tasks including more than seven', async () => {
  for (const count of [1, 2, 3, 7, 8, 9, 12]) {
    const tasks = Array.from({ length: count }, () => task('waiting'))
    const widths = allocate(tasks.map(() => 1), 48)

    expect(widths).toHaveLength(count)
    expect(widths.reduce((sum, w) => sum + w, 0)).toBe(48)
    expect(Math.max(...widths) - Math.min(...widths)).toBeLessThanOrEqual(1)

    // Every drawn segment is the same width, read from where the half lines fall.
    const drawn = widthsOf(chars(barCells(tasks, 55)))
    expect(drawn).toHaveLength(count)
    expect(new Set(drawn).size).toBe(1)
    expect(drawn[0]).toBeGreaterThanOrEqual(1)
  }
})

test('a bar of n tasks has n - 1 half lines in it, one closing each segment but the last', async () => {
  const text = chars(barCells(five('waiting'), 55))

  expect([...text].filter(c => c === '╸')).toHaveLength(4)
  expect(text.endsWith('━')).toBe(true)
})

test('with no cell for every task, there is no bar', async () => {
  expect(barCells([], 55)).toEqual([])
  // Sixty tasks need sixty cells.
  expect(barCells(Array.from({ length: 60 }, () => task('done')), 55)).toEqual([])
  expect(barCells(five('done'), 4)).toEqual([])
  // A cell each is the least: four half lines and the last segment's line.
  expect(chars(barCells(five('done'), 5))).toBe('╸╸╸╸━')
  // A lone task has no gap to leave.
  expect(chars(barCells([task('done')], 8))).toBe('━'.repeat(8))
})

test('while the run is made, each task made fills one of five equal slots and the rest of the bar is left out', async () => {
  expect(growingCells(0, 55)).toEqual([])
  // The slot just made has no half line yet: another may follow, and then it closes.
  expect(chars(growingCells(3, 55))).toBe(seg(11) + seg(11) + seg(11, false))
  expect(chars(growingCells(1, 55))).toBe(seg(11, false))
  // More tasks than slots leave the bar full, and the line beneath counts them.
  expect(chars(growingCells(99, 55))).toBe(seg(11).repeat(4) + seg(11, false))
  expect(new Set(growingCells(3, 55).map(c => c.color))).toEqual(new Set(['subtle']))
  // Five slots need five cells.
  expect(growingCells(3, 4)).toEqual([])
})

test('toSpans folds runs of one color into one span, so the bar is a handful of elements', async () => {
  const cells = barCells([task('done'), task('done', true), task('inProgress'), task('waiting'), task('waiting')], 55)
  const spans = toSpans(cells)

  expect(spans.map(s => s.text).join('')).toBe(chars(cells))
  // Two segments of the same color are one span: there is no blank cell between them.
  expect(spans.map(s => [s.color, s.text.length])).toEqual([['success', 11], ['claude', 11], ['warning', 11], ['subtle', 22]])
  for (let i = 1; i < spans.length; i++) {
    expect(spans[i - 1]?.color === spans[i]?.color).toBe(false)
  }
})

test('the bar takes what the row leaves after the left padding, the gap and the percent, with no upper limit', async () => {
  expect(barWidth(61)).toBe(55)
  expect(barWidth(80)).toBe(74)
  expect(barWidth(100)).toBe(94)
  expect(barWidth(200)).toBe(194)
  expect(barWidth(30)).toBe(24)
  expect(barWidth(6)).toBe(0)
})

test('a bar that fills a wide row is still equal segments, and the cells the division leaves over stay off its end', async () => {
  // 194 cells for five tasks: 190 divide evenly, so the bar is four short of the row.
  const cells = barCells(five('waiting'), barWidth(200))

  expect(cells).toHaveLength(190)
  expect(widthsOf(chars(cells))).toEqual([38, 38, 38, 38, 38])
})

test('lineText joins the lead, the title and the note with two spaces', async () => {
  expect(lineText('▸ now 3/5', 'Wire the lifecycle hooks', '· 2 in review', 78)).toBe('▸ now 3/5  Wire the lifecycle hooks  · 2 in review')
  expect(lineText('▸ now 3/5', 'Wire the lifecycle hooks', '', 78)).toBe('▸ now 3/5  Wire the lifecycle hooks')
  expect(lineText('▸ planning', '', '', 78)).toBe('▸ planning')
})

test('lineText cuts the title with an ellipsis to keep the note, and drops the note only when it cannot fit beside the lead', async () => {
  // 40 columns: lead 9, note 13, two gaps of 2 leave 40 - 9 - 2 - 2 - 13 = 14 for the title.
  expect(lineText('▸ now 3/5', 'Wire the lifecycle hooks', '· 2 in review', 40)).toBe('▸ now 3/5  Wire the life…  · 2 in review')
  expect(lineText('▸ now 3/5', 'Wire the lifecycle hooks', '· 2 in review', 40)).toHaveLength(40)
  // 24 columns hold the lead, a gap and the note exactly, with no room left for the title.
  expect(lineText('▸ now 3/5', 'Wire the lifecycle hooks', '· 2 in review', 24)).toBe('▸ now 3/5  · 2 in review')
  // One column less and the note cannot fit with the lead, so it goes and the title keeps the room.
  expect(lineText('▸ now 3/5', 'Wire the lifecycle hooks', '· 2 in review', 23)).toBe('▸ now 3/5  Wire the li…')
})

test('equalWidth trims the bar to a multiple of the task count, so every segment is the same width', async () => {
  expect(equalWidth(48, 5)).toBe(45)
  expect(equalWidth(48, 7)).toBe(42)
  expect(equalWidth(48, 9)).toBe(45)
  expect(equalWidth(48, 4)).toBe(48)
  expect(equalWidth(48, 1)).toBe(48)
  // Fewer cells than tasks leaves no bar, and no tasks has none to size.
  expect(equalWidth(7, 12)).toBe(0)
  expect(equalWidth(48, 0)).toBe(0)

  for (const count of [2, 3, 5, 6, 7, 9, 11]) {
    const widths = allocate(Array.from({ length: count }, () => 1), equalWidth(48, count))
    expect(new Set(widths).size).toBe(1)
  }
})

test('desktop segments: equal widths with a one-cell gap across the room, in the colors and icons of each state', async () => {
  const tasks = [task('done'), task('done', true), task('inProgress'), task('waiting'), task('waiting')]
  const segments = desktopSegments(tasks, 52)

  // 52 cells less four gaps leaves 48, which five tasks share as 9 each.
  expect(segments.map(s => s.width)).toEqual([9, 9, 9, 9, 9])
  expect(segments.map(s => s.color)).toEqual(['success', 'claude', 'warning', 'subtle', 'subtle'])
  expect(segments.map(s => s.icon)).toEqual(['✓', '◐', '●', '', ''])
  // The step text is in the last, which is waiting: plain text on the grey, and no icon to drop.
  expect(segments.map(s => s.step)).toEqual(['', '', '', '', '2 of 5'])
  expect(segments[4]).toMatchObject({ color: 'subtle', textColor: 'text' })
  expect(segments[0]).toMatchObject({ textColor: 'inverseText' })
})

test('desktop segments: the last keeps its icon only while the icon and the step text fit together, then the step text alone, then neither', async () => {
  const done = (count: number) => Array.from({ length: count }, () => task('done'))
  const last = (room: number) => desktopSegments(done(5), room).at(-1)

  // Five tasks: widths of 9, 8, 6, 5 cells come from rooms of 49, 44, 34, 29.
  expect(last(49)).toMatchObject({ width: 9, icon: '✓', step: '5 of 5' })
  expect(last(44)).toMatchObject({ width: 8, icon: '', step: '5 of 5' })
  expect(last(34)).toMatchObject({ width: 6, icon: '', step: '5 of 5' })
  expect(last(29)).toMatchObject({ width: 5, icon: '✓', step: '' })
  // Three cells is the least that marks a task; below that there are no segments, and the row shows the count instead.
  expect(desktopSegments(done(5), 19).map(s => s.width)).toEqual([3, 3, 3, 3, 3])
  expect(desktopSegments(done(5), 18)).toEqual([])
  expect(desktopSegments([], 52)).toEqual([])
})

test('desktop growing pieces: one for each task made, four cells each, as many as the room holds, and at least one', async () => {
  expect(growingSegments(0, 52).map(s => s.width)).toEqual([4])
  expect(growingSegments(3, 52).map(s => [s.width, s.color])).toEqual([[4, 'subtle'], [4, 'subtle'], [4, 'subtle']])
  // 52 cells hold ten pieces of 4 with a gap of 1 between.
  expect(growingSegments(99, 52)).toHaveLength(10)
  expect(growingSegments(2, 3)).toHaveLength(1)
})

test('titleParts joins the ref and the title, or gives the ref alone when the plan names no title', async () => {
  expect(titleParts('PHA-368', 'Home page: Restrict actions and CTAs, add video', '', 80)).toEqual({
    label: 'PHA-368 Home page: Restrict actions and CTAs, add video',
    note: '',
  })
  expect(titleParts('PHA-368', '', '', 80)).toEqual({ label: 'PHA-368', note: '' })
  expect(titleParts('PHA-368', '', '· 2 in review', 80)).toEqual({ label: 'PHA-368', note: '· 2 in review' })
})

test('titleParts cuts the title with an ellipsis to keep the note, and drops the note only when it cannot fit beside the ref', async () => {
  const title = 'Home page: Restrict actions and CTAs, add video'
  const note = '· 2 in review'

  // 36 columns: the note and its gap take 14, leaving 22 for the label.
  expect(titleParts('PHA-368', title, note, 36)).toEqual({ label: 'PHA-368 Home page: Re…', note })
  expect(titleParts('PHA-368', title, note, 36).label).toHaveLength(22)
  // 21 columns hold the ref, a gap and the note exactly: the note stays, and the title has no room, so the ref is alone.
  expect(titleParts('PHA-368', title, note, 21)).toEqual({ label: 'PHA-368', note })
  // One column less and the note cannot fit beside the ref, so it goes and the label gets the row.
  expect(titleParts('PHA-368', title, note, 20)).toEqual({ label: 'PHA-368 Home page:…', note: '' })
  // The cut never leaves a space before the ellipsis.
  expect(titleParts('PHA-368', 'Home page restrict', '', 14).label).toBe('PHA-368 Home…')
})

test('titleParts keeps the ref whole while it can, then cuts it, and shows nothing when there is no room at all', async () => {
  const title = 'Home page: Restrict actions and CTAs, add video'

  // Under three characters of title are not worth showing beside the ref.
  expect(titleParts('PHA-368', title, '', 9).label).toBe('PHA-368')
  expect(titleParts('PHA-368', title, '', 10).label).toBe('PHA-368 H…')
  expect(titleParts('PHA-368', title, '', 7).label).toBe('PHA-368')
  expect(titleParts('PHA-368', title, '', 5).label).toBe('PHA-…')
  expect(titleParts('PHA-368', title, '', 1).label).toBe('')
  expect(titleParts('PHA-368', title, '', 0).label).toBe('')
})
