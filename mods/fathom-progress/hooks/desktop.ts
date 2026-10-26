import type { RunTask } from '../types'
import { progressOf } from './state'

// The desktop app's bar: the segments of the design's `Desktop` section (Figma 79:1402), one
// thin rounded segment for each task, drawn as one Svg. The terminal's cells cannot round a
// corner, and Box has no radius, so the desktop bar is an image.
//
// An Svg is drawn as an image (the engine's types say so), so it cannot use theme keys,
// CSS variables or the page's fonts: its colors are literal. They come in as a `Palette`
// and nothing below names a color. The only palette here is the Claude Code dark theme's,
// from the Figma "Claude Code theme" collection (Dark), so the Svg is used only when the
// person's theme is `dark`; any other theme gets the cell bar, which follows it.
export type Palette = {
  // A task waiting behind the one before it.
  waiting: string
  // The one task `bd ready` offers next.
  next: string
  inProgress: string
  // A task that is done and whose review is open.
  review: string
  done: string
  // The band's own color: the ring marking the current step of a scaffold run.
  claude: string
}

// Values from the Figma collection, checked against what a terminal rendered for the dark
// theme: success #4CBA64, claude #D67855 and subtle #505050 there, within two of these.
// In progress is the collection's `warning` and next its `inactive`; a terminal render of
// either was not checked.
export const DARK: Palette = {
  waiting: '#505050',
  next: '#999999',
  inProgress: '#FFC107',
  review: '#D77757',
  done: '#4EBA65',
  claude: '#D77757',
}

// The palette for the person's theme, or null for a theme this has no colors for. The
// value is what the `theme` row of `/config` holds.
export function paletteFor(theme: string | null): Palette | null {
  return theme === 'dark' ? DARK : null
}

// The design's bar: segments 6px tall with corners half that, 3px apart. 420 is the width
// when none is asked for; the band asks for the room the row has, below.
export const BAR_WIDTH = 420
export const BAR_HEIGHT = 6
const SEGMENT_GAP = 3

// An Svg is sized in CSS pixels and a band is laid out in cells, so this is the one bridge
// between them. Measured in the app with a strip `bodyColumns` cells wide: 95 cells filled a
// 752px card, and its first ten cells were 79px, so a cell is 7.9px. It holds at the app's
// default font size.
export const CELL_PX = 7.9
// The percent's box on the desktop, in cells: `100%` in bold takes 33px of its 39.5.
export const PERCENT_CELLS = 5
// The design puts 12px between the bar and the percent. A Box can only gap in whole cells
// (7.9px), so the Svg carries the space itself: see `trail` below.
export const PERCENT_GAP_PX = 12
const MIN_BAR_WIDTH = 120
const MAX_BAR_WIDTH = 1200

// The width of the bar that fills its row after the percent and the space before it, in
// CSS pixels. The bar has a row of its own, so the dot and the label take none of it. A few
// pixels are left over at the end, never a row too wide.
export function desktopBarWidth(bodyColumns: number): number {
  const room = bodyColumns * CELL_PX - PERCENT_CELLS * CELL_PX - PERCENT_GAP_PX
  return Math.max(MIN_BAR_WIDTH, Math.min(MAX_BAR_WIDTH, Math.floor(Math.round(room * 100) / 100)))
}

// Numbers in the markup, to two places.
const n = (value: number) => String(Math.round(value * 100) / 100)

function fillOf(task: RunTask, palette: Palette): string {
  if (task.state === 'done') return task.isInReview ? palette.review : palette.done
  if (task.state === 'inProgress') return palette.inProgress
  return task.state === 'next' ? palette.next : palette.waiting
}

// The space between two segments: the design's 3px, or less when so many tasks share the
// width that the gaps would take all of it.
function gapOf(width: number, count: number): number {
  return count > 1 ? Math.min(SEGMENT_GAP, width / count / 4) : 0
}

