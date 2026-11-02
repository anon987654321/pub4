# pub4 outstanding work

The one cross-tree backlog: work an agent in this checkout can do. Work that
needs the operator, a device, a credential, a paid call, ears or a console on
vm23 is a seam in `MASTER/data/operator_seams.yml`. Refusals live under
"Refused, and why" in `MASTER/AGENTS.md`. An item closes by being deleted in
the commit that carries its evidence; nothing here records finished work.

## Open from the 2026-11-02 session — external tree audit (MASTER)

An external pass ran the full suite on Linux (Ruby 4.0.9, no browser, no
operator state) and landed the mechanical fixes in the same commit as this
section. The three clusters below are what an agent cannot close alone, plus
one measurement nobody has taken on a non-macOS host.

- [ ] **Verify the Soul-owned authority and absolute-policy migration on the pinned toolchain.**
  `soul.yml#authority_order`, `absolute.sacred_paths` and
  `absolute.anti_simulation.forbidden` are now declared and validated.
  `Master::Soul`, `ConfigurationGuard`, `Core::Constitution::Paths`,
  `FlatLawCatalogue`, PromptFilter, the agent context and receipt readers
  have been aligned; focused regressions are present. The GitHub editing pass
  did not execute them. Run the Soul, configuration-guard, core-path,
  PromptFilter/agent and registry tests on the pinned Ruby toolchain, then
  run the MASTER suite. Keep the outcome NOT_RUN until commands produce actual
  output; do not infer success from source changes.
- [ ] **Measure the suite on Linux and triage the environment-skewed
  failures.** ~85 test files fail here for machine reasons, not tree
  reasons: no headless Chrome (`TestCdpSessionHistory`, browser suites),
  `/tmp`-trust hooks refusals (`ToolHooksTest`), `NO_COLOR`/truecolor
  terminal contracts (`TraceDmesgTest`, `TestCliTerminalFace`), sandboxed
  fork/pty limits (`TestFixKernelLifecycle#test_execution_lock_serializes_independent_processes`,
  `TestCliReplExit`), and missing operator state. The method that separates
  them from real defects: rerun each failing file alone with
  `bundle exec ruby -Ilib:test <loader> <file>` and compare against the
  parallel shard run. Files that fail both ways and are not in the clusters
  above still need a per-file disposition (~90 at audit time).
- [ ] **Explain the ratchet run's shape on Linux.**
  `TestRatchets#test_no_ratchet_is_over_its_ceiling` measured 300 s here —
  its own deadline — where the helper comment promises about a minute across
  the corpus. Either the host is that much slower or a ratchet walks
  something it should not; the run's per-ratchet durations say which.
- [ ] **Finish the retired-tool surface.** The postpro/lora trees are gone
  and the compatibility contracts now match (`MASTER/tools` symlinks,
  `ScriptDispatch`, cohesion roots, doc baselines), but `Io::LoraIntent` and
  `Io::MediaIntent` still call `ScriptDispatch.run(tool: "lora"/"postpro")`
  and degrade into missing-entrypoint errors at request time. Decide the
  intent layer's fate with the `STUDIO/postpro` / `STUDIO/replicate`
  archaeology item below rather than widening dispatch again.

## Open from the 2026-11-01 session — repository flattening

Initial recursive Git tree at `496cfb32497bcedb4de6a98bc452d030e82d886b`
contained 5,597 files and 719 directories. After the STUDIO and RAILS batches,
the pinned source tree at `88bbd45bb2ede7a10d768c101c796ec786e15f70`
contains 5,593 files and 718 directories: MASTER 2,210/125, RAILS
3,085/556, OPENBSD 281/29, STUDIO 3/2. RAILS has 379 files at depth 7
or greater and 102 at depth 8 or greater; maximum path depth is 9. The four
removed files comprise one duplicate STUDIO implementation and three duplicate
Turbo Stream templates. Measurements are structural signals, not proof that a
directory or namespace is unnecessary. Refresh them at the start and end of
each batch; compare pinned revisions only.

### Decisions landed

- [x] RAILS shared namespaces — **RETAIN**. The repeated `shared` segment
  expresses the `Shared` Ruby namespace and Rails view lookup contract across
  controllers/concerns, models/concerns, helpers, services, channels, reflexes
  and views. The shared engine README describes these as one engine-owned
  surface; flattening the segment would change constants or partial names, not
  remove accidental structure. Keep true service subdomains such as
  `discovery/` and `link_embed/`.

- [x] RAILS service namespaces — **RETAIN**. `Marketplace::Payments`,
  `Fediverse`, `Marketplace` and `Dating` are real constant and ownership
  boundaries. Payment providers, federation delivery, marketplace services and
  dating matchmaking do not become clearer or safer by moving their files to
  a generic `services/` root or across engine boundaries.

- [x] Takeaway boundary — **RETAIN as a nested isolated engine**. It has
  `Takeaway::Engine`, `isolate_namespace Takeaway`, its own routes,
  controllers, models, views and locale files, and an explicit
  `takeaway_` table contract. Brgen mounts the same engine at Marketplace
  `/food` and on the legacy Takeaway host. The nested location reflects that
  ownership; moving it to a sibling app would contradict the product topology
  and compatibility mount.

- [x] RAILS cross-app implementation duplication — keep the existing
  extraction boundary. `RAILS/test/app_duplication_test.rb` compares shared
  relative paths across Amber, Brgen and BSDPorts and fails when identical
  implementation exceeds its 12-line compatibility budget. Bare-name
  controller/Reflex host constants remain thin adapters; shared behavior lives
  in `__shared`. The shared-engine historical migrations are deliberately
  inert: `Shared::Engine` does not add a migration path, and
  `engine_migration_convention_test.rb` freezes the three historical files
  while requiring live migrations in each app. Do not flatten app-specific
  schemas or migration histories.

- [x] STUDIO duplicate IdeaPicture implementation — **DELETE** landed.
  Removed unused `STUDIO/generators/idea_picture.rb`; the only entrypoint,
  `STUDIO/photograph.rb`, and `STUDIO/test/idea_picture_test.rb` load
  `STUDIO/photograph/idea_picture.rb`. The removed file had the exact same
  Git blob and no tracked caller was found. The `generators/` directory
  disappeared with it. A regression test now asserts that the photograph
  implementation exists and the duplicate generator path stays absent; that
  test is committed but NOT_RUN in this GitHub editing pass.
  Commit: `2fe2701ec268ed94b04c2f1602853a3657872db1` (delete) followed by
  `9a5c884de24857effebe44f9686da6592453bf29` (test).
