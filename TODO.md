# pub4 outstanding work

The one cross-tree backlog: work an agent in this checkout can do. Work that
needs the operator, a device, a credential, a paid call, ears or a console on
vm23 is a seam in `MASTER/data/operator_seams.yml`. Refusals live under
"Refused, and why" in `MASTER/AGENTS.md`. An item closes by being deleted in
the commit that carries its evidence; nothing here records finished work.

## Verification run, after the fixes below land

One pass on one commit, recorded as PASS, FAIL, INCONCLUSIVE, BLOCKED or
TIMEOUT per command. The 2026-10-25 and 2026-10-26 connector sessions committed
source and tests they could not run; this pass is what measures them.

- [ ] MASTER: `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 MASTER_TEST_PROGRESS_EVERY=25 rake test`,
  then `MASTER_TEST_JOBS=3 rake test`; check `.master/check/suite-report.json` for incomplete
  workers and mismatched start/result counts. Then `bin/check --profile=agent`.
- [ ] RAILS: `ruby RAILS/test/contract_runner_contract_test.rb`, `ruby RAILS/test/run_all.rb`, and
  `bin/ci` in each app in `RAILS/apps.yml`, including the 26 playlist, tv and takeaway tests
  that no command ran until `Pub4TestScope`, brgen's share-target, share-draft and job
  concurrency tests and a fresh test database for amber's `account_merges` and identity migrations.
- [ ] OPENBSD: `ruby OPENBSD/test/run_all.rb` and `ruby OPENBSD/test/test_evidence_tool.rb`, smoke-testing
  PASS, FAIL, BLOCKED, INCONCLUSIVE and TIMEOUT with process-group termination.
- [ ] STUDIO: `cd STUDIO && rake check test`, including the full `test/dilla_test.rb` (25 minutes;
  seven failures on 2026-10-23, reconciled in source on 2026-10-24 and never rerun).
- [ ] Generated outputs match their sources: `RAILS/__shared/design_tokens.yml`,
  `RAILS/master/public/face.runtime.js`, `face.css`, and `rake docs:agent_contracts` followed by
  `rake lint:agent_contracts`.
- [ ] The route suites on MASTER's pinned Ruby with Ollama absent: `test_route_policy.rb`,
  `test_lane_selection.rb`, `test_fix_fresh_checkout_models.rb`, `test_compute_pool.rb`,
  `test_fallback_chain.rb`, `test_lane_pool.rb`.
- [ ] Refresh `MASTER/data/self_findings.yml` through `ruby MASTER/lib/operator/self_findings.rb --ratchet` after source changes settle. Review the law and registry member deltas and both counts; the ratchet must refuse to raise either existing ceiling.
- [ ] Then `/fix` on the repository root: four independent reports, 30–40 grounded tournament
  candidates per tree, and each terminal state (DONE, PLATEAU, HUMAN_DECISION, BLOCKED,
  VALIDATION_FAILED, DELIVERY_FAILED, TIMEOUT) reached truthfully. The checksum-verified
  `.master/fix_architecture` sidecar and provenance-gated reuse are implemented; still run a real
  process-interruption/restart probe and preserve its receipt. No trial has yet reached a repair,
  so repair quality is unmeasured.

## Execution contract

- [ ] Fold FixLoop, RepairLoop and RunJournal into `Fix::Kernel` in the gated order
  `MASTER/docs/fix_coordinator_map.md` sets, recovery tests first; the one gap left in
  `MASTER/docs/lifecycle_ownership.md`.

## MASTER behaviour

- [ ] Latency: a monotonic timeline for boot, first token, completed reply and greeting, CLI and
  web separately, on current HEAD (17.6 s boot and 13–16 s replies on 2026-10-23). Stream the
  first words of a reply; a failed stream says so before switching lanes.
