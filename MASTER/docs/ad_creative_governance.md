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
  and measurements, after normalizing object keys and excluding only this digest.

The CLI reseals after it attaches measurement diagnostics, so the receipt covers
the JSON payload actually printed. The existing `AdAudit.require_pass!` API is a
strict consumer-side gate: when called, it verifies the receipt, current policy
and detector sources, current token version, exact placement and all six required
checks. This change does not wire a new publication switch into RAILS or claim
that a publishing path calls this API at runtime.

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

`Master::Review::CopyReview` is implemented as a read-only Ruby API at
`MASTER/lib/review/copy_review.rb`. It accepts a creative Hash and a persisted
product object or Hash. The result carries `pass`, `fail` or `inconclusive`
status, coded findings, source references, suggestions, confidence and a digest
of the product snapshot. It makes no network request, database write or model call.

The deterministic claim kinds are exact product title, merchant, category,
feed price (integer minor units plus currency) and a small English/Bokmål
availability phrase set. Unknown claim kinds remain INCONCLUSIVE because the
product row does not establish them. A missing claim ledger is INCONCLUSIVE.
An explicit empty array records that the publisher supplied no claims, but the
review cannot independently prove that every factual statement was declared.
A reference string alone never upgrades an external claim to verified.

Example:

```ruby
report = Master::Review::CopyReview.review(
  creative: {
    headline: "Kjole – NOK 149.90",
    body: "Kjole fra Fjord Studio. På lager.",
    cta: "Se produktet",
    locale: "nb-NO",
    disclosure: "Annonse – annonselenke",
    claims: [
      { kind: "product_title", text: "Kjole" },
      { kind: "merchant", text: "Fjord Studio" },
      { kind: "price", text: "NOK 149.90" },
      { kind: "availability", text: "På lager" }
    ]
  },
  product: affiliate_product,
  market: "NO"
)

report.status # :pass, :fail or :inconclusive
```

Affiliate disclosure wording is checked separately from rendered prominence.
The existing visual audit still owns placement/contrast evidence, and the
existing consent boundary still owns advertising permission. A passing
CopyReview is not a publication approval and is not yet called by a live RAILS
publishing path or integrated into `/fix`.

Stylistic preferences remain review advice until the operator deliberately
makes them Laws. Normative policy still belongs only in the protected canonical
Law catalogue and its Ruby definitions.

Before a creative experiment, define the primary metric, conversion event,
comparison, audience/placement, sample-size rule and observation window. Report
the result with the experiment evidence. Do not describe a design as “proven” on
the basis of taste, a single anecdote or click-through rate alone.

A safe implementation sequence is:

1. The initial claim-record shape and freshness policy now use the fields
   already present on `Shared::AffiliateProduct`; external source documents
   still require a separately reviewed evidence adapter.
2. Implemented: read-only `CopyReview` API and positive/negative fixtures.
3. Extend deterministic checks only where the repository can prove both a known
   bad case and a known good case; leave unsupported claims INCONCLUSIVE.
4. Have the operator add any normative Law IDs and their catalogue/source
   mappings in the protected Law files; run `LawRegistryAudit` and the
   existing three-modality assessment.
5. Integrate review into the existing `/fix` improvement path only after its
   evidence, lifecycle and refusal behaviour are covered by tests.

Do not add a new engine, migration, enforcement vocabulary or visual-token
source to accomplish this. The purpose is a more honest creative, not more
plumbing.