- [x] Duplicate Turbo Stream responses — **MERGE** landed. Three alternate
  action templates were byte-identical to their paired action template:
  Amber `follows/destroy` now renders `:create` after deleting the Follow;
  Amber `planned_outfits/destroy` runs `load_planner` then renders
  `:create`; BSDPorts `ports#unwatch` renders `:watch` after setting
  `@watching = false`. Deleted the three redundant templates without
  changing URLs, response MIME types or the post-mutation state rendered.
  Added request regressions for follow/unfollow, planner removal and
  watch/unwatch. A structural assertion in
  `RAILS/test/app_duplication_test.rb` also prevents the retired templates
  from reappearing without explicit canonical reuse. Functional and static
  regressions are committed but NOT_RUN in this GitHub editing pass. The
  controller edits, removals and functional tests were committed through
  `2b660c5c080f5ecff2eae0ec15b2257269561a73`; the structural ratchet followed
  in `88bbd45bb2ede7a10d768c101c796ec786e15f70`.

### Remaining work

- [ ] Complete the semantic flattening census before moving more code. For
  every candidate record current path, owning application/engine, Ruby
  constant or asset/view identity, all callers/references, autoload/eager-load
  behavior, routes, migrations, serialization/public API effects, test
  coverage, compatibility requirements, proposed destination and rollback
  plan. Classify each as MERGE, MOVE, RENAME, INLINE, DELETE, RETAIN or
  INVESTIGATE. Never infer redundancy from path depth or repeated words alone.

- [ ] MASTER /fix: map every production caller and state owner across
  `MASTER/lib/fix/fix_loop/`, `MASTER/lib/fix/fix_loop/pass_runner/`,
  `MASTER/lib/fix/repair_loop/`, `MASTER/lib/fix/scan/`, and the existing
  `Fix::Kernel` implementation. The current tree has separate files for
  pass execution, pass runner, builder, lifecycle, completion, committer,
  background runner, convergence configuration, repo scope, council round,
  stream cursor, file collector, and repair policies. Consolidate only
  demonstrably duplicate orchestration; retain distinct transaction,
  verification, recovery, budget, evidence and terminal-outcome
  responsibilities. Compatibility constants remain until caller and
  receipt-parity tests prove they can be retired. Run focused
  interruption/recovery tests before and after.

- [ ] MASTER artifact-preservation enforcement: validated task contracts now
  enter operator-facing /fix via --intent, bound the resolved repository-relative
  scope in FixPlan and Transaction, and produce before/after SHA-256 receipts
  linked to the FixPlan digest in the persisted assessment artifact. RepairAdapter
  now invokes the HTML/ERB source verifier before accepting a candidate; a failed
  or inconclusive supported-format check vetoes the write. Full required-dimension
  proof remains open: source-level PASS is still reported INCONCLUSIVE until
  rendered, runtime and accessibility evidence is complete.

- [ ] MASTER artifact-format coverage: add format-aware preservation and
  rendered-output comparison for DOCX, PDF, XLSX and PPTX. Changed files without
  a registered verifier must remain INCONCLUSIVE; do not treat archive-byte
  equality or successful parsing as visual preservation.

- [ ] MASTER golden preservation campaign: add real baseline/candidate fixtures
  spanning HTML, Ruby source, Rails pages and interactions, legal/long-form
  documents, spreadsheets and slide decks. Prove the requested preservation
  dimensions per format and keep tests that demonstrate intentional change as
  well as regressions. Do not claim broad artifact preservation from the HTML
  fixtures alone.

- [ ] MASTER scanner/check boundaries: trace production call graphs across
  `MASTER/lib/review/scan/`, `MASTER/lib/fix/scan/`, `MASTER/checks/`
  and `MASTER/checks/support/`. Keep the three distinct concepts explicit:
  Law (requirement), detector/check (measurement instrument), evidence
  (observed result). Unify duplicate finding schemas, registries or dispatch
  only where callers and cache invalidation semantics match. A Law/catalogue
  change must invalidate affected cached findings.

- [ ] MASTER nested modules: inspect
  `MASTER/lib/cli/face/ascii/`,
  `MASTER/lib/cli/pipeline/proof/`,
  `MASTER/lib/cli/routing/model_router/`,
  `MASTER/lib/fix/scan/ast_fixer/` and
  `MASTER/lib/review/council/critique/`. Establish whether each nesting
  level represents a stable public namespace or only file grouping. Preserve
  the single face renderer, model-routing authority, AST transformation
  coverage, proof semantics and council behavior. No blind directory moves.

- [ ] RAILS view/asset/test organization: inspect mailer templates currently
  under `RAILS/__shared/app/views/shared/passwordless_mailer/` and
  `verification_mailer/`, shared icon partials under
  `app/views/shared/icons/`, repeated product asset/token imports, and
  duplicate test support under `RAILS/__shared/test/`, `RAILS/test/` and
  app-local test trees. In particular, `_messages.html.erb` and
  `_reply.html.erb` currently contain the same SVG path; determine whether
  that is intentional reuse or an incorrect icon only after rendered review.
  Preserve Rails lookup contracts and each product's visual identity. Share
  foundations, not product compositions.

- [ ] Residual exact-blob audit: a post-dedup scan still finds 46 duplicate
  content groups across the repository. This is an investigation set, not a
  deletion list. It includes per-app Ruby/version pins, boot/config files,
  migration and test files that must remain at app-local paths, framework
  entrypoint/constant shims, and repeated assets/licence text. The Amber and
  Brgen `DraftsController` pair is already a thin adapter over
  `Shared::DraftsActions`; `Session` and `Current` are similarly tiny
  host-level class declarations, not worth adding another shared abstraction
  for. Keep the `_messages` / `_reply` icon SVG collision open until a
  rendered visual review establishes whether the same glyph is intentional.
  Do not perform hash-only deletion.

- [ ] OPENBSD: inspect `OPENBSD/bin/`, `OPENBSD/lib/`,
  `OPENBSD/checks/` and source-layout mirrors `OPENBSD/etc/`, `home/`,
  `usr/`, `var/`, `dev/`. Distinguish repository source organization
  from the target host filesystem contract. Consolidate duplicate
  deployment/backup/verification wrappers only after host-path, privilege,
  rollback and evidence behavior is proven. Never flatten required target
  filesystem paths.

- [ ] STUDIO audio pipeline: preserve its already-small tree. Keep one Dilla
  generation entrypoint and one audio processing pipeline; do not introduce a
  second visualizer, audio engine or generator. Reassess only after the
  `radio_brgen_tunnel.js` audio/visual split has a tested ownership boundary.

- [x] Root governance and agent instructions: the generator now has one source
  in `MASTER/AGENTS.md`, emits only `AGENTS.md`, `GEMINI.md`, `GLM.md`
  and `.cursorlaws`, and does not recreate `.github/`. Copilot reads root
  `AGENTS.md`; Claude's native settings path is a root symlink into
  `STUDIO/agent-guidance/claude/`. The four-directory root contract is enforced.