// What Svg takes: the markup, the alt text it requires, and its size in CSS pixels. Every
// task is a segment of its state's color, and nothing else is drawn: the design's bar has
// no ticks, pill or count. The segments are equal widths until Fathom records sizes, as in
// the terminal bar; the one line to change then is where `seg` is worked out. A segment
// narrower than its height gets a corner that fits, since Svg limits `rx` to half the width.
//
// `width` is the bar's. `trail` is empty space after it that the Svg's own size includes,
// so the returned width is `width + trail`.
export function barSvg(
  tasks: readonly RunTask[],
  { palette, width = BAR_WIDTH, trail = 0, alt: altText }: { palette: Palette; width?: number; trail?: number; alt?: string },
): { source: string; alt: string; width: number; height: number } {
  const count = tasks.length
  const gap = gapOf(width, count)
  const seg = count > 0 ? (width - gap * (count - 1)) / count : 0
  const { done, total } = progressOf(tasks)
  const reviews = tasks.filter(t => t.isInReview).length
  const running = tasks.findIndex(t => t.state === 'inProgress')

  const out: string[] = []
  const boxWidth = width + trail
  out.push(`<svg xmlns="http://www.w3.org/2000/svg" width="${n(boxWidth)}" height="${BAR_HEIGHT}" viewBox="0 0 ${n(boxWidth)} ${BAR_HEIGHT}">`)
  tasks.forEach((task, i) => {
    out.push(
      `<rect class="segment" x="${n(i * (seg + gap))}" width="${n(seg)}" height="${BAR_HEIGHT}" rx="${BAR_HEIGHT / 2}" fill="${fillOf(task, palette)}"/>`,
    )
  })
  out.push('</svg>')

  const alt =
    altText ??
    `${done} of ${total} tasks done` +
      (reviews > 0 ? `, ${reviews} in review` : '') +
      (running !== -1 ? `, task ${running + 1} in progress` : '')
  return { source: out.join(''), alt, width: boxWidth, height: BAR_HEIGHT }
}

// The bar while the run's tasks are made: one waiting segment for each task made so far,
// sharing the whole width, as the design's Creating frame draws it. There is no total yet,
// so the segments re-divide as each task is made; with none made the bar is empty.
export function growingSvg(made: number, { palette, width, trail }: { palette: Palette; width: number; trail?: number }) {
  const tasks: RunTask[] = Array.from({ length: Math.max(0, made) }, (_, i) => ({ id: `made-${i}`, ref: null, title: '', state: 'waiting', isInReview: false }))
  const alt = made === 0 ? 'no tasks made yet' : `${made} task${made === 1 ? '' : 's'} made so far`
  return barSvg(tasks, { palette, width, trail, alt })
}

// The scaffold band's marks, as the design draws them: a circle 9px across. The current step
// is a ring, 2px thick inside the 9px, in the band's color; a finished step and the waiting
// dot are the same circle filled. A terminal cell cannot draw a ring, so the terminal uses
// `○` and `●`; this is the desktop's.
export const MARK_PX = 9
const MARK_STROKE = 2

export type Mark = 'done' | 'current' | 'waiting'

const MARK_ALT: Record<Mark, string> = { done: 'done', current: 'current step', waiting: 'waiting on you' }

export function markSvg(mark: Mark, { palette }: { palette: Palette }): { source: string; alt: string; width: number; height: number } {
  const half = MARK_PX / 2
  const circle =
    mark === 'current'
      ? `<circle cx="${half}" cy="${half}" r="${half - MARK_STROKE / 2}" fill="none" stroke="${palette.claude}" stroke-width="${MARK_STROKE}"/>`
      : `<circle cx="${half}" cy="${half}" r="${half}" fill="${mark === 'done' ? palette.done : palette.inProgress}"/>`
  const source = `<svg xmlns="http://www.w3.org/2000/svg" width="${MARK_PX}" height="${MARK_PX}" viewBox="0 0 ${MARK_PX} ${MARK_PX}">${circle}</svg>`
  return { source, alt: MARK_ALT[mark], width: MARK_PX, height: MARK_PX }
}
