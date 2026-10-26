import { test, expect } from 'claude-code/testing'

import { parseChecklist } from './checklist'
import { beadsCreates, checklistExample, planLines, skillNames } from './contract.fixtures'
import { startOf, startOfPrompt } from './lifecycle'
import { parsePlan } from './plan'

// The formats as the Fathom skills state them today, copied by bin/sync-contract.sh.
// A change to one of them in skills/fathom-shared fails a test here, and
// skills/fathom-shared/progress.md says what the band reads.

const VALUES: readonly [string, string][] = [
  ['<ISSUE-REF>', 'ONC-5'],
  ['<issue ref>', 'ONC-5'],
  ['<title>', 'Add login flow'],
  ['<tracker url>', 'https://linear.app/acme/issue/ONC-5'],
  ['<branch>', 'feat/onc-5-login'],
  ['<k>', '1'],
  ['<N>', '2'],
  ['k/N', '1/2'],
  ['<sub-issue refs, comma separated>', 'ONC-6, ONC-7'],
  ['<id>', '17'],
  ['<url>', 'https://github.com/acme/app/pull/17'],
]

function filled(template: string): string {
  const line = VALUES.reduce((text, [placeholder, value]) => text.split(placeholder).join(value), template)
  expect(line).not.toMatch(/<[^>]+>/)
  return line
}

const linesStarting = (prefix: string) => planLines.filter(line => line.startsWith(prefix))

test('conventions.md states every plan document line the band reads', async () => {
  for (const prefix of ['# ', '- Issue: ', '- Ref: ', '- Branch: ', '- Bundle ', '- Finalization: ']) {
    expect(linesStarting(prefix)).toHaveLength(1)
  }
  expect(linesStarting('- Review: ').length).toBeGreaterThan(0)
})

test('the band reads a plan document written to conventions.md', async () => {
  const plan = parsePlan(
    ['# ', '- Issue: ', '- Ref: ', '- Branch: ', '- Bundle ', '- Finalization: '].map(prefix => filled(linesStarting(prefix)[0] ?? '')).join('\n'),
  )
  expect(plan.title).toBe('Add login flow')
  expect(plan.issue).toBe('https://linear.app/acme/issue/ONC-5')
  expect(plan.ref).toBe('ONC-5')
  expect(plan.branch).toBe('feat/onc-5-login')
  expect(plan.bundles).toEqual([{ index: 1, of: 2, branch: 'feat/onc-5-login', refs: ['ONC-6', 'ONC-7'], review: null }])
  expect(plan.isFinalized).toBe(true)
})

test('the band reads each kind of review line conventions.md states, attached to its bundle', async () => {
  const bundle = filled(linesStarting('- Bundle ')[0] ?? '')
  const kinds = linesStarting('- Review: ').map(review => parsePlan(`${bundle}\n  ${filled(review)}\n`).bundles[0]?.review?.kind)
  expect(kinds.sort()).toEqual(['none', 'pending', 'recorded'])
})

test('the band reads the example checklist in memory/checklist.md', async () => {
  const checklist = parseChecklist(checklistExample)
  const taskLines = checklistExample.split('\n').filter(line => /^- \[/.test(line))
  expect(checklist.ref).not.toBeNull()
  expect(checklist.title).not.toBeNull()
  expect(checklist.issue).not.toBeNull()
  expect(checklist.branch).not.toBeNull()
  expect(checklist.tasks).toHaveLength(taskLines.length)
  expect([...new Set(checklist.tasks.map(t => t.marker))].sort()).toEqual(['done', 'inProgress', 'open'])
  expect(checklist.tasks.some(t => t.doneOn !== null && t.hash !== null)).toBe(true)
  expect(checklist.tasks.some(t => t.deps.length > 0)).toBe(true)
  expect(checklist.tasks.every(t => t.subIssue !== null)).toBe(true)
})

test('memory/beads.md gives the epic and each task the fields the band reads', async () => {
  const epic = beadsCreates.filter(command => command.includes('--type epic'))
  const task = beadsCreates.filter(command => !command.includes('--type '))
  expect(epic).toHaveLength(1)
  expect(task).toHaveLength(1)
  expect(epic[0]).toContain('--external-ref "<issueRef>"')
  expect(epic[0]).toContain('-l "<issueRef>"')
  expect(task[0]).toContain('-l "<issueRef>"')
  expect(task[0]).toContain('--external-ref "<subIssueRef>"')
  expect(task[0]).toContain('--deps ')
})

test('the Fathom skill names arm the band from the Skill tool and from a typed command', async () => {
  expect(skillNames.map(name => startOf(name)).sort()).toEqual(['execute', 'scaffold'])
  for (const name of skillNames) expect(startOfPrompt(`/${name} ONC-5`)).toBe(startOf(name))
})