- [ ] Verify from a local Claude Code session on macOS that project hooks load
  through the `.claude` symlink; this session could verify the Git tree and
  link target but could not launch Claude Code. Root `TODO.md` remains the
  single actionable backlog.

- [ ] FULL.yml retirement: reconcile every remaining item against
  `MASTER/data/recovery/full_yml_assessment.yml` and current implementation;
  adopt only unique, still-valid material with provenance, then delete
  `FULL.yml` in the same commit that proves no required material is lost.
  Preserve source archives/history as appropriate.

- [ ] Cross-tree duplication graph: detect repeated decision logic,
  configuration defaults, status/error vocabularies, adapters, serializers,
  wrappers, registries, generated artifacts, test fixtures and documentation.
  For each duplicate distinguish identical behavior from superficially
  similar behavior with different security, transaction, tenant, product or
  runtime contracts. Consolidate the authority, not merely the syntax.

- [ ] Add or extend structural ratchets for file count, directory count,
  maximum path depth, single-child directories, repeated namespace segments,
  dependency fan-out/cycles, public API changes and duplicate implementation
  fingerprints. Ratchets must be measured from a pinned revision and must not
  encourage deleting meaningful boundaries or merging unrelated code.

- [ ] Execute verification after each bounded batch: focused tests, relevant
  app/engine tests, autoload/eager-load checks, route/view rendering, asset
  builds, law/check parity and full suites where available. Capture exact
  commands, revision, output, exit status and evidence paths. Run
  before/after structural metrics and compare behavior. Keep unrun checks
  NOT_RUN and unknown behavior INCONCLUSIVE; do not claim a code flattening
  is complete from a tree-only audit.

- [x] Replace the obsolete whole-tree read gate with scoped source review. The operator authorizes bounded implementation when the root and MASTER agent contracts, applicable Law records, target sources, direct callers, focused tests and task contract have been read. Record unreviewed adjacent surfaces as INCONCLUSIVE; do not remove compatibility APIs or change constitutional authority without specific evidence. This narrows the reading scope, not the preservation, Law, safety or verification requirements.

## Open from the 2026-11-01 session — Baymard UX audit

- [ ] Add exact, case-specific runtime adapters for the 392 currently unmapped
  entries in `RAILS/test/interaction_campaign_400.json`. The premerge gate
  now runs all 400 rows and reports unmapped rows as SKIPPED/BLOCKED; it must
  remain non-green until each applicable action/fault pair has a genuine
  isolated test and saved evidence. Do not generate generic tests that merely
  assert a nearby page loads, or relabel source expectations as runtime passes.
- [ ] Run `ruby MASTER/tools/rails/premerge.rb --interactions` after adapter
  work and retain the exact ledger, command, revision and exit status. The
  current checked-in inventory remains 8 mapped adapters and 392 unmapped;
  that campaign has not been executed in this editing session.
- [ ] Extend the new computed accessibility-tree check from its bounded sample
  to the full declared surface inventory only after measuring runtime and
  resource cost. It checks accessible names in Chrome's computed AX tree; it
  is not a substitute for real VoiceOver/NVDA sessions or announcement testing.
- [ ] Keep actual participant usability sessions, human screen-reader testing
  and controlled conversion experiments as separate operator evidence. The
  automated `/fix` pipeline can validate supplied, anonymised records; it
  cannot recruit participants, observe human behaviour or manufacture results.
- [ ] Execute the new Ruby contract tests and full verification on the pinned
  Ruby runtime with all required app servers and Chrome/Chromium available.
  The GitHub source edits in this session were not run locally; the reported
  Vercel status is failed with a build-rate-limit URL, not a successful build.


- [ ] Execute the new Baymard regression suite on pinned Ruby 4.0.5:
  from the repository root run
  `cd MASTER && bundle exec ruby -Ilib:test test/test_baymard_law.rb`.
  Preserve the actual output and exit status. Then run
  `rake -f MASTER/Rakefile ux:baymard` and review the complete report for
  every declared RAILS app and shared engine. The 21 regression methods are
  committed but were not executed in the GitHub editing pass. Fix confirmed
  defects; do not suppress findings merely to obtain a green report, and keep
  framework-generated or otherwise unmeasurable cases INCONCLUSIVE.

- [ ] Resolve rendered-review gaps using the existing browser/CDP and
  accessibility instruments, not a second browser framework. Inspect actual
  rendered controls and accessibility trees wherever source checks cannot
  resolve Rails/Haml/Slim helpers or partial composition: control names,
  informative/decorative image alternatives, button/link names, native
  keyboard semantics, focus visibility and viewport behavior. Record the
  app, surface, viewport, observed result and a repository-relative
  `rendered_review=<path>` evidence reference. Source markup alone is not
  proof of the rendered experience.

- [ ] Collect privacy-reviewed task evidence for each applicable app and
  feature: `first_screen_purpose`, `navigation_findability`,
  `search_recovery`, `product_evaluation`, `cart_editing_and_costs`,
  `checkout_guest_and_recovery`, `mobile_task_completion`, and
  `keyboard_and_assistive_technology`. Use a permitted method
  (`moderated_user_test`, `expert_walkthrough`, `browser_task` or
  `screen_reader_review`), a positive participant count, anonymised
  aggregate observations, and repository-local artifacts with verified
  SHA-256 digests. Manually review/redact every artifact: do not store names,
  contact details, identifiers or raw audio/video; image evidence requires
  the explicit human `redacted: true` attestation. The text scanner is only
  a guardrail, not a complete privacy detector. Populate
  `MASTER/.master/baymard/evidence.yml`, then rerun
  `BAYMARD_STRICT=1 BAYMARD_EVIDENCE=MASTER/.master/baymard/evidence.yml ruby MASTER/checks/runner.rb baymard_ux`.
  Keep unobserved tasks INCONCLUSIVE; do not imply an official Baymard score,
  certification or affiliation.

## Open from the 2026-10-31 session

- MASTER browser: submit forms for an operator-approved host. The operator chose
  "approve per site, then free" (2026-11-01); `Io::WebBrowse` forwards only GET/HEAD,
  so add same-host POST with the session cookies, once-per-site-per-task approval,
  and a test against a real login form. Blocked on the session_browser_post_policy seam.
- whyp.it slug links (`/tracks/radio-bergen-1-…`) carry no numeric id, so
  `Playlist::Track#whyp_embed_url` returns nil for them; resolve the id.
- Run under Ruby 4.0.5 the app tests written but NOT_RUN: billing core
  (`stripe_billing_test`), law API (`api_key_test`, `api_lint_controller_test`),
  dating identity gate and splash, `radio_bergen_manifest_test`, `track_import_test`.
- `test_core_bridge` `test_lifecycle_events_persist_without_a_host_bus` fails at
  HEAD (expected "reversible", got nil).
