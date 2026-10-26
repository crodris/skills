import { test, expect } from 'claude-code/testing'

import { parsePlan } from './plan'

// Plans as template strings, in the shape conventions.md (fathom 2.2.0) gives the
// plan document: labeled lines under Issue, a Bundles section only for a stack, and
// a Finalization line once the issue's closing actions have run.
const SINGLE = `# SLU-123: Add the progress band

- Issue: https://linear.app/acme/issue/SLU-123/add-the-progress-band
- Ref: SLU-123
- Branch: feat/slu-123-progress-band

## Issue description

Show Fathom progress above the prompt.

## Tasks

- Draft the plan doc (SLU-123-1)
- Wire the lifecycle hooks (SLU-123-3)
`

const STACK = `# SLU-200: Split the importer

- Issue: https://linear.app/acme/issue/SLU-200/split-the-importer
- Ref: SLU-200
- Branch: feat/slu-200-importer

## Bundles

- Bundle 1/3: feat/slu-200-importer-1 - SLU-201, SLU-202
  - Review: 90 https://github.com/acme/repo/pull/90 (bundle 1/3)
- Bundle 2/3: feat/slu-200-importer-2 - SLU-203
  - Review: pending (bundle 2/3)
- Bundle 3/3: feat/slu-200-importer-3 - SLU-204, SLU-205

- Merge-closer: suppressed
`

const EMPTY = { issue: null, ref: null, branch: null, title: null, bundles: [], review: null, isFinalized: false }

test('parsePlan reads the title, the Issue, Ref and Branch lines, and finds no bundles in a plan that was not split', async () => {
  expect(parsePlan(SINGLE)).toEqual({
    issue: 'https://linear.app/acme/issue/SLU-123/add-the-progress-band',
    ref: 'SLU-123',
    branch: 'feat/slu-123-progress-band',
    title: 'Add the progress band',
    bundles: [],
    review: null,
    isFinalized: false,
  })
})

test('a review line with no bundle suffix is the issue\'s own review', async () => {
  const plan = parsePlan(`${SINGLE}\n- Review: 4821 https://github.com/acme/repo/pull/4821\n`)

  expect(plan.review).toEqual({ kind: 'recorded', id: '4821', url: 'https://github.com/acme/repo/pull/4821' })
  expect(plan.bundles).toEqual([])
})

test('parsePlan reads a three-bundle stack with a recorded review, a pending marker and no line', async () => {
  const plan = parsePlan(STACK)

  expect(plan.ref).toBe('SLU-200')
  expect(plan.review).toBeNull()
  expect(plan.bundles).toEqual([
    {
      index: 1,
      of: 3,
      branch: 'feat/slu-200-importer-1',
      refs: ['SLU-201', 'SLU-202'],
      review: { kind: 'recorded', id: '90', url: 'https://github.com/acme/repo/pull/90' },
    },
    { index: 2, of: 3, branch: 'feat/slu-200-importer-2', refs: ['SLU-203'], review: { kind: 'pending' } },
    { index: 3, of: 3, branch: 'feat/slu-200-importer-3', refs: ['SLU-204', 'SLU-205'], review: null },
  ])
})

test('none confirmed is a record of its own, and still names no id', async () => {
  const plan = parsePlan(STACK.replace('Review: pending (bundle 2/3)', 'Review: none confirmed (bundle 2/3)'))

  expect(plan.bundles[1]?.review).toEqual({ kind: 'none' })
})

test('a review line attaches by its suffix wherever it sits, and one naming an unlisted bundle is dropped', async () => {
  const moved = STACK.replace('  - Review: pending (bundle 2/3)\n', '') + '- Review: 91 https://github.com/acme/repo/pull/91 (bundle 3/3)\n- Review: 7 https://github.com/acme/repo/pull/7 (bundle 9/9)\n'
  const plan = parsePlan(moved)

  expect(plan.bundles.map(b => b.review?.kind ?? null)).toEqual(['recorded', null, 'recorded'])
  expect(plan.bundles[2]?.review).toEqual({ kind: 'recorded', id: '91', url: 'https://github.com/acme/repo/pull/91' })
  expect(plan.review).toBeNull()
})

test('a recorded review outranks the pending marker and none confirmed, whichever line comes last', async () => {
  const recorded = '- Review: 90 https://github.com/acme/repo/pull/90 (bundle 1/3)'
  const pending = '- Review: pending (bundle 1/3)'
  const none = '- Review: none confirmed (bundle 1/3)'
  const bundle = '- Bundle 1/3: feat/x-1 - SLU-1'

  for (const lines of [[recorded, pending], [pending, recorded], [none, recorded, pending]]) {
    expect(parsePlan([bundle, ...lines].join('\n')).bundles[0]?.review?.kind).toBe('recorded')
  }
  expect(parsePlan([bundle, pending, none].join('\n')).bundles[0]?.review?.kind).toBe('none')
})

