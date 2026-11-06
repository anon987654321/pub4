# pub4 - remaining work

Audit snapshot: 2026-11-06, rechecked against `main` at `9c03cef500cc18b10e9acf7a7dbc49eb6fee1a6d` immediately before this register update.
This register replaces the previous 1,275-line, 462-checkbox carry-forward
dump. It contains unresolved outcomes, not session notes or speculative
architecture proposals.

## Stewardship

Documentation reduction and decisive stewardship remain priorities one and two.
Keep one canonical instruction at each real boundary; remove duplication before
adding a registry, wrapper or document. Add no Markdown files for backlog
administration.

When an authorised request overlaps an item below, do the work now and remove
the item when its evidence is committed. Add no TODO for work available with
current tools, credentials and authority. Keep only genuine unresolved work
and external prerequisites. Continue independent work when one item is blocked.

A source change, authored test, passing test, full suite, rendered product and
live deployment are different claims. Record revision, command, exit status
and evidence. Use PASS, FAIL, INCONCLUSIVE, BLOCKED, NOT_RUN, TIMEOUT or
DELIVERY_FAILED truthfully. Never infer PASS from a declaration, commit,
screenshot count or previous revision.

## 1. Current-revision acceptance

- [ ] **MASTER on pinned Ruby 4.0.5.** Run focused Law, Soul, configuration,
  registry, replay-reader, fix-loop oscillation, reachability, run-ledger,
  media and CLI regressions. Then run
  `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 MASTER_TEST_PROGRESS_EVERY=25 rake test`,
  `MASTER_TEST_JOBS=3 rake test`, `rake audit` and
  `bin/check --profile=agent`. Inspect
  `.master/check/suite-report.json` for incomplete workers and mismatched
  start/result counts. Preserve actual output.
- [ ] **RAILS full contracts on one current revision.** Run
  `ruby RAILS/test/run_all.rb`, every app's `bin/ci` and
  `ruby MASTER/checks/runner.rb --all`. The last recorded RAILS run had six
  red checks: CSS budgets, file-length and method-length ratchets,
  `studio_contract` (possibly a stale diagnosis), viewport spill, and live
  locale/layout checks against old servers. Reproduce against fresh servers
  and current migrations; fix confirmed defects rather than suppressing
  findings or raising ceilings.
- [ ] **RAILS focused gaps.** Run billing, API-key/API-lint, dating identity,
  Radio manifest/TrackImport, share and job-concurrency, Amber account-merge,
  Marketplace filter/card/mutation, Takeaway model/migration, empty-state,
  token-projection and design-token tests. Use fresh databases; verify both
  fresh-install and upgrade migrations where applicable.
- [ ] **OPENBSD updated runner and native proof.** Previous evidence was
  45 files/0 red, rehearsal 16/16, PF policy 11/11 and evidence tool 9/9.
  The runner now rejects empty or invalid Minitest summaries and has new
  regression tests. Run the updated `ruby OPENBSD/test/run_all.rb` and
  runner tests; on actual OpenBSD run `pfctl -nf /etc/pf.conf`.
- [ ] **STUDIO full proof.** Earlier `rake check` and Dilla test
  (17 runs, 386 assertions) passed. The strict per-file runner now forwards
  keyword and positional subprocess environments correctly and rejects empty
  or invalid Minitest summaries. Its new subprocess regressions are source
  coverage, not a passing run. Run `cd STUDIO && rake check test` on pinned
  Ruby 4.0.5. Review an actual Dilla render by ear with rights-cleared local
  source and confirm the sample level leaves voice room.
- [ ] **Generated-output freshness.** Check design-token projection and CSS;
  compare `MASTER/web/public/face.runtime.js` and `face.css` with their
  sources; run `cd MASTER && rake docs:agent_contracts` and
  `rake lint:agent_contracts`. Run
  `ruby MASTER/lib/operator/self_findings.rb --ratchet` after source changes
  settle; review member deltas and ensure neither ceiling rises.
- [ ] **Law and Baymard gates.** Run `rake lint:law_parity` and
  `rake -f MASTER/Rakefile ux:baymard` on the pinned toolchain. The Baymard
  regression file previously ran 24/24; the full report remains unverified.
  Keep unmeasurable surfaces INCONCLUSIVE and reuse existing Law identities.

## 2. MASTER /fix convergence and recovery

