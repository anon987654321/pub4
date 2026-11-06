# Restoration report — pub4.good BPLANS, November 2026

## What was restored, and from where

| Plan | Source generation | Restored content | Logo restored |
|---|---|---|---|
| syre | pub4 anlage (from pub3, superseding pub2/pub) | full completion + MASTER print-governance + compoundsøk | yes — «SYRE» fractal mark (Flower-of-Life pattern SVG) from pub/bplans/syre, static |
| speis | pub4 anlage | full completion + 3D-print/MASTER block for flight components | yes — «SPEIS» gradient wordmark from pub2 (#ff007f–#00c9ff–#ffcc00) |
| ragnhild | pub4 anlage + operator archive (tjenestesider, Ilumild page, halloween versions) | full completion + tjenestekatalog med partnere + søstermerket Ilumild + digital plattform + merkevarehistorie | yes — «Ragnhilds» wordmark in Nosifer (SIL OFL), the dripping halloween face |
| nato | pub4 anlage | full completion | none in any generation — nothing added |
| norwegianhedge | pub4 anlage (pub + pub2 variants consolidated) | full completion | yes — «NORWEGIAN HEDGE» gradient wordmark from pub2 |
| pubhealthcare | pub4 anlage | full completion + national platform block (hAPI/OpenBSD, SSHM, druglab/Laupsa) | none in any generation — nothing added |
| govt_bergen | pub4 anlage + Evighetspartiet document + Fetat hefte | full completion + FETAT (nytt barnevern) with the hefte's facts and effect targets + politietaten under loven («Byen vest for loven») + parametrisk arkitektur og Bergen-coin + partiets visjon, verdier, landskapstall, faser og finansiering | yes — «Bergens Selvstyreparti» gradient wordmark from pub2 |

Kept as-is, per the keep-list: pub4's FETAT working master
(`STUDIO/docs/fetat/proposal.md`, copied unchanged into this bundle).
`ai3` is not in the keep-list; its pub3/pub4 copies remain in the archives.
The retired Python build scripts are kept untouched in `scripts/legacy/`.

## What "complete" added (all seven plans)

Hvorfor nå · Kundeinnsikt og problemforståelse · Markedsføring og salg ·
Enhetsøkonomi · Milepæler og måltall · Resultatbudsjett 2026–2028 ·
Likviditetsbudsjett 2026–2028 · Risiko og risikoredusering · Behov for ekstern
kompetanse — placed inside the existing eight sections (the table of contents
is unchanged), all in the Bringhurst anlage with oldstyle/tabular figure
discipline. Every number comes from the plans' own figures or from the
operator's archive documents; nothing is invented.

## MASTER laws.yml — research and compliance

The whole of `pub4/MASTER/data/laws.yml` (3 736 lines: the axiom, nine
constitutional invariants, support laws, named principles, universal laws,
transformations, catalogue) and the relevant runtime sections of
`law_runtime.yml` (tool discipline, typography, Norwegian prose, visual
identity) were read before this build. See
`research/master-laws-research.md (bundled at BPLANS/research/)` for the per-law notes. The
operative consequences:

- **REACH_non_native_tool** bans python, bash, sed, awk, head, tail, wc,
  perl; "Use Ruby" — but Ruby/zsh do not exist on this host and cannot be
  installed (no root). The pipeline therefore runs on Node.js, which is not
  on the banned list, and invokes none of the banned commands. The retired
  Python scripts remain as archived data, parsed as text, never executed.
- **PRESERVE_FIRST**: the pub4 anlage files are read-only sources; all
  completion content is inserted, never rewritten. Two reviewed exceptions,
  both cosmetic and recorded: CRLF/trailing-space/blank-line normalisation of
  the archived fractal SVG markup, and one Norwegian leech word
  («virkelig») removed from ragnhild's preserved prose under
  STRUNK_WHITE.
- **BRINGHURST / OPERATOR_RENDERED**: 66-character measure, #F7F2E9 ground,
  EB Garamond for all text; the new Nosifer wordmark is brand artwork and
  never replaces a semantic heading (checked mechanically).
- **TRUTHFUL_STATUS / FINDING_HYGIENE / VERIFICATION_REQUIRED_FOR_COMPLETION**:
  checks that cannot parse their subject fail loudly as inconclusive instead
  of passing silently (two such defects were found and fixed in the verifier
  itself during this build).
- **EVIDENCE_SCORING**: arithmetic re-verified from the output files
  (test-pass equivalent), character/placeholder/law scan clean, and this
  report plus the docs are the review record.

## Cover revision — November 2026 (Bringhurst / Strunk & White)

After the restoration was verified, the front matter was revised on demand,
following a second research pass over Bringhurst's *Elements of Typographic
Style* and Strunk & White's *Elements of Style* (per-law notes and the full
rule inventory: `research/bringhurst-strunk-research.md`). The revision is
applied to the built documents by `scripts/bp_cover.mjs` (idempotent,
expected transforms enforced) — the anlage itself is untouched.