test('parsePlan sees the Finalization line only when it reads complete', async () => {
  expect(parsePlan(`${SINGLE}\n- Finalization: complete\n`).isFinalized).toBe(true)
  expect(parsePlan(`${STACK}\n- Finalization: complete\n`).isFinalized).toBe(true)
  expect(parsePlan(`${SINGLE}\n- Finalization: incomplete\n`).isFinalized).toBe(false)
  expect(parsePlan(SINGLE).isFinalized).toBe(false)
})

test('lines inside a code fence are examples, not records', async () => {
  const fence = '`'.repeat(3)
  const text = [
    SINGLE,
    fence,
    '- Ref: FAKE-1',
    '- Bundle 1/1: feat/fake - FAKE-1',
    '- Review: 1 https://example.com/1',
    '- Finalization: complete',
    fence,
  ].join('\n')

  expect(parsePlan(text)).toEqual(parsePlan(SINGLE))
})

test('the first Issue, Ref and Branch line wins, and the first line of a bundle wins', async () => {
  const text = `${SINGLE}\n- Ref: OTHER-1\n- Branch: other\n- Bundle 1/1: feat/a - SLU-1\n- Bundle 1/1: feat/b - SLU-2\n`
  const plan = parsePlan(text)

  expect(plan.ref).toBe('SLU-123')
  expect(plan.branch).toBe('feat/slu-123-progress-band')
  expect(plan.bundles).toEqual([{ index: 1, of: 1, branch: 'feat/a', refs: ['SLU-1'], review: null }])
})

test('parsePlan reads Windows line endings the same as Unix ones', async () => {
  expect(parsePlan(STACK.replace(/\n/g, '\r\n'))).toEqual(parsePlan(STACK))
})

test('text with no plan lines, or review lines that name no id and url, reads as an empty plan', async () => {
  expect(parsePlan('')).toEqual(EMPTY)
  expect(parsePlan('Just some notes.\n\n- a bullet\n')).toEqual(EMPTY)
  expect(parsePlan('- Review: only-one-token\n- Review: a b c\n- Review: \n')).toEqual(EMPTY)
})

// The title is the first heading, `# <ref>: <title>`, the way Fathom wrote the plans in the
// repositories it ran in. conventions.md fixes the labels of the Issue, Ref and Branch lines
// and says the Issue section carries the title, but gives the heading no label, so a plan
// may have none.

test('the title is what follows the ref in the first heading, and it may hold colons, quotes and slashes', async () => {
  const plan = (heading: string) => parsePlan(`${heading}\n\n- Ref: PHA-368\n`).title

  expect(plan('# PHA-368: Home page: Restrict actions and CTAs, add video')).toBe('Home page: Restrict actions and CTAs, add video')
  expect(plan('# PHA-368: Relabel the 3-way results control: "Preferred" / "Full" / Grid')).toBe('Relabel the 3-way results control: "Preferred" / "Full" / Grid')
  // Runs of spaces and trailing spaces do not reach the band.
  expect(plan('# PHA-368:   Home   page   ')).toBe('Home page')
})

test('a heading with no title, or with a different ref, or that is not the first one, gives no title', async () => {
  const plan = (text: string) => parsePlan(text).title

  // `# PHA-186 plan` is a heading some of Fathom's own plans carry.
  expect(plan('# PHA-186 plan\n\n- Ref: PHA-186\n')).toBeNull()
  expect(plan('# PHA-186:\n\n- Ref: PHA-186\n')).toBeNull()
  // A plan about another issue is not this issue's title.
  expect(plan('# PHA-999: Someone else\'s plan\n\n- Ref: PHA-368\n')).toBeNull()
  // Only the first heading counts: it names no title, so a later one does not.
  expect(plan('# PHA-186 plan\n\n# PHA-186: Later heading\n- Ref: PHA-186\n')).toBeNull()
  // A section heading is not the title.
  expect(plan('## PHA-368: Not the title\n- Ref: PHA-368\n')).toBeNull()
  expect(plan('- Ref: PHA-368\n')).toBeNull()
  expect(plan('')).toBeNull()
})

test('the title is matched to the plan\'s ref without regard to case, and is kept when the plan names no ref', async () => {
  expect(parsePlan('# pha-368: Home page\n- Ref: PHA-368\n').title).toBe('Home page')
  expect(parsePlan('# PHA-368: Home page\n').title).toBe('Home page')
})

test('a heading inside a code fence is an example, not the title', async () => {
  const fenced = '```\n# PHA-368: Example title\n```\n\n# PHA-368: The real title\n- Ref: PHA-368\n'

  expect(parsePlan(fenced).title).toBe('The real title')
  expect(parsePlan('```\n# PHA-368: Example title\n```\n- Ref: PHA-368\n').title).toBeNull()
})

test('the title reads from a plan written with Windows line endings', async () => {
  expect(parsePlan('# PHA-368: Home page\r\n\r\n- Ref: PHA-368\r\n').title).toBe('Home page')
})
