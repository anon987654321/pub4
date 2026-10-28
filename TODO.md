# pub4 outstanding work

The one cross-tree backlog: work an agent in this checkout can do. Work that
needs the operator, a device, a credential, a paid call, ears or a console on
vm23 is a seam in `MASTER/data/operator_seams.yml`. Refusals live under
"Refused, and why" in `MASTER/AGENTS.md`. An item closes by being deleted in
the commit that carries its evidence; nothing here records finished work.

## Session note 2026-10-28

- Root and MASTER Ruby pins now use the available Ruby 3.3.8; MASTER/Gemfile accepts
  >= 3.2 for constrained environments. Individual deployed app runtimes remain
  governed by their own stack/lock contracts. This does not claim test results.
- Added the token-owned face swarm under face_interface.swarm, the shared
  Master::Face::Swarm module, CLI frame overlay, and web stipple integration.
  Coverage was added for token reading, deterministic seeding, force direction,
  cohesion/separation, bounded integration, depth/ramp mapping, spatial budget,
  reduced-motion freeze, and CLI/web adapter contracts. The Ruby and Node suites
  still need to run against a checkout.
- Added six named recovery gates before any Fix::Kernel fold. Gate 1 now
  exercises a real aborted Transaction and checks byte-exact binary restoration,
  file mode/owner/group, and deletion of a newly created path. That source test
  has not yet been run here. Gates 2–6 remain explicit skips; wire each to the
  production recovery path and prove red then green before folding coordinator
  owners.
- Added docs/seo_audit_2026-10-28.md from session-provided observations. Raw HTTP
  captures were not attached to this commit, so those observations are advisory;
  re-probe and preserve timestamped headers/bodies before closing the SEO audit.

## Verification run, after the fixes below land

One pass on one commit, recorded as PASS, FAIL, INCONCLUSIVE, BLOCKED or
TIMEOUT per command. The 2026-10-25 and 2026-10-26 connector sessions committed
source and tests they could not run; this pass is what measures them.

- [ ] MASTER focused regressions on the pinned Ruby: from `MASTER/`, run
  `bundle exec ruby -Ilib:test test/test_law_parity.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_kernel_lifecycle.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_convergence.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_convergence_wiring.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_mission.rb`,
  `bundle exec ruby -Ilib:test test/test_core_no_lib_backedges.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_interruption_restart.rb`,
  `bundle exec ruby -Ilib:test test/test_ingress_jobs.rb`,
  `bundle exec ruby -Ilib:test test/test_security_audit.rb`,
  `bundle exec ruby -Ilib:test test/test_io_atomic_write.rb`,
  `bundle exec ruby -Ilib:test test/test_security_headers_source_check.rb`,
  `bundle exec ruby -Ilib:test test/test_check_runner_registry.rb`,
  `bundle exec ruby -Ilib:test test/test_turn_router.rb`,
  `bundle exec ruby -Ilib:test test/test_command_registry_dispatch.rb`,
  `bundle exec ruby -Ilib:test test/test_architecture_exploration.rb`,
  `bundle exec ruby -Ilib:test test/test_run_journal_lifecycle.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_kernel.rb`,
  `bundle exec ruby -Ilib:test test/test_check_chain.rb`,
  `bundle exec ruby -Ilib:test test/test_strict_mode.rb`,
  `bundle exec ruby -Ilib:test test/test_ecosystem_features.rb`,
  `bundle exec ruby -Ilib:test test/test_compute_pool.rb`,
  `bundle exec ruby -Ilib:test test/test_provider_concurrency.rb`,
  `bundle exec ruby -Ilib:test test/test_keyless_routing.rb`,
  `bundle exec ruby -Ilib:test test/test_llm_dispatcher.rb`,
  `bundle exec ruby -Ilib:test test/test_event_privacy.rb`,
  `bundle exec ruby -Ilib:test test/test_trace_log_append_jsonl.rb`,
  `bundle exec ruby -Ilib:test test/test_trace_metrics_log.rb`,
  `bundle exec ruby -Ilib:test test/test_trace_telemetry.rb`,
  `bundle exec ruby -Ilib:test test/test_trace_recorder_storage.rb`,
  `bundle exec ruby -Ilib:test test/test_dom_surface_seo_metadata.rb`, and
  `bundle exec ruby -Ilib:test test/test_cli_boot_e2e.rb` (the last exercises the real
  PTY prompt/face lifecycle; its live-model case remains opt-in).
- [ ] MASTER full suite: `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 MASTER_TEST_PROGRESS_EVERY=25 rake test`,
  then `MASTER_TEST_JOBS=3 rake test`; check `.master/check/suite-report.json` for incomplete
  workers and mismatched start/result counts. Then run `rake audit` (the complete declared lint
  inventory), followed by `bin/check --profile=agent`.
- [ ] RAILS: `ruby RAILS/test/contract_runner_contract_test.rb`, `ruby RAILS/test/deploy_checks_contract_test.rb`, `ruby RAILS/test/check_failopen_test.rb`, `ruby RAILS/test/checks/runner_explain_test.rb`, `ruby RAILS/test/checks/constitutional_scan_targets_test.rb`, `ruby RAILS/test/run_all.rb`, and
  `bin/ci` in each app in `RAILS/apps.yml`, including the 26 playlist, tv and takeaway tests
  that no command ran until `Pub4TestScope`, brgen's share-target, share-draft and job
  concurrency tests and a fresh test database for amber's `account_merges` and identity migrations.