- [ ] Run `MASTER/test/test_fix_interruption_restart.rb` on pinned Ruby.
  Verify interruption, rollback, durable mission resumption, orphaned
  Kernel-receipt recovery and checkpoint survival. Then exercise budget and
  collapse behavior, zero-repair ledger honesty and adapter receipt parity.
- [ ] Run one genuine repository-wide `/fix` over MASTER, RAILS, OPENBSD and
  STUDIO. Preserve four independent reports, grounded candidates, revision,
  receipts and truthful terminal states (DONE, PLATEAU, HUMAN_DECISION,
  BLOCKED, VALIDATION_FAILED, DELIVERY_FAILED or TIMEOUT). Measure actual
  convergence and repair quality; an architecture map is not runtime proof.
- [ ] Verify shared-checkout lock, writer ownership, interruption cleanup and
  path-scoped commit behavior with another active writer. Never stage another
  writer's changes.
  
Build on existing Mission, Supervisor, TaskSteward, TaskContract,
OutcomeLearning, RepairMemory, RunBudget, RunPulse, Transaction and
Checkpoint owners. Do not create a YAML backlog, second proposal system,
second push path or duplicate orchestration to make TODO.md machine-readable.

## 3. Interaction, rendered UI and accessibility

- [ ] **400-case interaction campaign.** The last audit counted 400 cases:
  8 mapped adapters and 392 unmapped. Add exact action/fault tests with
  isolated state and saved evidence. Do not map unrelated tests or use generic
  page-load assertions. Run
  `ruby MASTER/tools/rails/premerge.rb --interactions`; SKIPPED/BLOCKED
  cases must keep the gate non-green.
- [ ] **Rendered review.** The 2026-11-03 sweep captured 181 pages, 1,751
  screenshots and 697 dialog states with zero capture failures. Review the
  captures, reach the 64 parameter routes missed by the guest sweep (mostly
  signed-in states), and inspect keyboard-only use, 200% zoom, forced colours,
  reduced motion, focus and responsive overflow.
- [ ] **Accessibility.** The computed Chrome AX-tree check samples at most
  two surfaces per app and viewport. Expand only after measuring cost. Keep
  VoiceOver/NVDA announcement tests and human assistive-technology sessions
  separate from automated AX-tree checks.
- [ ] **Human task evidence.** Collect privacy-reviewed, anonymised evidence
  for navigation, search recovery, product evaluation, cart costs, guest
  checkout/recovery, mobile completion, keyboard and assistive technology.
  Never manufacture participants or observations.
- [ ] **WebGL proof.** Verify Brgen Maps clustering in a real browser at
  mobile/desktop widths: cluster expansion, popups, search, cross-city links,
  keyboard/list alternative, failure fallback, context teardown and console.
  Run its focused Rails test. Verify BSDPorts' dependency graph in a real
  browser and run `cd RAILS/bsdports && bin/ci`; keep the text tree accessible.

## 4. RAILS product quality

- [ ] **End-to-end journeys.** Cover Brgen feed, posts, moderation, maps,
  Marketplace, dating, messenger, radio and takeaway, including authorisation,
  empty/error states, guest-to-account conversion and transfer/retry for every
  sign-in path.
- [ ] **Budgets and ratchets.** Re-measure CSS, JS and PWA from a fresh build.
  Last recorded CSS values were Brgen 289/217 KB, Amber 154/103 KB and
  BSDPorts 91/62 KB (measured/ceiling); refresh before choosing refactors.
  Re-run file/method length checks on current main and fix actual hot spots.
- [ ] **SEO/indexability.** Crawl canonical hosts brgen.no, ai.brgen.no,
  amberapp.art and bsdports.org; verify aliases amberapp.no, amberapp.online
  and bsdports.net. Include representative Brgen vertical hosts and city
  apexes. Record timestamped HTTP/redirect, robots, sitemap, JSON-LD and
  indexability evidence. Decide whether the MASTER face should be indexed.
  Reuse existing surface-schema and SEO checks.
- [ ] **Marketplace/Takeaway.** Run focused filters, cards, mutations, render
  and model suites; verify fresh and upgraded migrations; capture responsive
  browser evidence without changing existing listing rows or ownership.
- [ ] **Whyp/Radio.** Run the import-time Whyp resolver, TrackImport and
  Playlist view/controller suites on pinned Rails. Prove Radio tenant
  isolation, idempotency, ordering, checksums and failure atomicity. Do not
  import any of the 35 selected recordings until distribution rights are
  confirmed individually.