- **Title page**: the category kicker is omitted (Strunk & White, "Omit needless
  words"; the eyebrow element goes), the wordmark is centered and trimmed for
  poise (fractal 44→40 mm, the two remaining gradient marks 1.5→1.3 em, Nosifer
  2.35→2.1 em), the h1 drops from 600 to roman 400 at 2.05 em with balanced
  lines, and the header becomes a tall box (184 mm in print) with the mark near
  the top, the title and byline near the bottom, and no rule — Bringhurst
  p. 61: "poise consists primarily of emptiness…". The title page stands alone
  (forced page break), and the Innhold list gets its own quiet page (no
  hairline, row spacing .15→.45 em, no dot leaders — Bringhurst p. 35).
  At the customer's request, govt_bergen's wordmark was replaced by a **plain
  mark in the anlage's own EB Garamond** (1.3 em, tracked .05 em) — the pub2
  gradient was withdrawn and the colophon records the replacement.
- **Rhythm and margins (poise v2)**: every large vertical step sits on a larger
  multiple of the 1.5 rem leading unit — section openings 7.5 rem in print
  (5 units), footer 6 rem (4), contents padding 4.5 rem (3) — and the print
  margins widen from 16/15 mm to **18/17 mm** around the unchanged 66-character
  measure, so the added margin is pure void.
- **No blank leaves (poise v2.1)**: `main`'s 3 rem print padding-bottom is
  dropped in print — on syre it spilled a fully blank page before the colophon,
  the "wad of blank leaves" Bringhurst p. 72–73 condemns. The corpus was
  re-scanned for near-blank pages; none remain.
- **Mechanical side** (DUAL_MODALITY): bp_check.mjs verifies that the kicker is
  gone, that the poise v2 stylesheet and the 184 mm title-page print rule are
  present, and that govt_bergen carries the plain mark with no gradient
  wordmark left anywhere in the document.

## Verification results (November 2026 build)

- Page size of every PDF: 442.08 × 663.12 pt (156 × 234 mm, 2:3), identical
  to the originals; EB Garamond embedded (Chromium print).
- Page counts after the poise revision: syre 15 · speis 15 · ragnhild 17 ·
  nato 16 · norwegianhedge 14 · pubhealthcare 15 · govt_bergen 20 — each plan
  carries the standalone title page and contents page; syre reflects the
  removed spill page and norwegianhedge re-flowed under the wider margins.
- Budget arithmetic: verified by `scripts/bp_check.mjs` re-reading every
  output file — resultat rows (inntekt + kost = driftsresultat; + finans =
  før skatt), likviditet sums and year-to-year balance continuity for all
  seven plans, and the new govt_bergen financing table (4 + 3 + 2 + 1 =
  10,0). Zero failures.
- Law checks (lang, charset, single h1, heading hierarchy, final newline,
  tabs, trailing whitespace, blank-line runs, placeholders, line art,
  trailing arrows, leech words, character audit, font-face counts,
  wordmark-not-a-heading): zero failures.
- No placeholders (`TODO`, `XXX`, `【…】`, `undefined`, `NaN`) in any PDF.
- Zero external requests in every HTML: fonts, figures and logos are inline
  (reviewed exemption to NO_INLINE_STYLES: standalone print sources have no
  asset pipeline, same class as the law's own error-page carve-out).
- Visual check of rendered pages: covers (logo restoration), the ragnhild
  service/Ilumild/platform pages, the govt_bergen FETAT/police/party pages,
  the milestone and budget tables, and the colophons.

## Regenerating

The pipeline ships with this bundle under `scripts/`. Build, check,
index and print tools share `scripts/paths.mjs`, so they no longer depend on
one developer's home directory. The source tree defaults to this BPLANS
folder (`BPLANS_SOURCE_DIR` can point at a separate clean source tree); build
artifacts default to the operating system's temporary directory and can be
moved with `BPLANS_OUT_DIR`. The SYRE mark and Nosifer WOFF2 font are read
from the existing `syre.html` and `ragnhild.html` files. Chromium and
Poppler's `pdfinfo` are discovered on the host or selected with
`BPLANS_CHROME_BIN` and `PDFINFO_BIN`.

The original Python content files are not in this repository. The converted
`plans_a.mjs` and `plans_b.mjs` are committed build inputs, so the ordinary
build does not need the optional one-time converter. When the original data
files are available elsewhere, `BPLANS_LEGACY_SOURCE_DIR` selects their
directory for `convert_content.mjs`.

    node scripts/bp_cover.mjs          # front-matter revision (idempotent, Bringhurst/S&W)
    node scripts/bp_check.mjs          # independent verification
    node scripts/bp_index.mjs          # index.html
    node scripts/bp_print.mjs          # PDFs via Chromium

`bp_build.mjs` inserts the completion content unconditionally and is safe only
against a clean source tree (`BPLANS_SOURCE_DIR` pointed at pristine anlage
files); the committed HTML files already carry the completion content, so the
standing design-level sequence is `bp_cover.mjs` → `bp_check.mjs` →
`bp_print.mjs` → `bp_index.mjs` against the built files.
