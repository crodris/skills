// What `$.process.run` resolves to: it resolves whatever the exit code is, so the
// caller checks it.
export type Run = { exitCode: number; stdout: string; stderr: string }

// The JSON a bd command printed, or an Error that says why there is none. bd prints
// its errors to stderr even with --json, so a non-zero exit has no JSON to parse,
// and a command run without --json exits 0 with text for a person. Neither is
// reported as an empty list: the band says bd is unavailable instead of zeros.
export function readBd(command: string, out: Run): unknown {
  if (out.exitCode !== 0) {
    const detail = out.stderr.trim().split('\n')[0]
    throw new Error(`bd ${command} exited ${out.exitCode}${detail ? `: ${detail}` : ''}`)
  }
  try {
    return JSON.parse(out.stdout)
  } catch {
    throw new Error(`bd ${command} did not print JSON`)
  }
}
