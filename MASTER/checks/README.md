# Checks

> **Terminology and authority.** The preferred user-facing term is **check**. This guide keeps **check** where it names existing implementation classes, environment variables, or commands; this is a glossary banner, not a partial mass rename. A Law is a normative requirement, a check is an instrument, and proof is evidence about what was measured. Source authority runs `soul.yml > laws.yml > executable laws and gates > tree contracts > Git history`. Soul owns global identity, preservation and protected paths; `laws.yml` owns individual Law identities, statements and internal invariant order. The registry in checks.yml is an execution inventory, not a second Law catalogue. The executable Law DSL reads per-Law policy from `laws.yml#law_catalogue`; `law_runtime.yml` retains runtime configuration and is guarded against a duplicate Law catalogue. See MASTER/docs/synonyms.yml. Do not invent hard/soft/ops tiers. Machine outcomes such as skipped, inconclusive, and gaps remain distinct.

**A check is a promise the repository makes to itself and keeps by machine: that
every page a visitor can reach is whole, honest and in the right language,
checked before anyone has to notice it is not.**

The checks judge the three Rails apps, brgen, amber and bsdports, together with
the MASTER web face. One runner, `runner.rb`, executes them. The registry,
`checks.yml`, declares them, and the runner adds no Law authority. A registry
row names a class to run, or a script, and the line to print when the check
passes. The registry also records which checks are covered by a composite, so
`--all` skips those leaves rather than running the same work twice. Before any
check starts, the runner validates the registry root and refuses a row that
has neither `class:` nor `script:`. A headless row is a configuration error,
not an outcome from a check that actually ran.

## What they check

Some checks read source and need nothing running. They check that the app
inventory in `apps.yml` agrees with the ports and the engines, that migrations
match the schema, that no foreign key points at a table that is gone, that
stylesheets obey the CSS constitution and the type and scale contracts, that
payment and affiliate pages say what they do, that Stimulus controllers are
wired to something, and that the shared engine is mounted where the apps expect
it. A neighbouring group checks the surface schemas and the first screen of each
page. One more reads the craft ledger:
`exemption_freshness` holds every recorded exemption to its `review_by` date —
fails the row whose review has passed, fails a row whose law no executable law
file declares, and warns when a review comes due — so an excuse recorded once
cannot quietly outlive its argument.

Others simulate a visitor. The page simulation walks every full-page template,
checking its identity, its dead ends and its labels, and when the apps listen it
requests every public path that takes no id. The flow journey follows
multi-step paths declared in `data/flows.yml` and holds each to its
postconditions and to honest redirects. The human walkthrough and the user flow
checks probe the verticals and secondary hosts as a guest.

The rendered checks need a real browser. They load pages in Chrome through the
DevTools protocol, then measure geometry, reflow, occlusion, viewport spill,
keyboard order, phone-sized tap targets, WebGL surfaces and web vitals, and they
compare layout against snapshots committed under `data/layout_snapshots`. The
rendered suite bundles most of them and is a required leaf of `layout_suite`, not a separate optional proof. A source-clean layout cannot pass acceptance if the browser is absent, a route is skipped, a measurement is inconclusive, a visual baseline is missing, or a rendered check has an unapproved finding. `web_vitals_budget` measures
LCP and CLS on one mobile first screen per app, using the canonical
`pixel_snapshot` inventory; it source-checks INP collection rather than inventing
an INP value from a scripted load with no real user interaction.

`browser_diagnostics` adds runtime evidence to that same CDP path. For each reachable
route in `data/geometry_surfaces.yml`, at its declared viewport, it records console
messages, uncaught JavaScript exceptions, failed HTTP responses, failed resource
requests, and a PNG screenshot. It writes a run-scoped `manifest.json` and
screenshots under the system temporary directory
(`pub4-browser-diagnostics/<run-id>/`).

For the deliberately small set of surfaces marked `pixel_snapshot: true` in the
canonical geometry inventory (including selected Brgen verticals), the check also
compares the PNG against `data/visual_baselines/<app>-<surface>-<viewport>.png`
using the dependency-free `support/png_diff.rb` decoder. Structural
`snapshot: true` alone does not opt every route into PNG references. The manifest records exact changed
pixel counts, ratio, and a red/transparent heatmap. The default threshold is 1%
of pixels; `CHECK_PIXEL_DIFF_MAX_RATIO=0` requests exact equality. Dimension
changes always fail. Missing baselines are clearly reported as soft findings
until `CHECK_PIXEL_BASELINE_STRICT=1` is enabled; corrupt or unsupported images
are never treated as equal.

