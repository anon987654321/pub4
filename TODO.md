# pub4 — remaining work

Audit snapshot: 2026-11-06, rechecked against `main@40d260cab2c2b92a268e2ccbc24695fcb22cfaa3` immediately before this consolidation.
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
- [ ] **Maps list hierarchy and stale-capture verification.** The current card
  source now omits the generic `place` kind instead of printing it as a raw
  label; a controller regression covers that case. Run the maps test and
  recapture desktop/mobile before closing this item. Review place name, kind,
  city and address order, and keep the list as an operable keyboard and
  screen-reader alternative to the full-bleed map.
  Laws: `DENSITY_aesthetic_integrity`, `BRINGHURST`, `REACH`.
- [ ] **Marketplace no-photo state verification.** The generic monogram is
  replaced by a compact, localized no-photo/no-featured-listing message, with
  a shorter media well and a controller regression. Run the marketplace
  test and recapture both viewports; keep the row open until the rendered
  hierarchy and media proportions are confirmed.
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
- [ ] **Radio tunnel recapture.** The current playlist home now uses the full-screen
  tunnel, an explicit tap-to-start overlay, and a live track label; the November
  5 image appears to predate that surface. Recapture after the source change and
  verify the first-play, no-track and reduced-motion states before deciding
  whether an empty/loading treatment is still missing.
  Laws: `TRUTHFUL_STATUS`, `WAITING_STATE_MEANING`,
  `DENSITY_aesthetic_integrity`.
- [ ] **Messenger rail recapture.** Current source strips the leading `#` and
  renders the channel's first letter, with the full channel name available
  to assistive technology. The November 5 screenshot predates or contradicts
  that source. Re-run the focused view test and recapture before changing the
  implementation again; preserve the populated split-pane layout.
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
- [ ] **Mr. Damascy empty checkout verification.** The GET action now redirects an
  empty cart to the cart's existing empty state (or resumes its just-placed
  unpaid order), and a regression asserts no zero-value payment buttons are
  rendered. Run the focused checkout test and recapture the empty-cart flow;
  the normal one-screen Vipps path remains unchanged.
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
- [ ] **Historical hardening review.** Reconcile the remaining P01–P11
  findings in `MASTER/docs/history/fix-review-log.md`. L4 stale-member
  detection/tests, L5 heredoc/keyword detection plus structured Council
  ideation, L7 declarative/runtime parity assertion, and L8 parse-time
  check-registry refusal now have source coverage on `main`; their focused
  test runs remain NOT_RUN. L4's stored census is not re-baselined until a
  pinned Ruby 4.0.5 run has reported exact member drift. Continue with the
  genuinely open R3/R8–R13/R16–R17/H2–H8 findings. The LLMDispatcher
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

## 8. Consolidated backlog inventory

This section brings the repository's remaining tracked TODOs, backlog rows, UX acceptance work, workstream wishlist and operator-only dependencies into the single root register. It is an index as well as an action list: the structured source files remain the detailed evidence and decision records, not competing Markdown queues. Do not treat an aspirational or unpicked idea as implementation authority.

The tracked repository has one TODO file: this root `TODO.md`. The cross-tree contract in `MASTER/test/test_single_backlog_contract.rb` intentionally rejects nested TODO files. Keep that contract. Do not delete the YAML ledgers below; their IDs, states, rejected alternatives and evidence contracts are consumed by MASTER and are not duplicate prose backlogs.

### 8.1 RAILS refinement survey — three items still open

`RAILS/refinements.yml` was surveyed on 2026-11-04: 770 rows, 755 marked done, 12 marked invalid, and 3 still open. The 12 invalid rows are historical refutations, not work to resurrect without new source evidence.

- [ ] **amber-057 — Amber wordmark.** Outline the Caprasimo wordmark in `RAILS/amber/app/views/shared/_logo.html.erb` as SVG paths so it no longer needs the webfont preload on every page.
- [ ] **shared-010 — Button sizing.** Retire `.button-small` in `RAILS/__shared/app/assets/stylesheets/_buttons.scss` in favour of the existing `$compact-contexts` contract; markup should not name a size.
- [ ] **shared-029 — Privacy-preserving embeds.** Cache link-embed thumbnails first-party in `RAILS/__shared/app/views/shared/_link_embed.html.erb`; the provider should not be contacted on page view before the reader presses play.

