# MASTER laws.yml — per-law research notes for the BPLANS restoration

Scope: the whole of `pub4/MASTER/data/laws.yml` (3 736 lines, schema 8) plus
the operative runtime sections of `data/law_runtime.yml` (tool discipline,
typography, Norwegian prose, visual identity contract). Every top-level law
was read; below is the structured summary and how each area binds this build.
Order and quotes follow the file itself.

## 1. The axiom

**APPLICATION_IS_UNIFORM** — every file passes through every law in both
modalities; no path skips a law; a file's kind is a fact, not an exemption.
Children ban: skipped laws, unrecorded findings, per-law reach sourced
outside law_catalogue, and the catalogue exempting itself.
→ Applied: the BPLANS HTMLs are judged by the same checks as any other file;
no "it is just a document" bypass is claimed anywhere.

## 2. The nine constitutional invariants

| Invariant | Core demand | How this build complies |
|---|---|---|
| **TRUTHFUL_STATUS** | Report observed state, never intent; claims carry evidence of their class; no simulated completion | Every number in the final report is copied from command output (pdfinfo, check runs); the Ruby-unavailable situation is reported as-is, not papered over |
| **ROBUSTNESS** | Fail safe, least authority, edge cases; the 2026-01-05 glob incident lives as NEVER_BATCH_DELETE | No batch deletion anywhere (explicit per-file `mv` only); the print step verifies page size per file and fails the run on deviation |
| **SINGULARITY** (with **DRY**) | One authoritative representation per fact; rule of three | One content source (plans_a/plans_b.mjs) feeds all outputs; index, budgets and logos derive from it; the ±3-site duplication guard is respected |
| **LINEARITY** | Sequential flow, minimal branches | The build is one straight pass per plan: read → insert → verify → write |
| **PROXIMITY** | Related things together; no div-itis | Completion content is inserted into the sections that own the topic; no wrapper elements added |
| **ABSTRACTION** | Right level, no leaky boundaries | Merge semantics ('+' append vs replace) are stated once, in one place |
| **DENSITY** | No noise, no dead code, no ASCII line art, kanso | No decorative separators, no filler prose; leech words audited |
| **OPERATOR_RENDERED** | Rendered values are operator-owned; the visual contract: signal and stillness; brand marks are original artwork; wordmark typography does not replace semantic page headings | Paper stays the operator's declared #F7F2E9; the restored gradient/fractal marks are the operator's own archived artwork, static; Nosifer carries only the «Ragnhilds» wordmark, never a heading (mechanically checked) |
| **INTER_MODEL_CONTRACT** | Evidence-backed findings only | Findings in the report cite their evidence (script output) |

## 3. Constitutional support

- **SACRED_AUTHORSHIP** — no autonomous write to paths declared sacred by
  soul.yml. The build writes only into `download/pub4.good/`; the anlage in
  `repos/pub4/` is read-only.
- **SOUL_SUBORDINATE_TO_LAW** — laws.yml alone owns law identities; nothing
  here restates or re-derives them.
- **DUAL_MODALITY** — every law has both a mechanical and a semantic side:
  the mechanical side is `bp_check.mjs`; the semantic side is the recorded
  review (this document and the restoration report).
- **FINDING_HYGIENE** — a finding is a hypothesis until evidence confirms;
  inconclusive never passes. Two verifier defects of exactly this shape
  (silently skipped foot-row checks; off-by-one foot indexing) were found
  and fixed during this build — the check now fails loudly when a table
  cannot be parsed.
- **BAYMARD_RESEARCH_BOUNDARY** (+ checkout/cost-transparency/user-agency
  children) — public research is evidence, not authority. The Innovasjon
  Norge and business-plan research informs the completion content; it never
  overrides the operator's own product identity. Cost transparency is also
  the plans' own sales argument (open price calculator).
- **ATTESTATION_IS_NOT_FINDING** — attestations and findings are kept
  separate: script outputs are findings with evidence; operator-owned
  aesthetic choices (the Nosifer wordmark) are declared as such.

## 4. The named principles

- **KISS / YAGNI** — the pipeline is five small Node scripts; no framework,
  no configuration layer.
- **POLA** — regeneration is the documented five-command sequence; output
  paths are unchanged from the earlier build.
- **SOLID / CQS / Law of Demeter** — each script does one job (convert,
  build, check, print, index); checks read the output files instead of
  reaching into the build's memory.
