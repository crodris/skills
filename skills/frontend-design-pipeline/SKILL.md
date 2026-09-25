---
name: frontend-design-pipeline
description: This skill should be used when the user asks to design and build a new UI, landing page, app screen, or visual identity, or to redesign an existing one, and wants to choose between design directions before anything is built. Also use when the user says "design pipeline", "frontend design pipeline", "give me design directions", or "run the full design flow", or asks to refine a UI that already has a DESIGN.md through the same flow. It chains the ui-ux-pro-max, taste-skill, emil-design-eng, and impeccable skills in a fixed order and stops once for the user to pick a direction.
version: 1.0.0
---

# Frontend design pipeline

Take a UI from product idea to finished build through four installed skills, in a fixed order, with one stop for the user to pick a direction.

This skill carries no design knowledge of its own.
Each stage invokes another skill and follows that skill's instructions, except where this file overrides them.

## Required skills

| Stage | Skill | Source |
|-------|-------|--------|
| 1 | `ui-ux-pro-max` | `nextlevelbuilder/ui-ux-pro-max-skill` |
| 2 | one of `minimalist-ui`, `high-end-visual-design`, `industrial-brutalist-ui`, `gpt-taste`, `design-taste-frontend`, `redesign-existing-projects` | `Leonxlnx/taste-skill` |
| 4 | `emil-design-eng` | `emilkowalski/skills` |
| 5 | `impeccable` | `pbakaus/impeccable` |

When a skill a stage needs is not installed, stop and name it with its source.

## Precedence

User instructions beat DESIGN.md.
DESIGN.md beats everything the earlier stages produced: ui-ux-pro-max candidates, any `design-system/` MASTER.md, and taste-skill rules, including their hard bans.
A preset that says "never Inter" loses to a DESIGN.md that picked Inter.
Impeccable builds last and makes the final call on anything DESIGN.md leaves open.

## Routing

Pick the entry stage before anything else.

- **New UI, or a redesign that replaces the current look:** start at stage 1.
- **Refinement that keeps the current look:** skip stages 1-3. Start at stage 4 when the change touches motion or interaction, otherwise at stage 5. An existing DESIGN.md is the brief; without one, impeccable works from the incumbent code.

When the request does not say whether the current look stays, ask once.

## 1. Options (ui-ux-pro-max)

Invoke the ui-ux-pro-max skill and generate 2-3 candidate design systems for the product type with `--design-system`.
Vary the query keywords or the `--variance`, `--motion`, and `--density` sliders between runs so the candidates differ.

Its SKILL.md builds the script path from `${CLAUDE_PLUGIN_ROOT}`, which exists only inside Claude Code plugins.
Run `scripts/search.py` from the directory that holds ui-ux-pro-max's own SKILL.md instead, with `python3`, or `python` where `python3` is missing.
Do not pass `--persist`.

## 2. Direction (taste-skill)

For each candidate, invoke exactly one taste-skill preset and turn the candidate into a direction brief.
Never apply two presets to one candidate, because they contradict each other: minimalist-ui bans gradients, and gpt-taste is built on GSAP.
Pick a different preset per candidate where the product allows it, so the briefs differ.
On a redesign, use redesign-existing-projects in place of a preset.
Take the preset's rules only and build nothing in this stage.

Each brief states palette, type, layout, and motion stance in a few lines.
Present the briefs to the user labelled A, B, and C.

## 3. Pick (user)

Wait for the user to pick one brief or combine them, as in "B's type with A's palette".
This is the only stage that waits for the user.

Write the result to DESIGN.md at the project root, in the seed format that impeccable's `reference/document.md` defines under Seed mode, SEED marker included.
From here on DESIGN.md is the authority, and the candidates, briefs, and any MASTER.md are not read again.

## 4. Motion (emil-design-eng)

Invoke the emil-design-eng skill for the picked direction.
Decide what animates and what does not, the easing, and the durations.
Add the decisions to DESIGN.md, the motion grammar in Overview and per-component interaction in Components, since the format has no motion section.

## 5. Build and finish (impeccable)

Invoke the impeccable skill last, every time, and build to DESIGN.md.
Tell it the visual world is settled in DESIGN.md, so it inherits that world instead of choosing a new one.
Then run impeccable's `critique` and `polish` on the result.
