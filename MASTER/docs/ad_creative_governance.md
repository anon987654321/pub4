# Ad creative governance

## Implemented path

pub4 already has one advertising implementation path. Do not create a parallel
`AdOrgan` engine or a second visual token file.

- `MASTER/data/tokens.yml#tokens.ad_visual_contract` is the ad-specific visual
  value contract.
- `MASTER/lib/visual/ad_audit.rb` runs the six visual checks and refuses a
  missing or stale token version, wrong placement, missing check, or failed check.
- `MASTER/tools/visual/audit_ad.rb` produces the JSON audit report and uses
  `BrowserlessMeasurements` when a browser capture is not supplied.
- `RAILS/__shared` owns the existing shared ad partials, consent-aware AdSense
  slot, affiliate product presentation, disclosures, `AffiliateProduct` inventory,
  `Shared::Tradedoubler` importer and `Shared::LinkConverter`.

The audit receipt adds:

- `provenance.schema_version`: report schema version.
- `provenance.policy_sha256`: digest of the canonical `MASTER/data/laws.yml`
  source as read when the report was produced.
- `provenance.detector_sha256`: digest of `MASTER/lib/visual/ad_audit.rb`.
- `provenance.artifact`: SHA-256 digests of the exact HTML and CSS inputs plus
  the declared placement.
- `provenance.measurement`: mode, reported version and digest of the supplied
  rendered-evidence object; browserless reports also carry the source digest of
  `MASTER/tools/visual/browserless_measurements.rb`.
- `evidence_sha256`: SHA-256 over the complete report, including artifact digests
  and measurements,
  after normalizing object keys and excluding only this digest field.

The CLI reseals after it attaches measurement diagnostics, so the receipt covers
the JSON payload actually printed. `AdAudit.require_pass!` verifies the receipt,
current policy and detector sources, current token version, exact placement and all
six required checks before allowing a creative through the audit gate.

This is a **tamper-evident checksum, not a signature**. It does not authenticate
who supplied external renderer evidence, and a party able to rewrite a report and
recompute its checksum can forge one. Browserless evidence is bound to the current
repository measurement source; externally supplied evidence is labelled
`caller_supplied_unverified`. Do not describe the receipt as a signed audit,
third-party certification or proof that a browser was run.

## Copywriting design proposal

This section is an implementation brief, not a new Law catalogue or an active
runtime gate. The operator-owned `MASTER/data/laws.yml` is a sacred path and is
not changed by this automated implementation. A future Law addition needs an
ordinary, deliberate operator commit that updates the canonical catalogue,
`law_catalogue.entries`, its Ruby `Law.define` source and the reconciliation
tests together.

The useful DeepSeek ideas are evidence-led claims, audience-aware language,
headline clarity, one primary promise, authentic narrative and measurable
creative experiments. Adapt them as a review sequence rather than forcing one
copy formula onto every placement.

### Claim ledger before persuasive copy

Every factual or comparative claim should resolve to a source record before it
is drafted. A future claim record should carry:

- the exact claim text and the product/feed field or source artifact supporting it;
- source identity and source digest (or stable vendor record ID);
- market, locale and eligibility/offer conditions;
- observed/verified time and expiry or freshness policy;
- whether the claim is a measured fact, a merchant assertion, an estimate or
  an unverified hypothesis.

No evidence means no factual assertion. Price, discount, stock and delivery
claims must be tied to current feed facts and must not be embellished. A stale
product is omitted rather than rewritten into a confident claim. Avoid words
such as “best”, “cheapest”, “guaranteed” and “number one” unless the scope,
comparison set, date and evidence actually support them. A numeric headline is
not automatically more truthful or more persuasive.

### Audience, format and narrative

The brief should describe the intended audience in task terms supplied by the
publisher: need, context, level of product familiarity, locale and reading
register. Do not infer sensitive traits or mine private user data to manufacture
a persona.

Choose the structure by format:

- A compact product tile needs a specific, verifiable headline, useful product
  detail, price where current, merchant identity and a clear next action.
- A performance ad should put its primary promise in the headline; supporting
  copy proves or qualifies it rather than rescuing an empty headline.
- A longer brand narrative may use a story arc (person, tension, credible change)
  where the format and evidence justify it. Do not force a three-act story into
  every feed card or turn an unsupported brand aspiration into a fact.

Use the reader's language, not internal product jargon. English and Norwegian
Bokmål need separate lexical and editorial review. Preserve the source meaning;
do not silently invent testimonials, experience, scarcity, endorsements,
performance results or brand behaviour.

### Permission and disclosure are different controls

“Permission” must never be implemented as a phrase that appears in the copy.
Marketing consent is an actual subscriber/CMP or advertising-consent state, read
from the existing permission boundary. The existing AdSense partial correctly
renders nothing unless the configured slot and `advertising_consent?` both pass.
A word in a headline or a supplied `consent_signal` string is not consent.

Affiliate disclosure is a separate transparency duty, not a substitute for
advertising consent. Keep the existing shared disclosure partial, per-link paid
mark, translated labels and `rel="noopener sponsored"` behaviour. Do not insert
an AdOrgan-specific disclosure vocabulary or create a second affiliate link
builder. Tradedoubler feed IDs, program metadata and Link Converter website IDs
are distinct data; retain the existing Products API and `Shared::LinkConverter`
contracts rather than guessing a click URL grammar.

### Review and measurement sequence

A future `CopyReview` should return structured findings through the existing
MASTER review/finding contracts, not introduce a second detector registry. Each
finding should identify the claim, evidence reference, reason, suggested
revision, confidence and the surface/locale assessed. Missing evidence is
`INCONCLUSIVE`, not a pass. Hard factual errors and missing commercial
disclosure block publication; stylistic preferences remain review advice until
the operator deliberately makes them Laws.

Before a creative experiment, define the primary metric, conversion event,
comparison, audience/placement, sample-size rule and observation window. Report
the result with the experiment evidence. Do not describe a design as “proven” on
the basis of taste, a single anecdote or click-through rate alone.

A safe implementation sequence is:

1. Agree a claim-record contract and source/freshness policy for existing
   `Shared::AffiliateProduct` data.
2. Add a read-only `CopyReview` that checks the claim ledger, locale, format,
   disclosure and CTA; start with positive and negative fixtures.
3. Add deterministic checks only where the repository can prove both a known
   bad case and a known good case.
4. Have the operator add any normative Law IDs and their catalogue/source
   mappings in the protected Law files; run `LawRegistryAudit` and the
   existing three-modality assessment.
5. Integrate review into the existing `/fix` improvement path only after its
   evidence, lifecycle and refusal behaviour are covered by tests.

Do not add a new engine, migration, enforcement vocabulary or visual-token
source to accomplish this. The purpose is a more honest creative, not more
plumbing.
