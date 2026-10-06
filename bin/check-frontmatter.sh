#!/usr/bin/env bash
# check-frontmatter.sh - fail when a skill's SKILL.md frontmatter does not parse
# as YAML, or when an unquoted " #" cuts its description short. An unquoted
# ": " in a value is a parse error, and an unquoted " #" starts a comment that
# silently ends the value; either way the skills CLI skips the skill or loads a
# truncated description.
# Untracked files count too, so verify catches a new skill before it is committed.
#
# Parses with the yaml npm package the skills CLI uses, pinned so a new release
# cannot change what passes here; bump it deliberately.
# Requires node, npm, and network access; installs yaml into a temporary directory.

set -euo pipefail

cd "$(dirname "$0")/.."

deps=$(mktemp -d)
trap 'rm -rf "$deps"' EXIT
npm install --loglevel=error --no-audit --no-fund --prefix "$deps" yaml@2.9.1 >/dev/null ||
  { echo "check-frontmatter: could not install yaml from npm" >&2; exit 2; }

git ls-files -z --cached --others --exclude-standard -- 'skills/*/SKILL.md' |
  NODE_PATH="$deps/node_modules" node -e '
const fs = require("fs");
const YAML = require("yaml");
let hits = 0;
for (const path of fs.readFileSync(0, "utf8").split("\0").filter(Boolean)) {
  if (!fs.existsSync(path)) continue;
  const fail = (why) => { console.log(`${path}: ${why}`); hits++; };
  // The same frontmatter pattern the skills CLI uses.
  const front = fs.readFileSync(path, "utf8").match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!front) { fail("no frontmatter"); continue; }
  const doc = YAML.parseDocument(front[1]);
  if (doc.errors.length) { fail(doc.errors[0].message.split("\n")[0]); continue; }
  const node = doc.get("description", true);
  if (!node || typeof node.value !== "string" || !node.value) { fail("no description"); continue; }
  // A plain scalar cannot hold " #", so one in its written lines is a comment that cut it short.
  const written = (front[1].match(/^description:(.*(?:\r?\n(?:[ \t]+.*|[ \t]*(?=\r?\n)))*)/m) || [, ""])[1];
  if (node.type === "PLAIN" && /(^|[ \t\r\n])#/.test(written))
    fail(`an unquoted " #" cuts the description short after "...${node.value.slice(-40)}"`);
}
if (hits) {
  console.error(`${hits} skill(s) with broken frontmatter. Reword, or quote the whole value.`);
  process.exit(1);
}
'
