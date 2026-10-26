---
name: html-comms
description: Readable HTML documents about the work, published to a private link. Use when the user wants a plan, spec, write-up, findings, summary, report, comparison, or set of UI mocks to read outside the terminal, even when the word "plan" never comes up, or says "HTML" with no other context. Not for HTML that ships in the product.
version: 1.1.0
---

# HTML comms

Write one self-contained HTML file about the work, publish it with the configured publisher, and report the link, or the unpublished path with the `local` publisher.

## Document

- Make it as dense and scannable as a spec: short sections, tables, and plain statements, with no hero banner, ornament, sales tone, or em dashes.
- Inline all CSS and SVG, use HTTPS or data-URL images, and stay under 100 KB by simplifying SVG and dropping images.
- Make it mobile-readable: a responsive viewport meta, fluid widths, and wide tables inside a horizontal-scroll wrapper.
- Support dark mode through `prefers-color-scheme`, and keep callout and tint backgrounds readable in both schemes.
- Use `<details>` for optional depth.
  Add a script only when interactivity earns it, and keep the page complete with scripts off.
- Add a linked table of contents once the page has 4 or more `<h2>` sections.
- Leave out secrets, tokens, private or internal URLs, and local filesystem paths, since the link can travel beyond this chat.

## Charts

Default to a chart for each section whose data has shape, and to a table for relationships.
Pick the chart by content:

- Bar chart for 2-8 quantities to compare.
- Grouped or stacked bar chart for 2-4 series across the same categories.
- Line chart for a value changing over time.
- Area chart for cumulative volume over time.
- Scatter plot for correlation between two variables.
- Donut chart for parts of a whole.
- Heatmap for magnitude across two categorical axes.
- Timeline for events in order, or phases with dates.
- Flow diagram for a process with steps or branches.
- Stat row for 3 or more headline metrics.

Draw each chart as inline SVG with a `viewBox` and no fixed size.
Give it `role="img"` and `aria-labelledby` pointing at its own `<title>` and `<desc>`, with IDs unique to that figure.

## UI mocks

Render real styled variants, labeled with letters from `A`, side by side in one file and stacked on narrow screens.

## Publish

The publisher is the `publisher` line in `$XDG_CONFIG_HOME/html-comms/config.md`, or in `~/.config/html-comms/config.md` when that variable is unset, empty, or not an absolute path.
When the file or the line is missing, or its value is neither `harness` nor `local`, ask the user once which publisher to use, and save the answer there as `publisher: <value>`:

- `harness`: the harness's own private publisher, which in Claude Code is the Artifact tool, and in Codex or any other harness the private publisher it designates.
- `local`: write the file and report its path as unpublished.

With no user to answer, as in a delegate or headless run, use `harness` and save nothing.

Once the publisher is set, publish every page you create or update, in auto mode too, without asking.
With `harness`, a page is done only when it has a link.
Write the file in the scratchpad or a temp directory outside the repository, unless the user names a location.
With the Artifact tool, call the Skill tool with "artifact-design" first, whose page rules win where they differ from the rules above.
When the harness has no private publisher, or a publisher fails, report its error and the local path as unpublished.

Update an existing page in place, at its current URL with `harness` and at the same file path with `local`.
With the Artifact tool, publishing the same file path again updates the same URL.
Create a new URL only when the user asks for a separate page.

Report a link only after the publisher confirms the upload, and say when it opens only for the owner's signed-in account.
Open or check the page in a browser only when the user asks.
