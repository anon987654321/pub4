# pub4 outstanding work

The one cross-tree backlog: work an agent in this checkout can do. Work that
needs the operator, a device, a credential, a paid call, ears or a console on
vm23 is a seam in `MASTER/data/operator_seams.yml`. Refusals live under
"Refused, and why" in `MASTER/AGENTS.md`. An item closes by being deleted in
the commit that carries its evidence; nothing here records finished work.

## Session note 2026-10-28 (bounded provider-health history)

- Provider-health scoring already uses a 15-minute event window and recovery bonus.
  This batch bounds defensive reads independently of the shared 25 MiB writer cap:
  at most 5 MiB and 20,000 complete records per file generation are parsed, with
  partial leading records discarded. Regression tests cover byte and event caps.
- Runtime tests remain NOT_RUN; the hardening-review item stays open until the focused
  provider-health and routing regressions execute successfully on Ruby 4.0.5.

## Session note 2026-10-28 (fail-closed hooks and canonical Ruby pin)

- Configured PreToolUse hooks now deny by default on hook failures, and an
  absent, malformed, symlinked, untrusted or broadly writable hook config refuses
  effects instead of silently disabling the gate. Explicit `on_fault: allow` is
  the only fail-open switch. Regression cases cover faults and config errors.
- Root and MASTER `.ruby-version` are reconciled to Ruby 4.0.5, matching every
  Rails app pin and MASTER's lockfile declaration. The dependency contract now
  asserts the exact canonical pin. Runtime tests remain NOT_RUN from GitHub.
- This commit establishes the implementation and tests; it does not claim their
  execution or full-suite completion.

## Session note 2026-10-28 (face-first boot and Dilla bed removal)

- Bare interactive `bin/master` now opens the existing terminal face by default;
  it carries the same live operator prompt. `MASTER_FACE_ON_START=0` keeps the
  shell-first prompt for diagnosis. Scripted messages and pipes remain plain.
- Removed the persistent Dilla bed as a runtime feature: no boot start, narrator
  restart, held-bed cleanup, or face microphone coupling; removed its config and
  module. Dilla remains available for deliberate Studio and `/play` work.
- Regression tests were updated for the new prompt default and the absence of
  ambient-bed configuration/runtime calls. Ruby tests and a live PTY launch were
  **NOT_RUN** through the GitHub editing surface. The full verification list below
  remains open; no suite or visual test is claimed as passing.

## Carried-forward requests from earlier sessions

- [ ] **Complete AI3 archive archaeology:** the bounded findings and no-port decision are recorded in [`docs/ai3_legacy_audit_2026-10-28.md`](docs/ai3_legacy_audit_2026-10-28.md). The visible AI3 tree and extracted reports were inspected, but the historical archive blobs were not all extracted; preserve this item as open until that source recovery is actually completed. No AI3 feature claim counts as working behavior without implementation and runtime evidence.

These requests were visible in prior conversations or handoffs but lacked an explicit,
actionable root-backlog item. Keep them open until the relevant evidence exists.

- [ ] **`STUDIO/postpro` / `STUDIO/replicate` archaeology:** trace commits, branches,
  unreachable/history-recoverable objects and historical wording across pub4, pub3,
  pub2 and pub. Restore only grounded, unique logic, ideas, contracts and tests into
  current owners; preserve provenance and do not reintroduce a deleted tree wholesale.
- [ ] **Oct. 26 hardening review:** reconcile every P01–P11 follow-up and the outstanding
  findings in `MASTER/docs/handoffs/2026-10-26-master-hardening-review.md`. Explicitly
  verify SILENT_RESCUE freshness, INTER_MODEL_CONTRACT heredoc/keyword sites, the
  declarative/runtime self-test parity, headless registry failures and strict-error
  policy; resource bounds/log append cache; DesignRun transaction and recovery semantics,
  abort/stall outcomes, undo pruning and silent rescues; provider-health recovery windows,
  Replicate auth/SSRF/timeouts, retry jitter, process-group termination, redaction and
  Gemini key transport; boot/loop claims, device/pairing/wake-word edges and CDP budgets;
  tool-hook fail-open, MCP SSRF/package pinning, environment-file permissions, scoped
  kills, and RAILS token timing/CSRF/ingress rate limiting. Classify each finding with a
  test or evidence reference; don't infer closure from a source edit.
