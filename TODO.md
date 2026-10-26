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
- [ ] Then `/fix` on the repository root: four independent reports, 30–40 grounded tournament
  candidates per tree, tournament fields that survive an interrupted process, and each terminal
  state (DONE, PLATEAU, HUMAN_DECISION, BLOCKED, VALIDATION_FAILED, DELIVERY_FAILED, TIMEOUT)
  reached truthfully. No trial has yet reached a repair, so repair quality is unmeasured.

## Law system: one catalogue

`MASTER/data/laws.yml` owns Law identity; detectors sit under `MASTER/law/detectors/`.

- [ ] One catalogue-backed loader. Trace and migrate the consumers of `Law.define`, `Law::Builder`,
  `LawDSL.law`, `Review::Scan::Law.registry`, `LawFactory`, `YamlDeclarativeLaw`, `VetoPatternLaw`,
  `LawBridgeLaw`, `SemanticLaw` and the scanner's `Rule` name.
- [ ] Derive the visual and semantic Law populations from the catalogue, not from Ruby ID lists
  such as `VisualUsability::IDS`.
- [ ] Run `LawRegistryAudit` and explain every member of `yaml_only`, `law_only`, `registry_only`,
  `lexical_unwired`, `structural_unwired`, `semantic_only`, `dep_graph_gaps` and `source_drift`.
- [ ] Prove finding-cache keys include every detector input, the catalogue digest among them, and
  that semantic scan reaches every target file.

## Execution contract

- [ ] Map lifecycle ownership from call sites: `Core::Fold`, `Core::Constitution`, `Core::World`,
  `FixLoop`, the inner repair loop, `Fix::Kernel`, `Mission`, `RunJournal`, `RunLedger`,
  `Transaction`, `Transaction::Delivery`, supervisors, MCP and tool dispatch. Record who owns
  state, authorisation, replay, recovery and delivery for each.
- [ ] Extend before/after receipts to every consequential `Master::Io` path, direct MCP and
  browser action, background worker, transaction-internal write and scheduler, with a source
  inventory test so a new call site cannot bypass them.
- [ ] Classify real effect handlers' reversibility from their semantics; unknown and irreversible
  outcomes reconcile before replay.
- [ ] Restart and duplicate-delivery tests: death after the before-receipt, after the effect but
  before the after-receipt, after commit but before delivery; duplicate events; stale leases.
  A worker with an expired lease cannot write, commit or deliver.
- [ ] Field-by-field privacy review of the commit/Phoenix journal and the remaining event, log and
  learning families, with adversarial tests for credentials, paths, prompts and tool output.
- [ ] Structured cancellation and deadlines for supervisors, scheduled jobs, child process trees,
  provider calls and checks.
- [ ] Trace the write planes (`Io::Base`, DiffStager, `Fix::Transaction`, Committer, direct
  filesystem writes) and add recovery tests: crash recovery, concurrent runs, refusal to roll back
  after commit, rollback when final verification fails.
- [ ] Keep DesignSweep out of automatic `/fix` until it has a candidate/apply split through
  `Fix::Transaction`.

## One verification vocabulary

- [ ] Adapt scanner findings, `Master::Proof`, the RAILS and OPENBSD check runners, visual and
  accessibility results, and deployment receipts to `Execution::Contract`'s normalised outcomes,
  keeping standalone trees on adapters rather than cross-tree requires.
- [ ] Incomplete coverage cannot read green: verifier, subject, scope digest, completeness and
  evidence reference are required; only an accepted terminal state with complete evidence is DONE.

## MASTER behaviour

- [ ] Latency: a monotonic timeline for boot, first token, completed reply and greeting, CLI and
  web separately, on current HEAD (17.6 s boot and 13–16 s replies on 2026-10-23). Stream the
  first words of a reply; a failed stream says so before switching lanes.
- [ ] Lookup policy: separate opinion and advice from factual or current questions, search only
  for the latter, and say plainly when a lookup was unavailable.
- [ ] Reminders: resolve relative times in the declared timezone, deliver through the face, and
  say at acceptance whether anything will ring.
- [ ] CLI cancellation in a PTY: Ctrl-C mid-generation, Ctrl-D, SIGTERM, child timeout; terminal
  modes restored; NO_COLOR, TERM=dumb and non-TTY piping; no face in a dumb terminal.
- [ ] Owner preferences: two repeated corrections surface a pending suggestion, acceptance is
  owner-only, and an accepted preference changes the prompt or routing it names.
- [ ] Check `CAPABILITY_STATUS_MUST_BE_TRUTHFUL`'s detectors against progress, success, pending
  and delivery labels that do not match observed state.
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

- [ ] Source-level security review of all four trees: outbound HTTP and SSRF, DNS pinning, body and
  time limits, authorisation, rate limits, CSP and CORS headers as actually sent, uploads, secret
  redaction, command construction, `html_safe` data flow.
- [ ] DRY and duplication census: duplicate decisions, one-use abstractions, single-child
  directories, stale pointers; compare structural ratchets before and after.
- [ ] Performance sweep with before/after numbers: boot, CLI response, web first paint, payloads,
  memory.
- [ ] Verify declared skill fixtures before promotion: trusted root, no traversal or symlink escape,
  bounded verifier types, recorded outcome.
- [ ] Unified health states (configured, authenticated, ready, degraded, failed, not tested) for
  providers, channels and services, with a concise boot report.
- [ ] Adapter contracts for CLI, web, voice, browser and MCP: caller identity, scope, typed
  input and output, cancellation, timeout, error class; each reaches the same constitutional gate.
- [ ] Separate the audit ledger, telemetry, transcript and learning store: receipts durable and
  fail-closed, metrics best-effort, retention stated for each.
- [ ] Record which source, test and config files a run read, at which revision, and report stale
  or unresolved reference-graph entries.
- [ ] Learned skills and memory: provenance, correction and retraction, retrieval tests; promotion
  only through the reviewed, fixture-backed skill contract.
- [ ] Model-backed evaluation of advice quality on realistic personal-assistance scenarios,
  labelled apart from human review (a seam).
- [ ] Reconcile the DeepSeek handoff findings against current source, each classified verified,
  changed but unverified, superseded, open or blocked.
- [ ] STUDIO billing and clip ledgers (`clips.jsonl`, per-subject `ledger.jsonl`) need an
  archive/export contract before any rotation; they are cost provenance, not telemetry.