Close these rows in `RAILS/refinements.yml` only with the corresponding source and rendered evidence. Do not copy the 755 completed or 12 invalid rows back into the active list.

### 8.2 MASTER UX acceptance matrix — 90 unverified contracts

`MASTER/data/ux_refinements.yml` contains 90 unique acceptance targets (`UX001`–`UX090`); all 90 remain `acceptance_required` and none is `verified`. Work through the existing proof contract and record receipts there. A source change or a screenshot alone does not satisfy a row whose contract also requires unit, terminal, browser, visual or accessibility proof.

- [ ] **Input UX001–UX015:** Immediate acknowledgement; preserve an unsent draft; intentional multiline entry; bracketed-paste safety; stable input while streaming; duplicate-submit prevention; command-history navigation; searchable history; filesystem path completion; command completion; visible interaction mode; empty-input guard; Unicode editing safety; explicit end-of-input behaviour; recovery after command exception.
- [ ] **Terminal UX016–UX030:** Active target indicator; model/provider indicator; idle versus waiting distinction; truthful busy state; cancellation affordance; degraded-capability state; stable visual baseline; bounded status text; narrow-terminal layout; face never intercepts prompt authority; monochrome operability; no decorative banners; repository-context visibility; canonical prompt vocabulary; REPL versus system-shell distinction.
- [ ] **Diagnostics UX031–UX045:** Outcome-first diagnostics; standard status verbs; elapsed-time reporting; actionable failure recovery; FAILED versus INCONCLUSIVE; no duplicate summaries; stable event prefixes; output navigation; precise failure location; bounded diagnostic traces; meaningful exit codes; predictable piped output; secret redaction; run identifiers; intentional quiet mode.
- [ ] **Command help UX046–UX060:** Registry-generated completions; canonical command spellings; helpful unknown-command suggestions; explicit read/write boundary; target preview before mutation; normalized flags; dry-run semantics; clear usage errors; argument completion; copyable paths; machine-readable output schema; stdout/stderr ownership; useful command listing; risk-aware confirmation; conservative natural-language routing.
- [ ] **Browser recovery UX061–UX075:** Scroll follows only near bottom; draft survives disconnect; reconnect does not duplicate turns; explicit stream terminal state; mobile keyboard and safe area; honest stop semantics; visible keyboard focus; accessible icon labels; status without colour; reduced-motion behaviour; forced-colours behaviour; 320px reflow; preserve conversation text shape; usable touch targets; recoverable browser errors.
- [ ] **Visual accessibility UX076–UX090:** Consistent prompt baseline; predictable heading wrapping; long-identifier handling; tabular numerals; muted-text contrast; unclipped focus ring; remove repeated metadata; clear primary-action hierarchy; useful empty states; aligned field labels; contextual validation errors; stable loading layout; bounded animation duration; screenshot-comparison evidence; text zoom and font scaling.

The row-level owner trees, proof types and receipt requirements remain in `MASTER/data/ux_refinements.yml`; the contract is tested by `MASTER/test/test_ux_refinements_contract.rb`.

### 8.3 Product and platform gaps — preserve every unresolved ledger row

`MASTER/data/gaps.yml` has 51 rows: 14 picked, 32 open, 4 blocked and 1 satisfied. The satisfied Dating row is intentionally not repeated as work. A picked row needs its named convergence workstream completed and evidenced. An open row is a decision candidate, not permission to build. A blocked row stays blocked until its stated prerequisite exists. Every implementation remains subject to MASTER's laws and normal /fix gates.

**Brgen**
- [ ] `brgen_ai_feed_ranking` — picked; complete `brgen_feed_ranking_deterministic`: deterministic recency plus local-engagement decay, not an opaque model.
- [ ] `brgen_cold_start_feed` — open; consider a labelled follows-plus-city-popular feed so a new reader can see a living city.
- [ ] `brgen_creator_monetization` — open; depends on the one shared commerce domain.
- [ ] `brgen_activitypub_inbound` — open; remote media proxying, per-origin controls, blocklist and moderation must precede storage.
- [ ] `brgen_recurring_events` — open; decide whether a small recurrence materialiser is warranted; external ticket links remain a valid simpler boundary.
- [ ] `brgen_city_population_seeds` — open; use a checked-in public-data table for the 43 registry cities if the value is demonstrated.
- [ ] `brgen_recent_searches` — picked; complete `brgen_recent_searches`: server-side per-reader recents, with the last committed searches available across devices.

