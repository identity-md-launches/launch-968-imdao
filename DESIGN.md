# IMDAO design system

## Overview

IMDAO is a community space for developing ideas, understanding decisions and following work. The implemented Soft Studio direction uses a centered home hero, generous spacing, rounded navigation and three quiet cards. Ideas, read-only examples and private drafts remain visibly distinct. Other routes use a left-aligned introduction and the same shell, surfaces and controls.

The source of truth is `web/src/style.css`; shared elements are in `web/src/components.tsx`. Both themes have identical structure and content. No decorative charts, illustrations, animation or remote assets are used.

## Colors

Tokens use hex values and semantic roles. The only theme selector is `html[data-theme="dark"]`.

| Token / role | Sage Light | Graphite Dark |
| --- | --- | --- |
| `--bg` page | `#edf1e9` | `#171b1d` |
| `--text` primary text | `#23372b` | `#edf0e9` |
| `--secondary` secondary text on cards | `#617364` | `#acb9ad` |
| `--muted` secondary text on page | `#5f7162` | `#acb9ad` |
| `--nav` navigation / neutral controls | `#ffffff` | `#262d30` |
| `--card` first surface | `#fffdf7` | `#22282a` |
| `--card-alt` second surface | `#fafcf7` | `#252b2e` |
| `--card-third` third surface | `#f6faf2` | `#242d29` |
| `--accent` quiet primary accent | `#c8ddbb` | `#bad5b2` |
| `--selected` selected controls / notices | `#dce7d3` | `#35453a` |
| `--badge` status badge | `#e4ebdf` | `#2f3832` |
| `--brand` logo foreground | `#202822` | `#e7eee6` |
| `--primary` strong action | `#23372b` | `#bad5b2` |
| `--on-primary` strong action text | `#ffffff` | `#23372b` |
| `--on-accent` pale button text | `#23372b` | `#23372b` |
| `--border` structural separator | `#c6d0c0` | `#435147` |
| `--input-border` field boundary | `#7b8b7d` | `#7f9587` |
| `--focus` keyboard outline | `#385d3e` | `#bad5b2` |
| `--error` destructive / error text | `#96352a` | `#ffb4a8` |

The specified light secondary color is retained on cards, where the measured first-card contrast is **4.98:1**. On the page background it measured **4.43:1**, below the 4.5:1 threshold for normal text. Page secondary text therefore uses the narrowly adjusted `#5f7162`, measured **4.56:1**. `.surface` and `.idea-card` locally reset `--muted` to `--secondary`. Dark page secondary text measures **8.50:1**. Measurements, including actual computed background pairs, are in `docs/frontend/interaction-results.json`.

`web/index.html` selects the system or valid remembered theme synchronously before rendering. `App.tsx` handles the toggle, system changes when no override exists, and a session-only preference if storage fails. Themes do not animate. Forced-colors mode uses system colors for focus and visible borders.

## Typography

Body: Arial, Helvetica, sans-serif; 16px root and unitless 1.6 line height. Regular and semibold weights distinguish prose and emphasis. Headings use 500 weight, balanced wrapping and tighter line heights; body descriptions use pretty wrapping. Long prose stays near 70ch. User-entered content wraps and preserves line breaks; no HTML is injected or content truncated.

Labels and journey steps use the complete **IBM Plex Mono Medium (500)** font, bundled as `web/public/fonts/IBMPlexMono-Medium.woff2`. It contains 930 mapped characters and was losslessly converted from the upstream TTF to WOFF2 without subsetting. The OFL license ships in `web/public/licenses/IBM-Plex-Mono-OFL.txt` and the export. This is not an IMDAO-only character subset. The generic monospace entry is an emergency UI fallback, not a substitute used to construct the logo.

- Hero: `clamp(3.4rem, 6.2vw, 5rem)`, line height 1.06, tracking −0.055em; 3.8rem below 760px, 2.9rem below 440px.
- Other h1: `clamp(2.3rem, 5vw, 3.5rem)`, line height 1.12, tracking −0.045em.
- h2: 1.7rem, line height 1.2; detailed sections use 1.45rem.
- Card title: 1.6rem, line height 1.22; starter title: 1.25rem.
- Supporting copy: 0.875rem; restrained mono eyebrow: 0.6875rem, tracking 0.075em.
- Inputs: 1rem, including mobile; numeric treasury values use tabular numerals.