- `MASTER/bin/operator measure` did not finish in 500s here; re-read the ratchets
  (law trace debt after SPONSORED_LINK_REL).
- Remaining FULL.yml adopts (see `MASTER/data/recovery/full_yml_assessment.yml`), then
  delete FULL.yml.
- Marketplace: active-filter chips with clear on the results; trim tile badges to one
  delivery line. Takeaway menu categories and restaurant cover photos need a schema
  column each.
- [x] Split the 1,269-line `radio_brgen_tunnel.js` into a 216-line
  coordinator, `radio_brgen_audio.js` and `radio_brgen_visual.js`. Importmap
  pins and module-boundary regression tests are in place; Node/browser execution
  remains NOT_RUN in this GitHub-only pass.

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

## Session note 2026-10-31 (historical recovery)

- Reconciled selected Library archives, the available `1_BACKUP.LOG` session log,
  `master_FULL.yml`, older recovery notes and the current GitHub tree. Pushed
  the Radio queue-order fix, importer tenant guard, corrected Law-parity wording,
  and explicit legacy app/visualizer dispositions in the preceding commits.
- Historical searches found already-absorbed work: shared RAILS cascade/auth test
  examples, MASTER quota/model-skip routing, per-language voice policy, FaceState
  stipple dial modulation, Dilla progression/patch rotation and the canonical
  Radio tunnel. Do not recreate parallel renderers, ad engines, Law registries or
  generators to satisfy stale snapshots.
- This is not an account-wide ChatGPT audit. The available recovery bundle states
  that not every ChatGPT conversation from account inception was available. The
  unresolved source/export boundary is listed below; no claim that every old chat
  was read is made.
- The older request for a floating footer transport is already implemented by the
  Playlist engine's `_transport_bar.html.erb` and `.playlist-transport-bar` CSS:
  play/pause/previous/stop/next/volume, floating rounded geometry, safe-area offset,
  nav autohide and reduced-motion handling. No duplicate implementation is needed.
- The TTS lip-sync implementation is already present: `face_speech_playback.js`
  schedules viseme plans against their audio clock, with `viseme_plan.test.mjs` and
  `performance_timeline.test.mjs` coverage. Audible latency/quality on the target
  device remains a separate runtime check.
- The current language policy (English Christopher; Norwegian Pernille/Finn; Malay
  Yasmin/Osman) supersedes the earlier request to rotate all voices indiscriminately.
  Preserve the per-language routing; do not regress into cross-language voice rotation.
- The requested Brgen responsive screenshot set is already present in Git: mobile and
  desktop pairs for Brgen, Dating, Maps, Marketplace, Messenger, Radio, TV and MASTER,
  plus Amber and BSDPorts. This is a current-tree asset inventory, not a fresh runtime
  capture from this recovery pass.
- Full Ruby 4.0.5/Rails/MASTER/STUDIO suites, live GPU/browser captures, local TTS
  renders and vm23 checks were not run through the GitHub editing surface. No
  production deployment or media import is claimed.

## Carried-forward requests from earlier sessions

- [ ] **Complete AI3 archive archaeology:** the bounded findings and no-port decision are recorded in [`STUDIO/docs/ai3_legacy_audit_2026-10-28.md`](STUDIO/docs/ai3_legacy_audit_2026-10-28.md). The visible AI3 tree and extracted reports were inspected, but the historical archive blobs were not all extracted; preserve this item as open until that source recovery is actually completed. No AI3 feature claim counts as working behavior without implementation and runtime evidence.

These requests were visible in prior conversations or handoffs but lacked an explicit,
actionable root-backlog item. Keep them open until the relevant evidence exists.

- [ ] **Account-wide ChatGPT transcript coverage:** the present pass used the available
  Library materials, `1_BACKUP.LOG`, `master_FULL.yml` and selected handoffs, not a
  complete account export. The recovery bundle itself says not every ChatGPT conversation
  from account inception was available. Complete the semantic sweep against a supplied
  official ChatGPT export, preserve timestamps/source IDs and deduplicate repeated
  handoffs; do not claim "all chats audited" until that source is available and indexed.
- [ ] **Avatar-derived FaceWorld geometry:** an older direct request says to base the
  particle face on `new_avatar.png` and proceed. The high-resolution mask poster is
  recoverable from Git history (`MASTER/loop_poster.png` at `0b0227a7e6f0`), but
  current `RAILS/master/public/face_avatar.png` is only 96×96 and is merely named in
  the asset manifest. Current `face_world.js` builds its head with procedural
  `SphereGeometry` and shader deformation; `face_stipple_system.js` samples that
  existing point geometry. No avatar-image-to-geometry path was found. Derive
  deterministic point positions from the recovered reference inside the existing
  single FaceWorld/FaceState renderer, retaining its fallback, point budgets and
  reduced-motion contract; add source regressions and browser/GPU evidence at narrow
  and wide sizes. Do not add a second renderer.
- [ ] **Radio-to-Face inward warp:** the old request explicitly says to reimplement the
  Radio tunnel's inward pull in the existing face particle shader, audio-modulated and
  stronger on the beat, rather than placing a second canvas over the face. The current
  `chat_actions.js` emits `music:radio` with `topology: "warp-tunnel"`, but
  `MASTER/data/tokens.yml` has no `warp-tunnel` profile; `face_world.js` falls back
  to `papua-mask` and has no radio-mode inward-force path. Preserve one renderer and
  its reduced-motion/performance limits. Add deterministic shader/geometry regressions
  and confirm live motion in a real browser with audio before calling it complete.
- [ ] **Radio visualizer transitions and shared aesthetic:** the old direct request
  was to rotate between the existing waveform and tunnel visualizers on track change,
  with a fade/mixed-flow transition, and keep the face and playlist visuals in one
  coherent design language. The footer transport request is already implemented:
  `_transport_bar.html.erb` renders play/pause/skip, while
  `.playlist-transport-bar` floats above the footer as a rounded rectangle and
  respects safe-area insets and reduced motion. Do not redo that bar or revive the
  deprecated standalone seven-mode visualizer. Implement and test only the two current
  visualizers' track-driven transition and confirm the shared style, reduced motion,
  and rendered mobile/desktop behavior before closing.
- [ ] **Norwegian MASTER README:** the earlier explicit request for a complete
  `MASTER.norwegian.md` translation is not represented in the current tree (no
  Norwegian counterpart exists). After reviewing the canonical README, its links and the language policy, translate
  the canonical README without changing technical meaning, keep links/commands/code
  identical, and add a parity check so material English README sections cannot silently
  disappear from the Norwegian edition.
