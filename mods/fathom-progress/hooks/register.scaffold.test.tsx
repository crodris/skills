import type { On } from 'claude-code'
import { mock, test, expect } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

// The plugin's own hooks, raised the way the engine raises them, with the world beneath
// them mocked. register.tsx reads engine state, which these tests give it, so the wiring
// the other tests cannot reach is exercised here: arming, the calls that move a scaffold
// run, and the rule that nothing else is moved by them.
const LINEAR = 'mcp__linear-server__'

// The test runner has timers; the mod's types, which have no DOM and no Node, do not name them.
declare function setTimeout(handler: () => void, ms?: number): unknown

const PROPS = {
  hasSurvey: false,
  isCollapsed: false,
  isWorking: false,
  maxRows: 4,
  bodyColumns: 80,
  scroll: { offset: 0, bodyRows: 4 },
  view: {},
}

type Node = string | { part?: { plugin: string }; children?: readonly Node[] }
const textOf = (node: Node): string => (typeof node === 'string' ? node : (node.children ?? []).map(textOf).join(''))

// The engine beneath the plugin. The clock starts at `now`: a scaffold start within three
// seconds of the last is the same start, and the module keeps that time between tests, so
// each test starts later than the one before. No cmux in the environment, so the row is
// left alone. A tool answers, or fails when the call is for an issue titled `refused`.
function engine(on: On, now: number) {
  const clock = mock.clock(on, { now })
  mock.env(on, {})
  on('tool.call', async (_$, e) => {
    const isRefused = (e as { title?: string }).title === 'refused'
    return isRefused ? { ref: 1, result: {}, text: 'no', isError: true as const } : { ref: 1, result: {}, text: 'ok' }
  })
  on('session.start', async (_$, e) => ({ cwd: (e as { cwd: string }).cwd }) as never)
  on('session.end', async () => ({ sessionId: 's1' }) as never)
  on('prompt.submit', async (_$, e) => ({ text: e.text }))
  on('skill.prompt', async (_$, e) => ({ text: e.text }))
  on('turn.start', async () => ({ turnId: 't1' }))
  on('turn.complete', async (_$, e) => ({ text: e.answer }))
  // An execute run reads bd; here bd lists no epics, so it stays on `starting`.
  on('session.root', async () => ({ value: '/work' }) as never)
  on('process.run', async () => ({ value: { exitCode: 0, stdout: '[]', stderr: '' } }) as never)
  on('config.list', async () => ({ value: [] }) as never)
  on('ui.log', async () => ({ value: undefined }) as never)
  // Where the plugin passes, an empty box is what draws.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
  return clock
}

// The band's rows, or null when the plugin passes. When more than one plugin draws a row, the
// kit draws the band as a column of parts, one per plugin. Here the test's empty box is always
// one, so this mod has drawn only when a part is stamped with its name.
async function rows($: Engine): Promise<string[] | null> {
  const ui = await $.ui.mount({ plugin: 'fathom-progress', surface: 'terminal', component: 'AbovePrompt', requestId: 'r', props: PROPS })
  const tree = (await ui.drawn()) as unknown as { children?: Node[] } | null
  await ui.unmount()
  const own = tree?.children?.find(node => typeof node !== 'string' && node.part?.plugin === 'fathom-progress')
  return typeof own === 'object' ? (own.children ?? []).map(textOf) : null
}

// The hooks hand an event to the band without waiting for it, so Claude is not held up: the
// band has it a moment later. A real session redraws as it lands; a test lets it land.
const settle = async () => {
  for (let i = 0; i < 5; i++) await new Promise(resolve => setTimeout(() => resolve(undefined), 0))
}

async function band($: Engine): Promise<string[] | null> {
  await settle()
  return rows($)
}

const call = ($: Engine, input: Record<string, unknown>) => $.tool.call(input as never)
const label = async ($: Engine) => (await band($))?.[0]
const complete = ($: Engine) => $.turn.complete({ turnId: 't1', answer: 'ok', durationMs: 1, isAborted: false, reason: 'answer' })
const create = ($: Engine, extra: Record<string, unknown> = {}) => call($, { tool: `${LINEAR}save_issue`, title: 'Issue', team: 'T', ...extra })

