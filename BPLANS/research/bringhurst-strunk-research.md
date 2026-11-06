# Bringhurst & Strunk & White — research notes for the cover revision

Scope: a second, more exhaustive pass over Robert Bringhurst, *The Elements of
Typographic Style* (Hartley & Marks; 1st ed. 1992, version 4.0 2012), and
William Strunk Jr. & E. B. White, *The Elements of Style* (Strunk 1918/1920;
Strunk & White 1959; 4th ed. 1999), as they bind the BPLANS covers. Quotes are
copied from the sources listed at the end; page numbers follow the third
edition as quoted there. The laws.yml hooks (BRINGHURST, STRUNK_WHITE,
OPERATOR_RENDERED, DENSITY, NO_EYEBROW_LABEL) are marked where they apply.

## 1. Bringhurst: first principles

- "Typography exists to honor content." (First principles; cited in the
  Typographica review.) The cover exists to present the plan, not to perform.
- "In a world rife with unsolicited messages, typography must often draw
  attention to itself before it will be read. Yet in order to be read, it must
  relinquish the attention it has drawn… Typography with anything to say
  therefore aspires to a kind of statuesque transparency." (p. 17)
  → The cover's one attention-drawing element is the restored wordmark;
  everything else must relinquish attention. (OPERATOR_RENDERED:
  one restrained signal.)
