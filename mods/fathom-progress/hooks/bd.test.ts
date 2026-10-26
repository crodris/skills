import { test, expect } from 'claude-code/testing'

import { readBd } from './bd'
import { epicEdge, noWorkspace, notJson, claimedFirst } from './fixtures'

test('readBd parses what a command printed, an empty list included', async () => {
  expect(readBd('list', { exitCode: 0, stdout: '[]', stderr: '' })).toEqual([])
  expect(readBd('count', { exitCode: 0, stdout: '{"groups":[],"total":0}', stderr: '' })).toEqual({ groups: [], total: 0 })
})

test('readBd throws bd\'s first stderr line when it exits non-zero, which is where bd puts errors even with --json', async () => {
  expect(() => readBd('list', noWorkspace)).toThrow('bd list exited 1: Error: no beads database found')
  expect(() => readBd('dep', epicEdge)).toThrow('bd dep exited 1: Error: epics can only block other epics, not tasks')
})

test('readBd names the exit code alone when bd said nothing', async () => {
  expect(() => readBd('ready', { exitCode: 2, stdout: '', stderr: '\n' })).toThrow('bd ready exited 2')
})

test('readBd refuses the text a command prints without --json instead of reading it as no issues', async () => {
  expect(notJson.exitCode).toBe(0)
  expect(() => readBd('list', notJson)).toThrow('bd list did not print JSON')
  expect(() => readBd('list', { exitCode: 0, stdout: '', stderr: '' })).toThrow('bd list did not print JSON')
})

test('readBd reads the captured bd 1.1.0 output as a list', async () => {
  const tasks = readBd('list', { exitCode: 0, stdout: JSON.stringify(claimedFirst.tasks), stderr: '' })

  expect(Array.isArray(tasks)).toBe(true)
  expect(tasks).toHaveLength(5)
})