- [ ] **BSDPorts/empty states.** Run Solid Queue proof: enqueue a development
  job, verify its configured SQLite database and recurring jobs, inspect the
  jobs UI. Run empty-state source lint and focused Amber/Brgen views.
- [ ] **Tokens/face CSS.** Run
  `ruby MASTER/tools/rails/build_all_css.rb --check` and the design-token
  tests. Distinguish semantic constants (black canvas/print and OpenBSD
  wscons green) from replaceable presentation literals; regenerate face CSS
  and compare rendered pages.
- [ ] Close accepted `MASTER/data/ux_refinements.yml` rows only with their
  declared test, browser, terminal, accessibility or rendered-runtime proof.

### Screenshot-led micro-refinements (reviewed 2026-11-06 at `main@3fb7dbc`)

These are targeted findings from the committed RAILS desktop/mobile and
Mr. Damascy flow captures, not proof of the current live render. Reproduce
each in the existing Chrome/CDP suite before changing source; distinguish
seed, consent, loading and empty states from persistent layout defects.
Keep the product dialects, operator-owned palette/typefaces, canonical
tokens, and original marks intact. The Mr. Damascy item sheet, empty-cart
recovery, loyalty and offline screens already have clear, coherent states;
preserve those strengths.

- [ ] **Shared consent banner / viewport clearance.** In the first-consent
  mobile captures across Brgen, Dating, Maps, Radio, Messenger and TV, the
  fixed consent panel occupies a substantial part of the first viewport and
  covers underlying page content. Compare fresh-consent with saved-consent
  sessions at 360x800, 390x844, short landscape and 200% zoom. Keep reject,
  manage and accept equally clear; verify the panel scrolls within the
  available safe-area, does not cover the persistent tab bar or focused
  control, and leaves the next page action reachable. Preserve consent
  semantics and copy; tune only measured geometry in the shared owner.
  Laws: `REACH`, `PROPORTION_eight_px_rhythm`, `OPERATOR_RENDERED_contract`.
- [ ] **Maps list icon and row hierarchy.** The committed desktop/mobile
  places-list captures show the literal word `place` before repeated result
  names. Trace the icon/font fallback that produces it; render the intended
  icon glyph or omit the decorative mark rather than exposing a ligature
  name. Tighten repeated row height and give place name, kind, city and
  address a deliberate reading order. Keep the list as a fully operable
  keyboard/screen-reader alternative to the full-bleed map.
  Laws: `DENSITY_aesthetic_integrity`, `BRINGHURST`, `REACH`.
- [ ] **Marketplace hero fallback.** The listing view emits a large initial
  letter (default `B`) when the featured listing has no photo; the desktop
  and mobile captures show that fallback dominating an otherwise empty
  media panel. Replace the generic monogram with a deliberate, truthful
  no-featured-image state, and keep the media proportion useful when no
  offer exists. When a listing/photo is available, let the real product
  lead. Preserve the existing commerce dialect, listing data and tokens.
  Laws: `DENSITY_form_follows_function`, `DENSITY_aesthetic_integrity`,
  `OPERATOR_RENDERED_contract`, `VISUAL_HIERARCHY`.
- [ ] **Amber editorial tile line breaks.** At the captured desktop width,
  `Bymorgen` breaks mid-word as `Bym / orge / n`; the mobile capture does
  not. Correct the desktop tile's available measure, wrapping and type
  constraint so Norwegian and English copy wrap at word boundaries without
  clipping or shrinking the editorial hierarchy. Check the existing tile
  grid at 1024, 1280 and 1440 CSS px plus 390px mobile.
  Laws: `BRINGHURST_line_breaks`, `BRINGHURST_measure`,
  `PROPORTION_eight_px_rhythm`.
- [ ] **Radio featured-track state.** The captured Radio home has a large
  grey media block below `Utvalgt spor`, with no visible cover or state
  explanation. Establish whether this is unloaded artwork or no selected
  track. Render the real cover when available and an explicit, compact
  loading/empty state otherwise; make playback controls and status agree
  with the actual player state. Do not fabricate artwork or playback.
  Laws: `TRUTHFUL_STATUS`, `WAITING_STATE_MEANING`,
  `DENSITY_aesthetic_integrity`.
