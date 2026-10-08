# Frontend validation and Better Interface review

## Scope and completion

**Complete for the stated frontend scope.** Implemented and inspected a working static site, with demo data and local drafts. No external service, wallet, transaction or public deployment is connected. No contract audit was performed. Results below are worker observations, not independent certification.

Baseline: `2e7c4f5f0489a0b1d4eedf38d59c70951803f7b2`. There was no existing frontend or supplied logo asset. The exact requested logo was reconstructed as a component, with the full locally bundled IBM Plex Mono Medium font. Existing source was used to describe governance powers; no guessed deployment, operator, approved budget or live balance was introduced.

The assigned browser MCP connector returned `Transport closed`. The installed Playwright library and Chromium headless shell worked through a bounded foreground test script. It started its own local HTTP server, exercised the production export at `/preview/`, saved screenshots, and closed browser/server on completion.

## Actual checks

- `npm ci --offline --cache /tmp/imdao-npm-cache --no-audit --no-fund`: **exit 0** using the delivered lockfile and a populated cache, in an isolated `/tmp/imdao-build/web` copy.
- `npm run typecheck`: **exit 0** (`tsc --noEmit`, strict TypeScript).
- `npm run build`: **exit 0**, 35 modules transformed. Final application output: approximately 1.70 kB HTML, 21.01 kB CSS, 232.91 kB JS before compression. Fonts and license assets are local. Full command output is in `build.log`.
- `web/checks/browser.mjs`: **33/33 checks passed** against the final production HTML, CSS and JS. Exact results and contrast observations are in `interaction-results.json`.
- Ten axe-core 4.10.3 checks (home desktop/mobile, editor, governance and treasury in both themes): **zero reported violations** for WCAG A/AA tags. Automated checks retained “incomplete” observations for SVG logo text and decorative arrows; these are not claimed as automatically verified.
- Exercised app flows produced **zero runtime console errors and zero unexpected failed resource loads**. The first-paint test deliberately blocks application JS in an isolated page; those expected failures are excluded from runtime-error tracking.
- 320, 375, 768 and 1440 CSS-pixel widths, both themes, on nine representative list/detail/editor routes: **no horizontal page overflow**. Mobile community cards and navigation were visually inspected.
- 200% root text enlargement at 768px: **passed reflow**. This is text enlargement, not browser-native zoom.
- Native confirmation tests covered unsaved route changes, browser Back, reload, replacement on the same editor route, deleting a saved draft and resetting damaged storage.

Worker command (repository root):

```sh
IMDAO_PLAYWRIGHT_MODULE=/opt/imd-tools/playwright-mcp/node_modules/playwright/index.mjs \
IMDAO_CHROMIUM=/opt/imd-tools/ms-playwright/chromium_headless_shell-1246/chrome-headless-shell-linux64/chrome-headless-shell \
IMDAO_AXE_SCRIPT=/tmp/imdao-checks/node_modules/axe-core/axe.min.js \
node web/checks/browser.mjs
```

Worker Playwright: `1.64.0-alpha-1789764292000`; Chromium headless shell build 1246; Node 22.23.3. Check-tool dependencies and caches are outside the deliverable. App dependencies are fully declared and locked under `web/`.

## Six-domain coverage

| Domain | Status | Evidence and coverage |
| --- | --- | --- |
| Accessibility | Checked | Native links/buttons/forms/disclosures; labeled fields; required/invalid/error associations; first-invalid focus; keyboard entry/save/navigation; skip link; visible focus screenshots; forced-colors outline; live save/result statuses; native destructive/unsaved confirmations. Ten automated scans supplement these checks. |
| Layout | Checked | Final rendered desktop/mobile screenshots, four widths in two themes on nine routes; stacked cards and treasury rows; 200% text enlargement; missing/no-results/error states. |
| Writing | Checked | Read-only examples consistently labeled; source-supported governance powers; votes separated from completion; operators/budgets unspecified; local-save language; actionable errors; principal returns separate from proceeds; no live counts/revenue. |
| Typography | Checked | Full IBM Plex Mono loaded in Chromium (`document.fonts.check` after readiness); exact logo dimensions and nine squares; neutral body type; responsive headline wraps; 16px inputs; no clipped user input; readable saved-draft preview. |
| Colors | Checked | Computed text/background pairs in both themes, measured ratios in JSON, selected control and pale-button text verified; light-page secondary contrast repaired. Brand geometry/low-opacity gaps visually inspected. |
| UI | Checked | Header, shared cards/badges/forms, theme switch, all four starters, editable preview, all named route/detail families, empty/missing/error states, save/reopen/edit/delete, storage corruption/failure, hover/focus, and stable theme on reload. Motion is absent. |