- [ ] **MASTER README narrated face preview:** older requests include an inline
  face-speaking preview, mobile `README_ss.webp` and Norwegian counterpart,
  a full-README TTS narration, and a real SSH/`bin/master` dmesg transcript.
  None of those image assets or a captured terminal-session transcript is present
  in the current README/tree. The `MASTER/tools/readme_take.rb` generator exists
  and can produce `README.wav`, `loop.mp4` and `loop.gif`; it requires the
  pinned local Ruby, a running face server, the TTS worker and FFmpeg, and defaults
  to highlights unless `--full` is passed. Run and inspect a fresh `--full` take
  on the supported host, produce the desktop/mobile and Norwegian previews, and
  capture only actual command output (no invented dmesg). Publish the GIF/MP4 and
  screenshots according to the generated-media policy. Do not re-track the ignored
  MP4/WAV without a separate storage decision.
- [ ] **Dilla local sample-flip interface — implementation landed; validation open:**
  the bounded local-file path is now in `STUDIO/dilla/dilla.rb`: `SAMPLE_LOOP`,
  `SAMPLE_LOOP_VOL`, `SAMPLE_LOOP_WEIGHT`, plus CLI controls for volume, weight
  and slice count. It decodes at most 24 seconds through local FFmpeg, estimates
  slice pitch classes, selects chord-aware chops deterministically, and mixes
  before the render's final tape/master stage. Three regression tests and the
  operating instructions are committed. Still run `STUDIO/test/dilla_test.rb`
  under pinned Ruby 4.0.5, review an actual cleared local source by ear, and verify
  the 0.42 level leaves voice room before marking complete. The source audio must
  remain operator-supplied and rights-cleared; do not restore remote YouTube
  acquisition, `demo.mp3`, or other deleted generated renders. Progression and
  patch rotation already exist in the shuffle-bag/showcase system; do not duplicate
  them.
- [ ] **Dilla README visual hero:** an older direct request asks for inline
  GIF/MP4 media. `STUDIO/dilla/README.md` currently documents offline MP4
  generation but contains no inline hero or linked render. Generate a fresh
  showcase on the audio/video-capable host, review the sound and picture, and
  choose a stable GIF or hosted video reference without committing arbitrary
  large generated renders.

- [ ] **`STUDIO/postpro` / `STUDIO/replicate` archaeology:** trace commits, branches,
  unreachable/history-recoverable objects and historical wording across pub4, pub3,
  pub2 and pub. Restore only grounded, unique logic, ideas, contracts and tests into
  current owners; preserve provenance and do not reintroduce a deleted tree wholesale.
- [ ] **Unlanded `MASTER/plugins/mov/` proposal:** an archived integration bundle exists, but it is not the current `MASTER/lib/io/mov.rb` adapter. The archived engine selects modern streaming-catalog titles but acquires releases through Torrentio, apibay/TPB, YTS and EZTV with `aria2c` magnet downloads; no licensing/provenance gate is demonstrated. Do not merge or run that acquisition path. After reviewing the adapter, provider contracts, licensing and applicable Laws, decide whether a safe plugin limited to lawful public-domain downloads and/or provider availability links is still wanted. The bundle is based on an old commit and its engine defaults to US while its README claims Norway; any plugin policy registration remains a human-owned change to sacred `MASTER/data/laws.yml`.
- [ ] **Oct. 26 hardening review:** reconcile every P01–P11 follow-up and the outstanding
  findings in `MASTER/docs/history/fix-review-log.md`. Explicitly
  verify SILENT_RESCUE freshness, INTER_MODEL_CONTRACT heredoc/keyword sites, the
  declarative/runtime self-test parity, headless registry failures and strict-error
  policy; resource bounds/log append cache; DesignRun transaction and recovery semantics,
  abort/stall outcomes, undo pruning and silent rescues; provider-health recovery windows,
  Replicate auth/SSRF/timeouts, retry jitter, process-group termination, redaction and
  Gemini key transport; boot/loop claims, device/pairing/wake-word edges and CDP budgets;
  tool-hook fail-open, MCP SSRF/package pinning, environment-file permissions, scoped
  kills, and RAILS token timing/CSRF/ingress rate limiting. Classify each finding with a
  test or evidence reference; don't infer closure from a source edit.
- [ ] **Law parity and visual enforcement:** run `rake lint:law_parity` on the pinned
  Ruby toolchain and preserve its actual output. The `RENDERED_VALUES` Law now has an
  executable semantic definition and active enforcement metadata; commit `455fa84`
  also corrected the old visual-custody/campaign identifiers to real catalogue Law IDs
  and updated their focused regressions. Do not describe that old mapping defect as an
  outstanding parity gap. The proposed `AD_VISUAL_QUALITY_MUST_BE_GORGEOUS` ID is not
  in the Law catalogue: the existing ad contract is `Master::Visual::AdAudit` (six
  scoped checks), the token-owned `ad_visual_contract`, and the RAILS ad-partial
  contract. Verify the current gate-to-renderer acceptance path and browser evidence
  without inventing a duplicate constitutional Law or second ad engine; source/geometry
  simulations remain partial evidence, not proof of rendered acceptance.
- [ ] **Tooling proposal, cherry-pick not replace:** reconcile
  `MASTER/TOOLING_COMPARISON_PROPOSAL_2026-10-26.md` with the remaining code gaps. Adopt
  only small, testable patterns (effect identities and before/after receipts, truthful
  checkpoint/recovery states, scoped execution, typed provider failures and bounded
  fallback); retain MASTER's Ruby/law authority and avoid importing a parallel agent
  framework. Link each accepted pattern to a production caller and regression test.
- [x] **Model routing — temporary Ollama exclusion:** during November 2026, Ollama is
  disabled in `models.yml` and filtered from both normal selection and the all-dead
  fallback. The allowlisted Gemma remains dormant; only an explicit
  `MASTER_OLLAMA_ENABLED=1` opts in, and `MASTER_NO_OLLAMA=1` is a hard-off.
- [ ] **Model routing — live provider proof:** on or after December 1, 2026, review the
  account/quota state before considering re-enabling Ollama. Prove signed-in
  `claude-cli:`, `codex-cli:` and `grok-cli:` selection, actual served model/provider
  and failure/retry behavior with live evidence, not just a routing log.
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
  `STUDIO/docs/evidence/csp_probe_2026-10-28.md`. Seam `csp_enforced_on_vm23` stays
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
- Added STUDIO/docs/seo_audit_2026-10-28.md from session-provided observations. Raw HTTP
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
coverage and acceptance criteria per item: `STUDIO/docs/wishlist_2026-10-28.md`.
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


## 2026-10-31 — legacy archive follow-through

- [ ] Execute `RAILS/brgen/test/services/radio_bergen_import_guard_test.rb` on the pinned Ruby/Rails checkout. The rake task now selects persisted `brgen.no`; the importer requires a same-city saved owner and wraps reads/writes in `ActsAsTenant.with_tenant`. Regression cases cover missing scope, cross-city owners, city assignment and visibility from another tenant, but remain unexecuted here. Do not import until these tests pass and the separate recording-rights decision is complete.