**Messenger**
- [ ] `messenger_webrtc_calls` — blocked; requires an operator-approved STUN/TURN service and host capacity.
- [ ] `messenger_notify_suppression` — open; decide how the active conversation suppresses redundant unread notifications without stale-tab claims.
- [ ] `messenger_business_crm` — open; consider a business inbox, labels and canned replies, with money features kept on the shared commerce domain.

**Marketplace**
- [ ] `marketplace_ai_recs` — open; prefer explainable co-view or category/price-band recommendations over a model without useful data.
- [ ] `marketplace_coupons` — open; one transparent campaign/credit ledger, not a second checkout accounting path.
- [ ] `marketplace_contact_relay` — blocked; requires inbound mail routing and expiring per-listing addresses on vm23.
- [ ] `marketplace_duplicates` — picked; complete `marketplace_duplicate_detection`: file a moderation report and leave the decision to a human.
- [ ] `marketplace_liquidity` — open; measure empty categories, saved-search demand and unmet supply before advertising.
- [ ] `marketplace_paid_boosts` — open; preserve quality-weighted organic discovery, clear sponsored labels and caps; payment never buys a trust outcome.
- [ ] `marketplace_seller_analytics` — open; derive seller/listing analytics from existing events where possible.

**Dating, Playlist and Takeaway**
- [ ] `dating_premium_boost` — open; any premium, boost or super-like design must preserve consent, avoid dark patterns and never sell moderation or safety outcomes.
- [ ] `playlist_creator_donations` — open; creator tips may use the shared commerce domain; do not sell an ad-free tier while there are no ads.
- [ ] `takeaway_delivery_area` — picked; complete `takeaway_delivery_area`: validate the reader's stored position against the restaurant's stated radius, nil-safely and with an honest explanation.
- [ ] `takeaway_cart_expiry` — picked; complete `takeaway_cart_expiry`: expire pending carts through the same state transition as manual cancellation, with notifications and a visible deadline.
- [ ] `takeaway_pro_surface` — open; promotion, loyalty and coupons depend on shared commerce and liquidity foundations.

**TV, Maps and shared commerce**
- [ ] `tv_live_stream_infra` — blocked; requires an explicitly chosen media server and delivery/transcoding tier; the existing broadcast state machine is not proof of live streaming.
- [ ] `maps_poi_substrate` — open; decide whether Places should become the stable shared POI service consumed by verticals.
- [ ] `commerce_shared_domain` — open; design one shared Commerce/Ledger/Campaign/Entitlements domain for all verticals, not separate billing stacks.
- [ ] `commerce_private_seller_verification` — open; determine a defensible, explainable proof for a private seller without an organisation number.
- [ ] `commerce_local_ads` — open; only after liquidity is measured and the shared campaign/ledger domain exists.

**Amber**
- [ ] `amber_fashion_embeddings` — open; start with owner-tagged typed attributes, not a Postgres/pgvector migration for a personal wardrobe.
- [ ] `amber_visual_similarity` — picked; complete `amber_similarity_right_sized`: explainable attribute matching and brute-force similarity at wardrobe scale.
- [ ] `amber_fitting_room` — open; keep garment-on-silhouette representation honest; do not imply body measurements or fit guarantees.
- [ ] `amber_mood_matcher` — open; use reader-declared tags or a colour-first alternative; never infer a reader's mood.
- [ ] `amber_event_outfit_planner` — open; consider outfits against an event the reader selects, with soft formality/season/recent-wear constraints.
- [ ] `amber_sustainable_resale` — open; release an item into the existing Marketplace rather than building a second resale surface.
- [ ] `amber_weather_suggestions` — blocked; no weather source is currently part of the suite; do not fabricate conditions.
- [ ] `amber_outfit_whole_score` — open; decide between explainable arithmetic and showing the combination without a score.
- [ ] `amber_trends_designers` — open; prefer dated, curated local-designer content over scraped global trend feeds.
- [ ] `amber_style_agents` — open; any MASTER integration must be advisory, read-only and attributed.