- "Think of the blank page as alpine meadow… The underlying truth of the blank
  page must be infringed, but it must never altogether disappear—and whatever
  displaces it might well aim to be as lively and peaceful as that original
  blank page." (p. 17–18, via Umphred)
  → Void is not leftover space; it is the ground the marks sit in. The redesign
  treats the paper (#F7F2E9) as the active substance of the cover.

## 2. Bringhurst: the title page (the operative law for this revision)

- "It is not enough, when building a title page, merely to unload some big,
  prefabricated letters into the center of the space, nor to dig a few holes in
  the silence with typographic heavy machinery and then move on. Big type, even
  huge type, can be beautiful and useful. But **poise is usually far more
  important than size — and poise consists primarily of emptiness**.
  Typographically, poise is made of white space. **Many fine title pages consist
  of a modest line or two near the top, and a line or two near the bottom, with
  nothing more than taut, balanced white space in between.**" (p. 61)
  → Applied composition: wordmark (modest, centered) near the top; title and
  byline (two lines, centered) near the bottom; nothing between but paper.
  Concretely: the 2.4 em/600 title is heavy machinery — reset to roman 400 at
  2.05 em; the category kicker line ("Forretningsplan · …") is removed
  altogether (see §5); the header hairline is removed — a rule across a title
  page is exactly the "typographic heavy machinery" digging holes in silence.
- The anlage's own geometry: page 156 × 234 mm (2:3), text block 15 mm side
  margins, 16 mm head/tail. The tall header box (175 mm of the 202 mm content
  height) with the title block foot-anchored reproduces the "top lines /
  bottom lines / taut space" pattern without inventing a new grid.

## 3. Bringhurst: contents pages and lists

- "Lists, such as contents pages and recipes, are opportunities to build
  architectural structures in which the space between the elements both
  separates and binds. The two favorite ways of destroying such an opportunity
  are setting great chasms of space that the eye cannot leap without help from
  the hand, and setting unenlightening rows of dots (dot leaders, as they are
  called)…" (p. 35)
  → The Innhold list keeps its chapter numbers, drops the hairline beneath it,
  and opens the row spacing slightly (.15 em → .35 em): enough air to separate,
  not enough to break the eye's leap; no leaders are introduced.
- The contents page becomes a page of its own (the title page stands alone, as
  a book's does). Eight quiet lines plus void is the intended result, not a
  defect of emptiness.

## 4. Bringhurst: blank pages, space and rhythm

- Half-titles and blank leaves "provide a place for inscriptions and notes and
  allow the text to relax in its binding"; but "a wad of blank leaves at the
  end of a book is a sign of carelessness". (p. 72–73)
  → One standalone title page and one contents page are granted at the front;
  no blank leaves are appended anywhere else. The colophon keeps its page.
- Vertical space reads as rhythm when it moves in multiples of the leading.
  Body leading is 1.5 (19 px screen / 11.5 pt print), so the rhythm unit is
  1.5 rem. The revision re-grids the large vertical steps onto that unit:
  section openings 3.5 rem → 4.5 rem (3 units — more void between chapters),
  h3 lead-ins 2 rem → 2.25 rem (1.5 units), footer 4 rem → 4.5 rem (3 units).
  (BRINGHURST law: rhythm on one grid.)
- "Poise … consists primarily of emptiness" applies to marks as well: the
  restored wordmarks are trimmed for quiet (gradient marks 1.5 → 1.3 em,
  Nosifer 2.35 → 2.1 em, fractal 44 → 40 mm) and centered. The marks themselves
  are untouched artwork (OPERATOR_RENDERED: brand marks are original artwork;
  only their setting changes).

## 5. Strunk & White: omit needless words (the cover's prose law)

- Strunk's commandment, repeated by White: "Omit needless words!"
  "Vigorous writing is concise. A sentence should contain no unnecessary words,
  for the same reason that a machine should have no unnecessary parts."
  (Cornell summary; rule 17 in the 4th ed. numbering of Principles of
  Composition.) (STRUNK_WHITE law.)
- Applied to the covers: the kicker "Forretningsplan · <kategori>" is omitted.
  The document does not need to announce its genre on its own title page (the
  running head and the index carry it), and the category already lives in the
  index. This also removes the last eyebrow-shaped element from the front
  matter (NO_EYEBROW_LABEL, semantic side).
- "Use definite, specific, concrete language"; "Place the emphatic word of a
  sentence at the end"; "In summaries, keep to one tense"; "Express coordinate
  ideas in similar form"; "Keep related words together"; "Avoid a succession of
  loose sentences" (composition principles 6–11 per the Gotham list).
  → The byline already follows these (name · sought funding · date, emphatic
  date last); it is kept verbatim — anlage facts are not rewritten
  (PRESERVE_FIRST). No cover prose is rewritten; one element is deleted.
- White's "An Approach to Style" reminders that bind the revision: "Do not
  overwrite"; "Do not overstate"; "Revise and rewrite"; "Place yourself in the
  background." The redesign's whole gesture is the designer withdrawing: fewer
  elements, fewer weights (title from 600 to 400), fewer rules.

## 6. The page and its margins — poise v2

- **Margins are not the frame around the text; they are the text's own
  breathing room.** Bringhurst's page-construction tradition (Van de Graaf,
  Tschichold's 9×9 canon, Rosarivo — see `typographic-styles.md` §0) puts the
  text block off-centre with the *widest* margins at the foot and the outer
  edge; the 2:3 page the anlage already prints is Tschichold's own preferred
  proportion.
- Poise v2 widens the print margins from 16 mm head/tail × 15 mm sides to
  **18 mm × 17 mm**. The measure does not move: the block binds at
  `max-width:min(66ch, 100% − 3rem)`, so 66 ch still caps the line and the
  added margin is pure void — the page grows around the text, the text does
  not shrink into the margin.
- Consciously *not* applied: the 1:1:2:3 inner:top:outer:bottom asymmetry.
  These are unbound, screen-and-print single files, not sect folios; an
  asymmetric gutter on a screen would read as an error. The deviation is
  recorded, not hidden.

## 7. Vertical rhythm — the 1.5 rem grid, deepened

- Body leading is 1.5, so the rhythm unit is 1.5 rem; v1 re-gridded the large
  steps onto it (3 and 1.5-unit multiples). Poise v2 moves each step up to the
  *next* multiple of the same unit — more void, one grid:

| Step | Anlage | v1 | v2 (print) | Units of 1.5 |
|---|---|---|---|---|
| Section opening | 3.5 rem | 4.5 rem | **7.5 rem** | 5 |
| h3 lead-in | 2 rem | 2.25 rem | 2.25 rem | 1.5 |
| Contents padding-top | 2 rem | 3.5 rem | **4.5 rem** | 3 |
| Contents rows | .15 em | .35 em | **.45 em** | — |
| Footer lead | 4 rem | 4.5 rem | **6 rem** | 4 |
| Title-page pad-top | 4.5 rem | 6 rem | **7.5 rem** | 5 |
| Title-page depth (print) | — | 175 mm | **184 mm** | — |

- The 184 mm title page inside the 198 mm print content area (234 − 2 × 18 mm)
  leaves the mark near the top, the title and byline near the foot, and roughly
  90 mm of untouched paper between — the p. 61 composition, at anlage
  proportions.

## 8. The full rule inventory

The whole of both books, reduced to the rules that can bind a page, with their
status in pub4.good. (Bringhurst is cited by principle and, where the sources
in §10 carry the passage, by page; Strunk & White rule numbers follow the 4th
edition: Elementary Rules of Usage 1–11, Elementary Principles of Composition
12–22.)

### Bringhurst

| Principle | Status in pub4.good |
|---|---|
| Typography exists to honour content; aspire to statuesque transparency (p. 17) | applied — v1/v2's whole gesture |
| The blank page as ground; void displaces it but never disappears (p. 17–18) | applied — paper #F7F2E9 is the cover's active substance |
| Page proportion 2:3 | kept (was already the anlage page) |
| Margins widest at foot/outer, text block off-centre | consciously deviated — symmetric for screen/print duality (§6) |
| Measure 45–75 ch, single-column ideal ≈ 66 | kept — `max-width:min(66ch,…)` |
| Leading grows with measure; one baseline grid | kept — 1.5 throughout; v2 steps all on the 1.5 rem grid (§7) |
| Title page: poise = emptiness; top lines, bottom lines, taut space (p. 61) | applied v1, deepened v2 — 184 mm title page |
| Title page: no big prefabricated letters, no heavy machinery | applied — h1 600→400 at 2.05 em; header rule removed |
| Lists/contents: space separates and binds; no dot leaders (p. 35) | applied v1, deepened v2 — rows .45 em |
| Blank leaves granted at the front, none as wads at the back (p. 72–73) | applied — one title page + one contents page; the v2.1 spill blank at syre's foot removed (§9) |
| Chapter openings: space above; heading never at page foot | kept — base `h2,h3{break-after:avoid}`; v2 adds the 7.5 rem opening |
| Oldstyle figures in text, lining tabular in tables | kept (anlage law) |
| Letterspacing: never lowercase text; short lines only | kept; the new plain mark letterspaces one short line at .05 em |
| Small caps, guillemets «», true en/em dashes, hanging punctuation | kept (anlage: `hanging-punctuation:first`) |
| Hyphenation must serve justification; ≤ 3 consecutive hyphenated line-ends; no proper-name hyphenation | partially applied — `hyphens:auto` set; the headless Chromium's Norwegian dictionary availability is a known, accepted limit |
| One family; display sizes in few, related steps | kept — EB Garamond only; 2.05/1.6/1.3 em steps |
| Ornaments and rules: fewer, thinner, meaningful | applied — header/nav hairlines removed; hairlines remain only where they tabulate (tables, colophon) |
| Folios and running heads | consciously not applied — the PDF is a screen archive; Chromium does not support @page margin boxes, and `position:fixed` repetition was judged too fragile for the archive copy |
| Brand marks are artwork, never semantic headings | kept and mechanically enforced (Nosifer law) |

### Strunk & White

| Rule | Status in pub4.good |
|---|---|
| 12 Choose a suitable design and hold to it | kept — one anlage, all fourteen files |
| 13 Make the paragraph the unit of composition | kept (anlage) |
| 14 Use the active voice | kept; checked by review, not mechanically |
| 15 Put statements in positive form | kept; PRESERVE_FIRST bars rewriting the anlage prose |
| 16 Use definite, specific, concrete language | applied — every added block carries the plan's own measured figures |
| 17 Omit needless words | applied — the cover kicker is gone (v1); the plain-mark colophon note states facts only (§9) |
| 18 Avoid a succession of loose sentences | kept; noted for future prose passes |
| 19 Express coordinate ideas in similar form | kept; noted for future prose passes |
| 20 Keep related words together | kept |
| 21 Keep to one tense | kept — colophons and added blocks consistent |
| 22 Place the emphatic word at the end | kept — bylines end on the date |
| Usage rules 1–11 (possessive 's, series comma, parenthetic commas, comma before conjunction, no comma splice, no broken sentences, dash, colon, subject–verb number, pronoun case, dangling participle) | kept; the character/typography audit pins the visible ones («», –, —, −) |
| Avoid the use of qualifiers (Approach to Style, reminder 8) | mechanically enforced — the nb leech list (`veldig, svært, ganske, nokså, temmelig, virkelig, simpelthen`) fails the build; one «virkelig» was removed from preserved prose |
| Do not overwrite; do not overstate; revise and rewrite; place yourself in the background | applied — the revision deletes elements; it adds none |

## 9. Two late rulings

### The plain wordmark (govt_bergen, poise v2)

The customer's instruction — *"Bergens Selvstyreparti needs new logo, use
plain, same font as the rest for now"* — is exactly Bringhurst's p. 17
movement: the wordmark relinquishes its drawn attention (the pub2 gradient,
`#ff8c00 – #ff0080 – #8a2be2`) and typesets itself in the document's own
voice, EB Garamond roman, 1.3 em, tracked .05 em — letterspacing on one short
capitalised line only, never in lowercase text. The artwork is withdrawn, not
re-set; the colophon records the replacement truthfully (TRUTHFUL_STATUS), and
the index row and the checker's expectations were updated in the same commit
so no surface describes the gradient as still present (DUAL_MODALITY). The
mark is a class of its own (`.mark-plain`), so the historical build path
(`bp_build.mjs` kind `plain`) reproduces it byte-for-byte if the anlage is
ever re-based.

### The blank leaf (syre, poise v2.1)

v2's deeper rhythm left syre printing a fully blank page 15 before the
colophon: `main`'s 3 rem print padding-bottom spilled past a flush last page
(the donation-growth figure ends flush). Bringhurst p. 72–73: *"a wad of
blank leaves at the end of a book is a sign of carelessness."* The padding is
dropped in print (`main{padding-bottom:0}`), syre returns to 15 pages, and
the whole corpus was re-scanned for near-blank pages — none remain.

## 10. Sources consulted

- Jeffrey Friedl, "Robert Bringhurst's The Elements of Typographic Style"
  (regex.info/blog/2007-12-03/650) — verbatim p. 17, 32, 35, 61, 72–73 quotes.
- Neal Umphred, "robert bringhurst and elements of typographic style"
  (nealumphred.com/elements-of-typographic-style) — p. 17 passages, alpine
  meadow, the Strunk homage.
- Maurice Meilleur, review of version 4.0 (typographica.org) — "Typography
  exists to honor content", the book's descent from Strunk's Elements.
- Gotham Writers Workshop, "Strunk & White: 11 Composition Principles"
  (writingclasses.com/toolbox/tips-masters/strunk-white-11-composition-principles).
- Archbee, book review with the ten core principles
  (archbee.com/blog/book-review-the-elements-of-style…).
- Cornell Chronicle, "Omit needless words … turns 50"
  (news.cornell.edu/stories/2009/03/omit-needless-words-elements-style-turns-50)
  — Strunk's 43-page 1918 primer, "Omit needless words!", "Do not break
  sentences in two", "Use the active voice".
- Wikipedia, "The Elements of Style" — edition history; Strunk's text public
  domain; the 4th-edition rule numbering (usage 1–11, composition 12–22, rule
  17 "Omit needless words") used in §8 follows that edition's contents as
  carried by the sources above.
- The Boston Globe and Cornell summaries of Strunk's 1918 rules and White's
  1959 expansion (cross-checks for the usage-rule titles).
- Wikipedia, "The Elements of Typographic Style" — chapter map (The Grand
  Design; Rhythm & Proportion; Harmony & Counterpoint; Structural Forms &
  Devices; Analphabetic Symbols; Choosing & Combining Type; Shaping the Page;
  The State of the Art) used to order §8's inventory.

Nothing in the sources could be checked against the books themselves in this
sandbox; the quotes are carried from the sources above with their page
numbers as given there, §8's unquoted principles are stated at principle
level so they can be re-audited independently of any single quote, and every
design decision above states which principle it serves.
