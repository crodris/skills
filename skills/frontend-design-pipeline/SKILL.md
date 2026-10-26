---
name: frontend-design-pipeline
description: This skill should be used when the user asks to design and build a new UI, landing page, app screen, or visual identity, or to redesign an existing one, and wants to choose between design directions before anything is built. Also use when the user says "design pipeline", "frontend design pipeline", "give me design directions", or "run the full design flow", or asks to refine a UI that already has a DESIGN.md through the same flow. It chains the ui-ux-pro-max, taste-skill, frontend-design, emil-design-eng, and impeccable skills in a fixed order and stops once for the user to pick a direction from rendered mocks.
version: 1.3.1
---

# Frontend design pipeline

Take a UI from product idea to finished build through installed design skills, in a fixed order, with one added stop where the user picks a direction from rendered mocks.
Every stage invokes its skill and follows that skill's instructions, except where this file overrides them.

## Companion skills

| Stage | Skill | Source |
|-------|-------|--------|
| 1 | `ui-ux-pro-max` | nextlevelbuilder/ui-ux-pro-max-skill |
| 2 | `design-taste-frontend` | Leonxlnx/taste-skill |
| 2 | `frontend-design` | anthropics/skills |
| 3 | `html-comms` | crodris/skills |
| 4 | `emil-design-eng` | emilkowalski/skills |
| 5 | `impeccable` | pbakaus/impeccable |

A skill's install command is `npx skills@latest add <source> -s <skill> -g`.
Never run an install command yourself.

Check for impeccable before routing.
When it is missing, stop and give its install command.
When another skill is missing, skip its part, give its install command once, and continue.

## Precedence

User instructions beat DESIGN.md.
DESIGN.md beats everything the earlier stages produced: ui-ux-pro-max candidates, any `design-system/` MASTER.md, frontend-design guidance, and taste-skill rules including their hard bans.
Impeccable builds last and decides anything DESIGN.md leaves open.

## Routing

After the impeccable check, pick the entry stage.

- **No visual world yet, or a redesign that replaces the current look:** take the stage 1 route.
  When PRODUCT.md is missing, call the Skill tool with "impeccable" and run its `init` first.
  Then read `directions.md` in this folder and run its stages 1-3.
- **Work inside the current look, whether a new page or a refinement:** skip stages 1-3.
  Start at stage 4 when the change touches motion or interaction, otherwise at stage 5.

The current look is DESIGN.md when it exists, and otherwise the incumbent code.
When the request does not say whether the current look stays, ask once.

## 4. Motion (emil-design-eng)

Call the Skill tool with "emil-design-eng" for the picked direction or the current look, and decide what animates, the easing, and the durations.
After stage 3, add the decisions to the Overview section of DESIGN.md, since the seed format has no motion section.
When stage 3 did not run, pass them to stage 5 instead, and change DESIGN.md only when the user asks for a system-wide change.

## 5. Build and finish (impeccable)

Call the Skill tool with "impeccable" last, every time.

- **After stage 3:** tell it DESIGN.md is an established world the user pinned, so its new-work flow builds the surface inside that world.
  Pass the pick's layout as the user-pinned structure for this surface, so it skips its surface structure round.
  On a redesign, also tell it the DESIGN.md world replaces the incumbent look in the code.
- **When routing skipped stages 1-3:** tell it to work inside the current look, and whether the change is a refinement or a new page.
- **When the stage 1 route produced no briefs:** let its new-work flow choose the world with the user, and on a redesign say the current look is being replaced.

Then run impeccable's `critique` and `polish` on the result.
When stage 3 wrote the seed, finish with impeccable's `document` in scan mode, told to merge.
The scanned tokens replace the seed, the SEED marker and placeholders are dropped, and the stage 4 motion decisions in Overview carry over.