- **STRUNK_WHITE** — prose law with a Norwegian leech list
  (veldig, svært, ganske, nokså, temmelig, virkelig, simpelthen), active
  voice, positive form, one topic per paragraph. New content avoids all
  leeches; one leech found in the preserved ragnhild anlage prose was
  removed after review (recorded in the restoration report).
- **BRINGHURST** — measure 45–75 chars (66 where one number must serve —
  the anlage's own measure), rhythm on one grid, two text weights,
  no fake tables, no justified padding beyond the anlage's existing style.
- **RAILS_DOCTRINE** — convention over configuration: the build reuses the
  anlage's own class names (.mark, .numbers, table discipline) instead of
  inventing a parallel system.

## 5. Universal laws most binding here

- **REACH** family: HTML_LANG, META_CHARSET, SINGLE_H1, IMG_ALT (the
  decorative fractal carries aria-hidden), form/label and touch rules N/A
  for static print documents; **REACH_non_native_tool** is the operative
  one — see the toolchain note in the restoration report.
- **NO_INLINE_STYLES / NO_INLINE_SCRIPT_BLOCK** — reviewed exemption, same
  class as the law's own error-page carve-out: standalone print sources have
  no asset pipeline, so inline styles and inline fonts are the only
  mechanism that works; recorded in the restoration report.
- **HTML_HEADING_HIERARCHY** — h1→h2→h3 verified per file; the new blocks
  add h3 under existing h2 sections only.
- **TYPOGRAPHY_DISCIPLINE / TYPOGRAPHIC_EXCELLENCE** — the character audit
  restricts non-ASCII to the anlage's own set (Norwegian letters, guillemets,
  dashes, curly quotes, −, ₂/³, ™, ·, §, °).
- **NO_EYEBROW_LABEL / NO_TRAILING_ARROW / NO_ASCII_LINE_ART** — checked
  mechanically on every output file.
- **FINAL_NEWLINE / TAB_CHARACTER / TRAILING_WHITESPACE /
  NO_CONSECUTIVE_BLANK_LINES** — enforced at build (normalisation) and
  re-checked at verification.
- **COST_TRANSPARENCY / PERSUASION_truth_bearing** — every figure in the
  plans traces to the plans' own data or to the operator's archive documents;
  no scarcity/urgency decoration exists in the tree.
- **PRESERVE_FIRST / STEWARDSHIP (Chesterton's fence)** — the anlage is
  preserved; the two cosmetic normalisations are named, bounded and recorded
  rather than silent improvements.
- **GALLS_LAW / MONOLITH_FIRST / INTEGRATED_SYSTEMS** — one self-contained
  HTML per plan, exactly as the anlage already shapes them.

## 6. Transformations

The twelve operations (REMOVE, DEFRAG, FLATTEN, DECOUPLE, SPLIT, HOIST,
MERGE, RELOCATE, RENAME, REORDER, REFLOW, SIMPLIFY, RECOMMEND) are used as
vocabulary in the build notes; the one applied non-trivially is REORDER —
the FETAT facts were inserted inside the Plattformforslag 1 group rather
than appended after it, so primary facts sit with their subject.

## 7. Kinds, ratchets, lints

The output HTMLs are **KIND_PRODUCTION** (permanent review until the
operator re-reviews). The ratchets (unreachable laws, audit-blind spots,
exemptions without expiry) are respected by giving the two exemptions above
explicit reasons in the restoration report; no expiry-free silent
exemptions. LINT_* rules on the catalogue itself are MASTER-internal and
were not modified — this tree only reads laws.yml.

## 8. law_runtime.yml (operative sections)

- **zsh.banned_commands** = [sed, awk, tr, cut, find, head, tail, wc, perl,
  python, bash] with "Use Ruby" replacements — the basis for the Node
  pipeline decision (Ruby unavailable on host; see restoration report).
- **typography** — Bringhurst rules for terminal/prose/docs; the anlage
  already satisfies them; new content keeps the same discipline.
- **prose.nb** — leeches [veldig, svært, ganske, nokså, temmelig, virkelig,
  simpelthen]; `bare` deliberately absent (measured evidence in the file);
  periphrastic passive = ble/blitt + av. Applied to all new Norwegian copy
  and audited by bp_check.mjs.
- **visual_identity_contract** (signal_and_stillness) — flat surfaces, one
  restrained signal, brand marks are original artwork, wordmark typography
  does not replace semantic page headings, reduced motion respected (the
  restored marks are static by design).