Not performed: a screen-reader session, physical-device testing, Safari/Firefox, native 200% browser zoom, RTL/localization, or a full accessibility/security certification. No async API/loading, wallet, auth, or transaction states exist; those are not applicable to this scope. Browser-storage data is not encrypted and cannot synchronize between devices. Native beforeunload prompts depend on browser policy and user activation, as with any static web app.

## Findings, fixes and rechecks

1. **High · light text contrast** — `web/src/style.css:8`, `.surface` / `.idea-card`. The specified `#617364` secondary text on `#edf1e9` measured 4.43:1 and failed axe contrast checks for small text. Preserved it on card surfaces (first-card ratio 4.98:1), introduced `#5f7162` for page secondary text (4.56:1), and rechecked both themes. Dark page secondary text is 8.50:1. This is the sole narrowly scoped palette adjustment for readable contrast.
2. **Medium · text enlargement** — `web/src/style.css:1146` and `web/src/style.css:1562`. At 768px with root text doubled, the original one-row header overflowed. Moved navigation to its own row at 1100px and collapsed the editor at 900px. Rechecked the failing enlargement state plus all four widths; no page overflow remains.
3. **Medium · draft storage limits** — `web/src/storage.ts:13` and `web/src/storage.ts:77`. Source review found that accumulated valid drafts could exceed the restore-size cap before hitting the count cap. Added the matching pre-write serialized-size check and validation of restored budget/unit pairs. Oversized/invalid writes cannot claim success; unknown schemas and malformed restored fields remain preserved with a recoverable error. Existing corruption, quota and persistence checks pass after the edit.
4. **Build compatibility** — `web/package.json` Rollup override. Vite with automatically resolved Rollup 4.64.2 stalled after transformation in repeatable bounded runs. A 4.46.2 override in the newly created frontend manifest resolved it. The frozen offline reinstall, typecheck and production build all subsequently exited 0. No pre-existing dependency or configuration file changed.
5. **Validation harness corrections** — `web/checks/browser.mjs`. The first run asserted some hash-route states before React committed them and changed theme storage without reloading. Added frame-settlement waits and explicit theme reloads. Expected aborted-JS failures in the isolated first-paint test are not runtime app failures. Re-ran the complete suite; 33/33 pass. These were harness defects, not falsely reported site fixes.

No known blocking frontend defect remains in the exercised scope.

## Screenshot evidence

All screenshots show actual local production rendering. Home images are full-page captures: desktop viewport 1440×1050 and mobile viewport 375×812.

- `desktop-light.png`, `desktop-dark.png`
- `mobile-light.png`, `mobile-dark.png`
- `focus-light.png`, `focus-dark.png`: visible keyboard focus on New idea at mobile width.
- `editor-light.png`, `editor-dark.png`: focused, labeled draft input in both themes.

The screenshots were opened and visually inspected. They show the centered hero, three-card desktop feed, stacked mobile feed, separate starters, themed navigation, full local logo and readable form focus. They do not establish screen-reader or physical-device behavior.

## Integrity, packaging and historical limitations

The pre-existing working-tree files were hashed before edits and compared after implementation. **README.md is the only pre-existing file changed.** Contracts, all existing tests, Foundry configuration, dependencies, vendored libraries, `.gitignore` and licenses were preserved byte-for-byte. Source and export additions are confined to `web/`, `dist/`, `DESIGN.md`, `docs/frontend/` and `artifacts/`. Scratch checks live under the already ignored `test/scratch/`; build/dependency tools live under `/tmp`.

An extra historical checksum check (`rg -v '  README.md$' REVIEW.sha256 | sha256sum -c -`) found **23 mismatches in pre-existing vendored-library entries**. Those same files match the start-of-task hashes; these mismatches were inherited, not introduced here. The historical checksum record and libraries were left untouched. This task does not certify the earlier contract review, and contract tests were not re-run for this frontend-only change. `integrity.json` records the independent preservation comparison and packaging sizes.

No `.git/` mutation, commit, submodule, public deployment, dependency/cache archive or node_modules directory was created in the repository. The contributor network must capture the prepared source/export and `docs/frontend/` evidence. The provided workspace excludes `artifacts/` through its local Git rules, so identical evidence copies live under `docs/frontend/` without modifying an ignore file. The packaging check uses the complete deliverable file set, including baseline source and vendored libraries, rather than counting only the frontend diff. Its precise sizes are recorded in `integrity.json`.
