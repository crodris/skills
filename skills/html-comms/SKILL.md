---
name: html-comms
description: Readable HTML documents about the work, published to a private link. Use when the user wants a plan, spec, write-up, findings, summary, report, comparison, or set of UI mocks to read outside the terminal, even when the word "plan" never comes up, or says "HTML" with no other context. Not for HTML that ships in the product.
version: 1.0.0
---

# HTML comms

Write one self-contained HTML file about the work, publish it privately, and report the link.
The page is about the work and stays out of the product: app templates, components, and marketing pages belong to the codebase.

## Document

- Write it like a spec: dense and scannable, tables and short sections over paragraphs, with no hero, decorative chrome, marketing voice, or em dashes.
- Keep it to one file with inline CSS, inline SVG, and HTTPS or data-URL images, under 100 KB. Simplify SVG and drop images to get there.
- Make it mobile-readable: a responsive viewport meta, fluid widths, and wide tables inside a horizontal-scroll wrapper.
- Support dark mode through `prefers-color-scheme`, and keep callout and tint backgrounds readable in both schemes.
- Use `<details>` for optional depth. Add a script only when interactivity earns it, and keep the page complete with scripts off.
- Add a linked table of contents once the page has 4 or more `<h2>` sections.
- Leave out secrets, tokens, private or internal URLs, and local filesystem paths, since the link can travel beyond this chat.

## Charts

Choose a visual for each section that carries data.
Tables carry relationships and charts carry magnitudes and trends, so default to a chart when the data has shape.

| Content | Visual |
|---|---|
| 2-8 quantities to compare | Bar chart |
| 2-4 series across the same categories | Grouped or stacked bar chart |
| A value changing over time | Line chart |
| Cumulative volume over time | Area chart |
| Correlation between two variables | Scatter plot |
| Parts of a whole | Donut chart |
| Magnitude across two categorical axes | Heatmap |
| Events in order, or phases with dates | Timeline |
| A process with steps or branches | Flow diagram |
| 3 or more headline metrics | Stat row |

Draw each chart as inline SVG with a `viewBox` and no fixed size.
Give it `role="img"` and `aria-labelledby` pointing at its own `<title>` and `<desc>`, with IDs unique to that figure.

## UI mocks

- Render real styled variants, not descriptions of them.
- Label them `A`, `B`, `C` and lay them side by side in one file, stacking on narrow screens.
- Iterate in that same file so the link stays the same.

## Publish

Publishing is pre-approved.
Publish every page you create or update, in auto mode too, without asking and without stopping at the local file.
Write the file outside the repository, in the session scratchpad or a temp directory, unless the user names a location.
Use the first publisher available:

1. The harness's own private publisher.
   In Claude Code that is the Artifact tool, and the artifact-design skill owns page mechanics (theme tokens, allowed CDNs, title) wherever it differs from the rules above.
   In Codex or any other harness, use the private publisher it designates.
2. here.now, through the here-now skill, when an API key is saved (anonymous Sites cannot be made private).
   Publish with its `publish.sh`, then in the same step `PATCH /api/v1/publish/{slug}/access` with `{"mode":"restricted","allowedEmails":[],"allowedDomains":[]}`, which makes the Site owner-only.
   here.now publishes as anyone-with-link by default, so `GET` the access policy and confirm the mode reads `restricted` before reporting the URL.
   If it does not, delete the Site and fall through to step 3.
   When the skill is missing, mention `npx skills@latest add heredotnow/skill -s here-now -g` once.
3. The local path, reported as unpublished.

Update in place: the same file path redeploys to the same Artifact URL, and `--slug <slug>` updates the same here.now Site.
Create a new URL only when the user asks for a separate page.

Report a link only after the publisher confirms the upload.
Open or check the page in a browser only when the user asks.