**BSDPorts**
- [ ] `bsdports_multi_parsers` — open; keep OpenBSD as production scope; other ports trees remain opt-in/on-demand and require an explicit need.
- [ ] `bsdports_semantic_search` — open; evaluate SQLite FTS synonyms first; a local corpus/similarity pass must justify its cost.
- [ ] `bsdports_knowledge_graph` — open; expose useful dependency and reverse-dependency questions from existing parsed data, not a new infrastructure graph.
- [ ] `bsdports_package_intel` — open; consider factual freshness/maintainer signals and a vulnerability source with reliable provenance.

**MASTER and STUDIO**
- [ ] `master_fleet_health` — picked; complete `master_fleet_panel`: sibling-app health, load and resource-guard order on the dashboard.
- [ ] `master_dead_payload_facts` — picked; complete `master_quota_facts`: show the already-computed model-quota and cache-efficiency facts.
- [ ] `master_pair_admin_surface` — open; add an authenticated operator surface for pairing issue/list/destroy only if its permission boundary is proven.
- [ ] `master_face_soothing` — picked; complete `master_face_breath` without adding colours or exceeding visual budgets.
- [ ] `master_voice_dsp_lanes` — picked; complete `master_voice_browser_dsp` so browser and terminal build the same declared voice presets, with honest unsupported-node behaviour.
- [ ] `master_voice_cooler` — picked; complete `master_voice_cooler_default` only after listening acceptance; operator taste remains the final gate.
- [ ] `dilla_grammar_beauty` — picked; complete `dilla_grammar_voicings` additively, keeping the existing Dilla generator's current renders stable.
- [ ] `dilla_corpus_depth` — picked; complete `dilla_corpus_measures` with sourced sample facts, measured timing and lineage; preserve unconfirmed attributions as unconfirmed.
- [ ] `free_model_lanes` — picked; complete `free_compute_design_of_record` with dated quota/source checks and explicit gates; do not wire provider lanes merely because a free tier is listed.

The complete candidate records and rejected alternatives live in `MASTER/data/ideations/*.yml`. Their `keep` verdict means a candidate survived adversarial critique; it is not blanket approval to implement. The 14 records are: `amber.yml`, `brgen.yml`, `bsdports.yml`, `creativity_lab.yml`, `dating.yml`, `maps.yml`, `marketplace.yml`, `master_surface_audit.yml`, `master_web_dilla_free.yml`, `master_web_face_voice.yml`, `messenger.yml`, `playlist.yml`, `takeaway.yml` and `tv.yml`. Consult the individual candidate and critique before selecting a direction. The Dating gap `dating_two_sided_ranked_for` is already marked satisfied in the gap ledger and is not open work.

### 8.4 MASTER convergence wishlist — 42 unfinished workstreams

`MASTER/convergence.yml` is the non-authoritative assistant wishlist and implementation/evidence map. It currently records 15 landed, 27 partial, 7 evidence-dependent and 8 missing workstreams (42 unresolved). These IDs are proof/ownership cross-links to the sections above, not permission to create duplicate implementations. Close each only when its named implementation and proof are real.

**Evidence-dependent — 7**
- [ ] `voice_local_first` — local-first speech ladder and real microphone proof.
- [ ] `face_semantic_motion` — large 3D face semantic motion in a real browser and on a device.
- [ ] `rails_product_completion` — production marketplace, authentication and media flows with staging credentials.
- [ ] `openbsd_appliance` — vm23 deployment, restore, DNS, TLS and resource proof.
- [ ] `dilla_music` — musical quality, authenticity and listening decisions.
- [ ] `recovery` — off-host backup and clean-host restore drill.
- [ ] `personal_companion` — resident voice-first phone companion on real Termux hardware.

