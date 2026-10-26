# UI review

These steps add to `SKILL.md` on a visual PR.
Run the sections from Builds through Capture after stage 4 of `SKILL.md` and before stage 5.
Hosting feeds stage 8, and the before/after table goes in the stage 9 summary.

## Cost discipline

A two-file UI PR takes about five minutes.
Past ten, count your build, serve, and browser-launch cycles, since they cost the time and the measuring does not.

**Build once per side, serve both, and keep them warm.**
Leave the PR and base previews running for the whole review.
Rebuild only after source changes on disk, which stage 5 of `SKILL.md` does, and re-assert build identity after each rebuild.

**One browser session, one measurement script.**
Run every viewport, both themes, geometry, contrast, and hit-testing through one pass that returns one structured object.
Drive the page directly instead of writing a throwaway spec file to read a few values, since each spec costs a whole build-and-serve cycle.

## Builds

Add a worktree at the merge-base next to the PR worktree from stage 2:

```bash
BASE_WT=$(mktemp -d "${TMPDIR:-/tmp}/review-wt-base.XXXXXX")
git worktree add "$BASE_WT" "$MB"
```

The base worktree serves the A/B and the before half of every screenshot pair, since stage 5 rebuilds the PR worktree.
Set up its env file, dependencies, and verified-free port the same way stage 2 sets up the PR worktree.

## Serve and verify the build's identity

Anything that rebuilds can leave build output from the wrong source, and restarting a preview server does not rebuild.
After every rebuild, and before believing any screenshot, assert the served build's identity with a computed value only the PR could produce:

```js
const PROBE_SELECTOR = '<selector>'   // an element this PR restyles
const PROBE_PROPERTY = '<property>'   // a computed property this PR changes
const probe = document.querySelector(PROBE_SELECTOR)
if (!probe) throw new Error('no match for ' + PROBE_SELECTOR)
getComputedStyle(probe)[PROBE_PROPERTY]   // differs between the PR build and the base build
```

If the answer is the base value, you are on the wrong build.
Rebuild, then check again.

## Visual pass

Check narrow (390), standard (1440), and at least one wide viewport (1600, 2200+).
Wide viewports expose measure and alignment bugs that never appear at 1440.

Then switch themes and repeat, since dark mode inverts the logic of elevation:

- a shadow tuned for a light page contributes far less on a dark one
- a borderless card's edge may come down to a background step of about 1.1:1
- a change justified by light-mode parity can erase an edge in dark

Measure the painted result before concluding anything from the stylesheet.

## Measure

Read geometry, computed styles, and contrast directly from the running page.
Collect everything in one pass over the running preview, across all viewports, both themes, and every element:

```js
const measure = (selector) => {
  const lum = (rgb) => {
    const [r, g, b] = rgb.map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) })
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }
  // Computed colours serialize as rgb() or rgba(); anything else, such as oklch() or color(), is not sRGB, so it gives no contrast.
  const parse = (s) => {
    if (!/^rgba?\(/.test(s)) return null
    const n = s.match(/[\d.]+%?/g) || []
    if (n.length < 3 || n.slice(0, 3).some(v => v.endsWith('%'))) return null
    const a = n[3] === undefined ? 1 : n[3].endsWith('%') ? parseFloat(n[3]) / 100 : Number(n[3])
    return { rgb: n.slice(0, 3).map(Number), a }
  }
  // The surface the text sits on: walk up until something opaque paints.
  const surfaceOf = (el) => {
    for (let e = el; e; e = e.parentElement) {
      if (Number(getComputedStyle(e).opacity) < 1) return null   // translucent layer anywhere above: sample pixels instead
    }
    for (let e = el; e; e = e.parentElement) {
      const style = getComputedStyle(e)
      if (style.backgroundImage !== 'none') return null
      const c = parse(style.backgroundColor)
      if (c && c.a === 1) return c.rgb
      if (c && c.a > 0) return null                     // composited: sample pixels instead
    }
    return null
  }
  // Compare contrast, never lightness, which inverts between themes.
  const ratio = (fgStr, bgRgb) => {
    const fg = parse(fgStr)
    if (!fg || !bgRgb) return null
    if (fg.a < 1) return null                           // translucent text: sample pixels instead
    const [hi, lo] = [lum(fg.rgb), lum(bgRgb)].sort((a, b) => b - a)
    return +((hi + 0.05) / (lo + 0.05)).toFixed(2)
  }
  const el = document.querySelector(selector)
  if (!el) return { error: 'no match for ' + selector }   // a silent null fakes a passing check
  const r = el.getBoundingClientRect()
  const c = getComputedStyle(el)
  return {
    box: { x: +r.x.toFixed(1), right: +r.right.toFixed(1), y: +r.y.toFixed(1), bottom: +r.bottom.toFixed(1) },
    type: { px: c.fontSize, weight: c.fontWeight, tracking: c.letterSpacing, transform: c.textTransform },
    surface: { bg: c.backgroundColor, radius: c.borderRadius, shadow: c.boxShadow, border: c.borderTopWidth },
    contrast: ratio(c.color, surfaceOf(el)),   // null: sample pixels instead
  }
}
const SELECTOR = '<selector>'   // the element to measure
const result = await page.evaluate(measure, SELECTOR)   // page.evaluate does not close over Node variables
```

