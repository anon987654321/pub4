# Research: typographic styles beyond the current anlage

For the pub4.good restoration — November 2026. The seven plans are set in the
pub4 anlage: EB Garamond (SIL OFL), 66-character measure, 1.5 leading, oldstyle
figures in running text, tabular figures in tables, sentence-case titles, paper
#F7F2E9 — explicitly "etter Robert Bringhurst, *The Elements of Typographic
Style*". This note researches the neighbouring traditions worth having as
presets, and records what each would change in the anlage's CSS. Sources
consulted: Bringhurst (Elements, 4th ed. — including its critics, e.g. Sam
Potts' "A Refutation of The Elements of Typographic Style"), Tschichold
(*The Form of the Book*, the Penguin Composition Rules and the 9×9 "perfect
page" canon), the canons of page construction (Van de Graaf, Rosarivo, the
"Golden Canon" paper by S. M. Max, Bridges 2012), Tufte (*The Visual Display of
Quantitative Information* — data-ink ratio, clear labelling, no chartjunk),
Butterick (*Practical Typography*) and Wikipedia's canon overview.

## 0. Page-construction canons (shared background)

- **Van de Graaf canon** (reconstruction of medieval practice): margins in
  a 2:3:4:6 relationship, text block placed by the classic diagonal method.
- **Tschichold's 9×9 canon** (*The Form of the Book*): divide the page in
  ninths; text block is 1/9 in from top and inside, 2/9 from outside and
  bottom; the resulting text-block height equals the page width.
- **Page ratio 2:3.** Tschichold argued 2:3 is the best page proportion —
  which is exactly what the pub4 anlage already prints (442.08 × 663.12 pt =
  156 × 234 mm). Any new preset should keep the page, or consciously break it.
- **Rosarivo's "Golden" number**: 1:1.538 diagonally derived — close to 2:3,
  useful when a taller page is wanted.

## 1. Bringhurst classicist — *current pub4 anlage*

- Type: EB Garamond (Georg Salden's revival of Garamond's roman, OFL),
  variable 400–800, embedded as data URI.
- Measure 66 characters (Bringhurst's 45–75 band, single-column ideal),
  leading 1.5 on one baseline grid, oldstyle figures in text, tabular in
  tables, guillemets, true dashes, sentence-case titles, hanging punctuation,
  justified with hyphenation.
- Paper #F7F2E9; ink #211C15; accent #7A3B2E.
- Best for: archive documents meant to be read end to end. Keep as default.

## 2. Tschichold / Penguin composition rules

- Type: a workhorse serif (Penguin used Times New Roman; open equivalents:
  **Crimson Pro** or **Source Serif 4**, both OFL).
- Rules that would change the anlage: paragraphs indicated **by indent only,
  never by space**; folios (page numbers) in the same size and type as text,
  Arabic numerals; chapter openings with dropped line and no folio; 1:1:2:3
  inner:top:outer:bottom margins on the 9×9 canon.
- Figures: lining figures in text too (Penguin was consistent), tabular in
  tables.
- Best for: long, chaptered documents; feels bookish rather than reportish.

## 3. Tufte / evidence-first

- Type: **ET Book** (free Palatino revival by Edward Tufte) or **Cardo**
  (OFL) for text; a quiet sans (**Source Sans 3**, OFL) for data labels.
- Layout signature: **sidenotes instead of footnotes** (margin notes,
  superscript-free), figures and tables flush into a wide text block, captions
  under the figure in the margin.
- Charts: maximise the **data-ink ratio** — no boxes, no gridlines beyond
  hairlines, direct labelling instead of legends, small multiples for
  comparison; "above all else show the data"; do not lie with proportion
  (area encodes area).
- Best for: the figures-heavy plans (NATO's capacity comparisons,
  pub.healthcare's cost/deployment charts). This preset is also the one to
  steal chart rules from, whatever the body preset is.

## 4. Swiss / International typographic style

- Type: **Inter** or **Archivo** (both OFL), weights 400/600 only.
- Flush-left, ragged right (no justification, no hyphenation), strict column
  grid, leading 1.4, tabular numerals everywhere, titles set lowercase or
  sentence case in the same size family with weight contrast only.
- Paper white or #FAFAF7; one accent, no italics as emphasis (use weight).
- Charts: flat, hairline axes, single hue.
- Best for: dashboards, KPI one-pagers, anything an investor reads on a
  screen. For the bplans corpus: good for a future one-page "sammendrag"
  companion, not for the archive documents.

## 5. Butterick practical (documents that must not fail)

- Type: **Charter** (Bitstream Charter, free) or Source Serif 4, 10.5–11 pt,
  leading 1.35–1.45, measure 45–90 characters; ragged right acceptable for
  business documents; curly quotes and proper dashes mandatory; one space
  after sentences; no all-caps for emphasis.
- Butterick's four body-text considerations: point size, line spacing, line
  length, typeface — get those right before any decoration.
- Best for: contracts, letters, boarding documents — the `__letters` corner
  of the archive rather than the plans.

## 6. Newspaper editorial (FT / broadsheet)

- Type: display serif for headlines (**Playfair Display**, OFL) over a
  serviceable text serif (**Source Serif 4**), kickers in spaced small caps.
- Narrow measures (2–3 columns), oldstyle figures in text, hanging indents
  for data lines, hairline rules between columns.
- Best for: the press-facing summary sheets (Ragnhild's VG/Dagbladet push,
  govt_bergen's media milestones).

## 7. Scandinavian public-sector plain style

- Type: system sans or **Inter**; strict left alignment; 60–75 character
  measure; generous white space; bullet discipline (max two levels).
- Language takes priority over typography: short sentences, one idea per
  paragraph — Altinn/Innovasjon Norge house style. WCAG-level contrast.
- Best for: anything sent *to* a public body as a form or attachment.

## Notes for implementation in pub4

- The anlage already isolates presentation in one `<style>` block with CSS
  custom properties (`--paper`, `--ink`, `--accent`, `--hair`); a preset swap
  is: font-face block + custom properties + a handful of element rules. No
  structural change needed — the HTML is semantic (section/h3/table/figure).
- Whichever preset is chosen, keep the pub4 invariants: zero external
  requests (fonts inline as data URIs), the 156 × 234 mm page, sentence-case
  titles, oldstyle/tabular figure split, and the colophon that names the
  anlage and the font licence.
- If a preset needs an animation (as pub2's gradient wordmarks had), it stays
  in the HTML for screens and dies at print — the PDF is the archive copy and
  must be still.