test('a scaffold started by its skill moves through the phases of the run and ends done', async ($, on) => {
  engine(on, 10_000)
  expect(await band($)).toBeNull()

  await $.skill.prompt({ skill: 'fathom:scaffold', text: 'scaffold' })
  expect(await band($)).toEqual(['Scaffold · Checking the tracker (0s)', '○ Resolve  Draft  Create  Done'])

  await call($, { tool: `${LINEAR}list_teams`, limit: 10 })
  expect(await label($)).toBe('Scaffold · Checking the tracker (0s)')

  await call($, { tool: `${LINEAR}get_user`, query: 'me' })
  expect(await label($)).toBe('Scaffold · Drafting the issues (0s)')

  await create($, { title: 'Main' })
  await create($, { title: 'Sub', parentId: 'X-1' })
  expect(await label($)).toBe('Scaffold · Creating, 2 issues made (0s)')

  await complete($)
  expect(await band($)).toEqual(['Scaffold · Done, 2 issues made (0s)', '● Resolve  ● Draft  ● Create  ● Done'])
})

test('a typed /fathom:scaffold starts the band too, and the skill\'s own signal a moment later does not restart it', async ($, on) => {
  engine(on, 20_000)
  await $.prompt.submit({ text: '/fathom:scaffold turn these notes into issues' } as never)
  await call($, { tool: `${LINEAR}get_user`, query: 'me' })
  expect(await label($)).toBe('Scaffold · Drafting the issues (0s)')

  await $.skill.prompt({ skill: 'fathom:scaffold', text: 'scaffold' })
  expect(await label($)).toBe('Scaffold · Drafting the issues (0s)')
})

test('a question waits on the person and its answer resumes the draft; one after an issue is made is the hand-off', async ($, on) => {
  engine(on, 30_000)
  await $.skill.prompt({ skill: 'fathom:scaffold', text: 'scaffold' })
  await call($, { tool: `${LINEAR}get_user`, query: 'me' })

  // The question is a call that has not come back until the person answers.
  await call($, { tool: 'AskUserQuestion', questions: [] })
  expect(await label($)).toBe('Scaffold · Drafting the issues (0s)')

  await create($, { title: 'Main' })
  await call($, { tool: 'AskUserQuestion', questions: [] })
  expect(await band($)).toEqual(['Scaffold · Done, 1 issue made (0s)', '● Resolve  ● Draft  ● Create  ● Done'])
})

test('an issue the tracker refused is not counted, and an update is not an issue made', async ($, on) => {
  engine(on, 40_000)
  await $.skill.prompt({ skill: 'fathom:scaffold', text: 'scaffold' })
  await create($, { title: 'refused' })
  expect(await label($)).toBe('Scaffold · Creating issues (0s)')

  await call($, { tool: `${LINEAR}save_issue`, id: 'RUE-5', state: 'Done' })
  await create($, { title: 'Main' })
  expect(await label($)).toBe('Scaffold · Creating, 1 issue made (0s)')
})

test('a turn ending before any issue is made leaves the run waiting, and the person\'s reply resumes it', async ($, on) => {
  engine(on, 50_000)
  await $.skill.prompt({ skill: 'fathom:scaffold', text: 'scaffold' })
  await call($, { tool: `${LINEAR}get_user`, query: 'me' })

  await complete($)
  expect(await label($)).toBe('Scaffold · ● Waiting on you (0s)')

  await $.turn.start({ turnId: 't2', text: 'the answer' })
  expect(await label($)).toBe('Scaffold · Drafting the issues (0s)')
})

test('an execute run is not moved by the calls and turns of anything else', async ($, on) => {
  engine(on, 60_000)
  await $.skill.prompt({ skill: 'fathom:execute', text: 'execute' })
  const starting = await band($)
  expect(starting).toEqual(['fathom starting…'])

  await call($, { tool: `${LINEAR}get_user`, query: 'me' })
  await create($, { title: 'Main' })
  await call($, { tool: 'AskUserQuestion', questions: [] })
  await complete($)
  expect(await band($)).toEqual(starting)
})

