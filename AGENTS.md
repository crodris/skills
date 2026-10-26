# Working in this repository

These rules cover changes to the skills here, and ship's Standards reviewer checks pull requests against them.
The verify pipeline in `.ship/config.md` enforces the mechanical rules: no em or en dashes, skill frontmatter that parses, versions in step, a word budget for every skill file, and a clean SkillSpector scan.

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
`bin/sync-versions.sh` copies each plugin version into its README heading and into the `SKILL.md` frontmatter of every skill the plugin claims, and copies each standalone version into its README heading.
CI fails when running it would change a file.
`git config core.hooksPath bin/hooks` runs it before each commit.
README headings for plugins and standalone skills keep the form `### <name> (v<version>)`, since the sync finds them by it.
A skill that no plugin claims is listed under `## Standalone Skills` in the README.

Every Markdown file in `skills/` has a word budget in `bin/skill-budgets.txt`, and `bin/check-skill-size.sh` fails when a file goes over it or has none.
A trim lowers the budget in the same pull request, and raising one needs a reason in the pull request.

Credit adapted outside work in the README's License section.

## Security scanning

Change the SkillSpector commit pin in the README and in `.github/workflows/skillspector.yml` together, so a local scan and CI run the same scanner.
Suppress a finding in `.skillspector-baseline.yaml` only after you understand it, with a written reason, and scope the rule by rule id and flagged text.