- [ ] Radio Bergen: confirm distribution rights individually for the 35 selected recordings, then run `radio_bergen:import_curated` from `RAILS/brgen` against the local `pub2` checkout and verify the public Playlist/Active Storage streaming path in a local Rails test environment. The importer is committed; the audio itself is not yet imported.
- [ ] Run `cd RAILS && npm run test:radio` in the full checkout and preserve its actual exit output. The selector fix and focused Node regression are committed; the isolated harness used during this pass is not a full Rails checkout or a browser playback proof.
- [ ] Run focused local tests for the curated manifest/import guard and the Playlist tunnel view/controller; add full importer idempotency, ordering, checksum and failure-atomicity coverage, then execute them. This GitHub-only pass did not run Rails tests.
- [ ] MASTER plugin candidates from pub2 misc remain reference-only; no plugin implementation until the existing adapter, provider contracts, applicable Laws and focused tests have been reviewed.


## Root directory contract

- [x] The tracked root directories are exactly `MASTER/`, `RAILS/`, `OPENBSD/` and `STUDIO/`. Claude's native settings path is a root symlink into `STUDIO/agent-guidance/claude`, not another root directory.
- [x] The agent-contract generator no longer creates `.github/`. Copilot uses root `AGENTS.md`; Gemini, GLM and Cursor retain generated pointers. `rake lint:agent_contracts` remains the drift check.
- [x] Claude's hooks remain available at the native `.claude/settings.json` path through the root symlink, with their configuration stored under `STUDIO/agent-guidance/claude/`.

## Open from the 2026-11-01 session — WebGL / WebGPU ecosystem research

Research scope: popular and active open-source GitHub projects for browser graphics,
GPU computation, spatial interfaces, generative art, geospatial visualization and
interactive graphs. Popularity is a discovery signal, not proof of fit, maintenance,
license compatibility or production readiness. Recheck upstream activity, license,
browser support and bundle/runtime cost before adopting a dependency.

### Reference repositories and transferable ideas

- [ ] **3D rendering and scene composition**
  - mrdoob/three.js — https://github.com/mrdoob/three.js — scene graph, cameras,
    instancing, loaders, post-processing and custom shaders. Evaluate for MASTER's
    face/observatory, Amber product previews and STUDIO visual scenes.
  - BabylonJS/Babylon.js — https://github.com/BabylonJS/Babylon.js — complete engine,
    material/node systems, physics and WebXR. Compare its integrated feature set
    with Three.js before choosing an engine per use case.
  - playcanvas/engine — https://github.com/playcanvas/engine — WebGL/WebGPU engine,
    editor workflows and asset pipeline. Study runtime lifecycle and scene loading.
  - pmndrs/react-three-fiber — https://github.com/pmndrs/react-three-fiber — declarative
    React renderer for Three.js. Only for React-owned surfaces; do not add React to
    Rails-rendered pages merely to use it.
  - pmndrs/drei — https://github.com/pmndrs/drei — reusable camera, control,
    environment, loader and staging helpers; mine patterns before importing broadly.
  - pmndrs/postprocessing — https://github.com/pmndrs/postprocessing — composable
    post-processing; prefer restrained effects with measured performance.

- [ ] **2D GPU interfaces, shaders and creative coding**
  - pixijs/pixijs — https://github.com/pixijs/pixijs — fast 2D renderer with
    WebGL/WebGPU backends, filters, sprites and batching. Evaluate for particles,
    face effects and dense interactive 2D scenes.
  - regl-project/regl — https://github.com/regl-project/regl — functional explicit
    WebGL resource/state model for small custom GPU experiments.
  - PavelDoGreat/WebGL-Fluid-Simulation —
    https://github.com/PavelDoGreat/WebGL-Fluid-Simulation — real-time fluid
    simulation; prototype as optional Amber/Dilla effect and measure mobile GPU load.
  - terkelg/awesome-creative-coding —
    https://github.com/terkelg/awesome-creative-coding — discovery index for
    generative art, interaction design and graphics.
  - owenob1/awesome-web-shaders —
    https://github.com/owenob1/awesome-web-shaders — GLSL/WGSL learning and shader
    references; research index, not a runtime dependency.
  - theatre-js/theatre — https://github.com/theatre-js/theatre — authored animation
    timelines and scene direction; not a replacement for audio-clock synchronization.
  - pixijs/filters — https://github.com/pixijs/filters — composable visual filters;
    inspect individual techniques and accessibility/performance costs.

- [ ] **Spatial data, maps and large-scale visualization**
  - visgl/deck.gl — https://github.com/visgl/deck.gl — GPU-accelerated layers for
    large geospatial/tabular datasets; evaluate Brgen heatmaps, activity density,
    routes and city-scale overlays.
  - maplibre/maplibre-gl-js — https://github.com/maplibre/maplibre-gl-js — open
    vector-map renderer; prefer for practical 2D Brgen maps, adding 3D only when useful.
  - CesiumGS/cesium — https://github.com/CesiumGS/cesium — globe, terrain, 3D Tiles
    and geospatial digital twins; likely excessive for ordinary local discovery.
  - visgl/luma.gl — https://github.com/visgl/luma.gl — lower-level GPU toolkit;
    study for GPU data pipelines and custom layers before bespoke WebGPU code.
  - keplergl/kepler.gl — https://github.com/keplergl/kepler.gl — exploratory
    geospatial analytics and layered datasets; borrow analysis patterns.
  - potree/potree — https://github.com/potree/potree — massive point-cloud rendering;
    defer until a licensed terrain/urban dataset and real use case exist.
  - maptalks/maptalks.js — https://github.com/maptalks/maptalks.js — pluggable
    2D/3D map layers; compare where layered maps or 3D city objects are needed.

- [ ] **Graphs, systems and knowledge exploration**
  - jacomyal/sigma.js — https://github.com/jacomyal/sigma.js — WebGL graph rendering
    for large networks; prototype MASTER dependency, Law-enforcement and memory maps.
  - vasturiano/3d-force-graph — https://github.com/vasturiano/3d-force-graph —
    interactive 3D force-directed graphs; compare with Sigma.js and require a
    comprehension benefit before using spatial depth.
  - antvis/G6 — https://github.com/antvis/G6 — graph analysis and interaction;
    study layouts, grouping, collapse/expand, edge routing and accessibility.
  - koala73/worldmonitor — https://github.com/koala73/worldmonitor — real-time
    dashboard aggregating public data feeds; study provenance, freshness,
    map/dashboard composition and uncertainty display.
  - bilawalsidhu/gods-eye-view —
    https://github.com/bilawalsidhu/gods-eye-view — 3D globe with live public
    geospatial feeds and voice interaction; inspect source attribution, stale-data
    behavior and privacy boundaries before adapting patterns.

