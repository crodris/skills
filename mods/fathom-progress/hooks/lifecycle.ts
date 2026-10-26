import type { Snapshot } from '../types'
import { startScaffold } from './scaffold'

// The small decisions the lifecycle in register.tsx makes, pulled out so they can be
// tested: register.tsx reads engine state, which is empty in a test, so none of its
// own code can be.

// The skills that start a Fathom run, and which of the two one is. The engine reports
// a skill as `plugin:skill` (`fathom:execute`, seen in the probe,
// claude-mods-fathom-5l2.2); a bare name is accepted too, since the Skill tool takes
// whatever the model passes. `review` and `ship` do not start a run, and the plugin's
// internal `fathom-shared` is never invoked.
//
// Only execute writes beads, so only execute has a run to find: scaffold arms no poll,
// which also keeps the band from showing some older open run as if scaffold had started
// it.
export function startOf(skill: string): 'execute' | 'scaffold' | null {
  const [, , name] = /^(fathom:)?(execute|scaffold)$/.exec(skill) ?? []
  return name === 'execute' || name === 'scaffold' ? name : null
}

// The same, for a prompt as typed. A Team organization's built-in security plugin answers
// `skill.prompt` itself and skips every user mod, so the band cannot rely on it
// (claude-mods-fathom-5l2.5): `prompt.submit` and the Skill tool's `tool.call` are not
// skipped, and between them they carry both ways a skill starts. Only a slash command
// with the plugin prefix counts: a bare `/execute` may be another plugin's, and a false
// start would leave the band on `starting` until the session ends.
export function startOfPrompt(text: string): 'execute' | 'scaffold' | null {
  const [, name] = /^\s*\/(fathom:(?:execute|scaffold))(?=\s|$)/.exec(text) ?? []
  return name === undefined ? null : startOf(name)
}

// What the band shows the moment a Fathom skill starts. Execute shows `starting` until
// its epic exists, and the poll then takes over. Scaffold has no epic to wait for and
// nothing polls for it: it starts on its first phase, and the events of the run move it on
// (scaffold.ts). That also replaces a finished run's band from before.
export function snapshotOnStart(start: 'execute' | 'scaffold'): Snapshot {
  return start === 'execute' ? { kind: 'starting' } : startScaffold()
}

// The issue refs in some text, in order and upper-cased, the way a tracker keys them
// (`PHA-352`, `ONC-5`). A token with a hyphen or a letter in front of it (`the-3` in a
// URL's slug) or a letter after it is not one; a hyphen after it is, since a branch name
// goes on with a slug (`feat/pha-352-relabel`).
const REF = /(^|[^A-Za-z0-9-])([A-Za-z][A-Za-z0-9]{1,9}-\d+)(?![A-Za-z0-9])/g

export function refsIn(text: string): string[] {
  const refs: string[] = []
  for (const match of text.matchAll(REF)) {
    const ref = (match[2] ?? '').toUpperCase()
    if (ref && !refs.includes(ref)) refs.push(ref)
  }
  return refs
}

// The refs a person typed after a Fathom command (`/fathom:execute pha-352`, or the URL
// of the issue); none for any other prompt, or a command with no arguments.
export function refsOfPrompt(text: string): string[] {
  return startOfPrompt(text) === null ? [] : refsIn(text.replace(/^\s*\/fathom:\w+/, ''))
}

// The ref a branch is named for, which is how Fathom itself finds the issue it resumes
// (`feat/pha-352-relabel-results-view-control`): only the first, and none for a branch
// with no ref in it (`main`, `wip-phase-3`).
export function refsOfBranch(branch: string): string[] {
  return refsIn(branch).slice(0, 1)
}

// A run's record under .fathom/<dir>/<ref>.md in the session's root. A ref that could
// leave that directory, or is not a plain token, has no record to read.
function recordPath(root: string, dir: 'plans' | 'tasks', ref: string): string | null {
  return /^[\w.-]+$/.test(ref) && ref !== '.' && ref !== '..'
    ? `${root.replace(/\/+$/, '')}/.fathom/${dir}/${ref}.md`
    : null
}

// The folder beads keeps its workspace in. A repository without it does not use beads.
export function beadsPath(root: string): string {
  return `${root.replace(/\/+$/, '')}/.beads`
}

// The plan document of a run: .fathom/plans/<ref>.md.
export function planPath(root: string, ref: string): string | null {
  return recordPath(root, 'plans', ref)
}

// The checklist of a run on the checklist memory backend: .fathom/tasks/<ref>.md.
export function checklistPath(root: string, ref: string): string | null {
  return recordPath(root, 'tasks', ref)
}

// A Bash command that may have changed what bd or the plan document holds: a bd call,
// or a commit (the plan document is committed with the breakdown, and each task with
// its own commit). The band refreshes after it instead of waiting for the next poll.
// A match that is not one, such as `git log --grep commit`, only costs a refresh.
export function touchesRun(command: string): boolean {
  return /(^|[\s;&|(])bd\s/.test(command) || /\bgit\b[^;&|\n]*\bcommit\b/.test(command)
}

// How often the band re-reads bd while armed. A bd call costs about 0.65s here, so
// one refresh is about 2s of work; 10s keeps that to a fifth of a core at worst.
export const POLL_MS = 10_000
