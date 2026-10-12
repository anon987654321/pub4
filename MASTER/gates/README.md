# Gates

**A gate is a promise the repository makes to itself and keeps by machine: that
every page a visitor can reach is whole, honest and in the right language,
checked before anyone has to notice it is not.**

The gates judge the three Rails apps, brgen, amber and bsdports, together with
the MASTER web face. One runner, `runner.rb`, executes them. The registry,
`gates.yml`, declares them, and the runner adds no knowledge of its own. A
registry row names a class to run, or a script, and the line to print when the
gate passes. The registry also records which gates are covered by a composite,
so `--all` skips those leaves rather than running the same work twice.

## What they check

Some gates read source and need nothing running. They check that the app
inventory in `apps.yml` agrees with the ports and the engines, that migrations
match the schema, that no foreign key points at a table that is gone, that
stylesheets obey the CSS constitution and the type and scale contracts, that
payment and affiliate pages say what they do, that Stimulus controllers are
wired to something, and that the shared engine is mounted where the apps expect
it. A neighbouring group checks the surface schemas and the first screen of each
page.

Others simulate a visitor. The page simulation walks every full-page template,
checking its identity, its dead ends and its labels, and when the apps listen it
requests every public path that takes no id. The flow journey follows
multi-step paths declared in `data/flows.yml` and holds each to its
postconditions and to honest redirects. The human walkthrough and the user flow
gates probe the verticals and secondary hosts as a guest.

The rendered gates need a real browser. They load pages in Chrome through the
DevTools protocol, then measure geometry, reflow, occlusion, viewport spill,
keyboard order, phone-sized tap targets, WebGL surfaces and web vitals, and they
compare layout against snapshots committed under `data/layout_snapshots`. The
rendered suite bundles most of them. When no browser exists, a gate that needs
one reports itself inconclusive and does not pass. `web_vitals_budget` measures
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
canonical geometry inventory (including selected Brgen verticals), the gate also
compares the PNG against `data/visual_baselines/<app>-<surface>-<viewport>.png`
using the dependency-free `support/png_diff.rb` decoder. Structural
`snapshot: true` alone does not opt every route into PNG references. The manifest records exact changed
pixel counts, ratio, and a red/transparent heatmap. The default threshold is 1%
of pixels; `GATE_PIXEL_DIFF_MAX_RATIO=0` requests exact equality. Dimension
changes always fail. Missing baselines are clearly reported as soft findings
until `GATE_PIXEL_BASELINE_STRICT=1` is enabled; corrupt or unsupported images
are never treated as equal.

PNG approval is separate from autofix. After reviewing the screenshots, run
`GATE_PIXEL_BASELINE_APPROVE=1 ruby MASTER/gates/runner.rb browser_diagnostics`
and inspect `MASTER/gates/data/visual_baselines` before committing. Only
successfully rendered surfaces without blocking runtime defects are written.
See `data/visual_baselines/README.md` for the baseline workflow.

Uncaught JavaScript exceptions, document HTTP errors, first-party server errors,
failed first-party scripts/stylesheets, and missing screenshot evidence fail the
gate. Ordinary console errors/warnings
and other resource failures remain soft until `GATE_STRICT_SOFT=1`, preserving the
existing severity calibration. Each route/viewport prints PASS, FAIL, SKIPPED or
INCONCLUSIVE and the manifest links its screenshot and detailed browser evidence.
Closed app ports are explicitly skipped; absent Chromium or no reachable apps is
inconclusive rather than green.

Run a focused inventory slice while diagnosing one surface, or run the entire
declared set:

```zsh
ruby MASTER/gates/runner.rb browser_diagnostics
GATE_SURFACES=brgen/marketplace,amber ruby MASTER/gates/runner.rb browser_diagnostics
GATE_BROWSER_DIAGNOSTICS_SETTLE_MS=800 ruby MASTER/gates/runner.rb browser_diagnostics
```

`GATE_BROWSER_DIAGNOSTICS_OUTPUT` overrides the artifact root, and
`GATE_BROWSER_DIAGNOSTICS_SETTLE_MS` bounds the post-load settling window
(0–5000 ms). The gate is also a leaf of `rendered_suite`, so the standard
composite and `--all` paths include it once, with no separate browser framework
or new runtime dependency.

A last group checks the checkers. The mutation gate plants known defects and
requires the other gates to catch them. The calibration gate keeps the design
metrics honest against fixed good and bad exemplars, which sit under
`fixtures`.

## Three outcomes

A gate passes, fails or is inconclusive, and a gate that raises is recorded as
errored. The difference matters. A gate that could not measure anything, because
the browser was missing or the apps were down, is inconclusive. It must never
read as a pass. The runner prints a summary of each outcome and exits non-zero
on a failure. The environment variables `GATE_STRICT_INCONCLUSIVE` and
`GATE_STRICT_ERRORS` make the other two block as well, and `GATE_STRICT_SOFT`
promotes soft findings to failures. Every run is appended to a ledger, and
`--ledger` prints what the ledger holds.

Gates that can repair what they find do so by default and measure again.
`--scan-only`, `--no-autofix` or `GATE_AUTOFIX=0` makes a run read-only.

## Three rules the gates have paid for

A gate that demands one of several correct outcomes reports the environment as
the tree. Amber's demo redirects home without a seeded wardrobe, and brgen's
marketplace shows an empty state without listings, so a check that insists on
the populated branch reads an empty database as a broken app. Name the set of
correct answers and keep each falsifiable.

A test that runs a gate over this tree and asserts clean proves nothing, since
it also passes against a gate whose body returns ok. Plant the defect, assert
red and named, remove it, assert green, and drive the test once against a
gutted gate.

Check what the instrument opens before believing what it says. A stylesheet
lint that globs a directory misses what the bundle pulls in through `@use` and
`@forward`, and a class extractor that stops at a quote cannot read a Ruby class
value with interpolation in it.

## Run

The apps come up with the operator, which reads their ports from `apps.yml`. The
whole ladder, including these gates, runs through `bin/operator gate`. To run
only these, name them or pass `--all`. `--explain` lists every gate with its
pass line and the environment switches the runner honors.

```zsh
MASTER/bin/operator triangle up
ruby MASTER/gates/runner.rb page_simulation flow_journey
ruby MASTER/gates/runner.rb --all
ruby MASTER/gates/runner.rb --ledger
```