PNG approval is separate from autofix. Run diagnostics first, inspect the
captured screenshots and manifest, then promote the exact files reviewed with
`ruby MASTER/tools/approve_visual_baselines.rb --manifest PATH`. The tool checks
the capture hash, dimensions, route inventory and runtime status, and refuses to
overwrite an existing reference unless `--replace` is explicit. See
`data/visual_baselines/README.md` for the workflow.

Uncaught JavaScript exceptions, document HTTP errors, first-party server errors,
failed first-party scripts/stylesheets, and missing screenshot evidence fail the
check. Ordinary console errors/warnings
and other resource failures remain soft until `CHECK_STRICT_SOFT=1`, preserving the
existing severity calibration. Each route/viewport prints PASS, FAIL, SKIPPED or
INCONCLUSIVE and the manifest links its screenshot and detailed browser evidence.
Closed app ports are explicitly skipped; absent Chromium or no reachable apps is
inconclusive rather than green.

Run a focused inventory slice while diagnosing one surface, or run the entire
declared set:

```zsh
ruby MASTER/checks/runner.rb browser_diagnostics
CHECK_SURFACES=brgen/marketplace,amber ruby MASTER/checks/runner.rb browser_diagnostics
CHECK_BROWSER_DIAGNOSTICS_SETTLE_MS=800 ruby MASTER/checks/runner.rb browser_diagnostics
```

`CHECK_BROWSER_DIAGNOSTICS_OUTPUT` overrides the artifact root, and
`CHECK_BROWSER_DIAGNOSTICS_SETTLE_MS` bounds the post-load settling window
(0–5000 ms). The check runs inside `rendered_suite`, which is required by `layout_suite`; there is one route inventory and one browser transport, with no separate browser framework or new runtime dependency.

A last group checks the checkers. The mutation check plants known defects and
requires the other checks to catch them. The calibration check keeps the design
metrics honest against fixed good and bad exemplars, which sit under
`fixtures`.

## Four outcomes

A check passes, fails or is inconclusive, and a check that raises is recorded as
errored. The difference matters. A check that could not measure anything, because
the browser was missing or the apps were down, is inconclusive. It must never
read as a pass. The runner prints a summary of each outcome and exits non-zero on a
failure or errored check. A check crash remains a distinct `errored` outcome
for diagnosis, but it can never count as a pass and cannot be made successful
by an environment switch. `CHECK_STRICT_INCONCLUSIVE` makes an inconclusive
result blocking, and `CHECK_STRICT_SOFT` promotes soft findings to failures.
Every run is appended to a ledger, and `--ledger` prints what the ledger holds.

The two flow checks, `user_flow` and `flow_journey`, say what happened to each
app. An app whose port is closed is reported as skipped because the app is down,
by name, with the flows it took with it, and the check is inconclusive however
many source checks ran beside it. A skipped app is never a pass. The variable
`CHECK_SOURCE_ONLY` says a run is meant to be source-only and keeps the check green;
on the deploy host `CHECK_REQUIRE_LIVE` turns the same skip into a failure.
`FLOW_BRGEN_PORT`, and the same name for each other app, points one app's flows at
a copy booted on a spare port.

Journeys marked as mutating create accounts, posts, listings and orders, and read
them back. They run against a development database and are refused on the deploy
host, where the port they would write to serves production, unless
`CHECK_ALLOW_WRITES` says the copy is disposable. They sign up with an address made
unique for each run, and they read confirmation and reset mail from the app's
`tmp/mails` directory, where the development mailer writes it.

Checks that can repair what they find do so by default and measure again.
`--scan-only`, `--no-autofix` or `CHECK_AUTOFIX=0` makes a run read-only.

## Baymard-informed UX review

The `baymard_ux` check is an original, independently worded assessment profile informed by public Baymard research. It is not an official Baymard audit, score, certification or affiliation. The research is ecommerce-heavy; commerce-specific journeys are applied only where the app inventory indicates that the feature exists. The audit does not impose one visual identity on Brgen, Amber, BSDPorts or their verticals.