**Partial — 27**
- [ ] `studio_provenance` — media provenance through every generation stage.
- [ ] `security_capability_graph` — capability ownership and least-privilege graph.
- [ ] `event_replay` — canonical event vocabulary, provenance and replay.
- [ ] `memory_governance` — durable memory provenance, review history, contradiction and forgetting.
- [ ] `task_scoped_prediction` — separate event-prediction streams across correlated tasks.
- [ ] `prediction_evaluation` — walk-forward comparison of contextual prediction against shared-stream and baseline models.
- [ ] `measured_repair_outcomes` — feed terminal /fix outcomes into the evidence-based self-model.
- [ ] `self_model_calibration` — measure capability outcomes and confidence calibration from explicit evidence.
- [ ] `cognition_measurement` — report workspace activity and saved-state restoration without consciousness claims.
- [ ] `task_outcome_learning` — per-target /fix outcome prediction from hashed receipts, scored before learning.
- [ ] `cognition_learning_benchmark` — prequential learning benchmark with no-learning ablation and constant baseline.
- [ ] `browser_proof` — rendered geometry, accessibility and performance evidence.
- [ ] `search_quality` — search relevance, explanations and a quality corpus.
- [ ] `moderation_governance` — moderation evidence, appeals and audit.
- [ ] `installation` — one-command host-aware installation and truthful doctor output.
- [ ] `structural_craft` — measured architectural collapse/relocation with proof.
- [ ] `unified_command_language` — one semantic command surface across CLI, web, voice and device.
- [ ] `media_effects` — Ruby-native analogue audio and image processing.
- [ ] `brgen_recent_searches` — server-side, cross-device recent searches.
- [ ] `marketplace_duplicate_detection` — duplicate listing creates a moderation report; a human decides.
- [ ] `takeaway_delivery_area` — stated delivery radius validated against the reader's stored position.
- [ ] `takeaway_cart_expiry` — pending carts expire through the manual-cancel transition.
- [ ] `master_face_breath` — stipple field breathes in brightness only and freezes under reduced motion.
- [ ] `master_voice_browser_dsp` — browser builds declared character presets in parity with terminal.
- [ ] `master_voice_cooler_default` — default voice room/doubler and optional presets; listening acceptance required.
- [ ] `dilla_corpus_measures` — sourced Dilla timing observations recorded without silently tuning generation.
- [ ] `free_compute_design_of_record` — dated free-compute landscape and verified quota assumptions.

**Missing — 8**
- [ ] `brgen_feed_ranking_deterministic` — deterministic recency-plus-engagement ranking in the existing Dating-style shape.
- [ ] `amber_similarity_right_sized` — wears-well-with from typed attributes and wardrobe-scale similarity.
- [ ] `master_fleet_panel` — dashboard renders sibling health, load and resource-guard order.
- [ ] `master_quota_facts` — status strip renders model-quota and cache-efficiency facts.
- [ ] `inconclusive_aging` — an INCONCLUSIVE finding that outlives its review window reopens as FAIL with its original receipt.
- [ ] `constitution_self_budget` — the laws file has an enforced line ceiling under the ratchet-down rule.
- [ ] `documentation_completeness` — public-contract changes carry documentation-review proof in the same task/commit.
- [ ] `ops_alert_channel` — heartbeat failures reach one operator-owned relay with an allowlisted endpoint and secret held outside the tree.

### 8.5 Operator-only and external evidence seams — 55 dependencies

These items require a real person, host console, device, registrar, provider credential, rights decision, material or listening judgement. They are included here so the root register exposes the full outstanding surface; the required evidence remains specified in `MASTER/data/operator_seams.yml`. Do not pretend to complete them from source inspection or simulation.

- [ ] **MASTER (17):** `android_consent_ux` (device); `android_termux_install` (device); `selfie_route_live` (provider); `browser_vision_end_to_end` (browser); `face_in_a_real_browser` (browser); `voice_by_ear` (ears); `worktree_delivery_against_github` (credential); `release_acceptance_on_an_idle_host` (idle host); `external_assessment_on_authorised_targets` (credential); `nmap_licence_boundary` (rights); `assessment_business_hypothesis` (material); `remote_branch_aliases` (credential); `assistant_calendar_or_mail_live` (credential); `messaging_channel_choice` (rights); `session_browser_post_policy` (rights); `advice_quality_human_review` (ears); `deepseek_findings_export` (material).
- [ ] **OPENBSD (15):** `shell_init_credential_rotation` (credential); `unregistered_domains` (registrar); `watched_all_target_deploy` (console); `deploy_failure_trap_window` (console); `second_offhost_backup_and_key_recovery` (console); `dnssec_ds_at_registrars` (registrar); `monitoring_and_crontab_on_vm23` (console); `two_consecutive_deploys` (console); `syspatch_in_a_console_window` (console); `full_check_after_deploy` (console); `privilege_migration_on_vm23` (console); `manual_pages_on_openbsd` (console); `prompt_parity_on_a_live_openbsd_shell` (console); `openbsd_native_suite` (console); `csp_enforced_on_vm23` (console).
- [ ] **RAILS (16):** `brgen_first_screen_in_chrome` (browser); `tenant_isolation_live` (browser); `messenger_journey_in_a_browser` (browser); `payments_in_provider_staging` (provider); `pwa_on_real_devices` (device); `city_registry_matches_dns_and_tls` (registrar); `journeys_in_all_three_apps` (browser); `amber_dashboard_geometry` (browser); `visual_identity_acceptance` (browser); `radio_whyp_tracks_imported` (console); `paid_plans_live` (credential); `checkout_steps_design` (material); `search_focus_shadow` (rights); `oauth_callbacks_live` (credential); `amber_outfits_on_the_real_catalogue` (material); `bsdports_lifecycle_on_openbsd` (console).
- [ ] **STUDIO (7):** `lora_source_refresh_and_paid_training` (provider); `private_media_and_history` (rights); `person_renders_and_duet_video` (material); `dilla_by_ear` (ears); `reference_workflow_with_a_real_link` (ears); `lora_route_end_to_end` (provider); `paid_media_cost_proof` (provider).

