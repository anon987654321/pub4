# pub4 outstanding work

Audit baseline: d9a008ba1f332a312122e342913486c54a32f18a. This is the one cross-tree backlog; do not create separate project TODO files. A source edit, a static contract, an empty CI status list, and a passing live run are different kinds of evidence. Close an item with the command or browser evidence recorded in the commit.

## P0 — evidence before calling the system complete

- [ ] Run a fresh bounded release pass against the exact commit intended for deployment: constitutional and repository gates, all RAILS contract tests, active app suites, OPENBSD tests, and STUDIO fast tests. Record PASS, FAIL, INCONCLUSIVE, BLOCKED, or TIMEOUT separately. GitHub returned no status entries for the audit head; that is not a green result.
- [ ] Complete the requested 200–400 scenario interaction matrix across MASTER CLI, MASTER web, keyboard/touch, session state, routes, errors, models/tools, speech, reconnects, offline mode, and PWA updates. Exercise success and failure paths. Record scenario ID, setup, action, observed result, and evidence; scripted mocks do not substitute for real browser/CLI smoke tests.
- [ ] Run the live rendered-layout suite with screenshots and geometry evidence at 320, 360, 375, 390, 430, 480, 640, 768, 1024, and 1280 CSS-pixel widths. Include keyboard-only use, zoom/reflow, safe-area, forced-colors, and reduced-motion checks. Do not report visual completion from source inspection alone.
- [ ] Run MASTER/bin/operator triangle up before relying on rendered gates, then run the repository gate runner. Inspect every INCONCLUSIVE or BLOCKED result rather than counting it as success.
- [ ] Prove deploy and recovery on the intended OpenBSD host. Check the deployed commit, service health, logs, backups, and a restore path. Keep deployment separate from local-source test evidence.

## MASTER CLI, web, voice, and shared session

- [ ] Finish the Ghostty-inspired web-console pass with rendered visual review. The canonical palette now separates graphite shell surfaces, muted violet focus, neutral text, and the sparse lime semantic signal; the face renderer remains the focal point. Source-level mobile rules are in place, but final spacing, face/prompt coexistence, dashboard density, contrast measurements, and desktop/mobile screenshots remain unverified.
- [ ] Verify the installed PWA end to end: install, launch, safe-area layout, offline fallback, stale asset handling, service-worker update, and recovery after a failed request. Confirm that the shared manifest stays host-aware and that only intended stable resources are cached.
- [ ] Validate parity across CLI and browser for conversation/session state and the requested /connect, /join, and /msg channel flows. Check destination, reconnect, history, interruption, and error behavior; do not assume parity from shared naming.
- [ ] Run the full /fix phase loop per tree and demonstrate truthful DONE, PLATEAU, HUMAN_DECISION, BLOCKED, VALIDATION_FAILED, DELIVERY_FAILED, and TIMEOUT states. Verify dirty-tree preservation, interrupted writes, disk exhaustion, retry convergence, and rollback/undo behavior.
- [ ] Validate the OpenBSD Operator CLI and /help against the requested plain dmesg style, correct checkout/tree-relative location, no decorative status, and useful scrollback. Re-check that ASCII art never appears outside the face.
- [ ] Complete real voice-path checks: single Christopher voice, no overlapping voices, natural turn timing, interruption/barge-in, microphone permission denial, STT/TTS timeout, and declared fallbacks. Measure latency on the target machine rather than relying on a mocked worker.
- [ ] Capture real-browser face boot/render evidence: first-tap behavior, failed asset recovery, context loss, lifecycle cleanup, reduced motion, renderer budget, phone thermal/battery behavior, and GPU/device performance claims.

## MASTER personal assistance

- [ ] Complete one real read-only non-Google-Calendar calendar or email workflow end to end. Start with a narrowly scoped adapter, subject-bound permission, inspectable local state, current-data freshness, explicit failure states, and regression tests. Do not claim a live provider integration from a parser or fixture alone.
- [ ] Add one operator-selected external messaging channel through the existing MASTER runtime and shared session contract; Telegram is not a target. Prove identity isolation, permission checks immediately before effects, reconnects, attachment limits, delivery receipts, and safe handling of untrusted inbound instructions before adding further channels.
- [ ] Evaluate real advice quality against realistic personal-assistance scenarios for practical usefulness, factuality, calibration, safety and actionable next steps. Static contract fixtures are not evidence of model behavior; label mocked, model-backed and human-reviewed results separately.

## RAILS 8+ and mobile-first PWA products