- [ ] **Law parity and visual enforcement:** run `rake lint:law_parity` and keep the
  `RENDERED_VALUES` gap visible until an authorized deferral or tagged detector closes
  it. Verify `AD_VISUAL_QUALITY_MUST_BE_GORGEOUS` from declaration through executable
  law/gates to renderer acceptance. When a live browser is unavailable, add deterministic
  source/geometry/layout simulations as partial evidence only; keep true browser/runtime
  results INCONCLUSIVE until measured.
- [ ] **Tooling proposal, cherry-pick not replace:** reconcile
  `MASTER/TOOLING_COMPARISON_PROPOSAL_2026-10-26.md` with the remaining code gaps. Adopt
  only small, testable patterns (effect identities and before/after receipts, truthful
  checkpoint/recovery states, scoped execution, typed provider failures and bounded
  fallback); retain MASTER's Ruby/law authority and avoid importing a parallel agent
  framework. Link each accepted pattern to a production caller and regression test.
- [ ] **Model routing carry-forward:** prove signed-in `claude-cli:`, `codex-cli:` and
  `grok-cli:` lanes are selected according to the route policy, no cloud Ollama route is
  admitted, and the sole permitted local Ollama fallback is the explicitly allowlisted
  `ollama:gemma3:4b`. Verify the actual served model/provider and the failure/retry
  boundary, not just a routing log.
- [ ] **Personalized MASTER behavior:** test that stable operator preferences and
  corrections influence greeting, language, response style and workflow selection through
  bounded, provenance-bearing memory. Memory must be retractable and must never override
  `soul.yml`, `laws.yml`, executable laws or explicit current instructions.

## Session note 2026-10-28 (A/B/C/D execution)

- **B — branch hygiene:** deleted 40 stale agent/fix/session/codex/claude/work
  branches that were 1-ahead/1-behind concurrent tips. Remote now has **only
  `main`**. Archaeology remains in commit history and tags.
- **C — bplans:** owner decision recorded as **archived** (not imported into
  public pub4). Updated `MASTER/data/recovery/pub_restore.yml` and
  `legacy_manifest.yml`. Provenance stays in `anon987654321/pub`.
- **D — CSP probe (external):** 2026-10-28 HTTPS probes show
  `Content-Security-Policy-Report-Only` on `brgen.no`, `amberapp.art`, and
  `ai.brgen.no` — enforcement not live. Evidence in
  `docs/evidence/csp_probe_2026-10-28.md`. Seam `csp_enforced_on_vm23` stays
  open until operator sets `PUB4_CSP_ENFORCE=1` on vm23 and re-probes.
- **A — verification:** full focused suite still needs pinned Ruby 4.0.5 and
  a successful `bundle install`. Added `MASTER/bin/verify-focused` to run the TODO list and
  report per-file exit codes. Dependency-light FinalCleanup remains
  3/17/0 on Ruby 3.2.3 in this executor.

## Session note 2026-10-28 (Grok triage + light proof)

- Branch inventory: ~40 agent/fix/session/codex/claude/work branches remain on
  the remote. Every inspected tip is **1 commit ahead and 1 behind** `main`
  (concurrent divergence). Priority tips checked:
  `fix/kernel-lifecycle-consolidation-20261028-final`,
  `fix/recovery-gate-mission-child-restart-20261028`,
  `polish/master-command-surface-2026-10-28`,
  `fix/master-state-group-write-boundary-20261028`. Main already carries longer
  `test_recovery_gates.rb` (440 lines) than the recovery-gate branch tip (313);
  unique branch content appears superseded or partially folded. No open PRs.
  Safe next step for the operator: after one verification pass on main, delete
  the stale agent branches (or leave them as archaeology).
- Executor constraint: this host is Ruby 3.2.3 / 1.2 GiB RAM. `bundle install`
  fails closed because `opentelemetry-sdk ~> 1.11` requires Ruby >= 3.3. Full
  MASTER suite and `rake test` remain **BLOCKED** here; they need the pinned
  4.0.5 checkout (or the explicitly supported OpenBSD runtime lane).
- Re-ran the dependency-light FinalCleanup harness against current
  `lib/fix/final_cleanup.rb` and the three tests in `test_final_cleanup.rb`:
  **3 runs, 17 assertions, 0 failures, 0 errors, 0 skips** (Ruby 3.2.3). This
  reconfirms the focused cleanup contract only; it is not repository-dependency
  integration and not the full MASTER suite.
- Recovery / restore ledger still open for owner decision: `bplans` (no
  generator ever existed; content may be sensitive; pub4 is public) — see
  `MASTER/data/recovery/pub_restore.yml`.
- Operator seams unchanged; CSP live enforcement on vm23 remains the production
  gate that source alone cannot close.

## Session note 2026-10-28

