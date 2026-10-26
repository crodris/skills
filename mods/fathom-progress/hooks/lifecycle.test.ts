import { test, expect } from 'claude-code/testing'

import { beadsPath, checklistPath, planPath, refsIn, refsOfBranch, refsOfPrompt, snapshotOnStart, startOf, startOfPrompt, touchesRun } from './lifecycle'

test('execute starts on `starting`, and scaffold, which nothing polls, on its first phase', async () => {
  expect(snapshotOnStart('execute')).toEqual({ kind: 'starting' })
  expect(snapshotOnStart('scaffold')).toEqual({ kind: 'scaffold', phase: 'resolving', created: 0 })
})

test('startOf names which Fathom skill started, with or without the plugin prefix', async () => {
  expect(startOf('fathom:execute')).toBe('execute')
  expect(startOf('execute')).toBe('execute')
  expect(startOf('fathom:scaffold')).toBe('scaffold')
  expect(startOf('scaffold')).toBe('scaffold')
})

test('the other Fathom skills, other plugins\' skills and near misses start nothing', async () => {
  for (const name of ['fathom:review', 'fathom:ship', 'fathom:fathom-shared', 'ship:execute', 'fathom:execute-all', 'xfathom:execute', 'commit', '']) {
    expect(startOf(name)).toBeNull()
  }
})

test('startOfPrompt reads a typed Fathom slash command, with or without arguments', async () => {
  expect(startOfPrompt('/fathom:execute')).toBe('execute')
  expect(startOfPrompt('/fathom:execute pha-352')).toBe('execute')
  expect(startOfPrompt('  /fathom:scaffold\nsome notes')).toBe('scaffold')
})

test('startOfPrompt ignores other prompts, other Fathom skills and near misses', async () => {
  for (const text of ['/execute', '/fathom:review', '/fathom:execute-all', '/fathom:executex', 'fathom:execute', 'run /fathom:execute', 'please /fathom:scaffold', '/ship:execute', '']) {
    expect(startOfPrompt(text)).toBeNull()
  }
})

test('refsIn finds issue refs, upper-cased and in order, once each', async () => {
  expect(refsIn('pha-352')).toEqual(['PHA-352'])
  expect(refsIn('ONC-5 onc-6, then ONC-5 again')).toEqual(['ONC-5', 'ONC-6'])
  expect(refsIn('https://linear.app/slickage/issue/PHA-352/relabel-the-3-way-results-control')).toEqual(['PHA-352'])
  expect(refsIn('feat/pha-352-relabel-results-view-control')).toEqual(['PHA-352'])
})

test('refsIn ignores what only looks like a ref', async () => {
  for (const text of ['', 'main', 'wip-phase-3', 'relabel-the-3-way', 'x-1', 'abcdefghijkl-1', 'PHA-', '3-way', 'PHA-352x']) {
    expect(refsIn(text)).toEqual([])
  }
})

test('refsOfPrompt reads the refs typed after a Fathom command, and only there', async () => {
  expect(refsOfPrompt('/fathom:execute pha-352')).toEqual(['PHA-352'])
  expect(refsOfPrompt('/fathom:execute ONC-5 ONC-6')).toEqual(['ONC-5', 'ONC-6'])
  expect(refsOfPrompt('/fathom:execute')).toEqual([])
  expect(refsOfPrompt('/fathom:scaffold https://linear.app/x/issue/SLU-9/some-title')).toEqual(['SLU-9'])
  expect(refsOfPrompt('fathom execute pha-352')).toEqual([])
  expect(refsOfPrompt('/fathom:review pha-352')).toEqual([])
})

test('refsOfBranch takes the first ref a branch is named for, and none from a branch without one', async () => {
  expect(refsOfBranch('feat/pha-352-relabel-results-view-control')).toEqual(['PHA-352'])
  expect(refsOfBranch('pha-352')).toEqual(['PHA-352'])
  expect(refsOfBranch('fix/pha-1-and-pha-2')).toEqual(['PHA-1'])
  expect(refsOfBranch('main')).toEqual([])
  expect(refsOfBranch('wip-phase-3')).toEqual([])
  expect(refsOfBranch('')).toEqual([])
})

test('planPath puts a plain ref under .fathom/plans, whether or not the root ends in a slash', async () => {
  expect(planPath('/work/repo', 'SLU-123')).toBe('/work/repo/.fathom/plans/SLU-123.md')
  expect(planPath('/work/repo/', 'ONC-5')).toBe('/work/repo/.fathom/plans/ONC-5.md')
  expect(planPath('/work/repo', '1209384756')).toBe('/work/repo/.fathom/plans/1209384756.md')
})

test('planPath refuses a ref that could leave the directory or is not a token', async () => {
  for (const ref of ['', '.', '..', '../x', 'a/b', 'a b', 'x\n', '$(id)']) {
    expect(planPath('/work/repo', ref)).toBeNull()
  }
})

test('checklistPath puts a plain ref under .fathom/tasks and refuses the refs planPath refuses', async () => {
  expect(checklistPath('/work/repo', 'ONC-5')).toBe('/work/repo/.fathom/tasks/ONC-5.md')
  expect(checklistPath('/work/repo/', 'ONC-5')).toBe('/work/repo/.fathom/tasks/ONC-5.md')
  for (const ref of ['', '.', '..', '../x', 'a/b', 'a b', 'x\n', '$(id)']) {
    expect(checklistPath('/work/repo', ref)).toBeNull()
  }
})

test('beadsPath is the .beads folder under the root, whether or not the root ends in a slash', async () => {
  expect(beadsPath('/work/repo')).toBe('/work/repo/.beads')
  expect(beadsPath('/work/repo/')).toBe('/work/repo/.beads')
})

test('a bd call or a commit may have changed the run, and other commands have not', async () => {
  for (const command of ['bd update fx-1 --claim', 'bd close fx-2', 'cd repo && bd list --json', 'git add x; bd ready', 'git commit -m "x"', 'git -C repo commit -m x']) {
    expect(touchesRun(command)).toBe(true)
  }
  for (const command of ['ls -la', 'git status', 'echo bdx', 'cat feedback.md', 'npm test', 'git commits']) {
    expect(touchesRun(command)).toBe(false)
  }
})