- [ ] **GPU compute, scientific and interactive simulation**
  - tensorflow/tfjs — https://github.com/tensorflow/tfjs — browser GPU machine
    learning; evaluate only for a measured client-side inference task.
  - google/filament — https://github.com/google/filament — physically based renderer
    with web support; compare for high-fidelity product materials if needed.
  - OmarShehata/webgpu-compute-rasterizer —
    https://github.com/OmarShehata/webgpu-compute-rasterizer — educational compute
    shader rasterizer; use to learn GPU pipelines, not as production infrastructure.
  - webgpu/webgpu-samples — https://github.com/webgpu/webgpu-samples — practical
    WebGPU patterns for capabilities, compute, buffers, textures and rendering.
  - processing/p5.js — https://github.com/processing/p5.js — approachable
    creative-coding sketches; useful for rapid prototypes and learning.

### Product-specific experiments to scope

- [ ] **MASTER — execution and architecture observatory:** represent real processes,
  jobs, model routes, tool calls, Law/detector/evidence links and /fix phases as a
  filtered graph/timeline. Use Sigma.js for large 2D graphs; compare 3d-force-graph
  only for a bounded optional spatial view. Visual states must come from actual
  receipts/events, never decorative fake data.
- [ ] **MASTER — code and memory navigation:** searchable graph of files, symbols,
  dependencies, memories and provenance, with path tracing, time playback, source
  links, access controls and deletion/retention semantics. Never expose private
  conversation content in a public/shared visualization.
- [ ] **MASTER — face renderer experiments:** compare PixiJS particles, Three.js
  instancing and custom GLSL for stipple/expression, visemes and transitions.
  Keep the existing face renderer and lip-sync clock authoritative; prototype
  behind an opt-in flag with a no-GPU fallback.
- [ ] **MASTER — system observatory:** render real CPU/memory/process/queue telemetry
  with freshness and sampling labels. Keep monitoring separate from audit receipts;
  GPU visualization must never become a required control plane.
- [ ] **RAILS / Brgen — geographic discovery:** compare MapLibre, deck.gl and
  vector-tile formats for local businesses, events, routes and density layers.
  Preserve accessible list/search alternatives; map interaction is never mandatory.
- [ ] **RAILS / Brgen — city data layers:** investigate open geodata, vector tiles,
  terrain and 3D buildings. Require source licensing, attribution, update cadence,
  caching and useful mobile fallback before implementation.
- [ ] **RAILS / Amber — product studio:** prototype orbit/inspection, material
  swatches, garment configuration and optional 3D previews. Retain the original
  large Amber identity and pastel/white visual language; no generic dark showroom.
- [ ] **RAILS / Amber — garment visualization:** research GLTF/GLB assets, texture
  compression and fit-data provenance. Do not imply accurate fit/body measurements
  from decorative avatars.
- [ ] **RAILS / BSDPorts — dependency explorer:** visualize package dependency paths,
  reverse dependencies, build state and security advisories. Preserve its
  ultraminimal white search-first interface; graph is an optional drill-down.
- [ ] **STUDIO / Dilla — audio-reactive renderer:** derive animation from the actual
  audio clock, onset/transient detection and frequency bands. Prototype fluid
  fields, particles, waveform geometry and section-specific motifs. Keep audio
  rendering deterministic and separate from the visual frame loop.
- [ ] **STUDIO — generative artwork pipeline:** export reproducible stills, loops
  and video from a song's section/tempo/seed manifest. Capture renderer version,
  seed, dimensions and audio alignment for repeatability.
