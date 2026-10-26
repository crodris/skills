# Stages 1-3 of the frontend design pipeline

These stages run on the stage 1 route only.
They produce direction briefs, show them as rendered mocks, and write the user's pick to DESIGN.md.
Feed PRODUCT.md into the stage 1 queries and the stage 2 briefs.

## When a stage's skill is missing

- Stage 2 runs when design-taste-frontend or frontend-design is installed.
- Without ui-ux-pro-max, stage 2 starts from 2-3 distinct candidates drawn from PRODUCT.md.
- When stage 2 cannot run, condense each stage 1 candidate into the brief shape stage 2 defines.
- When neither stage 1 nor stage 2 can run, skip stages 3 and 4 and go to stage 5.
- Without html-comms, publish the stage 3 page with the harness's private publisher, or report its local path when there is none.

## 1. Options (ui-ux-pro-max)

Run the Skill tool and `scripts/search.py` in this section only when ui-ux-pro-max is installed.
Otherwise build the candidates from PRODUCT.md, as When a stage's skill is missing says, and skip the rest of this section.
Call the Skill tool with "ui-ux-pro-max" and generate 2-3 candidate design systems for the product type with `--design-system`.
Vary the query keywords or the `--variance`, `--motion`, and `--density` sliders between runs so the candidates differ.
Run `scripts/search.py` from the directory that holds ui-ux-pro-max's own SKILL.md, not from `${CLAUDE_PLUGIN_ROOT}`, with `python3`, or `python` where `python3` is missing.
Do not pass `--persist`.

## 2. Direction (taste-skill, frontend-design)

For each candidate, call the Skill tool with each of "design-taste-frontend" and "frontend-design" that is installed, in that order, and turn the candidate into a direction brief.
Deal each candidate a different direction with design-taste-frontend's `draw.mjs --options 3`, passing `--keep palette,type` when the candidate already fixes them.
Give a candidate a classic taste preset (minimalist-ui, high-end-visual-design, industrial-brutalist-ui, gpt-taste) only when the user ran that preset in this session, and deal that candidate no direction.
Run frontend-design's plan pass on each brief, grounding it in the product's subject and revising whatever reads as one of that skill's generic defaults.
When design-taste-frontend is missing, the plan pass alone makes each brief, and when frontend-design is missing, design-taste-frontend's direction alone makes it.
Within a brief, the preset's rules beat frontend-design's list of generic defaults.
Take only briefs from this stage, since stage 3 builds the mocks.

Each brief states palette, type, layout, and motion stance in a few lines.

## 3. Mock and pick (html-comms, user)

Build each brief as a static HTML mock of the requested screen with the product's real content, and label the mocks with letters.
When the screen exists, add a Current panel: a screenshot of the running app without browser chrome and with demo data, or a rebuild from its code when the app cannot run.
Render each mock and the Current rebuild in its own `<iframe srcdoc>` at the screen's real viewport width, scaled with a CSS `transform` to fit its column.
Call the Skill tool with "html-comms" and put everything on one page through it, or, without html-comms, build the one page directly and publish it as the missing-skill fallback above says.
Its Document rules govern the page around the mocks, and the mocks and the screenshot are exempt from its 100 KB cap.
Report the link, or with `publisher: local` the path as unpublished, with one line per brief.

Then wait for the user to pick one brief or combine them, as in "B's type with A's palette".
When a combined pick names no layout, ask which brief's layout to keep.
This is the only stop the pipeline adds, and the invoked skills still ask their own questions.
When DESIGN.md already exists, say in the same question that the pick replaces it, and keep the old file unless the user confirms.
If they decline, stop before stage 4.

Write the pick to DESIGN.md at the project root, in the Seed mode format of impeccable's `reference/document.md`, SEED marker included.
DESIGN.md takes only what holds on every screen, and the pick's page-specific layout goes to stage 5.
From here on DESIGN.md is the authority, and the candidates and any MASTER.md are not read again.
