# Screenshot law-adherence audit — RAILS, November 2026

**The 34 screenshots committed on 2026-11-05 were judged against MASTER's Laws, and the
family holds its line better than any single surface holds it perfectly.** This document
records, surface by surface, how the new RAILS screenshot sets adhere to the house rules
in `MASTER/law/` (cosmetic, css, web, brand, rails, interface, surface, universal),
`MASTER/data/tokens.yml` (dialects, shared chrome, visual identity), `visual_directives.yml`,
`visual_rubric.yml` and `minimalism.yml`. It is a reading of rendered evidence, not a
restyle proposal: rendered values stay operator-owned (RENDERED_VALUES), so every defect
below is a finding with a law tag, never a silent patch.

Method follows `visual_rubric.yml`: a screenshot proves a rendered state and source proves
implementation, so every strong claim was cross-checked against the tree (locale files,
seeds, view partials) before it was written down. Where the capture alone cannot decide —
lazy-loaded regions, animation, runtime contrast — the finding says INCONCLUSIVE instead of
manufacturing a taste verdict.

## The house the screenshots were judged against

Typography — `swiss_sans_only` (one Helvetica-family sans; serif forbidden; monospace only
in terminal, chat and code), `CLAMP_TYPOGRAPHY`, `MEASURE_OPTIMUM` (45–75 characters of
running text), `TYPE_HIERARCHY` (one modular scale, few steps), `EN_DASH_RANGE`,
`ALL_CAPS_NO_TRACKING` and `NO_EYEBROW_LABEL` (no tracked all-caps kickers above headings).

Graphic design — `AESTHETIC_FLAT_SEMANTIC` (flat surfaces on an 8px rhythm; no ornamental
shadow, blur or glow), `NO_DECORATIVE_GRADIENT`, `NO_ORDINAL_ORNAMENT`, `NO_TRAILING_ARROW`,
`NO_DOT_SEPARATED_META` (two or more dot separators on one line), `SIGNAL_COLOR_IS_SEMANTIC`
(the signal marks selection and state, never ordinary paint), `CONTRAST_TOKENS`
(≥ 4.5:1), `WHITESPACE_RHYTHM`, plus `minimalism.yml`: 44px touch floor, at most three
accent zones, words before icons, an empty state of one truth sentence and one verb, labels
of at most three words.

Architecture — the shared-chrome contract in `tokens.yml`: dialects restyle surfaces but
never invent a second z-scale, tap floor or skip-link; the dialect map (social → brgen,
luxury → amber, bsdports ultraminimal white, radio dark_audio, master face_root CRT-flat,
mrdamascy standalone with `--signal` naming under `brand.rb`); and the constitutional
dimensions of `visual_rubric.yml`: hierarchy, alignment, rhythm, density, states, motion,
content, affordance.

## Per-surface verdicts

| Surface | Typography | Graphic | Architecture | Overall |
|---|---|---|---|---|
| bsdports | 5 | 4.5 | 5 | 4.5 |
| mrdamascy | 4.5 | 4 | 4.5 | 4.5 |
| master | 4.5 | 4.5 | 4 | 4 |
| brgen (feed) | 4 | 3.5 | 3.5 | 3.5 |
| brgen_marketplace | 4 | 3.5 | 4 | 3.5 |
| brgen_messenger | 4 | 3.5 | 3.5 | 3.5 |
| brgen_radio (tv) | 3.5 | 3 | 3.5 | 3 |
| brgen_radio (radio) | 3.5 | 2.5 | 3.5 | 2.5 |
| amber | 3 | 2.5 | 3 | 2.5 |
| brgen_dating | 3 | 2.5 | 3 | 2.5 |
| brgen_maps | 3 | 2 | 3 | 2 |

### bsdports — 4.5/5, the dialect's best student