### 8.6 Aspirational horizons — visible, but not active by default

`RAILS/apps.horizon.yml` explicitly sets `agent_policy: ignore`. Its 47 planned rows are product horizons, not an unattended implementation queue. The gap IDs in §8.3 are the recorded candidate path; promote an additional horizon only after an explicit product decision, adversarial review, a named workstream and normal law-gated proof.

The broader horizons that need to remain visible are:

- [ ] **Messenger replacement threshold:** E2EE, delivered/read receipts, multi-device sessions and voice/video calls before claiming it can replace the operator circle's current messenger.
- [ ] **Takeaway consolidation:** decide whether food becomes a Marketplace vertical on the shared commerce rail; no parallel payment stack or migration without an explicit decision and rollback plan.
- [ ] **Marketplace catalogue scale:** shipping rates and labels, multi-currency, dispute/chargeback handling, catalogue-scale search and independently scalable heavy surfaces; bring the shelf, product page, buy box and checkout to one coherent standard.
- [ ] **Playlist creator surface:** creator uploads, reposts, waveform comments and discography-like profiles to support the SoundCloud/Whyp positioning; preserve import provenance and rights boundaries.
- [ ] **Shared commerce completion:** one ledger/campaign/entitlement source, seller credits, payment abstraction (refunds, invoices, VAT, reconciliation) and a revenue dashboard beyond the existing first slices; respect the liquidity-before-ads order.
- [ ] **Solidus/Dintero evaluation:** the planned Solidus core mount, starter storefront, native marketplace features, Dintero split checkout and Amazon feature-parity map remain staging/evaluation work. Do not replace native Marketplace flows or enable live checkout before provider staging, migrations, cutover and rollback are proved.
- [ ] **Amber media capabilities:** real garment matting/segmentation and richer try-on capabilities remain separate from the right-sized typed-attribute work; require real assets and a measurable consumer.
- [ ] **BSDPorts expansion:** FreeBSD/NetBSD parsers, semantic search and knowledge-graph ambitions remain subordinate to the OpenBSD-only production scope and a demonstrated reader need.
- [ ] **Own-domain horizon:** any planned domain/host work needs an actual zone, registrar decision, ACME configuration and host proof.

The authoritative feature/status detail is in `RAILS/apps.yml` and `RAILS/apps.horizon.yml`. Their planned rows are intentionally not to be confused with active implementation work.

### 8.7 Creativity experiments, decisions and refutations

`MASTER/data/ideations/creativity_lab.yml` records six experiments as implemented: `spark_cli`, `deploy_story`, `cities`, `domain_ghosts`, `tree_weight` and `law_weight`. Three remain deferred, not active: `city_pack_api` (no consumer/auth design), `semantic_canary` (no offline rubric/model budget) and `dilla_fixture_wav` (needs its STUDIO golden-hash pass).

`MASTER/data/proposals.yml` is the refutation ledger: 13 proposals landed, 17 refuted, none open. Preserve the rejected records and their reasons; do not re-propose them as fresh work without new evidence.

### 8.8 Runtime-generated wishlist — not present in the GitHub tree

