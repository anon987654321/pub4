# Bergen static sites — law run and screenshot regeneration, 2026-10-28

Scope: `RAILS/__other/alfa` and `RAILS/__other/sommerseth` (the two
`apps.yml#static_exports` trees). Tool: `MASTER/bin/operator lint` — the
same deterministic house-law engine `/fix` walks, run here with no model.

## What the run measured

First pass: **180 findings across 8 files**. After this commit's fixes:
**6 findings across 2 files**, all six deliberately deferred:

- `alfa/assets/site.css` and `sommerseth/assets/site.css`: SMALL_FILES
  (655/652 lines vs the 300 limit) — splitting a stylesheet into modules
  changes cascade order and belongs in its own visually verified commit.
- Both files: MOBILE_FIRST ×2 each — the `max-width` blocks at the end of
  each file invert into mobile-first `min-width` only by restructuring the
  cascade; same reasoning as above.

## What was fixed (law → change)

- NO_ORDINAL_ORNAMENT (11): dropped the 01–04 section numbers and the
  row numbers; order on these pages is decorative, not sequential.
- NO_TRAILING_ARROW (7): dropped the `→` affordance spans; the row styling
  carries the affordance.
- `<img> loading=lazy` (6): added to all content images on both sites.
- NO_VAR (15+), TEMPLATE_LITERALS, 4-level chains, VERTICAL_BREATH: both
  `assets/motion.js` files rewritten to const/let discipline with breathing
  room (the two files were byte-identical before; one rewrite serves both).
- NO_INLINE_SCRIPT_BLOCK (2): the `html.js` gate moved to `assets/boot.js`,
  referenced by `<script src>`; no shebang on the web asset.
- NO_DOT_SEPARATED_META (2): the meta line is now one `<span>` per fact,
  separated by flex gap.
- NO_INLINE_STYLES: the marquee speed is now `--mq-duration` custom property.
- CLASS_RESTATES_TAG (5): `<section class="section">` → bare `<section>`,
  `<footer class="footer">` → bare `<footer>`, CSS retargeted.
- TYPOGRAPHY (44+): every HTML/SVG line over the measure wrapped
  (HTML limit 100, SVG 120); headings' uppercase treatment removed from the
  ten small tracked label blocks the NO_EYEBROW_LABEL detector names
  (meta lines, nav links, CTAs, figcaptions), keeping mono + tracking.
- Design tokens: raw `rgba()` uses replaced with `color-mix` over
  `--ink`/`--signal`; `line-height` 1.02–1.06 → 1.0; `margin/padding-left`
  → logical properties; 18px → 16px on the 8px rhythm; `backdrop-filter`
  and entrance `blur()` removed (flat-surface law).
- CURSOR_NONE_REQUIRES_CURSOR: the native cursor stays hidden; the
  replacement dot+ring is rendered by motion.js and gated by
  `pointer: fine` + `prefers-reduced-motion` — documented inline with
  `scan: intentional` per the law's own "replacement rendered and gated" clause.
- README_PROSE (6): both READMEs lead with one bold sentence; the file
  listings moved under a final heading.

## Screenshot regeneration

All four captures re-taken after the fixes, from this exact tree, served
over loopback (`python3 -m http.server`), full-page headless Chromium at
the documented viewports (desktop 1440, mobile 390), entrance animations
settled by scrolling the page before capture:

- `alfa/screenshots/alfa-desktop.png` 1440×4398 (was 1440×4430)
- `alfa/screenshots/alfa-mobile.png` 390×3966 (was 390×4051)
- `sommerseth/screenshots/sommerseth-desktop.png` 1440×4270 (was 1440×4275)
- `sommerseth/screenshots/sommerseth-mobile.png` 390×4751 (was 390×4758)

Before this commit, the committed captures were verified current against
their HTML (re-render matched all four pixel dimensions exactly); the
heights changed here because the law fixes changed the pages.

## Blocker found and fixed on the way

`MASTER/test/test_trace_telemetry.rb` carried a duplicated appended test
body (syntax error at line 87) — `Operator::ParseSweep` refused to start
any `fix-here` run because of it. Removed and verified: the file parses
and reports 6 runs, 18 assertions, 0 failures on this checkout.

## Live deployment note

`alfa.brgen.no` and `thor.brgen.no` serve the previous tree until the
operator runs `zsh OPENBSD/bin/vps-deploy-static alfa|sommerseth` on vm23;
that redeploy is an operator seam and is not part of this commit.