Baymard's public methodology describes 200,000+ hours of research, 4,400+ participant/site sessions, and 54 rounds of manual benchmarking across 344 major US and European ecommerce sites. That methodology page describes the benchmark as 818 guidelines; the live benchmark page now presents 1,254 guidelines across desktop web, mobile web and mobile apps. These are differently scoped public research views, not totals to combine or scores MASTER can claim. The profile also cites Baymard's [checkout research](https://baymard.com/research-articles/ecommerce-checkout-usability-report-and-benchmark), [2026 cart-abandonment data](https://baymard.com/lists/cart-abandonment-rate) and [inline-validation research](https://baymard.com/research-articles/inline-form-validation).

The 2026 abandonment research distinguishes shoppers who were just browsing or not ready to buy from people reporting avoidable friction. That distinction is built into the audit: an abandonment percentage is not itself a diagnosis, and a purchase-flow improvement must not hide costs or undermine a visitor's ability to decline.

The source lane measures a bounded set of inspectable markup and stylesheet contracts: form-control names, image alternatives, interactive names, non-native click targets, focus-outline suppression and viewport declarations. Framework-generated controls and ambiguous cases remain inconclusive until the rendered browser can inspect them. Existing rendered checks still own geometry, contrast, keyboard execution, touch targets, overflow and visual snapshots.

The task lane describes participant or expert tasks for first-screen comprehension, navigation findability, search recovery, offer evaluation, cart editing and cost comprehension, checkout recovery (including inline error timing and retained values), mobile completion, and keyboard/screen-reader operation. The mapped laws also reject coercive conversion tactics such as hidden charges, deceptive urgency, unnecessary forced accounts and obstructed refusal or cancellation. Source text cannot prove that a person understood a page or completed a journey. Without task evidence, these assessments remain `INCONCLUSIVE`; they are never silently counted as passes.

Run the audit by itself or as part of the layout suite:

```zsh
rake -f MASTER/Rakefile ux:baymard
ruby MASTER/checks/runner.rb baymard_ux
BAYMARD_EVIDENCE=MASTER/.master/baymard/evidence.yml ruby MASTER/checks/runner.rb baymard_ux
BAYMARD_STRICT=1 BAYMARD_EVIDENCE=MASTER/.master/baymard/evidence.yml ruby MASTER/checks/runner.rb baymard_ux
```

The evidence file is repository-local YAML with `schema: 1` and an `apps` mapping. Each task row names `status: pass`, `status: fail` or `status: inconclusive`; a non-inconclusive verdict also requires a method (`moderated_user_test`, `expert_walkthrough`, `browser_task` or `screen_reader_review`), a positive participant count, an anonymised aggregate observation and one or more artifacts. Artifacts are limited to text/structured notes or screenshots (Markdown, text, JSON, YAML, PNG, JPEG or WebP), each with a repository-relative path and SHA-256 digest, and are capped at 2 MB each. Text artifacts are scanned for email addresses, phone-like strings and common structured participant/customer name or ID fields; this is a guardrail, not a complete PII detector. Manually anonymise and review every artifact before storage. Image artifacts require `redacted: true` as an explicit human attestation; the audit checks file signature and hash, not whether image content is actually redacted. Raw audio/video, participant names and identifiers must not be stored. Missing, changed, oversized, escaped, symlinked or unsupported evidence remains inconclusive. `BAYMARD_STRICT=1` makes unresolved task evidence blocking.

The report separates measured pass/fail counts from inconclusive and not-applicable assessments, includes source paths and line numbers, and explicitly reports no official Baymard score. A clean source scan is not a usability certification: task observations and rendered browser evidence remain separate proof.

## Three rules the checks have paid for

A check that demands one of several correct outcomes reports the environment as
the tree. Amber's demo redirects home without a seeded wardrobe, and brgen's
marketplace shows an empty state without listings, so a check that insists on
the populated branch reads an empty database as a broken app. Name the set of
correct answers and keep each falsifiable.

A test that runs a check over this tree and asserts clean proves nothing, since
it also passes against a check whose body returns ok. Plant the defect, assert
red and named, remove it, assert green, and drive the test once against a
gutted check.

Check what the instrument opens before believing what it says. A stylesheet
lint that globs a directory misses what the bundle pulls in through `@use` and
`@forward`, and a class extractor that stops at a quote cannot read a Ruby class
value with interpolation in it.

## Run

The apps come up with the operator, which reads their ports from `apps.yml`. The
whole ladder, including these checks, runs through `bin/operator check`. To run
only these, name them or pass `--all`. `--explain` lists every check with its
pass line and the environment switches the runner honors.

```zsh
MASTER/bin/operator triangle up
ruby MASTER/checks/runner.rb page_simulation flow_journey
ruby MASTER/checks/runner.rb --all
ruby MASTER/checks/runner.rb --ledger
```

`--json` prints one JSON document instead of the dmesg lines — every named
check's outcome, failure/warning/error lines, gaps and the summary — with the
same exit codes as the prose run. It exists so harnesses and foreign runtimes
can consume findings as data instead of parsing them back out of the log:

```zsh
ruby MASTER/checks/runner.rb --json --all > check_run.json
```
