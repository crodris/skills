export const MAX_BAR_CELLS = 48

// Splits `cells` across `values` in proportion (largest remainder), giving every
// nonzero value at least one cell. Needs cells >= the number of nonzero values.
export function allocate(values: number[], cells: number): number[] {
  const total = values.reduce((sum, v) => sum + v, 0)
  const exact = values.map(v => (v / total) * cells)
  const widths = values.map((v, i) => (v > 0 ? Math.max(1, Math.floor(exact[i] ?? 0)) : 0))
  let left = cells - widths.reduce((sum, w) => sum + w, 0)

  // The share of a cell a value is still owed.
  const owed = (i: number) => (exact[i] ?? 0) - (widths[i] ?? 0)

  while (left > 0) {
    let pick = -1
    values.forEach((v, i) => {
      if (v > 0 && (pick === -1 || owed(i) > owed(pick))) pick = i
    })
    widths[pick] = (widths[pick] ?? 0) + 1
    left -= 1
  }
  while (left < 0) {
    let pick = 0
    widths.forEach((w, i) => {
      if (w > (widths[pick] ?? 0)) pick = i
    })
    widths[pick] = (widths[pick] ?? 0) - 1
    left += 1
  }
  return widths
}

export function centered(text: string, width: number): string {
  const shown = text.length <= width ? text : ''
  const before = Math.floor((width - shown.length) / 2)
  return ' '.repeat(before) + shown + ' '.repeat(width - shown.length - before)
}