The ultraminimal-white contract is kept exactly: white ground, Arial-class sans, blue
underlined links, square corners, no radius, no chrome heavier than the content. The page
says what it is ("OpenBSD-porter"), states its keyboard affordance ("Trykk / eller ⌘K for å
fokusere søk"), and its two states are honest: "Laster mer…" where more rows arrive, and
"Ingen importering er kjørt." with two recovery buttons where nothing has been imported.
Both follow the empty-state law — one truth sentence, one verb. The repeated grey
"oppdateringskalender…" comment under each row is data, not noise, but on a capture of
twenty seeded rows it reads as filler; a quantity knob on seeds would make the surface look
as disciplined as its stylesheet. The shared-chrome footer line (changelog, affiliate
notice, commit hash) is cramped onto one baseline-separated line and is the only typographic
loose thread.

### mrdamascy — 4.5/5, the most craft per pixel

The standalone kitchen app is the strongest all-round surface: matte paper ground, one green
signal (#276B55 sampled) reserved for add-to-cart and confirm actions, clear item
hierarchy (name, price, origin chip, weight, heat dots), generous spacing on a steady
rhythm, and microcopy that is honest rather than decorative ("Ekstra sterk? Uten løk? Vi
leser alt (valgfritt)", "Mock-innlogging — bare dev og test"). States are the family's most
complete: cart, checkout, tracking, loyalty, offline ("Du er offline… Prøv igjen"), staff
board and orders each have a real resting state, and the empty states follow the law ("Kurven
er tom — ennå." / "Ingen bestillinger ennå"). Deductions: `config/locales/nb.yml` ships
"Drikkegis" as the Norwegian word for a tip — not snl.no bokmål ("drikkepenger"); several
locale strings use two dot separators on one line ("3 steg · ingen kortfelter · trygg
betaling", "Kurv · %{count} · %{total}", the hero's "★ 4,9 · Man–Fre 11–21 ·
Lør–Søn 14–21"), which `NO_DOT_SEPARATED_META` names as a flat string the reader must
parse; and the emoji icon set (🌯 🍽 🍟 🥤) is a second icon vocabulary where the house
prefers words.

### master — 4/5, identity-exact

The face page is the visual identity verbatim: greyscale ASCII field on black, deep-blue
band in the header (#143D5B sampled), zero radii, monospace confined to the machine voice,
one truthful status line ("master varmer opp…"). Motion is absent from the still capture,
which is what the "motion defaults to still" policy wants. The one deduction is noise on a
consumer surface: the input bar leads with a raw conversation UUID
("c-6ae1e85a-145cf406-…") — dmesg-truthful, but a random identifier is not information a
reader can act on, and `DENSITY` would spend it on something meaningful.

### brgen feed — 3.5/5, right bones, unfinished edges

The feed keeps the family bones: a centred column near the 600px feed measure
(`MEASURE_OPTIMUM` holds), quiet Helvetica hierarchy, real Norwegian throughout, and the
"Lokal aktivitet" panel pairing one heading with one verb-button ("Lukk"). Deductions: the
desktop capture shows two posts and then roughly two viewport-heights of blank white (the
mobile capture is worse — content ends under the consent banner and ~1500px of ground
follows), which is either a lazy-load capture artifact or a genuinely starved feed —
INCONCLUSIVE, but it is the screenshot a reader sees; the mobile bottom bar is seven
icon-only taps with no words, against "words before icons" and the 44px floor; and the
"Logg inn" nav pill carries a trailing arrow glyph, the exact shape `NO_TRAILING_ARROW`
forbids on a control whose styling already says "followable".

### brgen_marketplace — 3.5/5, strong hero, borrowed blues

The promoted hero has the best pure hierarchy in the family: category label, two-line
display heading, two-sentence promise in a held measure, price, one action. Deductions: the
right tile is a bare letterform "B" sampled at #1E40AF — a Tailwind-class blue, not the
brgen band, and it reads as a missing-asset fallback rather than a mark; the offer price is
set in red, which collides with the shared `color_danger` and has no state to explain it;
and the utility strip on top ("Fri levering fra 20", "Rask levering…", "Fri retur") sits as
three floating fragments whose separation is spacing alone.

### brgen_messenger — 3.5/5, exemplary empty state

"Ingen samtaler ennå" plus "Send en melding for å starte." plus one action is the textbook
empty state the law asks for, and the page stays quiet around it. Deductions: the left rail
renders a stack of bare "#" glyphs where channels should be — unfinished chrome in an
otherwise finished surface; the page title sits inside a grey slab that reads as a selected
row rather than a header; and the helper line repeats "Logg inn" twice in one sentence.

### brgen_radio (TV) — 3/5, off-dialect accent

Structure and copy are right (one heading, one promise, "Populære videoer" with duration
badges), but the active "Strøm" toggle is painted in the danger red (sampled #DC635C against
the shared `color_danger` #d1594a) — the selected state of a benign toggle wears the colour
the house reserves for failure. The sibling "Kanaler" pill is white-on-hairline, so the
pair also breaks the "same interaction vocabulary" affordance rule.

### brgen_radio (radio) — 2.5/5, the capture hides the product

Typography and nav are family-correct ("Lyd fra Bergen" label, "Hør hva byen lager" display
line, "Bla i spor" with no trailing arrow), but "Utvalgt spor" — the page's whole reason —
renders as an empty grey frame in the capture, with the track title clipped under the
consent overlay. Either the player needs a resting state for its unloaded artwork, or the
capture fired before the frame filled; as evidence it is INCONCLUSIVE, and as a screenshot
it undersells the surface.

### amber — 2.5/5, the dialect drifts

The amber contract in `tokens.yml` is a greyscale family ("light_accent: #000000") so the
garment is the only colour on the page; the collection cards instead carry sampled pastels
(#E8DEF6 lavender, #DCECF8 blue, #DFF1E7 mint). That is a second palette inside one identity
— exactly what `visual_directives.yml` forbids inventing inside a refinement — and it is
operator-owned, so the finding is a request to either tokenise the pastels as an explicit
amber campaign adaptation or return the cards to the family ground. The desktop capture also
breaks "Bymorgen" mid-word across three lines ("Bym / org / e / n") while mobile renders it
whole — an intrinsic-sizing failure on the card's text zone. Vertical gaps between cards
read as arbitrary against the 8px rhythm. The footer directory, by contrast, is disciplined
and almost law-clean.

### brgen_dating — 2.5/5, the lorem is the story

The shell is right and the pills are honest about their verbs ("Angre", "Matcher",
"Kryssede spor", "Opprett profil"), but the discovery cards under the fold render Latin
filler ("Provident vitae exercitationem. Sed ullam cum…") — and `brgen/db/seeds.rb` line 282
already rules on this in the tree's own voice: "Latin lorem read as a scam sign". The
rendered surface contradicts the repo's own written decision, which is why this is the
highest-priority content defect in the set. The pills also look vertically clipped and below
the 44px touch floor at capture scale — INCONCLUSIVE without a measurement. The nav flips to
a light chrome here while the brgen apex renders dark (see cross-cutting note below).

### brgen_maps — 2/5, data leaking through the paint

Every row of the near-search list carries the raw label "place" above the venue name — the
seed vocabulary rendered to Norwegian users, `DENSITY` and the content rubric's "real
Norwegian strings" both fail on it, and the repetition turns the page into a monotone grey
rhythm with no grouping. The search dropdown also collides with the site header in the
capture (the "brgen" wordmark is overdrawn), which is a layering or scroll-integrity defect.
The venue names themselves carry "check" suffixes from seeded data. Underneath all of this
the bones are the family's — the fix is data hygiene, not layout.

## What the family does well

One sans everywhere. No serif, no second display face, no tracked all-caps eyebrow appears
on any of the ten surfaces; `swiss_sans_only` and `NO_EYEBROW_LABEL` hold across the whole
set, and monospace appears only where the law allows it (master's machine voice, code
chips).

The engine architecture is legible in the chrome. The brgen verticals all carry the same
nav with the active engine underlined, the same consent partial, the same bottom bar — the
"verticals inherit Brgen identity" rule is visible without reading a word of code, and
mrdamascy's independence (it mounts none of the engine) is equally visible in its separate
shell. The shared shell is doing exactly what `TREE_CONTRACTS.md` says it should.

Empty states are a house strength. Messenger, mrdamascy (cart, orders), bsdports and the
bsdports import flow each state one truth and offer one verb, which most products never get
right.

Honesty is rendered, not just claimed. The Vipps mock says it is a mock; the offline screen
says the cart survives; bsdports says no import has run; master says it is warming up.
`AESTHETIC_RAMS_SEMANTIC` (honest progress, no dishonest states) holds on every surface
where a state exists.

Dash hygiene. Norwegian ranges render with real en dashes ("Man–Fre 11–21",
"Lør–Søn 14–21") — `EN_DASH_RANGE` holds in the rendered copy, not just in the linter.

## Cross-cutting defects

1. **Latin lorem on a shipped surface (dating).** Highest priority; the repo's own seeds
   comment names Latin filler a scam sign. Re-seed the discovery decks from the Norwegian
   opener bank and re-capture.
2. **Raw data vocabulary on a shipped surface (maps).** "place" as a row label and "check"
   suffixes in venue names. Translate or drop the label; the kind is already in the name.
3. **Danger red as a selected state (TV).** Selected-state paint must come from the accent
   family, not `color_danger`.
4. **A second palette inside amber.** Tokenise the pastels as an explicit operator-owned
   adaptation or return the cards to the luxury ground.
5. **Dot-separated meta in mrdamascy locales.** Split the facts into elements per the law's
   `good` shape, or accept and document the separator as brand voice.
6. **Trailing arrow on brgen's "Logg inn" pill.**
7. **Icon-only seven-item bottom bar on brgen mobile.** Add words (the law prefers words
   before icons) or at minimum accessible names.
8. **Shell flip between the brgen apex (dark nav) and its engines (light nav).** One of the
   two is drift; `tokens.yml` should own the decision as an explicit adaptation so the next
   vertical knows which band it inherits.
9. **"Drikkegis" is not bokmål.** "Drikkepenger" per snl.no, or a deliberate coinage marked
   as brand voice in the locale file.
10. **Amber desktop word-break, marketplace "B" tile, messenger "#" rail, master UUID.**
    Four small unfinished edges, each one commit away from quiet.

## What the screenshots cannot prove

Motion behaviour, reduced-motion fallbacks, focus-visible rings, measured contrast at
runtime, real 44px touch geometry (the dating pills are suspected sub-floor but unmeasured),
and every state that exists only between frames. Blank regions on brgen and radio may be
lazy-load capture artifacts rather than shipped emptiness — the next capture pass should
dismiss the consent partial, scroll to settle, and use the existing capture tools
(`MASTER/tools/visual_capture.rb`, `web_screenshot.rb`) so evidence is comparable across
surfaces.

## Verdict

Typography 4/5 — one family, one scale, correct dashes; loses for the amber word-break and
case-inconsistent consent labels ("Avvis Valgfrie / Tilpass Valg / Godta Valgfrie").
Graphic design 3/5 — flat, calm, token-painted surfaces with real states; loses for
danger-as-active, amber's second palette, placeholder tiles and dot-separated meta strings.
Architecture 4/5 — the engine map is visible in the chrome, dialects own their surfaces, the
shared shell holds; loses for the apex/engine shell flip and the unfinished rails (# rail,
"B" tile, UUID).

The set's centre of gravity is already where the Laws want it: quiet, flat, Helvetica,
Norwegian, honest. The distance to full adherence is not a redesign — it is roughly a dozen
tagged, single-purpose fixes, most of them data and locale hygiene rather than paint.