- [ ] OPENBSD: `ruby OPENBSD/test/test_pf_policy_check.rb`, `ruby OPENBSD/test/run_all.rb` and
  `ruby OPENBSD/test/test_evidence_tool.rb`, smoke-testing PASS, FAIL, BLOCKED, INCONCLUSIVE and TIMEOUT
  with process-group termination. The PF policy test includes a negative case for protocol-specific
  unscoped pass rules; validate native syntax separately on OpenBSD with `pfctl -nf /etc/pf.conf`.
- [ ] STUDIO: `cd STUDIO && rake check test`, including the full `test/dilla_test.rb` (25 minutes;
  seven failures on 2026-10-23, reconciled in source on 2026-10-24 and never rerun).
- [ ] Generated outputs match their sources: `RAILS/__shared/design_tokens.yml`,
  `RAILS/master/public/face.runtime.js`, `face.css`, and `rake docs:agent_contracts` followed by
  `rake lint:agent_contracts`.
- [ ] The route suites on MASTER's pinned Ruby with Ollama absent: `test_route_policy.rb`,
  `test_lane_selection.rb`, `test_fix_fresh_checkout_models.rb`, `test_compute_pool.rb`,
  `test_fallback_chain.rb`, `test_lane_pool.rb`, `test_ecosystem_features.rb`.
- [ ] Refresh `MASTER/data/self_findings.yml` through `ruby MASTER/lib/operator/self_findings.rb --ratchet` after source changes settle. Review the law and registry member deltas and both counts; the ratchet must refuse to raise either existing ceiling.
- [ ] Then `/fix` on the repository root: four independent reports, 30–40 grounded tournament
  candidates per tree, and each terminal state (DONE, PLATEAU, HUMAN_DECISION, BLOCKED,
  VALIDATION_FAILED, DELIVERY_FAILED, TIMEOUT) reached truthfully. The checksum-verified
  `.master/fix_architecture` sidecar and provenance-gated reuse are implemented. The process-kill
  regressions at `MASTER/test/test_fix_interruption_restart.rb` use the public `FixLoop#run`
  entry point with a controlled pass-interruption seam and cover transaction rollback, durable-run
  resumption, orphaned Kernel-receipt recovery, and journal deletion while the Mission checkpoint
  survives. Run them on pinned Ruby and preserve receipts, then run a real repository-wide `/fix`.
  The crash/restart tests are authored but unexecuted here; no live repository-wide trial has been
  measured, so repair quality remains unmeasured.

## Execution contract

- [ ] Complete and verify the Kernel consolidation in `MASTER/docs/fix_coordinator_map.md`:
  production `/fix` now enters Kernel; the convergence, lifecycle-journal and repair-policy
  implementations live under `Fix::Kernel`, with compatibility constants retained. Kernel owns
  the repository-wide, process-shared execution lock at `.master/fix-execution.lock`,
  coordinator receipts, shared journal accessor, repair factory and unknown-outcome
  reconciliation. Regression sources cover separate Kernel instances in one process,
  independent processes, and refusal of symlinked or group/world-writable lock paths.
  The hash-chained ledger also refuses symlinked paths, hard links, non-regular files and
  non-private permissions. Runtime results remain unmeasured here. The process-kill tests cover
  transaction rollback, Mission/checkpoint survival, durable journal resumption and orphan-receipt
  recovery, but are unexecuted. Run them on pinned Ruby 4.0.5, then prove budget/collapse and
  zero-repair ledger honesty, the full adapter receipt-parity matrix and a real repository-wide
  `/fix` trial. Do not remove compatibility aliases until those gates pass.
  Six named recovery-gate skips remain in `MASTER/test/test_recovery_gates.rb`; none closes this
  gate until wired to real fixtures and verified red then green.
- [ ] Define a retention/segmentation policy for hash-chained `.master/log.jsonl` before
  long-running production use. Any compaction must preserve verifiable chain continuity with
  explicit segment checkpoints; never truncate arbitrary prefixes.
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
- [ ] Run an evidence-backed public SEO/indexability audit across the hostnames and
  surfaces recorded in `RAILS/apps.yml` and the deployment inventory. Start with the
  canonical app hosts (`brgen.no`, `ai.brgen.no`, `amberapp.art`, `bsdports.org`) and
  verify redirects/canonicals for owned aliases (`amberapp.no`, `amberapp.online`,
  `bsdports.net`) before treating them as indexable equivalents. Include representative
  Brgen vertical hosts and city apexes; explicitly decide whether the MASTER face should
  be indexed. The rendered surface schemas now require exactly one non-empty title, meta
  description, absolute canonical URL, Open Graph title/description/URL for the five
  current Brgen surface contracts, with good fixtures and focused negative tests. Attribute
  quote handling now permits valid apostrophes in metadata text without accepting empty
  values or relative canonical URLs. The full
  hostname crawl remains open: record timestamped HTTP/redirect results, robots and sitemap
  coverage, JSON-LD validity, indexability and measured performance where available.
  Claude SEO may be used as a reviewed advisory crawler, with optional paid/API extensions
  disabled unless approved; preserve raw evidence and falsifiable recommendations. Reuse
  `content_honesty`, `surface_schema`, the SEO kit and existing structured-data tests; do
  not add duplicate checks or new Law IDs until the audit proves a distinct, repeatable
  invariant that the current checks miss.

## Production security evidence

- [ ] Close the live CSP operator seam in `MASTER/data/operator_seams.yml` (`csp_enforced_on_vm23`): the operator must enable `PUB4_CSP_ENFORCE=1` for the intended app environments, inspect real HTTPS response headers on `brgen.no`, `ai.brgen.no` and `amberapp.art`, and verify the MASTER face still embeds from the approved Brgen/Amber origins. Record the host, timestamp, headers and embed result. The source contract and report-only responses are not proof of enforcement; do not install a global CSP in relayd.

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