test('handing off to execute replaces the scaffold run with execute\'s', async ($, on) => {
  engine(on, 70_000)
  await $.skill.prompt({ skill: 'fathom:scaffold', text: 'scaffold' })
  await create($, { title: 'Main' })
  expect(await label($)).toBe('Scaffold · Creating, 1 issue made (0s)')

  await $.skill.prompt({ skill: 'fathom:execute', text: 'execute' })
  expect(await band($)).toEqual(['fathom starting…'])
})

test('the time on the first row counts up each second while the run goes, and stops when it is done', async ($, on) => {
  const clock = engine(on, 80_000)
  await $.session.start({ cwd: '/work' } as never)
  await $.skill.prompt({ skill: 'fathom:scaffold', text: 'scaffold' })
  expect(await label($)).toBe('Scaffold · Checking the tracker (0s)')

  await clock.advance(37_000)
  expect(await label($)).toBe('Scaffold · Checking the tracker (37s)')

  await call($, { tool: `${LINEAR}get_user`, query: 'me' })
  await complete($)
  await clock.advance(195_000)
  expect(await label($)).toBe('Scaffold · ● Waiting on you (3m 52s)')

  await create($, { title: 'Main' })
  await complete($)
  await clock.advance(60_000)
  expect(await label($)).toBe('Scaffold · Done, 1 issue made (3m 52s)')
})

function mockChecklists(on: On, files: Record<string, string>) {
  on('fs.read', async (_$, e) => {
    const path = (e as { path: string }).path
    const content = files[path]
    if (content !== undefined) return { value: content } as never
    throw new Error(`ENOENT: ${path}`)
  })
}

test('a plain-language prompt stays idle until the Skill tool runs, then locks onto the ref from that prompt', async ($, on) => {
  engine(on, 90_000)
  mockChecklists(on, {
    '/work/.fathom/tasks/PHA-352.md': '# PHA-352: Plain-language execute\n\n## Tasks\n- [>] 1. Implement ref capture\n',
  })

  await $.prompt.submit({ text: 'execute pha-352' } as never)
  expect(await band($)).toBeNull()

  await call($, { tool: 'Skill', skill: 'fathom:execute' })
  const rendered = await band($)
  expect(rendered?.[1]).toContain('PHA-352 Plain-language execute')
  expect(rendered?.[2]).toBe('▸ now 1/1  Implement ref capture')
})

test('a ref mentioned in an earlier chat turn does not leak into a later arg-less /fathom:execute', async ($, on) => {
  engine(on, 100_000)
  mockChecklists(on, {
    '/work/.fathom/tasks/PHA-100.md': '# PHA-100: Earlier chat issue\n\n## Tasks\n- [>] 1. Should not be followed\n',
  })

  await $.prompt.submit({ text: 'what is the status of PHA-100?' } as never)
  await complete($)

  await $.prompt.submit({ text: '/fathom:execute' } as never)
  await call($, { tool: 'Skill', skill: 'fathom:execute' })
  expect(await band($)).toEqual(['fathom starting…'])
})

test('a delayed Skill tool call more than 3s after /fathom:execute in the same turn keeps the typed ref', async ($, on) => {
  const clock = engine(on, 110_000)
  mockChecklists(on, {
    '/work/.fathom/tasks/PHA-352.md': '# PHA-352: Keep typed ref\n\n## Tasks\n- [>] 1. Preserve armedRefs\n',
  })

  await $.prompt.submit({ text: '/fathom:execute pha-352' } as never)
  expect((await band($))?.[1]).toContain('PHA-352 Keep typed ref')

  await clock.advance(5_000)
  await call($, { tool: 'Skill', skill: 'fathom:execute' })
  const rendered = await band($)
  expect(rendered?.[1]).toContain('PHA-352 Keep typed ref')
  expect(rendered?.[2]).toBe('▸ now 1/1  Preserve armedRefs')
})

