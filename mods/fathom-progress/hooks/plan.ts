import type { Plan, PlanBundle, PlanReview } from '../types'

// The plan document at .fathom/plans/<ref>.md, read back as data. Fathom writes it
// at breakdown and afterwards only adds its review lines and the Finalization line,
// so this reads structure and never task status: status is bd's. The labels are the
// exact ones conventions.md fixes (fathom 2.2.0), because other readers match them
// too.
const FIELD = /^\s*- (Issue|Ref|Branch): (.+?)\s*$/
// The first heading, `# <ref>: <title>`. A title may hold colons, quotes and slashes, so
// everything after the first colon and space is the title. A heading with no title, as in
// `# PHA-186 plan`, does not match.
const HEADING = /^# +([A-Za-z][A-Za-z0-9]*-\d+): +(\S.*?)\s*$/
const BUNDLE = /^\s*- Bundle (\d+)\/(\d+): (\S+) - (.+?)\s*$/
const REVIEW = /^\s*- Review: (.+?)\s*$/
const SUFFIX = /^(.*?)(?: \(bundle (\d+)\/(\d+)\))?$/
const FINALIZED = /^\s*- Finalization: complete\s*$/
const FENCE = /^\s*(```|~~~)/

// When one bundle carries several review lines, a recorded review beats a
// confirmation that none exists, which beats the pending marker; among equals the
// later line wins.
const RANK = { recorded: 2, none: 1, pending: 0 } as const

function stronger(current: PlanReview | null, next: PlanReview): PlanReview {
  return current === null || RANK[next.kind] >= RANK[current.kind] ? next : current
}

// What follows `- Review: `, without the `(bundle k/N)` suffix: the pending marker,
// `none confirmed`, or `<id> <url>`. Anything else is not a record.
function reviewOf(head: string): PlanReview | null {
  if (head === 'pending') return { kind: 'pending' }
  if (head === 'none confirmed') return { kind: 'none' }
  const [id, url, ...rest] = head.split(/\s+/)
  return id && url && rest.length === 0 ? { kind: 'recorded', id, url } : null
}

// Lines inside a code fence are skipped, so a plan that quotes Fathom's own format
// in an example does not read as a record.
export function parsePlan(text: string): Plan {
  const plan: Plan = {
    issue: null,
    ref: null,
    branch: null,
    title: null,
    bundles: [],
    review: null,
    isFinalized: false,
  }
  const reviews: { review: PlanReview; index: number | null }[] = []
  let isFenced = false
  // Only the first heading is the document's: a later one is a section of its own.
  let hasHeading = false
  let heading: { ref: string; title: string } | null = null

  for (const line of text.split(/\r?\n/)) {
    if (FENCE.test(line)) {
      isFenced = !isFenced
      continue
    }
    if (isFenced) continue

    if (!hasHeading && /^# /.test(line)) {
      hasHeading = true
      const match = HEADING.exec(line)
      if (match) heading = { ref: match[1] ?? '', title: (match[2] ?? '').replace(/\s+/g, ' ') }
      continue
    }

    const field = FIELD.exec(line)
    if (field) {
      const key = field[1] === 'Issue' ? 'issue' : field[1] === 'Ref' ? 'ref' : 'branch'
      if (plan[key] === null) plan[key] = field[2] ?? null
      continue
    }

    const bundle = BUNDLE.exec(line)
    if (bundle) {
      const index = Number(bundle[1])
      if (!plan.bundles.some(b => b.index === index)) {
        plan.bundles.push({
          index,
          of: Number(bundle[2]),
          branch: bundle[3] ?? '',
          refs: (bundle[4] ?? '')
            .split(',')
            .map(ref => ref.trim())
            .filter(ref => ref !== ''),
          review: null,
        })
      }
      continue
    }

    const review = REVIEW.exec(line)
    if (review) {
      const parts = SUFFIX.exec(review[1] ?? '')
      const parsed = reviewOf(parts?.[1] ?? '')
      if (parsed) reviews.push({ review: parsed, index: parts?.[2] ? Number(parts[2]) : null })
      continue
    }

    if (FINALIZED.test(line)) plan.isFinalized = true
  }

  // A review line names its bundle in a suffix, so it attaches wherever it sits in
  // the document. One naming a bundle the plan does not list is dropped; one with
  // no suffix is the issue's own review.
  for (const { review, index } of reviews) {
    if (index === null) {
      plan.review = stronger(plan.review, review)
      continue
    }
    const bundle: PlanBundle | undefined = plan.bundles.find(b => b.index === index)
    if (bundle) bundle.review = stronger(bundle.review, review)
  }

  // The heading's title belongs to this plan only when its ref is the plan's own.
  if (heading && (plan.ref === null || plan.ref.toUpperCase() === heading.ref.toUpperCase())) {
    plan.title = heading.title
  }

  return plan
}