A `null` contrast means the surface is a gradient, an image, or a translucent stack, or the text itself is translucent, and only sampled pixels give the true number.
Never quote a ratio you got by treating `transparent` as black.

### Sample pixels for any visibility claim

Computed styles show what was asked for, and pixels show what landed.
A box-shadow still paints a halo when `getComputedStyle` reports `border: 0px`, and a neighbour's border can delineate an edge by coincidence.
For any claim that a user can or cannot see something, clip a screenshot to the boundary, decode it, and compare row averages either side of the edge.
The same measurement proves that a claimed fix landed.

A page cannot screenshot itself, so this runs in Node with Playwright.
Node's `zlib` is enough to decode a PNG, so install no image library, and skip no measurement for lack of one:

```js
// Decodes an 8-bit RGB or RGBA PNG: signature, chunks, inflate, un-filter.
import zlib from 'node:zlib'

function decodePng(buf) {
  let p = 8, w = 0, h = 0, ct = 0
  const idat = []
  while (p < buf.length) {
    const len = buf.readUInt32BE(p)
    const type = buf.toString('ascii', p + 4, p + 8)
    const data = buf.subarray(p + 8, p + 8 + len)
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); ct = data[9] }
    else if (type === 'IDAT') idat.push(data)
    else if (type === 'IEND') break
    p += 12 + len
  }
  const bpp = ct === 6 ? 4 : 3, stride = w * bpp
  const raw = zlib.inflateSync(Buffer.concat(idat))
  const out = Buffer.alloc(h * stride)
  let q = 0
  for (let y = 0; y < h; y++) {
    const filter = raw[q++]
    const line = raw.subarray(q, q + stride); q += stride
    const prev = y > 0 ? out.subarray((y - 1) * stride, y * stride) : Buffer.alloc(stride)
    const cur = out.subarray(y * stride, (y + 1) * stride)
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? cur[x - bpp] : 0, b = prev[x], c = x >= bpp ? prev[x - bpp] : 0
      let v = line[x]
      if (filter === 1) v += a
      else if (filter === 2) v += b
      else if (filter === 3) v += (a + b) >> 1
      else if (filter === 4) {
        const pp = a + b - c, pa = Math.abs(pp - a), pb = Math.abs(pp - b), pc = Math.abs(pp - c)
        v += (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
      }
      cur[x] = v & 0xff
    }
  }
  return { w, h, bpp, data: out }
}

// Node-side contrast over RGB arrays, separate from the in-page ratio, which takes a colour string.
const lumRgb = ([r, g, b]) => {
  const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
}
const ratioRgb = (p, q) => {
  const [hi, lo] = [lumRgb(p), lumRgb(q)].sort((a, b) => b - a)
  return +((hi + 0.05) / (lo + 0.05)).toFixed(3)
}

// Average the middle band of a row, since the ends are rounded corners and neighbours.
const rowAvg = ({ w, bpp, data }, y) => {
  const x0 = Math.floor(w * 0.25), x1 = Math.max(x0 + 1, Math.floor(w * 0.75))
  let r = 0, g = 0, b = 0, n = 0
  for (let x = x0; x < x1; x++) { const i = (y * w + x) * bpp; r += data[i]; g += data[i + 1]; b += data[i + 2]; n++ }
  return [r / n, g / n, b / n]
}

// Average the middle band of a column, since the ends are rounded corners and neighbours.
const colAvg = ({ w, h, bpp, data }, x) => {
  const y0 = Math.floor(h * 0.25), y1 = Math.max(y0 + 1, Math.floor(h * 0.75))
  let r = 0, g = 0, b = 0, n = 0
  for (let y = y0; y < y1; y++) { const i = (y * w + x) * bpp; r += data[i]; g += data[i + 1]; b += data[i + 2]; n++ }
  return [r / n, g / n, b / n]
}

// Measures the step across the requested edge within 3 pixels of its offset inside the strip, clamped to the image.
const strongestStep = (img, edge, offset) => {
  const horizontal = edge === 'top' || edge === 'bottom'
  const span = horizontal ? img.h : img.w
  let best = 1
  for (let i = Math.max(1, Math.ceil(offset - 3)); i <= Math.min(span - 1, Math.floor(offset + 3)); i++) {
    best = Math.max(best, ratioRgb(horizontal ? rowAvg(img, i - 1) : colAvg(img, i - 1), horizontal ? rowAvg(img, i) : colAvg(img, i)))
  }
  return best
}

// page.evaluate does not close over Node variables, so pass the selector in.
const SEL = '<selector>'   // the element whose edge you measure
const EDGE = 'bottom'   // or 'top', 'left', 'right'
const box = await page.evaluate((sel) => {
  const el = document.querySelector(sel)
  if (!el) return null
  const b = el.getBoundingClientRect()
  return { x: b.x, y: b.y, w: b.width, h: b.height, right: b.right, bottom: b.bottom }
}, SEL)

if (!box) throw new Error('no element matched ' + SEL)
if (box.w < 1 || box.h < 1) throw new Error(SEL + ' has zero size, so the screenshot clip would be rejected')

const horizontal = EDGE === 'top' || EDGE === 'bottom'
const start = horizontal
  ? Math.max(0, (EDGE === 'top' ? box.y : box.bottom) - 12)
  : Math.max(0, (EDGE === 'left' ? box.x : box.right) - 12)
const offset = Math.round((horizontal ? (EDGE === 'top' ? box.y : box.bottom) : (EDGE === 'left' ? box.x : box.right)) - start)
if (offset < 4) throw new Error(SEL + ' ' + EDGE + ' edge is within 4px of the viewport origin, so scroll it into view before measuring')
const png = await page.screenshot({
  scale: 'css',   // offset is in CSS pixels
  clip: horizontal
    ? { x: Math.max(0, box.x), y: start, width: Math.round(box.w), height: 24 }
    : { x: start, y: Math.max(0, box.y), width: 24, height: Math.round(box.h) },
})
console.log(strongestStep(decodePng(png), EDGE, offset))
```

