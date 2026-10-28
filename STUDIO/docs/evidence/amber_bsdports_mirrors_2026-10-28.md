# amber + bsdports design-mirror verification — measured, 2026-10-28

The aa38346 handoff declared three mirrors: brgen → X.com, amber →
newyorker.com + outnet.com, bsdports → classic google.com. brgen's X mirror
was verified when it shipped (its application.scss carries the measured
#16181c/#202327/#526273 set and the 3.16:1 blue-ink decision). This pass
verifies the other two against the declared sources, from tokens and the
591a67d captures.

## amber → newyorker.com + outnet.com — HOLDS in code, two render caveats

Declared mirror (aa38346): "white paper, #121212 masthead ink, hairline #d6d6d6
rules, Source Serif 4 display over the Source Sans 3 commerce sans".

Measured in `RAILS/amber/app/assets/stylesheets/application.scss`:

| Mirror value | In tree | Measured note |
|---|---|---|
| #121212 masthead ink | `--text: #121212` ("The New Yorker's own value") | 18.75:1 on white — stated and correct |
| hairline #d6d6d6 | `--border: #d6d6d6` | 1.6:1 — "a rule, not a boundary", the Outnet row hairline |
| muted ink | `--text-secondary: #4d4d4d` | 8.45:1 — Outnet's warm grey re-tuned to clear the tree's TYPOGRAPHY 7.0 floor, which the raw reference grey does not |
| serif display | `--font-display: "Source Serif 4", Georgia, …` | wired to h1/h2 with masthead leading/tracking; Source Serif 4 is the family's bundled OFL face, matching the house stack |
| commerce sans | `--font: "Source Sans 3", …` | the Outnet-style UI sans |
| editorial anatomy | footer columns, hairline-ruled strips | matches the Outnet chrome read in the capture's footer |

The mirror is real in the cascade, and the discipline points hold: the inks
are deliberately re-tuned to the tree's own contrast floors rather than copied
raw (the same rule brgen's X mirror followed), the wordmark stays Caprasimo
("the wordmark is the only thing set in" it), and page scopes do not paint
pure white.

Screenshot freshness: the saved media captures are from commit 591a67d
(2026-10-28 14:16Z). Commit 1aeae125 (2026-10-28 22:54Z) later restored the
homepage masthead from a 380px wordmark and automatic height to an 880px
wordmark in a 72svh stage. Therefore the checked-in Amber desktop/mobile
screenshots are stale for the current homepage geometry. Do not use them as
evidence against the restored source; recapture with real Chrome/CDP before
judging that revision.

Other render caveats, both needing a booted DOM (see rails_media_fixpass doc):
the older 1440px capture shows the "Bymorgen" look title breaking mid-word, and
the tile headings read as the bold sans rather than the serif display — the
token wiring says serif, so computed styles must be read before the mirror can
be called fully verified *as rendered*. Code side: verified.

## bsdports → classic google.com — HOLDS, tokens and rendered capture agree

Declared mirror (aa38346): "Arial, #1a0dab links with #609 visited,
#202124/#4d5156 inks, square corners" — every value re-tuned to the tree's
floors where the raw reference sits under them.

Measured in `RAILS/bsdports/app/assets/stylesheets/application.scss`:

| Mirror value | In tree | Measured note |
|---|---|---|
| Arial, no download | `--font: Arial, "Helvetica Neue", Helvetica, sans-serif` | the 2005–2017 frontpage face; zero webfont bytes |
| #1a0dab links | `--accent: #1a0dab` | 8.6:1 on white — Google's own blue, and it clears the tree floor untouched |
| visited #609 | `a:visited { color: #609 }` | the classic purple, hover-only underline per the 2005–2017 serpentine comment |
| #202124 ink | `--text: #202124` | 16.1:1 on white |
| #4d5156 snippet grey | `--text-secondary: #4d5156` | 8.0:1 — stated in the stylesheet and correct |
| #f8f9fa/#f2f2f2 greys | button/footer greys | the frontpage's button band |
| square corners | "already this dialect's own" | no radius overrides introduced |
| centred narrow column, grey pill search | capture | the frontpage anatomy on the ports index |

The 591a67d captures confirm the rendered result: Arial with blue #1a0dab
port names, grey pill search on white, square chips, snippet-grey meta. The
mirror reads as the classic Google frontpage carrying a ports catalogue —
the bsdports identity, not a Google imitation of chrome.

Known render defects on this surface are the footer/sentinel collisions in
the fixpass doc — they are layout bugs, not mirror drift.

## Verdict

- bsdports: **verified** — tokens, values and rendered capture agree with the
  declared mirror.
- amber: **verified in code**, two rendered caveats pending a booted DOM
  (mid-word title break; tile-heading face). The palette/typography mirror
  itself is present, measured, and re-tuned where the law requires.
- brgen (X.com): verified at aa38346 time; the capture's white below-fold body
  is filed under the fixpass boot block, not as mirror drift.
