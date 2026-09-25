---
name: frontend-design-pipeline
description: This skill should be used when the user asks to design and build a new UI, landing page, app screen, or visual identity, or to redesign an existing one, and wants to choose between design directions before anything is built. Also use when the user says "design pipeline", "frontend design pipeline", "give me design directions", or "run the full design flow", or asks to refine a UI that already has a DESIGN.md through the same flow. It chains the ui-ux-pro-max, taste-skill, emil-design-eng, and impeccable skills in a fixed order and stops once for the user to pick a direction.
version: 1.0.0
---

# Frontend design pipeline

Take a UI from product idea to finished build through installed design skills, in a fixed order, with one added stop for the user to pick a direction.

This skill carries no design knowledge of its own.
Every stage except the pick invokes another skill and follows that skill's instructions, except where this file overrides them.

## Companion skills

| Stage | Skill | Install |
|-------|-------|---------|
| 1 | `ui-ux-pro-max` | `npx skills@latest add nextlevelbuilder/ui-ux-pro-max-skill -s ui-ux-pro-max -g` |
| 2 | one of `minimalist-ui`, `high-end-visual-design`, `industrial-brutalist-ui`, `gpt-taste`, `design-taste-frontend`, `redesign-existing-projects` | `npx skills@latest add Leonxlnx/taste-skill -s <preset> -g` |
| 4 | `emil-design-eng` | `npx skills@latest add emilkowalski/skills -s emil-design-eng -g` |
| 5 | `impeccable` | `npx skills@latest add pbakaus/impeccable -s impeccable -g` |

Impeccable is required.
When it is missing, stop before any stage and give its install command.

The others are optional.
When one is missing, skip its stage, say so once with its install command, and continue.
Without ui-ux-pro-max, stage 2 builds each brief from its preset and PRODUCT.md alone.
Without any taste preset, stage 3 offers the stage 1 candidates as the briefs.
With neither, skip stage 3 too.

## Precedence

User instructions beat DESIGN.md.
DESIGN.md beats everything the earlier stages produced: ui-ux-pro-max candidates, any `design-system/` MASTER.md, and taste-skill rules, including their hard bans.
A preset that says "never Inter" loses to a DESIGN.md that picked Inter.
Impeccable builds last and makes the final call on anything DESIGN.md leaves open.

## Routing

Pick the entry stage before anything else.

- **No visual world yet, or a redesign that replaces the current look:** start at stage 1.
- **Work inside the current look, whether a new page or a refinement:** skip stages 1-3. Start at stage 4 when the change touches motion or interaction, otherwise at stage 5.

The current look is DESIGN.md when it exists, and otherwise the incumbent code.
When the request does not say whether the current look stays, ask once.

## 1. Options (ui-ux-pro-max)

When PRODUCT.md is missing, invoke the impeccable skill's `init` first, since impeccable's new-work flow requires one.
Feed PRODUCT.md into the stage 1 queries and the stage 2 briefs.

Invoke the ui-ux-pro-max skill and generate 2-3 candidate design systems for the product type with `--design-system`.
Vary the query keywords or the `--variance`, `--motion`, and `--density` sliders between runs so the candidates differ.

Its SKILL.md builds the script path from `${CLAUDE_PLUGIN_ROOT}`, which exists only inside Claude Code plugins.
Run `scripts/search.py` from the directory that holds ui-ux-pro-max's own SKILL.md instead, with `python3`, or `python` where `python3` is missing.
Do not pass `--persist`.

## 2. Direction (taste-skill)

For each candidate, invoke exactly one taste-skill preset and turn the candidate into a direction brief.
Never apply two presets to one candidate, because they contradict each other: minimalist-ui bans gradients, and gpt-taste is built on GSAP.
Pick a different preset per candidate where the product allows it, so the briefs differ.
On a redesign, replace one candidate's preset with redesign-existing-projects.
Take the preset's rules only and build nothing in this stage.

Each brief states palette, type, layout, and motion stance in a few lines.
Present the briefs to the user labelled with letters.

## 3. Pick (user)

Wait for the user to pick one brief or combine them, as in "B's type with A's palette".
When a combined pick names no layout, ask in the same question which brief's layout to keep.
This is the only stop the pipeline adds, and the skills it invokes still ask their own questions.
When DESIGN.md already exists, say in the same question that the pick replaces it, and keep the old file unless the user confirms.
If they decline, stop before stage 4.

Write the result to DESIGN.md at the project root, in the seed format that impeccable's `reference/document.md` defines under Seed mode, SEED marker included.
DESIGN.md takes only what holds on every screen.
The pick's page-specific layout goes to impeccable in stage 5, for its surface brief.
From here on DESIGN.md is the authority, and the candidates and any MASTER.md are not read again.

## 4. Motion (emil-design-eng)

Invoke the emil-design-eng skill for the picked direction or the current look.
Decide what animates and what does not, the easing, and the durations.
After stage 3, add the decisions to the Overview section of DESIGN.md, since the seed format has no motion section and omits Components.
When stage 3 did not run, pass them to stage 5 instead, and change DESIGN.md only when the user asks for a system-wide change.

## 5. Build and finish (impeccable)

Invoke the impeccable skill last, every time.

After stage 3, build to DESIGN.md.
Tell it DESIGN.md is an established world the user pinned, so its new-work flow creates the surface inside that world instead of creating or replacing one.
Pass the pick's layout as the user-pinned structure for this surface, so it skips its surface structure round.
On a redesign, also tell it the DESIGN.md world replaces the incumbent look in the code.

When routing skipped stages 1-3, tell it to work inside the current look, and whether the change is a refinement or a new page.

When stage 3 did not run because nothing was installed to produce briefs, let impeccable's new-work flow choose the world with the user.

Then run impeccable's `critique` and `polish` on the result.
