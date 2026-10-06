# Coding standards

Ship's Standards reviewer reads this file during review.
It holds the judgment calls only.
The mechanical rules are checks in the verify pipeline in `.ship/config.md`: `bin/check-dashes.sh` bans em and en dashes, `bin/check-frontmatter.sh` fails when a skill's frontmatter does not parse as YAML or its description is cut short, `bin/sync-versions.sh` keeps versions in step and every skill claimed, and `bin/scan-skills.sh` scans each skill with SkillSpector.

## Skill prose

An agent follows a skill literally, so every step must be something an agent can carry out as written.
Before adding a rule, grep `skills/` for its key terms and resolve any rule it would contradict.

Each rule lives in one file.
Another file that needs it points to it by path and does not restate it.
The Fathom contracts in `skills/fathom-shared/` (trackers, forges, memory, conventions, approval) are defined only there.

A contract row says what the operation does, not which skill calls it.

Fathom skills stay agent-neutral.
Tool names, model names, and other per-agent details go in `skills/fathom-shared/agents.md`.

Material that only some runs reach goes in a disclosed file behind a pointer, such as `execute/fan-out.md` or `ship/lanes.md`.
The main `SKILL.md` keeps what every run needs.

Keep a reason only when a rule is easy to misread, or likely to be simplified wrongly, without it.

Write one sentence per line in Markdown, in plain declarative sentences, with one term per concept.

## What ships with a skill change

Update `README.md` and `docs/fathom.md` wherever they describe the changed behavior.

Update the version in the same pull request.
Plugin skills take theirs from `.claude-plugin/marketplace.json`, which `bin/sync-versions.sh` copies into the README.
Standalone skills carry theirs in the `SKILL.md` frontmatter and the README heading.

Credit adapted outside work in the README's License section.
