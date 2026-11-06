# bplans — seven concepts, one pair each

Restored from the pub, pub2 and pub3 archives into the pub4 anlage and completed
for Innovasjon Norge applications. Each concept is delivered as one self-contained
HTML document and one PDF printed from it. The separate `__templates/` directory
preserves the original `bob` and `bob2` correspondence in HTML and PDF form; those
files are historical source material, not part of the seven plan deliverables:

    syre.html + syre.pdf             3D-printede sko, NOK 250 000
    ragnhild.html + ragnhild.pdf     begravelsesbyrå (karaokekiste), NOK 150 000
    speis.html + speis.pdf           maritime og forsvar, NOK 500 000
    nato.html + nato.pdf             arktiske dominanseskip, NOK 500 000
    norwegianhedge.html + .pdf       Ruby-handelsroboter, NOK 300 000
    pubhealthcare.html + .pdf        autonome parametriske sykehus, NOK 500 000
    govt_bergen.html + .pdf          bergensk selvstyre-teknologi, NOK 200 000

Seven concepts, sought funding in total: **NOK 2 400 000**. (ai3 remains in the
pub3/pub4 archives but is not in the keep-list for this restoration.)

## The typographic contract

All fourteen files share one anlage, after Robert Bringhurst's *The Elements of
Typographic Style*: EB Garamond embedded in the document (SIL Open Font
License), a 66-character measure, 1.5 leading on one baseline grid, oldstyle
figures in running text and tabular figures in tables, guillemets and true
dashes, sentence-case titles, and a paper ground of #F7F2E9. No front page
shouts in uppercase. The HTML makes zero external requests — stylesheet,
figures and fonts are inline — so each file is its own archive copy, and the
PDF is printed from that same file so the pair cannot drift apart.

The plans are written in Norwegian for Innovasjon Norge applications:
sammendrag, markedsanalyse, teknologi og innovasjon, forretningsmodell,
utviklingsveikart, finansieringsbehov, team og kompetanse, bærekraft og
samfunnsansvar.

## What the completion added (November 2026)

To satisfy Innovasjon Norge's assessment criteria — innovasjon, marked,
gjennomføringsevne, vekstpotensial og behovet for støtte, plus their
oppstartstilskudd checklist (problemforståelse, løsning og usikkerhet, dagens
alternativ, segment og marked, IPR, team og gjennomføring) — every plan gained
seven new blocks inside the existing eight sections, with all figures derived
from each plan's own data:

- **Hvorfor nå** (sammendrag) — the timing argument.
- **Kundeinnsikt og problemforståelse** and **Markedsføring og salg**
  (markedsanalyse) — evidence from each plan's own pilots, and the go-to-market.
- **MASTER-adaptasjon og plattformforslag** (teknologi) — see below.
- **Enhetsøkonomi** (forretningsmodell) — per-unit economics table.
- **Milepæler og måltall** (utviklingsveikart) — milestone table.
- **Resultatbudsjett, Likviditetsbudsjett og Risiko** (finansieringsbehov) —
  three-year budgets and a risk matrix; the existing budget allocation doubles
  as the investeringsbudsjett.
- **Behov for ekstern kompetanse** (team) — what is bought in, and why.

All budget arithmetic is machine-verified (rows sum, cash balances carry
forward). Oldstyle figures stay in prose, tabular figures stay in tables.

## Platform proposals and MASTER adaptation

Per the restoration brief:

- **govt_bergen** carries three governance proposals on the same stack
  (OpenBSD, Ruby, pub4 MASTER law-catalogue governance):
  *FETAT — ny barnevernsforvaltning* (the FETAT/Familieetaten proposal, the new
  Norwegian Barnevern, working master at
  `STUDIO/docs/fetat/proposal.md`: evidence-based decisions, 48-hour first
  response, multidisciplinary teams, regional units, child hotline 123,
  independent review — now with the hefte's own facts: 24 EMD judgments under
  ECHR art. 8, NOK 26 bn annual cost across 356 kommuner, the 3 % vs 35 %
  appeal-approval contrast between Trøndelag and Oslo, NOU 2023:7, the four
  pillars, the 30 %/50 %/0/400 mill effect targets and the
  pilot-2026/validation-2027/scale-2028–30 phases, contact fetat.no),
  *politietaten under loven* (a police-integrity platform motivated by the
  «Byen vest for loven» findings: cryptographic chain-of-custody for evidence,
  protected complaint and whistleblower lines, open per-station statistics, AI
  pattern-flagging for human review only), and *parametrisk arkitektur og
  Bergen-coin* (adaptive municipal buildings, a local cryptocurrency under the
  same open-source transparency rules, smart contracts and the transparent
  open-source budget).

  The party movement behind the plan is imported from the Evighetspartiet
  document: motto «Frihet, autonomi, transparens», the five core values, the
  political landscape measurements (60/45/70/80), the five-point political
  platform (selvstyre, direkte demokrati, karbonnøytral 2030, boliger,
  næringsliv), the three movement phases (mobilisering, valgkamp,
  implementering — lokalvalget 2027 as the full-scale pilot) and the movement
  financing target of NOK 10 million (donations 4, crowdfunding 3, membership
  2, events 1 — sum machine-verified), kept strictly separate from the
  company budgets.
- **pubhealthcare** now states the national health platform behind the
  hospitals: hAPI on OpenBSD (the RFC-draft successor to FHIR from the pub
  archive), SSHM for molecular-scale patient modelling, the druglab
  synthesizing cube with Laupsa Pharmaceuticals, governed by MASTER's
  law-catalogue so no algorithmic decision touches a patient record without a
  human, documented, reviewable decision.
