# Bergen brand systems — doctrine and /fix runbook

Measured design system for the two standalone brand sites in
`RAILS/__other/sommerseth/` and `RAILS/__other/alfa/`, calibrated against
bob.no's production design (measured in-browser: Sofia Pro 900, 102 px
display titles, `#582483`/`#320E3B`, gold pill CTAs, white rounded cards,
yellow underline hovers, long arrows). bob.no is the direct competitor:
same quality bar, deliberately different identities.

Everything below is what `/fix` must be able to verify and restore. The
line-level teeth are `MASTER/law/brand.rb`; the source of truth for the
palettes and mark parameters is `MASTER/data/tokens.yml#tokens.brand_systems`.

## 1. Bergen-snittet v1 — the parametric mark system

Both marks derive from ONE construction grammar. Nothing is hand-drawn;
paths are computed from constants. Never paste coordinate soup into a
component (law `PARAMETRIC_MARK_ONLY`).

| Parameter   | Value | Meaning                                   |
|-------------|------:|-------------------------------------------|
| GRID        | 48    | viewBox units                             |
| STROKE      | 3.2   | shared stroke, round caps + joins         |
| HORIZON_Y   | 38    | the ground/fjord line every mark stands on|
| RISE        | 25    | roofline rise over its half-width         |
| ROOF ANGLE  | ≈57.4°| atan(25/16) — shared slope constant       |
| SUN_R       | 6.5   | half-disc radius (midnight sun)           |
| DOOR_R      | 5.2   | 0.8 × SUN_R — Alfa's arch door            |

- **Sommerseth** — midnattssol over setertak: half-disc sun centred on the
  roofline's left foot (15, 38); roofline rises from the sun's centre to
  apex (30, 13) and down to (45, 38); horizon 4→44.
- **Alfa** — A-scråtak: symmetric roofline, feet (8, 38) → apex (24, 13) →
  (40, 38); half-disc door r 5.2 centred (24, 38); horizon 4→44. The door
  and the sun are the SAME circle parameter — sun ↔ door is the sibling
  reveal between the two brands.

Implementation contract: `src/lib/marks.ts` exports `SYS` + composed path
constants; `scripts/gen-marks.mjs` regenerates the favicon SVGs from the
same constants (`node scripts/gen-marks.mjs`). A mark component renders
named parts (`d={SOMMERSETH.roof}`), never literal dumps.

## 2. Brand token systems

| Token     | Sommerseth (varm minimalisme) | Alfa (arkitektonisk minimalisme) |
|-----------|-------------------------------|----------------------------------|
| --paper   | #F7F2E9                       | #F2F4F6                          |
| --ink     | #1E322D (fjord green)         | #14212E (ink blue)               |
| --muted   | #5F6D66                       | #55636F                          |
| --signal  | #C97E1E (amber)               | #A4762F (brass)                  |
| --line    | rgba(30,50,45,.16)            | rgba(20,33,46,.16)               |
| --cur     | var(--ink)                    | var(--ink)                       |

Discipline (laws `SIGNAL_COLOR_NAMING`, `PAPER_NOT_PURE_WHITE`): one
signal colour per identity, used once per visual unit (kicker dot,
underline, numeral, italic em, mark detail). Page scopes paint
`var(--paper)`, never `#FFF`. Corner logic is part of the identity:
Sommerseth may round (pill CTAs), Alfa is sharp (0 radius everywhere
except none).

## 3. Typography

| Role    | Sommerseth                    | Alfa                             |
|---------|-------------------------------|----------------------------------|
| Display | Instrument Serif 400 (+italic)| Bricolage Grotesque 700 caps     |
| Body    | Geist 400                     | Geist 400                        |
| Meta    | Geist Mono                    | Geist Mono                       |

Loaded with `next/font/google` (variable `--font-display`, `--font-body`,
`--font-mono`). Display sizes are fluid clamps anchored at viewport width
(`clamp(2.8rem, 7.2vw, 6.6rem)` class values — see the modules). Norwegian
bokmål copy throughout, snl.no orthography (law `NORWEGIAN_COPY_BOKMAL`).

## 4. Motion kit — "fully immersive, still honest"

Shared client kit: `src/components/motion.tsx`. Every part respects
`prefers-reduced-motion` (returns static rendering when set).

- `SmoothScroll` — Lenis (duration ≈ 1.15), rAF loop, destroyed on unmount.
- `Reveal` — opacity 0→1, y 26→0, blur 8→0, once, stagger by delay.
- `WordReveal` — per-word masks (`.wr-mask` overflow hidden, inner span
  y 112%→0). **The measured trap**: `whileInView` on the clipped inner span
  never fires (intersection area 0). Observe the outer unclipped wrapper
  with `useInView`, drive inner spans with `animate`
  (law `WORDMASK_OBSERVES_UNCLIPPED`).
- `Parallax` — image 114% height in an overflow-hidden frame; y ±10% tied
  to `useScroll` progress of the frame.
- `Marquee` — duplicated row, linear `translateX(0 → -50%)` loop.
- `Counter` — animates 0→N on first view, tabular numerals.
- `Magnetic` — spring-follow on pointer move (strength ≈ 0.28), resets on
  leave.
- `Cursor` — dot + trailing ring, `pointer: fine` only; every page that
  sets `cursor: none` MUST render it (law `CURSOR_NONE_REQUIRES_CURSOR`).

Shared styles live in `src/app/motion.css` (bundles) / `reveal.css` (dev
preview): `.wr-mask`, `.wr-word`, `.pl-frame`, `.pl-inner`, `.mq`,
`.cur-dot`, `.cur-ring`.

## 5. Page anatomy (both brands)

Sticky nav (paper blur, hairline bottom) → hero (kicker in mono, display
headline with signal-coloured em, lead, magnetic primary + quiet CTA) →
full-bleed parallax figure with mono caption → hairline-ruled fact strip →
split section (text + portrait parallax) → numbered rows (mono numeral,
display title, muted description, arrow that translates on hover) →
values/services columns → contact (display-size invitation + underlined
contact rows) → hairline footer with sister-brand link.

Photographs are brand-generated per storefront_art (matte paper light, no
embedded text/logos/watermarks); never stock with watermarks. Alt text in
Norwegian.

## 6. /fix runbook (this tree)

When repairing anything under `RAILS/__other/sommerseth|alfa` or the dev
preview of these sites:

1. Run the laws of `MASTER/law/brand.rb` plus the web laws
   (`REDUCED_MOTION`, `MEASURE_OPTIMUM`, `CLAMP_TYPOGRAPHY`, …).
2. Verify mark components import from `src/lib/marks.ts` and favicons
   regenerate via `scripts/gen-marks.mjs` — regenerate and diff if in doubt.
3. Verify `WordReveal` observes outer wrappers (grep for
   `whileInView={{ y:` — zero hits allowed).
4. Verify `cursor: none` is always paired with a rendered `<Cursor/>` and
   the two media gates.
5. Verify every `motion` consumer respects `useReducedMotion`.
6. Verify copy is bokmål and meta/mono strings use Geist Mono.
7. Re-screenshot at 1440×900 top/mid/low/end before declaring done.