- [ ] **Messenger empty rail.** The captured empty inbox shows repeated bare
  `#` markers in the room rail while the main pane says there are no
  conversations. Confirm that each marker represents a real, named room;
  otherwise remove the inert placeholders or give populated rooms an
  accessible name. In the genuinely empty state, keep one clear next action
  and avoid presenting an empty navigation rail as usable content. Preserve
  the populated desktop split-pane layout.
  Laws: `BOUNDED_LOAD_choice_overload`, `REACH`,
  `OPERATOR_RENDERED_contract`.
- [ ] **BSDPorts result readability, without redesign.** The desktop/mobile
  captures preserve the intentionally spare Google-like search surface, but
  result names, versions, repository identifiers and update metadata read
  very small and weakly separated at capture scale. Measure their actual
  CSS-pixel size, contrast and line-height in Chrome; improve only the
  information hierarchy and readable measure where evidence warrants it.
  Keep white paper, Arial, blue links, square geometry and compact density;
  do not cardify or re-theme the product.
  Laws: `BRINGHURST_measure`, `BRINGHURST_scale`,
  `PROPORTION_contrast`, `REACH`.
- [ ] **Mr. Damascy empty checkout state.** The checkout capture shows `0 kr`
  and both payment CTAs even though no cart lines are present. The controller
  already redirects an empty-cart submission back to the cart, so this is a
  rendered-state mismatch rather than evidence of a payment bypass. Present
  an explicit recoverable empty-cart state and hide/disable payment actions
  until a payable cart and a valid total exist; keep the normal one-screen
  Vipps Express path short. Preserve the restaurant's original logo, palette
  and mobile-first 480px shell.
  Laws: `TRUTHFUL_STATUS`, `AFFORDANCE_CLARITY`, `COST_TRANSPARENCY`,
  `OPERATOR_RENDERED_contract`.
## 5. MASTER CLI, web, voice and face

- [ ] **CLI performance and interaction.** Measure boot, first token,
  completed-reply latency and memory on current main. Improve measured
  bottlenecks without blocking input on face rendering. Finish result-first
  output, live status, collapsed tool output, width-aware wrapping,
  NO_COLOR/dumb-terminal behavior, PTY cancellation and terminal restoration,
  paste/multiline handling, queued interruptions, actionable errors, real
  help examples, fast startup, session resume, /diff and JSON-only quiet mode.
- [ ] **Web control surface.** Make conversation, face, missions and live log
  useful together. Prove mission transitions, morning summary and explicit
  decisions, per-hunk diff review, before/after visual review, mobile and
  keyboard access, reduced motion and session search. Add health/spend views
  only when their backing measurements are reliable; hold no secrets.
- [ ] **Voice.** Measure time-to-first-audio. Improve sentence streaming,
  interruption on typing/speech, phrase caching, short spoken forms for code
  and paths, secret suppression, per-sentence Norwegian detection, loudness
  and local fallback. Report worker failure truthfully. Voice default/startup
  behavior remains an operator decision.
- [ ] **One face contract.** Keep the existing single FaceWorld/FaceState
  renderer, frame limits, caching and reduced-motion behavior. Add
  phoneme-timed lip sync, Norwegian vowel shapes, listening pose, attention
  cues and CLI/web snapshot coverage without a second renderer.
- [ ] **Avatar geometry.** Derive deterministic particle positions from the
  recovered avatar reference inside the current renderer; preserve fallback
  and point budgets, then prove narrow/wide browser and GPU behavior.
- [ ] **Radio-to-face motion.** Implement the audio-modulated inward warp in
  the existing particle shader and track-driven transitions between the two
  current visualizers. Keep the existing transport bar; prove beat response,
  reduced motion and mobile/desktop playback.
- [ ] **Conversation evaluation.** Replay representative prior conversations
  for answer-first behavior, no repeated known facts, one necessary question
  at most, natural interruption/resumption, preference use and uncertainty.
  Turn recurring corrections into regressions, not another personality system.

## 6. Ownership and documentation simplification

- [ ] **Semantic ownership census.** For each real duplication candidate,
  map owner, callers, constants/assets/views, autoload/eager-load behavior,
  routes, migrations, serialization/public APIs, tests, security/tenant/
  transaction contracts, destination and rollback. Classify MERGE, MOVE,
  RENAME, INLINE, DELETE, RETAIN or INVESTIGATE. Compare behavior, not
  hashes or names; never delete based only on file size, path depth or an
  unclear caller.