MASTER's `Fix::Wishlist` reads/writes the local runtime ledger `.master/fix_wishlist.json`. That ignored runtime file is not present in the tracked GitHub tree, so its current suggestions could not be inspected or merged from GitHub.

- [ ] Export and review `MASTER/.master/fix_wishlist.json` from the live MASTER checkout; reconcile its still-valid entries against this root register and the convergence/gap IDs before claiming runtime-generated wishes are included.

### 8.9 Separate proposals that are not repository-wide backlogs

`STUDIO/docs/fetat/proposal.md` is a substantive policy/project proposal, not a software task queue. Keep its research, legal questions and implementation blueprint in that document; only promote a specific, authorised and scoped software task into this register. Do not explode the proposal into speculative checkboxes.

---

**Consolidation rule:** Root `TODO.md` is the only cross-tree Markdown action list. `RAILS/refinements.yml`, `MASTER/data/ux_refinements.yml`, `MASTER/data/gaps.yml`, `MASTER/convergence.yml`, `MASTER/data/operator_seams.yml`, `MASTER/data/proposals.yml`, the ideation sheets and the RAILS feature inventories remain structured owners for IDs, proof receipts, provenance, accepted/rejected reasoning and state. Update the owner and this root index together when an item is implemented or its state changes. Do not create another backlog file.


## model pool — free compute and never-modelless (researched 2026-11-06)

Research against openclaw.ai (394k stars, MIT) and the free-tier landscape
surfaced verified additions for MASTER's lanes. Verified live same-day: Kilo
gateway (https://api.kilo.ai/api/gateway, model openrouter/free, keyless) and
OVHcloud AI Endpoints (https://oai.endpoints.kepler.ai.cloud.ovh.net/v1,
keyless, 2 RPM per IP per model, 20+ models). GitHub Models retired 2026-07-30;
Gemini free tier hides its numbers; Hugging Face free monthly credits are gone.

- [x] Register Kilo and OVHcloud as keyless lanes beside llm7 in `data/models.yml`, with llm7's keyless_max_concurrency pattern and a per-row verified-on date. (bb188de11c)
- [ ] Read OpenRouter's remaining free quota from `GET /api/v1/key` (`free_model_daily_requests`) into `Io::ModelQuota` instead of forecasting the burn rate.
- [ ] Adopt openclaw's cooldown contract in `Io::LaneQuota`: parse `Retry-After` headers as exact cooldown, ladder everything else 30s-1m-5m with reset, disable auth-failed profiles about ten minutes, and cap stated waits at 60s before falling through.
- [x] Spread free-load selection across every live `:free` model slug from `/api/v1/models`, ranked by `free_latency`, with per-model quota buckets, instead of the single default slug. (verified built 2026-11-06: use_live_catalog merges up to 40 live slugs — 12 free rows in the snapshot, plus kilo's own slugs since bb188de11c — with per-model daily buckets in Io::ModelQuota; residual: no latency field exists in the catalog, so ranking stays pool order)
- [ ] Split lane deadlines into a connect/handshake budget (dead handshake trips the circuit breaker) and a read-idle budget (a stream that keeps delivering is never cut).
- [ ] Flip Ollama Tier-D to probe-on warm: periodic one-token probe on `gemma3:4b` recorded into quota state, 2-4K context cap and `OLLAMA_KV_CACHE_TYPE=q8_0` for this 8 GB Mac, rehearsed as the final fallback-chain link.
- [x] Keep a verified free-provider ledger row per provider (limit, models, keyless?, verified-on) so every free-tier fact carries its own staleness signal. (bb188de11c + models.yml annotations: llm7 re-verified 2026-11-06, key-gated providers marked recorded-2026-09 not re-verified)

## simplicity-book laws (candidate batch, researched 2026-11-06)

laws.yml already cites Rams, Strunk & White and NN/g. The uncited,
machine-checkable simplicity canon yields a deterministic first batch; the
rendered or task-evidence canon waits for the screenshot workflow.

- [ ] MAEDA_THE_ONE: one primary action per surface — the check counts primary CTAs on a card or form and fails a second.
- [ ] TUFTE_DATA_INK_RATIO: erase non-data ink — decoration-to-content ink measured in CSS decoration rules and chart ink versus data ink.
- [ ] GESTALT_PROXIMITY: grouping distance must be smaller than separation distance on a rendered surface (screenshot geometry pairs with the layout-refinement workflow).
