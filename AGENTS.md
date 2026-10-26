# Working in this repository

These rules cover changes to the skills here, and ship's Standards reviewer checks pull requests against them.
The verify pipeline in `.ship/config.md` enforces the mechanical rules: no em or en dashes, skill frontmatter that parses, versions in step, and a clean SkillSpector scan.

## Skill prose

An agent follows a skill literally, so every step must be something an agent can carry out as written.
Before adding a rule, grep `skills/` for its key terms and resolve any rule it would contradict.

Each rule lives in one file.
Another file that needs it points to it by path and does not restate it.
The Fathom contracts in `skills/fathom-shared/` are defined only there, and a contract row says what the operation does, not which skill calls it.

Fathom skills stay agent-neutral.
Tool names, model names, and other per-agent details go in `skills/fathom-shared/agents.md`.

Material that only some runs need goes in a separate file behind a pointer, such as `execute/fan-out.md`.
The main `SKILL.md` keeps what every run needs.

Keep a reason only when a rule is easy to misread without it.
Write one sentence per line, in plain declarative sentences, with one term per concept.

## What ships with a skill change

Update `README.md` and `skills/execute/README.md` wherever they describe the changed behavior.

Update the version in the same pull request.
Plugin skills take theirs from `.claude-plugin/marketplace.json`, and standalone skills from their `SKILL.md` frontmatter.
`bin/sync-versions.sh` copies them into the README, and CI fails when running it would change a file.
`git config core.hooksPath bin/hooks` runs it before each commit.
A skill that no plugin claims is listed under `## Standalone Skills` in the README.

Credit adapted outside work in the README's License section.