- **syre** (and by the SYRE technology-sharing, **speis**) now describe the
  adaptation of pub4's MASTER to the 3D-printer farm — every print job is a
  proposal admitted by the written law catalogue, scanner logs as evidence in
  the QA system — and the materials-science program that screens graphene-TPU,
  mycelium and self-healing polymer compounds against one test protocol and
  locks the winning compound into the law catalogue as production law.

## Ragnhild: archive material imported (November 2026)

The tjenestesider, the Ilumild booking page and the halloween versions from
the operator's archive are now woven into the plan:

- **Tjenestekatalog og partnere** — the full catalogue (Karaokekiste,
  Diskokiste, klovne-pallbærere, pyroteknisk avskjed, stand-up-eulogier,
  poetisk avskjed, sprø kistedesign, kiste med rutsjebane, romferd, musikalsk
  avskjed, Piratferd i flammene) with each service's fixed partner (Festbyrået,
  Lysmestrene, Latterfabrikken, Fyrverkeriekspertene, Humorhuset, Ordsmia,
  Kistegalskapen, Morrogutta).
- **Søstermerket Ilumild** — the quiet sister brand on the same booking
  platform: Basis fra 30 000 / Premium fra 60 000 / Deluxe fra 120 000 kroner
  plus 50/80/200 per guest, the 60-second calculator, Ro-modus, WCAG AA and
  the ≥ 12 % conversion target.
- **Den digitale plattformen** — the two-week MVP pilot and the OpenBSD/Ruby
  stack (Rails, Hotwire/Stimulus, OpenBSD, CRM), GDPR and encryption, offline
  fallback, authorised funeral contractors, green profile.
- **Merkevare og kanal** — the founder story (karaoke exile, ABBA, the
  2-million-follower begravelses-influencer, #EtterLivMålene), the signature
  «Vi tar vare på deg, selv når du ikke lenger tar vare på deg selv», and
  halloween as the annual campaign arena.

## Logos restored

If the original HTML carried a custom logo, it is restored as a static mark on
the opening page, with its provenance noted in the colophon:

- **syre** — the «SYRE» fractal mark (Flower of Life pattern-fill wordmark,
  SVG with displacement and glow filters) from the pub generation, static.
- **speis** — «SPEIS» gradient wordmark, pub2 generation
  (#ff007f – #00c9ff – #ffcc00), static.
- **norwegianhedge** — «NORWEGIAN HEDGE» gradient wordmark, pub2 generation,
  static.
- **govt_bergen** — «Bergens Selvstyreparti» set plain in the anlage's own
  EB Garamond at the customer's request (November 2026, «use plain, same font
  as the rest for now»); the pub2 gradient wordmark
  (#ff8c00 – #ff0080 – #8a2be2) was withdrawn, and the colophon records the
  replacement.
- **ragnhild** — «Ragnhilds» wordmark set in Nosifer (SIL Open Font License),
  the dripping face from the archive's halloween versions, restored at the
  operator's request. Nosifer carries the wordmark only; every semantic
  heading stays in EB Garamond, per the visual-identity contract in
  MASTER's laws (brand marks are artwork, wordmark typography never replaces
  semantic page headings).
- nato, pubhealthcare — no custom logo exists in any archived
  generation; nothing was added.

The gradients are kept at reduced size and static (no animation) so the marks
sit quietly in the Bringhurst anlage; the original CSS animations live on in
the pub2 archive.

## Build pipeline (law-compliant)

MASTER/data/laws.yml governs this tree. The committed build and check
pipeline is plain Node.js: it reads and writes files directly and does not
invoke Python, Bash, sed, awk or shell text processing.

The content port is already committed in `scripts/plans_a.mjs` and
`scripts/plans_b.mjs`. `convert_content.mjs` is an optional one-time
re-importer for the archived text sources; run it only when those two original
files are available, setting `BPLANS_LEGACY_SOURCE_DIR` to their directory.
Ordinary rebuilds start here:

    node scripts/bp_cover.mjs          # front-matter revision (idempotent)
    node scripts/bp_check.mjs          # independent verification of the outputs
    node scripts/bp_index.mjs          # regenerate index.html
    node scripts/bp_print.mjs          # print PDFs via Chromium

`bp_build.mjs` inserts the completion content unconditionally; the committed
HTML files already carry it, so design-level regeneration runs the four steps
above (with `BPLANS_OUT_DIR` set to the output directory) and leaves
`bp_build.mjs` for a clean anlage tree.

Source defaults to this BPLANS directory. Set `BPLANS_SOURCE_DIR` when using a
separate clean source tree. Generated files go to the system temporary directory
(`pub4-good-BPLANS`); set `BPLANS_OUT_DIR` to choose another destination.
The PDF step discovers Chrome/Chromium on the host; set `BPLANS_CHROME_BIN`
when it is not on PATH. `pdfinfo` (Poppler) is also required and can be
selected with `PDFINFO_BIN`.

bp_check.mjs executes the HTML/typography/prose laws (lang, charset, single
h1, heading hierarchy, final newline, tabs, trailing whitespace, blank-line
runs, TODO/placeholder scan, ASCII line art, trailing arrows, Norwegian
leech words, character audit, and the full budget arithmetic re-read from the
output files — inconclusive checks fail loudly, never pass silently).