- [ ] **Cross-tree — interactive technical illustrations:** study isometric/
  diagram generation patterns, including wheresryan22/anatomy
  (https://github.com/wheresryan22/anatomy), for architecture docs, deployment
  maps and hardware explainers. Prefer SVG for crisp accessible diagrams; use
  WebGL only for genuine interactive depth or large scenes.

### Architecture and acceptance gates before adopting any renderer

- [ ] Inventory existing rendering code, generated assets, browser/CDP tools,
  asset pipelines and visual contracts in MASTER, RAILS and STUDIO. Reuse existing
  engines and the radio audio/visual ownership boundary; do not create a parallel
  face, audio engine, browser harness or design system.
- [ ] Build a comparison matrix per use case: Canvas/SVG/DOM, PixiJS, Three.js,
  MapLibre/deck.gl and WebGPU. Record task benefit, API fit, maintenance/activity,
  license, bundle delta, startup cost, GPU memory, frame time, mobile thermals,
  accessibility and fallback behavior.
- [ ] Establish progressive enhancement: HTML/CSS/SVG remains usable baseline;
  feature-detect WebGL2/WebGPU; handle context/device loss, shader compile failure,
  memory pressure, tab suspension and unsupported browsers. No WebGPU-only critical
  workflow.
- [ ] Add reduced-motion and low-power modes, keyboard-operable controls,
  accessible textual equivalents and deterministic loading/error states. Never
  encode essential state only through color, depth, motion or spatial position.
- [ ] Measure representative devices/workloads before setting budgets: initial
  JS/GPU payload, time to first useful content, sustained frame time, memory,
  battery/thermal behavior, resize/context restoration and mobile interaction
  latency. Capture before/after browser evidence and exact revision.
- [ ] Review licenses and transitive dependency footprint before copying code or
  adopting packages. Prefer learning upstream patterns over importing entire
  engines; pin versions and document the reason for each dependency.
- [ ] Keep product identities distinct. Extract shared technical capability only
  after two real consumers prove identical lifecycle/API needs; do not impose one
  visual language across MASTER, Amber, Brgen, BSDPorts and STUDIO.
- [ ] Deliver a small opt-in proof of concept for the highest-value use case,
  with real data, testable behavior, browser evidence and a removal path. This
  research backlog does not claim implementation or production rollout.

## Open from the 2026-11-01 session — GPU rendering implementation

- [ ] Verify the Brgen Maps MapLibre clustering change on a real browser with
  WebGL enabled. Run
  `cd RAILS/brgen && bundle exec ruby -Itest test/controllers/maps_layers_test.rb`
  and the existing WebGL surface check; then inspect maps.brgen.no at mobile
  and desktop viewports. Confirm cluster expansion, unclustered point popups,
  search updates, cross-city links, keyboard/list alternative, WebGL failure
  fallback, context teardown and console errors. The GitHub editing pass could
  not execute Rails or browser tests; these checks are NOT_RUN, not PASS.
- [ ] The MASTER execution observatory, memory/code constellation, particle-face
  experiments and system telemetry remain proposals, not implementations.
  Review the applicable MASTER authority records and inspect the
  existing face, browser, event, receipt and visual-conformance paths before
  changing any MASTER implementation. Keep real receipts as the only source
  of execution state; no simulated telemetry or second face renderer.
- [ ] The STUDIO / Dilla audio-reactive renderer and reproducible artwork export
  remain proposals. First map the existing audio-clock, section manifest,
  render/export and radio_brgen_tunnel.js ownership boundaries. Do not add a
  second audio engine or let frame timing drive audio.
- [ ] Amber 3D garment/product inspection remains a proposal. Preserve the
  original large Amber identity, neutral fashion surfaces and truthful product
  colours; prototype only against real optimized assets and retain the current
  non-WebGL product path.
- [ ] BSDPorts dependency visualization remains a proposal. Preserve its
  ultraminimal white search-first experience; add a graph only as an optional
  drill-down over actual package dependency data.
- [ ] Evaluate WebGPU only against a measured compute/rendering need. Current
  Brgen Maps uses its existing MapLibre WebGL renderer; do not add Three.js,
  PixiJS, deck.gl, Sigma.js or a WebGPU dependency without a concrete consumer,
  compatibility review, performance evidence, license review and a tested
  progressive fallback.

## 2026-11-01 — renderer implementation status

- [x] **Brgen Maps:** MapLibre clustering uses GeoJSON source/layers with cluster expansion, safe DOM popups, same-city URL checks and a text/list fallback. Browser verification is still NOT_RUN.
- [x] **BSDPorts:** port pages now offer an optional collapsed SVG dependency overview from recorded database edges. Traversal is bounded to 60 packages and six dependency levels; the existing text tree remains the readable baseline. English and Norwegian labels are supplied. No graph renderer dependency was added.
- [x] **Brgen Radio / Dilla:** the existing radio tunnel already owns the WebGL renderer and 2D fallback. Local hosted audio can supply real FFT data; cross-origin iframe playback cannot, and the existing proxy motion is not measured spectrum. No parallel audio engine was introduced.
- [ ] **Amber 3D:** deferred until the product has real, optimized garment assets and an honest fit-data contract. The current product documentation explicitly excludes virtual fitting; a decorative mannequin would imply a capability the application does not have.
- [ ] **MASTER visual/observability work:** no MASTER implementation was edited. The obsolete whole-tree read gate has been replaced by scoped source review; read the relevant authority, face, browser, event, receipt and visual-conformance paths before editing.
- [ ] **Verification:** run `cd RAILS/bsdports && bin/ci` and the focused graph/controller tests, then capture browser evidence. This GitHub editing session could not execute Rails or browser tests; they remain NOT_RUN, not PASS. Brgen Maps browser checks are also outstanding.

## Open from the 2026-11-01 session — Rails ABC, configuration, UX and tokens

- [ ] Re-measure the ABC baseline against the current `main`, not the
  superseded `5cbb312ed` snapshot. The planned `abc_refactor.rb` driver is
  absent from the current repository tree. Restore or implement it as a
  deterministic Ruby AST refactorer with `--dry-run`, bounded `--limit`,
  source-location-aware helper insertion inside the owning class/module, syntax
  validation and fixture tests before running another mechanical batch. Keep
  `Metrics/AbcSize Max: 15`; do not change the threshold to make the report pass.
- [ ] Close the remaining mechanical ABC work only after the driver exists:
  run the 20-file batch across Brgen, Amber and BSDPorts, review each helper
  placement, run `ruby -c` on every changed model, and measure the new
  violation count. The current `RAILS/.rubocop.yml` disables the entire
  `Metrics` department, so a separate governance change is required before
  RuboCop itself can enforce `Metrics/AbcSize`; the MASTER
  `BOUNDED_LOAD_abc_size` law remains authoritative meanwhile.
- [ ] Finish BSDPorts Solid Queue proof in a local checkout: run
  `cd RAILS/bsdports && bin/ci`; enqueue a development job and verify it is
  stored in `storage/development_queue.sqlite3`; verify recurring jobs use
  the same configured database; and inspect `/admin/jobs`. Queue/cache YAML
  and the development adapter/database mapping are committed, but this runtime
  proof is NOT_RUN.
- [ ] Complete empty-state migration with a full caller scan across every Rails
  app and engine. The shared partial now logs a deprecation when legacy
  `actions:` is supplied and documents `action: { label:, path: }`; migrate
  any remaining legacy callers, prove none remain, then remove the compatibility
  branch in a separately verified change. The new logging regression is
  committed but NOT_RUN.
- [ ] Finish the canonical token correction in `MASTER/data/tokens.yml` and
  `MASTER/tools/design_tokens.rb`, then regenerate
  `RAILS/__shared/design_tokens.yml`, `RAILS/__shared/public/styles/tokens.css`
  and CSS through the documented builder. Current `social.surface` and
  `social.surface_elevated` are both `#111111`; light-mode generation hardcodes
  a white background and a white highlight. The canonical light palette already
  defines a grey page background, so the generator must consume that source
  rather than invent another palette. `radius-md` is already 12px and
  `radius-lg` 16px; preserve this correct distinction. Do not hand-edit
  generated token artifacts.
- [ ] Finish the face CSS audit by distinguishing semantic constants from
  presentation literals. Keep the black canvas/print surfaces and OpenBSD
  wscons green where they are identity or accessibility requirements. Replace
  only fallback/presentation literals owned by canonical face tokens, then
  regenerate `RAILS/master/public/face.css` and compare rendered face pages
  before/after. A source grep alone is not visual proof; confirm the production
  visual contract measures rather than silently warning.
- [ ] Keep Perplexity disabled until the intended product is chosen and tested.
  Do not add it to `openai_compatible` or a quality tier by model name alone:
  the current hosted adapter expects `GET /models` plus a chat-completions
  response, whereas current Perplexity Agent API uses its own request/response
  envelope and carries citations and cost/usage metadata. Decide between
  citation-preserving Agent research, raw Search retrieval, or the separately
  access-controlled Orchestrator model offering. Implement a provider-specific
  adapter with typed errors, bounded timeout/tool budget, citation and usage
  preservation, explicit per-operation eligibility, measured conservative
  scores, and an opt-in spend-capped canary. Test auth, model-list drift,
  unavailable models, malformed responses, timeouts, rate limits, citations,
  cost/usage, health/quota parking and fallback before any default route.
- [ ] Keep the router free-route invariant: a route whose policy is `free`
  starts with keyless/free candidates and must not silently put a keyed paid
  endpoint first. The fallback policy and regression tests have been updated;
  run the focused routing suite and the full MASTER check runner before
  treating the change as verified.
- [ ] Run each affected app's `bin/ci`, then
  `ruby MASTER/checks/runner.rb --all`, and capture fresh output/evidence.
  GitHub-only editing cannot execute these commands or validate SQLite,
  Rails rendering, RuboCop metrics or browser contracts; all new tests in this
  batch remain NOT_RUN until run from a working checkout.