- [ ] **Documentation reduction.** Keep one canonical entry at each real
  boundary (repository, tree, product/engine). Remove stale instructions only
  after checking references, generators, links, tests and agent entrypoints.
  Preserve useful recovery/provenance records. Update sources and generators
  together; add no Markdown files.
- [ ] **Historical hardening review.** Reconcile the remaining P01-P11
  findings in `MASTER/docs/history/fix-review-log.md`. L4 stale-member
  detection/tests, L5 heredoc/keyword detection plus structured Council
  ideation, L7 declarative/runtime parity assertion, and L8 parse-time
  check-registry refusal now have source coverage on `main`; their focused
  test runs remain NOT_RUN. L4's stored census is not re-baselined until a
  pinned Ruby 4.0.5 run has reported exact member drift. Continue with the
  genuinely open R3/R8-R13/R16-R17/H2-H8 findings. The LLMDispatcher
  Replicate chat poll is source-fixed for URL trust, bearer-token confinement
  and network deadlines. STUDIO ReplicateClient now validates model, version,
  training and prediction identifiers before URL interpolation and rejects
  dot-segment or escaped API paths. Six focused path regressions are added
  but NOT_RUN; transport, upload/download and provider-integration review
  remains open. R8 also has a definite commit-refusal rollback regression;
  the full transaction-aware candidate/apply and later-verification recovery
  path remains open.
- [ ] **Local Claude hooks.** On macOS, launch a real Claude Code session and
  verify project hooks load through the `.claude` symlink.
- [ ] **AI3 recovery.** Compare recovery manifests with recoverable historical
  Git/archive objects; map unique behavior to current owners and state what
  is actually absent. Do not restore a former tree wholesale.
- [ ] **Account-wide transcript coverage.** Resume the earlier archive review
  only when an official ChatGPT export is supplied. Preserve source IDs and
  timestamps, deduplicate handoffs and do not claim all conversations were
  audited without that source.

## 7. OpenBSD production safety and external seams

- [ ] **Measure vm23 before changing it.** The 2026-11-04 note reported 1 GB
  and near-exhausted swap; that is not a current measurement. Capture live
  RAM, swap, service RSS, job processes and health first. Present a provider
  upgrade only if current measurements justify it. Do not add swap, restart
  services or change production as an unapproved stopgap.
- [ ] **Reproducible deployment artifact.** Build code, assets and
  OpenBSD/amd64 native gems on the Mac. vm23 should unpack and run a reviewed
  artifact, not compile dependencies during deployment. Prove manifest,
  checksums and target compatibility.
- [ ] **Staged deploy and rollback.** Prove isolated release directory,
  atomic live switch, pre-deploy rehearsal, resource guard, route-manifest
  smoke test and rollback to the previous known-good release. Preserve
  actual host and backup/restore evidence.
- [ ] Run native `pfctl -nf /etc/pf.conf` on OpenBSD; source parsing on macOS
  is not equivalent.

External/operator evidence remains separate from code work: individual
distribution rights for the 35 Radio Bergen recordings; human usability and
screen-reader sessions; the macOS Claude hook launch; live vm23 capacity
decision; distance, expiring-post and voice-default decisions. Review account
quota after 2026-12-01 before considering Ollama re-enablement. Do not
re-enable it by assumption.

## Deferred, not active work

- pub5 is deferred. Do not freeze or migrate pub4 until its acceptance evidence
  is complete and the operator explicitly chooses to start a new tree.
- The archived movie-acquisition proposal is not approved. Reopen only for a
  lawful provider/catalogue integration with explicit provenance and licensing.
- Amber 3D garment inspection and new STUDIO audio-reactive artwork remain
  experiments until real assets, a concrete consumer and measurable acceptance
  exist. Preserve the non-WebGL path and single audio clock.
- Perplexity's old task is retired: its generic hosted-provider route has been
  removed from `models.yml` and a regression asserts it is not routable.
  Reopen only for a provider-specific adapter with reviewed product choice,
  citation/usage preservation and bounded canary.
- Replicate ownership is settled: STUDIO owns `STUDIO/replicate/client.rb`.
  Do not reopen the ownership question or move its implementation into MASTER.

---

The previous list mixed completed source changes, duplicated verification,
historical narration and unapproved alternatives. This version retains
unresolved outcomes and removes the false impression that every checkbox is
a separate current task.