test('a new turn switches to a different issue instead of staying locked on the previous turn\'s ref', async ($, on) => {
  const clock = engine(on, 120_000)
  mockChecklists(on, {
    '/work/.fathom/tasks/PHA-352.md': '# PHA-352: First issue\n\n## Tasks\n- [>] 1. First task\n',
    '/work/.fathom/tasks/PHA-400.md': '# PHA-400: Second issue\n\n## Tasks\n- [>] 1. Second task\n',
  })

  await $.prompt.submit({ text: '/fathom:execute pha-352' } as never)
  expect((await band($))?.[1]).toContain('PHA-352 First issue')
  await complete($)

  await clock.advance(5_000)
  await $.prompt.submit({ text: 'work on pha-400' } as never)
  await call($, { tool: 'Skill', skill: 'fathom:execute' })
  const rendered = await band($)
  expect(rendered?.[1]).toContain('PHA-400 Second issue')
  expect(rendered?.[2]).toBe('▸ now 1/1  Second task')
})

test('scaffold handoff ignores refs from the scaffold prompt, and reads refs from Skill args when present', async ($, on) => {
  const clock = engine(on, 130_000)
  mockChecklists(on, {
    '/work/.fathom/tasks/PHA-100.md': '# PHA-100: Context issue from scaffold prompt\n\n## Tasks\n- [>] 1. Wrong issue\n',
    '/work/.fathom/tasks/PHA-500.md': '# PHA-500: Newly scaffolded issue\n\n## Tasks\n- [>] 1. Right issue\n',
  })

  await $.prompt.submit({ text: '/fathom:scaffold follow up on PHA-100' } as never)
  await create($, { title: 'Main' })
  await call($, { tool: 'Skill', skill: 'execute' })
  expect(await band($)).toEqual(['fathom starting…'])

  await complete($)
  await clock.advance(5_000)
  await $.prompt.submit({ text: '/fathom:scaffold another follow up on PHA-100' } as never)
  await create($, { title: 'Main 2' })
  await call($, { tool: 'Skill', skill: 'execute', args: 'PHA-500' })
  const rendered = await band($)
  expect(rendered?.[1]).toContain('PHA-500 Newly scaffolded issue')
  expect(rendered?.[2]).toBe('▸ now 1/1  Right issue')
})

test('editing or writing a Fathom checklist refreshes the band immediately without waiting for the poll', async ($, on) => {
  engine(on, 140_000)
  let checklist = '# PHA-352: Instant refresh\n\n## Tasks\n- [ ] 1. First task\n- [ ] 2. Second task\n'
  on('fs.read', async (_$, e) => {
    const path = (e as { path: string }).path
    if (path === '/work/.fathom/tasks/PHA-352.md') return { value: checklist } as never
    if (path === '/work/.fathom/plans/PHA-352.md') return { value: '# PHA-352: Instant refresh\n\n- Ref: PHA-352\n' } as never
    throw new Error(`ENOENT: ${path}`)
  })

  await $.prompt.submit({ text: '/fathom:execute pha-352' } as never)
  expect((await band($))?.[2]).toBe('▸ next 1/2  First task')

  checklist = '# PHA-352: Instant refresh\n\n## Tasks\n- [>] 1. First task\n- [ ] 2. Second task\n'
  await call($, { tool: 'Edit', file_path: '/work/.fathom/tasks/PHA-352.md' })
  expect((await band($))?.[2]).toBe('▸ now 1/2  First task')

  checklist = '# PHA-352: Instant refresh\n\n## Tasks\n- [x] 1. First task (done 2026-11-27)\n- [>] 2. Second task\n'
  await call($, { tool: 'Write', file_path: '/work/.fathom/tasks/PHA-352.md' })
  expect((await band($))?.[2]).toBe('▸ now 2/2  Second task')
})

test('session.end resets scaffold dedup so a new scaffold right after /clear arms immediately', async ($, on) => {
  const clock = engine(on, 150_000)
  await $.prompt.submit({ text: '/fathom:scaffold first run' } as never)
  expect(await label($)).toBe('Scaffold · Checking the tracker (0s)')

  await $.session.end({} as never)
  expect(await band($)).toBeNull()

  await clock.advance(1_000)
  await $.prompt.submit({ text: '/fathom:scaffold second run' } as never)
  expect(await label($)).toBe('Scaffold · Checking the tracker (0s)')
})
