# pub4 outstanding work

Audit baseline: d9a008ba1f332a312122e342913486c54a32f18a. This is the one cross-tree backlog; do
not create separate project backlog files. A source edit, a static contract, an empty CI status
list, and a passing live run are different kinds of evidence. Close an item with the command or
browser evidence recorded in the commit.

## P0 — evidence before calling the system complete

- [ ] Run a fresh bounded release pass against the exact commit intended for deployment:
  constitutional and repository checks, all RAILS contract tests, active app suites, OPENBSD
  tests, and STUDIO fast tests. Record PASS, FAIL, INCONCLUSIVE, BLOCKED, or TIMEOUT separately.
  GitHub returned no status entries for the audit head; that is not a green result.
- [ ] Complete the requested 200–400 scenario interaction matrix across MASTER CLI, MASTER web,
  keyboard/touch, session state, routes, errors, models/tools, speech, reconnects, offline mode,
  and PWA updates. Exercise success and failure paths. Record scenario ID, setup, action,
  observed result, and evidence; scripted mocks do not substitute for real browser/CLI smoke
  tests.
- [ ] Run the live rendered-layout suite with screenshots and geometry evidence at 320, 360,
  375, 390, 430, 480, 640, 768, 1024, and 1280 CSS-pixel widths. Include keyboard-only use,
  zoom/reflow, safe-area, forced-colors, and reduced-motion checks. Do not report visual
  completion from source inspection alone.
- [ ] Run MASTER/bin/operator triangle up before relying on rendered checks, then run the
  repository check runner. Inspect every INCONCLUSIVE or BLOCKED result rather than counting it
  as success.
- [ ] Prove deploy and recovery on the intended OpenBSD host. Check the deployed commit, service
  health, logs, backups, and a restore path. Keep deployment separate from local-source test
  evidence.

## MASTER CLI, web, voice, and shared session

- [ ] Run `cd MASTER && ruby -Itest test/test_owner_preferences.rb` and the relevant agent/command-registry tests on the exact current commit; then smoke-test two repeated correction turns through CLI and web, verify the pending suggestion is surfaced, and prove acceptance is owner-only. Source and regression cases are committed, but runtime execution is not yet evidenced.
- [ ] Finish the Ghostty-inspired web-console pass with rendered visual review. The canonical
  palette now separates graphite shell surfaces, muted violet focus, neutral text, and the
  sparse lime semantic signal; the face renderer remains the focal point. Source-level mobile
  rules are in place, but final spacing, face/prompt coexistence, dashboard density, contrast
  measurements, and desktop/mobile screenshots remain unverified.
- [ ] Verify the installed PWA end to end: install, launch, safe-area layout, offline fallback,
  stale asset handling, service-worker update, and recovery after a failed request. Confirm that
  the shared manifest stays host-aware and that only intended stable resources are cached.
- [ ] Validate parity across CLI and browser for conversation/session state and the requested
  /connect, /join, and /msg channel flows. Check destination, reconnect, history, interruption,
  and error behavior; do not assume parity from shared naming.
- [ ] Run the full /fix phase loop per tree and demonstrate truthful DONE, PLATEAU,
  HUMAN_DECISION, BLOCKED, VALIDATION_FAILED, DELIVERY_FAILED, and TIMEOUT states. Verify
  dirty-tree preservation, interrupted writes, disk exhaustion, retry convergence, and
  rollback/undo behavior. On 2026-10-22 three bounded MASTER trials each stopped on a /fix
  defect before any repair, and each is now fixed with tests: a spent run journal was resumed
  instead of replaced, the read-only baseline was voided by any other session committing (it now
  brackets working bytes, so commits pass and edits still block), the ratchet stage measured
  every RAILS ceiling for a MASTER target, and the known-red record named failed steps rather
  than tests, so a narrow proof could not tell old red from new. Rails targets are now
  recognised from their files. The parallel test runner now polls worker exit status, applies a
  configurable 1,800-second per-worker deadline (`MASTER_TEST_WORKER_TIMEOUT`), terminates a
  timed-out worker process group, reports the offending PID/log and includes the final worker
  log in its report; relay-thread exceptions are surfaced, and a worker without a final Minitest
  summary, matching verbose result count, and matching test-start count cannot pass with exit 0.
  The normal `rake test` task uses this supervisor for both one-worker diagnostics and parallel
  runs. Worker logs record the active test (`test-start0`) so a timeout or abrupt exit identifies
  the last test entered. Regression tests cover a hung worker, an incomplete exit, and the
  supervised one-worker route. These source changes are not yet runtime-verified: run
  `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 rake test` to isolate a serial hang, then
  `MASTER_TEST_JOBS=3 rake test`, and record exact test/output before closing.
  No trial has reached a repair, so repair
  quality remains unmeasured on both MASTER and RAILS. Run /fix again only when the operator asks.