### Hit-test instead of comparing boxes

`toBeVisible()` and bounding-box comparisons both pass on clipped content, because an out-of-flow child keeps its geometry while painting nowhere.
`document.elementFromPoint(x, y)` returns what is actually painted and clickable there:

```js
const hit = document.elementFromPoint(x, barBottom + 20)   // null outside the viewport
;({ hit: hit ? hit.className : null, insideDropdown: hit ? dropdown.contains(hit) : false })
```

Use it for clipping, overlap, sticky corners, and anything z-index shaped.

### Trace animation state

A `MutationObserver` on the `style` attribute logs each inline-style write in order, which catches a wrong value set one frame before unmount:

```js
new MutationObserver(() => log.push({
  t: Math.round(performance.now()), overflow: el.style.overflow,
  height: el.style.height, opacity: el.style.opacity, connected: el.isConnected,
})).observe(el, { attributes: true, attributeFilter: ['style'] })
```

The observer sees only animation driven by inline-style writes.
CSS transitions, `element.animate()`, and compositor-driven libraries never touch the `style` attribute.
When the log looks quieter than what you see, sample computed values every frame instead:

```js
const until = performance.now() + 2000   // the observation window
const sample = () => {
  const c = getComputedStyle(el)
  log.push({ t: Math.round(performance.now()), overflow: c.overflow, height: c.height, opacity: c.opacity, connected: el.isConnected })
  if (el.isConnected && performance.now() < until) requestAnimationFrame(sample)
}
requestAnimationFrame(sample)
```

Use the observer for write-ordering bugs, and rAF sampling for what the user actually saw.

### Scroll and measure in separate calls

`scrollIntoView` and smooth scrolling have not settled when the same function reads `getBoundingClientRect()`.
Scroll with `behavior: 'instant'` in one call, and measure in the next.

## A/B against base

Whether a finding is this PR's problem is decided as stage 7 in `SKILL.md` says.
Take the same measurement on the base preview and the PR preview.
The result decides between "you introduced this" and "this predates you", which sets severity, tone, and whether the author owes anything.
Measure the broken state on base before crediting a fix the PR claims.

## Capture

Every visual surface the PR touches gets a before/after pair, presented as a two-column table:

- **before** is the surface on the base build, at the same viewport and theme
- **after** is the same surface on the PR build

Capture each pair while both previews are warm, before stage 5 rebuilds the PR side.
Re-assert build identity before any screenshot taken after stage 5.

Each finding with a visual component also gets one annotated capture.
Inject overlays into the page before capturing: guide lines at the two edges that should agree, a labelled band across the gap, and dashed outlines that carry the measured value.
The annotation and the measurement state the same number.

## Hosting

The GitHub API has no image-upload endpoint, so images must already be hosted.
Keep screenshots out of the repo, and host them through the browser:

1. Open any PR comment box, `find` the "Add files" input, and upload every image in one call.
2. Wait, then read `textarea[name="comment[body]"]`, which GitHub fills with `<img src="https://github.com/user-attachments/assets/...">` or `![image](https://github.com/user-attachments/assets/...)`, and harvest every `https://github.com/user-attachments/assets/` URL from either form.
3. Clear the textarea with the native value setter plus an `input` event, so no draft stays staged.
4. Post the review with `gh api`, embedding the harvested URLs.

`curl` on those URLs returns 404 on a private repo even when they work.
Verify by loading the posted review in the authenticated browser and checking `img.naturalWidth > 0`.