The inline `Logo` is the approved A / Signal Mono reconstruction: lockup viewBox `0 0 379.5 120`, nine 4×4 squares at the Cartesian product of 0, 7, 14; opacity 0.25 only at (0,7) and (7,14). The symbol transforms by `translate(24 33) scale(3)`. Text is IBM Plex Mono 500 at x=106, baseline y=90, size 84.507 and letter spacing −2. The entire SVG scales uniformly. The home link supplies the navigation name; the SVG has its own IMDAO label.

## Layout

The content container is at most 1200px with 48px desktop gutters. The header uses three columns: logo, centered pill navigation, actions. The home hero precedes the community feed, then the separate four-starter section. The starter section has a 40px inset above it and a single structural separator. Standard gaps are 12–24px within groups and 32–74px between major groups.

- At 1100px and below: 32px gutters, navigation moves to its own centered row, starters become two columns, filter search occupies a full row.
- At 900px and below: draft form and contextual aside become one column; the navigation can use the available width.
- At 760px and below: 24px gutters; community/project cards, detail columns and paired surfaces stack. Header navigation remains fully visible.
- At 440px and below: 20px gutters; starters stack; treasury table becomes labeled rows while retaining native table headings; smaller controls wrap rather than clip.
- At 1500px and above: the hero gets extra vertical space while the content width stays bounded.

Reflow was checked at 320, 375, 768 and 1440 CSS pixels in both themes on nine representative routes. No horizontal page overflow was observed. A 200% root-text-size check at 768px also passed; this is not a claim of native browser zoom coverage.

## Elevation & depth

Surfaces are flat and separated by tone and whitespace. Hover adds a one-pixel inset boundary to navigable cards. Borders define fields and ledger rows. There are no persistent shadows, sticky overlays or custom modal layers. Destructive and unsaved-work confirmations use native browser dialogs.

## Shapes

`--radius: 24px` is used by cards, standard surfaces and empty states. Controls use 30px pill radii; navigation uses 40px. Notices and discussion prompts use 16px, and fields use 10–12px. The logo's square geometry must stay square.

## Components

`web/src/components.tsx` provides `Logo`, `Icon`, `Badge`, `Notice`, `PageIntro`, `Missing`, `DetailSection` and `Journey`. Icons are local inline strokes, use `currentColor` and are hidden from assistive technology when decorative.

`App.tsx` owns the shell, hash navigation, theme state and local draft list. Internal links remain actual anchors and support opening a separate tab. Normal in-page navigation protects dirty editors; browser Back and reload are protected too. New routes move focus to their heading. The first skip link moves focus to the main landmark.

`pages.tsx` provides reusable card/feed, starter, detail, milestone, decision and ledger patterns. Filters use native search/select controls; counts use a polite status region. Empty results offer a clear-filter action. Missing records offer routes back to ideas and drafts. Starter disclosures use native details/summary.

`Editor.tsx` reuses a labeled field pattern with inline instructions, required cues, `aria-invalid`, error descriptions and first-error focus. Edit and preview buttons expose `aria-pressed`; preview reports missing content as “Not specified”. Save remains enabled so validation can explain what is needed. The save status appears only after successful persistence. Error notices remain visible and explain recovery. Deletion and replacement require confirmation.

All interactive controls have a 3px visible keyboard outline with a 5px offset. Most buttons are at least 44px tall. States always include text, rather than relying on color. There is no animated or loading state to simulate.

## Do’s and don’ts

- Add a page through the existing shell, `PageIntro`, surfaces and semantic color tokens. Keep exactly one h1 per rendered page.
- Keep ideas, template examples, governance fixtures and private drafts separate. Do not count templates as votes or live activity.
- Use dark text on pale buttons. Keep the page/card secondary-text distinction so small text stays readable.
- Preserve the logo geometry and full local font. Do not approximate the mark with bars or substitute another face.
- Keep user input as React text. Keep an absent operator or budget unspecified.
- Add future data through typed records rather than embedding a service call into a card. Backend/onchain integration and security review are separate work.

Applied guidance: Jakub Krehel’s Better Interface (MIT, pinned commit `267330e1adfc66a718fb65fa6918c1f06d0a689e`) and the documentation method adapted from Paul Bakaus’s Impeccable (Apache-2.0, `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8`). The combined license record is retained under `web/public/licenses/Better-Interface-LICENSE.txt`.
