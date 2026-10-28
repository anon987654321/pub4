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

- [ ] MASTER focused regressions on the pinned Ruby: from `MASTER/`, run
  `bundle exec ruby -Ilib:test test/test_law_parity.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_kernel.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_kernel_lifecycle.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_convergence.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_convergence_wiring.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_mission.rb`,
  `bundle exec ruby -Ilib:test test/test_core_no_lib_backedges.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_interruption_restart.rb`,
  `bundle exec ruby -Ilib:test test/test_ingress_jobs.rb`,
  `bundle exec ruby -Ilib:test test/test_security_audit.rb`,
  `bundle exec ruby -Ilib:test test/test_turn_router.rb`,
  `bundle exec ruby -Ilib:test test/test_command_registry_dispatch.rb`,
  `bundle exec ruby -Ilib:test test/test_architecture_exploration.rb`,
  `bundle exec ruby -Ilib:test test/test_run_journal_lifecycle.rb`, and
  `bundle exec ruby -Ilib:test test/test_cli_boot_e2e.rb` (the last exercises the real
  PTY prompt/face lifecycle; its live-model case remains opt-in).
- [ ] MASTER full suite: `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 MASTER_TEST_PROGRESS_EVERY=25 rake test`,
  then `MASTER_TEST_JOBS=3 rake test`; check `.master/check/suite-report.json` for incomplete
  workers and mismatched start/result counts. Then run `rake audit` (the complete declared lint
  inventory), followed by `bin/check --profile=agent`.
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
  `.master/fix_architecture` sidecar and provenance-gated reuse are implemented. The process-kill
  regressions at `MASTER/test/test_fix_interruption_restart.rb` now call the public `FixLoop#run`
  entry point with a controlled pass-interruption seam and cover transaction rollback, durable-run
  resumption, orphaned Kernel-receipt recovery, and journal deletion while the Mission checkpoint
  survives; run them on pinned Ruby and preserve receipts, then run a real repository-wide `/fix`.
  The crash/restart test is authored but unexecuted here; no live repository-wide trial has been
  measured, so repair quality remains unmeasured.

## Execution contract

- [ ] Complete and verify the Kernel consolidation in `MASTER/docs/fix_coordinator_map.md`:
  production `/fix` now enters Kernel; the convergence, lifecycle-journal and repair-policy
  implementations live under `Fix::Kernel`, with compatibility constants retained. Kernel owns
  the execution lock, coordinator receipts, shared journal accessor, repair factory and
  unknown-outcome reconciliation. The subprocess tests cover transaction rollback, deletion of
  the run journal with Mission/checkpoint survival, resumption when the journal remains, and
  orphan-receipt recovery, but are unexecuted. Run them on pinned Ruby 4.0.5, then prove
  budget/collapse and zero-repair ledger honesty, the full adapter receipt-parity matrix, and one
  real repository-wide `/fix` trial. Do not remove compatibility aliases until those gates pass.

## MASTER behaviour

- [ ] Latency: a monotonic timeline for boot, first token, completed reply and greeting, CLI and
  web separately, on current HEAD (17.6 s boot and 13–16 s replies on 2026-10-23). Stream the
  first words of a reply; a failed stream says so before switching lanes.
- [ ] CLI cancellation in a PTY: Ctrl-C mid-generation, Ctrl-D, SIGTERM, child timeout; terminal
  modes restored; NO_COLOR, TERM=dumb and non-TTY piping; no face in a dumb terminal. The PTY
  regression covers `/face` exit and canonical `host:path` restoration; run
  `bundle exec ruby -Ilib:test test/test_cli_boot_e2e.rb` on the pinned Ruby and record the actual
  terminal output. Do not reintroduce the deleted `Master::Io::Chat.destination_label`; the current
  model-only route uses the renderer's `llm` destination default.
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