- [ ] CLI cancellation in a PTY: Ctrl-C mid-generation, Ctrl-D, SIGTERM, child timeout; terminal
  modes restored; NO_COLOR, TERM=dumb and non-TTY piping; no face in a dumb terminal. A PTY
  regression now covers `/face` exit and canonical `host:path# pub4 outstanding work

The one cross-tree backlog: work an agent in this checkout can do. Work that
needs the operator, a device, a credential, a paid call, ears or a console on
vm23 is a seam in `MASTER/data/operator_seams.yml`. Refusals live under
"Refused, and why" in `MASTER/AGENTS.md`. An item closes by being deleted in
the commit that carries its evidence; nothing here records finished work.

## Verification run, after the fixes below land

One pass on one commit, recorded as PASS, FAIL, INCONCLUSIVE, BLOCKED or
TIMEOUT per command. The 2026-10-25 and 2026-10-26 connector sessions committed
source and tests they could not run; this pass is what measures them.

- [ ] MASTER: `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 MASTER_TEST_PROGRESS_EVERY=25 rake test`,
  then `MASTER_TEST_JOBS=3 rake test`; check `.master/check/suite-report.json` for incomplete
  workers and mismatched start/result counts. Then `bin/check --profile=agent`.
- [ ] RAILS: `ruby RAILS/test/contract_runner_contract_test.rb`, `ruby RAILS/test/run_all.rb`, and
  `bin/ci` in each app in `RAILS/apps.yml`, including the 26 playlist, tv and takeaway tests
  that no command ran until `Pub4TestScope`, brgen's share-target, share-draft and job
  concurrency tests and a fresh test database for amber's `account_merges` and identity migrations.
- [ ] OPENBSD: `ruby OPENBSD/test/run_all.rb` and `ruby OPENBSD/test/test_evidence_tool.rb`, smoke-testing
  PASS, FAIL, BLOCKED, INCONCLUSIVE and TIMEOUT with process-group termination.
- [ ] STUDIO: `cd STUDIO && rake check test`, including the full `test/dilla_test.rb` (25 minutes;
  seven failures on 2026-10-23, reconciled in source on 2026-10-24 and never rerun).
- [ ] Generated outputs match their sources: `RAILS/__shared/design_tokens.yml`,
  `RAILS/master/public/face.runtime.js`, `face.css`, and `rake docs:agent_contracts` followed by
  `rake lint:agent_contracts`.
- [ ] The route suites on MASTER's pinned Ruby with Ollama absent: `test_route_policy.rb`,
  `test_lane_selection.rb`, `test_fix_fresh_checkout_models.rb`, `test_compute_pool.rb`,
  `test_fallback_chain.rb`, `test_lane_pool.rb`.
- [ ] Refresh `MASTER/data/self_findings.yml` through `ruby MASTER/lib/operator/self_findings.rb --ratchet` after source changes settle. Review the law and registry member deltas and both counts; the ratchet must refuse to raise either existing ceiling.
- [ ] Then `/fix` on the repository root: four independent reports, 30–40 grounded tournament
  candidates per tree, and each terminal state (DONE, PLATEAU, HUMAN_DECISION, BLOCKED,
  VALIDATION_FAILED, DELIVERY_FAILED, TIMEOUT) reached truthfully. The checksum-verified
  `.master/fix_architecture` sidecar and provenance-gated reuse are implemented; still run a real
  process-interruption/restart probe and preserve its receipt. No trial has yet reached a repair,
  so repair quality is unmeasured.

## Execution contract

- [ ] Fold FixLoop, RepairLoop and RunJournal into `Fix::Kernel` in the gated order
  `MASTER/docs/fix_coordinator_map.md` sets, recovery tests first; the one gap left in
  `MASTER/docs/lifecycle_ownership.md`.

## MASTER behaviour

- [ ] Latency: a monotonic timeline for boot, first token, completed reply and greeting, CLI and
  web separately, on current HEAD (17.6 s boot and 13–16 s replies on 2026-10-23). Stream the
  first words of a reply; a failed stream says so before switching lanes.
 prompt restoration; run it on the
  pinned Ruby and compare the visible output with historical prompt commit `c70f54b06be1`.
- [ ] Measure provider failover at the boundary: the provider, model and credential actually used
  under auth failure, rate limit, timeout, malformed reply and budget exhaustion.

## RAILS

- [ ] The 400-case interaction inventory in `RAILS/test/interaction_campaign_400.json`, run against
  the real CLI, HTTP and browser surfaces an agent can reach, with each case's observed result.
- [ ] Rendered layout through the CDP checks at 320, 360, 375, 390, 430, 480, 640, 768, 1024 and
  1280 px, with keyboard-only, zoom, forced-colours and reduced-motion passes; `bin/operator
  triangle up` first.
- [ ] brgen journeys end to end in integration tests: feed, posts, moderation, maps, marketplace,
  dating, messenger, radio and takeaway, with authorisation boundaries and empty and error states.
- [ ] Guest-to-account conversion and guest-transfer retry tests through every sign-in path.
- [ ] Re-measure CSS, JS and PWA budgets from a fresh build against the ratchets.

## Cross-tree

- [ ] DRY and duplication census: duplicate decisions, one-use abstractions, single-child
  directories, stale pointers; compare structural ratchets before and after.
- [ ] Performance sweep with before/after numbers: boot, CLI response, web first paint, payloads,
  memory.
- [ ] Adapter contracts for CLI, web, voice, browser and MCP: caller identity, scope, typed
  input and output, cancellation, timeout, error class; each reaches the same constitutional gate.
- [ ] Separate the audit ledger, telemetry, transcript and learning store: receipts durable and
  fail-closed, metrics best-effort, retention stated for each.
- [ ] Record which source, test and config files a run read, at which revision, and report stale
  or unresolved reference-graph entries.
- [ ] Learned skills and memory: provenance, correction and retraction, retrieval tests; promotion
  only through the reviewed, fixture-backed skill contract.
- [ ] Work through `MASTER/data/ux_refinements.yml` UX001–UX090 using the declared proof per row. Keep every row `acceptance_required` until its real test, browser, terminal, accessibility, or rendered-runtime evidence is recorded.
- [ ] Model-backed evaluation of advice quality on realistic personal-assistance scenarios,
  labelled apart from human review (a seam).