- [ ] Validate the OpenBSD Operator CLI and /help against the requested plain dmesg style,
  correct checkout/tree-relative location, no decorative status, and useful scrollback. Re-check
  that ASCII art never appears outside the face.
- [ ] Complete real voice-path checks: single Christopher voice, no overlapping voices, natural
  turn timing, interruption/barge-in, microphone permission denial, STT/TTS timeout, and
  declared fallbacks. Measure latency on the target machine rather than relying on a mocked
  worker.
- [ ] Capture real-browser face boot/render evidence: first-tap behavior, failed asset recovery,
  context loss, lifecycle cleanup, reduced motion, renderer budget, phone thermal/battery
  behavior, and GPU/device performance claims.

## MASTER personal assistance

- [ ] Complete one real read-only non-Google-Calendar calendar or email workflow end to end.
  Start with a narrowly scoped adapter, subject-bound permission, inspectable local state,
  current-data freshness, explicit failure states, and regression tests. Do not claim a live
  provider integration from a parser or fixture alone.
- [ ] Add one operator-selected external messaging channel through the existing MASTER runtime
  and shared session contract; Telegram is not a target. Prove identity isolation, permission
  checks immediately before effects, reconnects, attachment limits, delivery receipts, and safe
  handling of untrusted inbound instructions before adding further channels.
- [ ] Evaluate real advice quality against realistic personal-assistance scenarios for practical
  usefulness, factuality, calibration, safety and actionable next steps. Static contract
  fixtures are not evidence of model behavior; label mocked, model-backed and human-reviewed
  results separately.