- [ ] Run an independent /fix and bin/ci pass for every active app in RAILS/apps.yml, plus RAILS/test/run_all.rb. Shared-engine changes must be verified in each consumer app and in the deploy copy-tree layout.
- [ ] Verify the shared OAuth callback end to end in Brgen and Amber after the Amber federated-identity migration runs: provider-subject reuse (including BankID without email and legacy placeholder recovery), account cleanup, email-verification boundaries, and real configured Google/Facebook/Vipps/BankID callbacks. Regenerate Amber's schema via the Rails migration runner and run both app suites; this session added migrations and regression tests but could not execute them or access live provider credentials, so keep the checks open until measured.
- [ ] Execute the shared guest-to-account conversion tests in Brgen and Amber after Amber's `account_merges` and federated-identity migrations run. Verify anonymous post presentation survives, both sender and recipient sides of Amber's MASTER chat move to the registered account, Brgen conversation participants and trust-signal deduplication remain intact, and a failed merge leaves guest history untouched. Confirm old guest-session IDs are destroyed rather than promoted into authenticated sessions. Regenerate Amber's schema from migrations; source and tests are committed but runtime proof remains open.
- [ ] Validate the BankID legacy-account recovery guard with the real app suites: recovery is allowed only for the old synthetic `uid@bankid.oauth` address with no email-verification token; a manually registered unverified address must remain unlinked. Runtime tests have been added but were not executed in this session.
- [ ] Brgen: finish and simulate the end-to-end hyperlocal social and marketplace journeys across feed, posts/comments, identity/moderation, discovery/maps, marketplace listings, dating, messenger, radio, and takeaway. Cover authorization boundaries, empty/error states, tenant/city resolution, upload limits, and mobile one-handed use.
- [ ] Brgen revenue readiness: verify the intended listing/offer/payment or monetization path, entitlements, moderation and abuse handling, privacy/terms, accounting/audit trail, and production configuration. Do not call it revenue-ready until the real configured path works end to end.
- [ ] Amber: run full outfit-combination and garment-scoring scenarios with real catalogue/media data. Verify diversity, garment identity/colour fidelity, user preference handling, provider/media limits, retries, caching, and any actual purchase or affiliate path.
- [ ] bsdports: complete a real package-index refresh and port lifecycle test. Verify signed archive manifests, DNS/public-HTTPS pinning, bounded response bodies, preserved metadata and dependency edges, CVE relationships, disk-space fallback, rollback safety, and OpenBSD package installation on a supported host.
- [ ] Audit all Rails mobile journeys at narrow widths, including keyboard-open layouts, focus visibility, 44px preferred primary targets, safe-area insets, 320px reflow, offline/read freshness, and install/update behavior. Keep product dialects distinct rather than flattening them into one palette.
- [ ] Re-measure generated CSS/JS and PWA budgets from a fresh source-to-build pass. Compare budgets to tracked ratchets; never raise ceilings to make a regression look green.

## OPENBSD deployment and operations

- [ ] Exercise the full deploy/canary/rollback sequence against a test target and then the intended host, including detached-commit behavior. Confirm deploy never leaves the production worktree attached to an unintended branch.
- [ ] Verify backup integrity and a real restore drill, scheduled jobs, health/uptime monitoring, certificate renewal, service restart permissions, bounded logs, and actionable alarms. A local fixture is not proof the remote host is healthy.
- [ ] Run relevant OPENBSD tests on OpenBSD itself for ksh/zsh, package signatures, service paths, permissions, pledge/privilege separation, and deployment scripts; label host-specific checks unmeasured when no OpenBSD host is available.

## STUDIO and Dilla

- [ ] Finish Dilla defragmentation only where one musical decision truly shares an owner. Keep dilla.rb as the thin public shell and one authoritative engine for theory, progressions, arrangement, drum feel, effects, mix, and master; avoid one-use wrapper files.
- [ ] Prove the default 92 BPM pocket and target sound in generated audio, not just parameter tests: 2–3-bar minor progressions, varied swing/dillatime, believable kick/snare/hat programming, saturation/tape/dub effects without muddying the drums, and restrained lead tones. Avoid overwriting an existing take; keep deterministic seeds reproducible.
- [ ] Render and inspect the requested dilla.wav and dilla.mp4 outputs, including the live path, postpro/three.js output, audio-analysis report, and failure cleanup. Compare against operator-supplied J Dilla reference tracks and document which musical characteristics are measured versus subjective.
- [ ] Run STUDIO fast tests and at least one full render on the target machine. Record audio peaks/loudness, clipping, duration, BPM, file integrity, and visual output; do not infer quality from a successful process exit.

## Cross-tree security, RubyLLM, and efficiency

- [ ] Finish the security review across MASTER, RAILS, OPENBSD, and STUDIO: outbound HTTP/SSRF, DNS pinning, body/time limits, authentication/authorization, rate limiting, CSP/CORS, upload paths, secret redaction, unsafe command construction, and safe failure states. Re-test the actual production boundary after recent hardening commits.
- [ ] Benchmark RubyLLM routing/provider gains using representative workloads: latency, success rate, token/context use, cost, retries, circuit breakers, and fallback quality. Keep measurements per provider/model and distinguish observed values from estimates.
- [ ] Re-run the DRY/KISS and duplication census across the current tree. Review duplicate decisions, one-use abstractions, generated files, single-child directories, stale pointers/docs, and concepts that should have one authoritative owner. Preserve public paths/contracts and compare structural ratchets before and after changes.
- [ ] Re-run the four-tree performance sweep with before/after evidence: boot, CLI response, web first paint and interaction latency, JS/CSS payloads, memory/CPU, background work, and Dilla render time. Avoid claims based only on source size or unrepresentative local machines.
- [ ] Reconcile older conversation requests against executable source/tests before closing them. The current scoped GitHub API check returned no open issues or pull requests; older issue numbers surfaced in broad search results but are not confirmed open. Prior chat commitments still outstanding include the larger DRY/KISS census, Dilla/Postpro and Brgen SCSS source consolidation, the complete DeepSeek/Master findings audit, and fresh bounded tests across all four trees. Keep these represented here until proven complete.

## Closure rule

An item is closed only when the owning command or interaction ran on the current commit, the result is recorded, and any generated artifact is in sync with its source. For rendered/UI work, include before/after screenshots, viewport, device/runtime, and relevant console/network errors. If a tool or host was unavailable, record that state explicitly instead of guessing.
