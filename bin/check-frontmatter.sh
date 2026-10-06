#!/usr/bin/env bash
# check-frontmatter.sh - fail when a skill's SKILL.md frontmatter does not parse
# as YAML, or when its description parses shorter than it is written. An
# unquoted ": " in a value is a parse error, and an unquoted " #" starts a
# comment that silently cuts the description short; either way the skills CLI
# skips the skill or loads a truncated description.
# Untracked files count too, so verify catches a new skill before it is committed.
#
# Parses with the yaml npm package, the one the skills CLI uses.
# Requires node and npm; installs yaml into a temporary directory on each run.

set -euo pipefail

cd "$(dirname "$0")/.."

deps=$(mktemp -d)
trap 'rm -rf "$deps"' EXIT
npm install --silent --no-audit --no-fund --prefix "$deps" yaml@2 >/dev/null

git ls-files -z --cached --others --exclude-standard -- 'skills/*/SKILL.md' |
  NODE_PATH="$deps/node_modules" node -e '
const fs = require("fs");
const YAML = require("yaml");
let hits = 0;
for (const path of fs.readFileSync(0, "utf8").split("\0").filter(Boolean)) {
  const fail = (why) => { console.log(`${path}: ${why}`); hits++; };
  const front = fs.readFileSync(path, "utf8").match(/^---\n([\s\S]*?)\n---\n/);
  if (!front) { fail("no frontmatter"); continue; }
  const doc = YAML.parseDocument(front[1]);
  if (doc.errors.length) { fail(doc.errors[0].message.split("\n")[0]); continue; }
  const description = doc.get("description");
  const written = (front[1].match(/^description:[ \t]*(.*)$/m) || [, ""])[1].trim();
  if (typeof description !== "string" || !description) fail("no description");
  else if (!/^["\x27|>]/.test(written) && description !== written)
    fail(`description is cut short after "...${description.slice(-40)}"`);
}
if (hits) {
  console.error(`${hits} skill(s) with broken frontmatter. Reword, or quote the whole value.`);
  process.exit(1);
}
'