- [ ] New-user trial of `bin/master` in a PTY, 2026-10-22 (16 turns: life, relationship,
  medical, sexual, workplace, philosophical and religious questions, then weather, flights,
  news, an email, a reminder and a repo search). The medical answer was right and short
  (legevakt 116 117, 113 for rest pain). Fixed since, each with a test: prose starting with an
  installed command ran as shell (`what`, `find`, `write`; 2608de39b); the operator's Claude
  Code Stop hook fired inside MASTER's claude lane and every reply opened "I did not run
  vps-deploy" (dc749128b); /clear sat 104s in council review and was vetoed (5a05b202a); "should
  I quit my job to make music" started dilla, which crashed on the fallback kit's missing `open`
  voice (71a3a97ff and 7ad060f92); a BINARY web result raised "incompatible character encodings"
  on every lane and opened every circuit (c1e3cef26); "what can you do" described only the
  repository (59e067d1f). Still open, unmeasured since the fixes:
  - Rerun 2026-10-23 on f507369b4: every answer was direct and useful, the capability answer
    covers a person's needs, and the reminder was kept as a task with an honest "nothing will
    ring". It found one more: "write an email asking him to fix the broken heater" started /fix
    in write mode (fixed in 6806b6fdc; its blank-line edits were restored). Still slow: boot
    17.6s, the greeting at 26.7s, each reply 13–16s end to end. Make replies stream their first
    words.
  - "does god exist? give me your actual view" ran two web searches (the second appending
    "official documentation") for a question that asks for a view, not evidence. Weather then
    said web tools were unavailable, and no answer cited a source. Decide whether ordinary
    lookups need approval at all.
  - "remind me tomorrow at 9" is kept as a task, but nothing alerts at the time; an alert needs
    a delivery channel (the face, a push, or the operator's messaging channel above).
  - Pre-existing reds found on the way: `test/test_media_intent.rb` went green in d8efe79db
    (each failure was a real misreading of postpro requests) and
    `test/test_ground_standing_orders.rb` in 40fd09ff7 (stale fakes), the two prompt tests in
    ffb4552ea, and `test/test_dialogue_rubric.rb`, which could not load, in 84d09daa1 and
    20028b7e5 ("what should I do next?" after a manipulation account kept no support protocol),
    and `test/test_self_test.rb` in abc31c68a (rename fallout).

## RAILS 8+ and mobile-first PWA products

- [ ] Run an independent /fix and bin/ci pass for every active app in RAILS/apps.yml, plus
  RAILS/test/run_all.rb. Shared-engine changes must be verified in each consumer app and in the
  deploy copy-tree layout.
- [x] Brgen's account-erasure suite ran on 2026-10-22: `test/jobs/user_purge_job_test.rb` 16
  runs, 223 assertions, green after 0866cf75b let the job destroy message metadata under strict
  loading (it raised on Vote#votable and rolled the erasure back) and classified
  activity_events, reactions, votes, outbound_clicks and conversation_participants as destroyed.
  Full brgen suite at a6fa4ac29: 1,432 runs, 0 failures, 0 errors.
- [x] Amber's suite ran on 2026-10-23 with its identity and merge migrations in the test schema:
  355 runs, 0 failures (47fe43c83), `test/jobs/user_purge_job_test.rb` 3 runs, 78 assertions.
  Getting there fixed two real faults: no account had a profile or privacy settings (a block
  passed to strict_loading! never ran), and erasure rolled back on a strict-loading refusal. The
  recurring 03:50 schedule is still unobserved on vm23, and amber's CI there died after 25 tests
  on dc749128b while the box was out of swap; rerun it.
- [ ] Verify the shared OAuth callback end to end in Brgen and Amber after the Amber
  federated-identity migration runs: provider-subject reuse (including BankID without email and
  legacy placeholder recovery), account cleanup, email-verification boundaries, and real
  configured Google/Facebook/Vipps/BankID callbacks. The 2026-10-25 source pass adds
  provider-row uniqueness recovery, recovery of eligible unverified non-guest non-BankID synthetic
  placeholders, merge-pair model validation with Brgen/Amber regression tests, and user/IP-scoped
  Amber AI rate limiting. These commits are source changes, not runtime evidence. Regenerate Amber's schema,
  run both app suites, and exercise real configured provider callbacks before closing this item.
- [ ] Execute the shared guest-to-account conversion tests in Brgen and Amber after Amber's
  `account_merges` and federated-identity migrations run. Verify anonymous post presentation
  survives, both sender and recipient sides of Amber's MASTER chat move to the registered
  account, Brgen conversation participants merge without colliding on unique conversation/user
  pairs, message receipts deduplicate while preserving earliest delivery/read evidence, typing
  indicators are cleared, trust signals deduplicate, and a failed merge leaves guest history
  untouched. Confirm old guest-session IDs are destroyed rather than promoted into authenticated
  sessions and the source guest row is anonymized with unusable credentials while retained only
  as the account-merge audit referent. Regenerate Amber's schema from migrations; source and
  regression tests are committed but runtime proof remains open.
- [ ] Run the guest-transfer failure and retry tests through password sign-in, magic-link
  sign-in, OAuth, and both signup controllers. The shared flow now checks for a committed audit
  record before rotating sessions, keeps the anonymous session active when transfer fails, and
  logs a retryable failure; confirm cookies, email verification, and already-created accounts
  behave correctly after migrations and app suites run.
- [x] The BankID legacy-account recovery guard is measured in both apps: brgen at a6fa4ac29,
  amber at 47fe43c83 (`test/controllers/bankid_identity_persistence_test.rb`, 9 runs). Recovery
  needs the synthetic `uid@bankid.oauth` address, no verification token and a returned
  `urn:bankid:bid;LOA=4`; a lower ACR is refused, and a BankID member without email can post as
  themselves.
- [ ] Brgen: finish and simulate the end-to-end hyperlocal social and marketplace journeys
  across feed, posts/comments, identity/moderation, discovery/maps, marketplace listings,
  dating, messenger, radio, and takeaway. Cover authorization boundaries, empty/error states,
  tenant/city resolution, upload limits, and mobile one-handed use.
- [ ] Brgen revenue readiness: verify the intended listing/offer/payment or monetization path,
  entitlements, moderation and abuse handling, privacy/terms, accounting/audit trail, and
  production configuration. Do not call it revenue-ready until the real configured path works
  end to end.
- [ ] Amber: run full outfit-combination and garment-scoring scenarios with real catalogue/media
  data. Verify diversity, garment identity/colour fidelity, user preference handling,
  provider/media limits, retries, caching, and any actual purchase or affiliate path.
- [ ] bsdports: complete a real package-index refresh and port lifecycle test. Verify signed
  archive manifests, DNS/public-HTTPS pinning, bounded response bodies, preserved metadata and
  dependency edges, CVE relationships, disk-space fallback, rollback safety, and OpenBSD package
  installation on a supported host.
- [ ] Audit all Rails mobile journeys at narrow widths, including keyboard-open layouts, focus
  visibility, 44px preferred primary targets, safe-area insets, 320px reflow, offline/read
  freshness, and install/update behavior. Keep product dialects distinct rather than flattening
  them into one palette.
- [ ] Re-measure generated CSS/JS and PWA budgets from a fresh source-to-build pass. Compare
  budgets to tracked ratchets; never raise ceilings to make a regression look green.

## OPENBSD deployment and operations

- [ ] Exercise the full deploy/canary/rollback sequence against a test target and then the
  intended host, including detached-commit behavior. Confirm deploy never leaves the production
  worktree attached to an unintended branch.
- [ ] Verify backup integrity and a real restore drill, scheduled jobs, health/uptime
  monitoring, certificate renewal, service restart permissions, bounded logs, and actionable
  alarms. A local fixture is not proof the remote host is healthy.
- [ ] Run relevant OPENBSD tests on OpenBSD itself for ksh/zsh, package signatures, service
  paths, permissions, pledge/privilege separation, and deployment scripts; label host-specific
  checks unmeasured when no OpenBSD host is available.

## STUDIO and Dilla

- [ ] Finish Dilla defragmentation only where one musical decision truly shares an owner. Keep
  dilla.rb as the thin public shell and one authoritative engine for theory, progressions,
  arrangement, drum feel, effects, mix, and master; avoid one-use wrapper files.
- [ ] Prove the default 92 BPM pocket and target sound in generated audio, not just parameter
  tests: 2–3-bar minor progressions, varied swing/dillatime, believable kick/snare/hat
  programming, saturation/tape/dub effects without muddying the drums, and restrained lead
  tones. Avoid overwriting an existing take; keep deterministic seeds reproducible.
- [ ] Render and inspect the requested dilla.wav and dilla.mp4 outputs, including the live path,
  postpro/three.js output, audio-analysis report, and failure cleanup. Compare against
  operator-supplied J Dilla reference tracks and document which musical characteristics are
  measured versus subjective.
- [ ] `STUDIO/test/dilla_test.rb` recorded 7 failures on 2026-10-23 (25 min run). A
  source/test follow-up was committed on 2026-10-24: the README reference heading, six-cent
  `prophet_pad` detune, tracked-tree expectation, eight-section 92 BPM showcase, five Rhodes
  layers, and guitar stereo group were reconciled. **Not rerun**; do not count these as closed
  until the fast suite and full suite run. The prior render-overwrite and bar-drift findings are
  still unverified. Decide each from fresh output before the `dilla.wav` overhaul.
- [ ] Run STUDIO fast tests and at least one full render on the target machine. Record audio
  peaks/loudness, clipping, duration, BPM, file integrity, and visual output; do not infer
  quality from a successful process exit.

## Cross-tree security, RubyLLM, and efficiency

- [ ] Finish the security review across MASTER, RAILS, OPENBSD, and STUDIO: outbound HTTP/SSRF,
  DNS pinning, body/time limits, authentication/authorization, rate limiting, CSP/CORS, upload
  paths, secret redaction, unsafe command construction, and safe failure states. Source-level
  hardening on 2026-10-25 keys Amber AI limits by user/IP and makes Brgen's generated avatar
  responses independent of account existence. Shared CSP nonce initializers exist, but real
  response headers/enforcement and targeted `html_safe` data-flow review remain unverified.
  Re-test the actual production boundary; do not close this item from source inspection alone.
- [ ] Benchmark RubyLLM routing/provider gains using representative workloads: latency, success
  rate, token/context use, cost, retries, circuit breakers, and fallback quality. Keep
  measurements per provider/model and distinguish observed values from estimates.
- [ ] Re-run the DRY/KISS and duplication census across the current tree. Review duplicate
  decisions, one-use abstractions, generated files, single-child directories, stale
  pointers/docs, and concepts that should have one authoritative owner. Preserve public
  paths/contracts and compare structural ratchets before and after changes.
  Initial Law-reader tranche landed on 2026-10-25: commits
  28a39324417f6a8f2562abdd17a7b17bb7592205 (canonical constitutional-priority reader),
  68b6ea269c7e24a1ea770f75e43e69ec52303201 (shared LawParity loaders and empty-catalogue
  refusal), and 83a3a9b26b2e9ec704ad6f641d08271fccc68a7b (canonical law-trace ceiling reader).
  These are source changes, not verified test passes. Run the focused constitutional-check,
  LawParity and ratchet tests, reader-singularity/law-trace checks, and then a bounded suite
  before closing any part of this work. The full LawRegistryAudit reconciliation and the
  FixLoop/RepairLoop/Kernel ownership analysis remain open.
- [ ] Re-run the four-tree performance sweep with before/after evidence: boot, CLI response, web
  first paint and interaction latency, JS/CSS payloads, memory/CPU, background work, and Dilla
  render time. Avoid claims based only on source size or unrepresentative local machines.
- [ ] Reconcile older conversation requests against executable source/tests before closing them.
  The current scoped GitHub API check returned no open issues or pull requests; older issue
  numbers surfaced in broad search results but are not confirmed open. Prior chat commitments
  still outstanding include the larger DRY/KISS census, Dilla/Postpro and Brgen SCSS source
  consolidation, the complete DeepSeek/Master findings audit, and fresh bounded tests across all
  four trees. Keep these represented here until proven complete.

## Closure rule

An item is closed only when the owning command or interaction ran on the current commit, the
result is recorded, and any generated artifact is in sync with its source. For rendered/UI work,
include before/after screenshots, viewport, device/runtime, and relevant console/network errors.
If a tool or host was unavailable, record that state explicitly instead of guessing.