- Historical checkpoint: root and MASTER temporarily used the available Ruby
  3.3.8 in the constrained executor. The canonical pin is now 4.0.5 as the
  execution contract requires; see the newer session note above. This does not
  claim test results.
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
- Post-merge static review removed duplicate appended test definitions from the
  RunJournal, quota, ComputePool, RoutePolicy and trace JSONL/storage test files,
  and added `test_recovery_gates.rb` to the focused release battery. These were
  source-structure repairs only; no project test command has been executed.
- Follow-up STUDIO review normalized shadow/highlight detail ratios before using
  them in correction thresholds, made missing pixel bands produce no tone-curve
  proposal, and tightened JSON-round-trip replay-manifest verification plus exact
  modality-version checks. Replay manifests now carry declared temporal schedule
  hashes and refuse mismatches. Reference-derived styles now require a source
  fingerprint per transferred attribute, and minted versions must name their
  predecessor. The seven cross-modal style contracts remain in laws.yml as STUDIO
  policy entries; they are not silently counted as MASTER's nine priority
  constitutional laws without MASTER detector coverage. Negative-list matching
  still needs a real modality-specific matcher; no lexical substitute is claimed
  as complete. Regression cases were added; the STUDIO and MASTER project suites
  remain NOT_RUN here.
- Added `Master::Fix::FinalCleanup` as the explicit final stage on every `/fix`
  exit. It releases the commit lease and owned visual runtime, removes the current
  run's temporary visual captures, prunes only unretained exact-named assessment
  and architecture artifacts, and writes a cleanup receipt; source files,
  checkpoints, transaction/recovery evidence, audit logs and test logs are not
  cleanup candidates. The exact committed cleanup implementation and test file were run in a
  dependency-light local harness with only `test_helper` replaced by a Minitest-only
  stub: Ruby 3.3.8 reported 3 runs, 17 assertions, 0 failures, 0 errors, 0 skips.
  This proves the focused cleanup behavior, not repository dependency integration
  or the full MASTER suite. The full project suite remains
  NOT_RUN in this executor: it has no Bundler executable and outbound DNS cannot
  resolve GitHub; Vercel was not used as test evidence.

## Agent ergonomics (2026-10-28 wishlist)

From the 2026-10-28 boot-crash session (346da8e). Rationale, existing
coverage and acceptance criteria per item: `docs/wishlist_2026-10-28.md`.
Half the items finish disciplines the tree already started; none removes a
compatibility alias ahead of the execution-contract gates.

- [ ] Run the authored recovery gates on the pinned Ruby, preserve receipts,
  then retarget callers to the Kernel-owned names and delete the
  compatibility aliases per the existing execution-contract gate.
- Ruby-pin conflict resolved: root, MASTER and the Rails apps use `4.0.5`; MASTER's
  Gemfile.lock records the same runtime. The focused runtime tests are still open.

## Verification run, after the fixes below land

One pass on one commit, recorded as PASS, FAIL, INCONCLUSIVE, BLOCKED or
TIMEOUT per command. The 2026-10-25 and 2026-10-26 connector sessions committed
source and tests they could not run; this pass is what measures them.

- [ ] MASTER focused regressions on the pinned Ruby: from `MASTER/`, run
  `bundle exec ruby -Ilib:test test/test_cli_face_on_start.rb`,
  `bundle exec ruby -Ilib:test test/voice/test_voice_bed.rb`,
  `bundle exec ruby -Ilib:test test/test_final_cleanup.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_loop_observability.rb`,
  `bundle exec ruby -Ilib:test test/test_law_parity.rb`,
  `bundle exec ruby -Ilib:test test/test_fix_kernel_lifecycle.rb`,
  `bundle exec ruby -Ilib:test test/test_recovery_gates.rb`,
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
- [ ] The route suites on MASTER's pinned Ruby with Ollama cloud absent and only local `ollama:gemma3:4b` allowlisted: `test_route_policy.rb`,
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
  No recovery gate remains as a placeholder skip. Gates 1–6 now have concrete tests for rollback,
  Mission restart, Git/Checkpoint source recovery after journal deletion, budget/collapse refusal,
  per-file zero-repair evidence, and the public CommandRegistry-to-Kernel receipt contract. Gate 6
  controls Pipeline::Pass so it does not invoke a model or mutate a real tree; the wider adapter
  matrix and end-to-end process-interruption trial remain separate gates. All are authored but
  unexecuted; run the focused file on pinned Ruby 4.0.5 and preserve its actual output before
  treating any consolidation gate as closed.
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
