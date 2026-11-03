# pub4 outstanding work

This is the single carry-forward register, not a planning substitute. Its
existing entries are inherited work, not permission to defer a relevant task:
when an authorised request overlaps an entry, execute it now and remove the
entry when its evidence is committed. `DO_THE_WORK_NOW` governs every agent:
never add a row for work available with current tools, credentials and
authority. Add a new row only for work the user explicitly defers or a genuine
external prerequisite that blocks the remaining action. Operator-only seams
belong in `MASTER/data/operator_seams.yml`; refusals live under "Refused, and
why" in `MASTER/AGENTS.md`. This file is not a record of finished work.

## Priority 1 — Documentation reduction and reorganisation

Make the documentation corpus smaller, clearer and easier for both people and
agents to follow. The measured starting point is 83 tracked Markdown files;
that is a baseline, not a quota. Reduce duplicated authority and stale
instructions, not useful context for the sake of a lower count.

- Keep one canonical entry at each real boundary: the repository, each
  governed tree, and each product/engine that has distinct ownership.
- Shorten README files by removing duplicated product briefs and feature
  inventories already owned by the engine README or `RAILS/apps.yml`.
  Preserve each product's actual identity and its useful local instructions.
- Retire unreferenced navigation pages and duplicated instructions only after
  checking code, generators, links, tests and agent entrypoints. Keep unique
  archive, recovery and provenance records.
- Apply Strunk and White: concrete words, active verbs, economical sentences,
  and no needless qualifiers removed from meaning. Apply Bringhurst to
  hierarchy, measure, spacing and typographic restraint. Neither is a licence
  to flatten every document into the same shape.
- Update generators, links, path baselines and focused tests in the same
  change. Add no new Markdown files.

Done means one obvious source for each instruction, no stale or duplicate
agent guidance, valid links and citations, accurate shipped-versus-planned
claims, and the focused documentation checks run with their output recorded.

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
## Structural baseline on main (b20f21a82933)

The current Git tree contains 5,901 files and 809 directories, with maximum
path depth 9. Per-tree file counts: MASTER 2,230; RAILS 3,354; OPENBSD 283;
STUDIO 20. RAILS has 416 files at depth 7 or greater and 105 at depth 8 or
greater. An exact-blob census finds 49 duplicate-content groups across 154
paths, including the 19 necessary empty `.keep` placeholders. The duplicate count
excludes the former `_messages.html.erb` / `_reply.html.erb` collision:
`_reply` now has a directional arrow rather than the messages bubble, with a
source regression; rendered/browser proof remains open. These are investigation
signals, not deletion instructions: app-local migrations, pins, entrypoint
shims, licence texts and intentional stubs remain until their ownership
contracts prove a safe consolidation. Refresh the census at each bounded batch
and compare pinned revisions only.

### Remaining work

- [ ] Complete the semantic flattening census before moving more code. For
  every candidate record current path, owning application/engine, Ruby
  constant or asset/view identity, all callers/references, autoload/eager-load
  behavior, routes, migrations, serialization/public API effects, test
  coverage, compatibility requirements, proposed destination and rollback
  plan. Classify each as MERGE, MOVE, RENAME, INLINE, DELETE, RETAIN or
  INVESTIGATE. Never infer redundancy from path depth or repeated words alone.

- [ ] MASTER /fix ownership and Kernel convergence: map every production caller
  and state owner across `MASTER/lib/fix/fix_loop/`,
  `MASTER/lib/fix/fix_loop/pass_runner/`, `MASTER/lib/fix/repair_loop/`,
  `MASTER/lib/fix/scan/` and `Fix::Kernel`. Use
  `MASTER/docs/fix_coordinator_map.md` as the responsibility/evidence map.
  Production `/fix` enters Kernel, which owns the repository-wide lock,
  coordinator receipts, shared journal accessor, adapter factories and
  unknown-outcome reconciliation. The convergence, repair and lifecycle-journal
  implementations live under `Fix::Kernel`; `FixLoop`, `RepairLoop` and
  `RunJournal` remain compatibility identities until caller and recovery
  parity are proved. Consolidate only duplicate orchestration; retain distinct
  transaction, verification, recovery, budget, evidence and terminal-outcome
  responsibilities.

  Process-kill regressions cover transaction rollback, Mission/checkpoint
  survival, durable journal resumption, orphan-receipt recovery and journal
  deletion with the Mission checkpoint retained. These tests are authored but
  unexecuted. Run them on pinned Ruby 4.0.5, then prove budget/collapse behavior,
  zero-repair ledger honesty, the full adapter receipt-parity matrix and a real
  repository-wide `/fix` trial. Do not remove compatibility aliases until
  those gates pass.

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

- [ ] Residual exact-blob audit: the current census finds 49 duplicate-content
  groups across 154 paths, including the 19 necessary empty `.keep` placeholders. This
  is an investigation set, not a deletion list. It includes per-app Ruby/version
  pins, boot/config files, migration and test files that must remain at app-local
  paths, framework entrypoint/constant shims, and repeated assets/licence text.
  The Amber and Brgen `DraftsController` pair is already a thin adapter over
  `Shared::DraftsActions`; `Session` and `Current` are similarly tiny
  host-level class declarations, not worth adding another shared abstraction.
  The former `_messages` / `_reply` duplicate was corrected: the reply action
  now draws a directional arrow and has a source regression. Keep only its
  rendered/browser proof open. Do not perform hash-only deletion.

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

- [ ] Verify from a local Claude Code session on macOS that project hooks load
  through the `.claude` symlink; this session could verify the Git tree and
  link target but could not launch Claude Code. Root `TODO.md` remains the
  single actionable backlog.

- [ ] Cross-tree duplication and shape census: map repeated decision logic,
  configuration defaults, status/error vocabularies, adapters, serializers,
  wrappers, registries, generated artifacts, test fixtures and documentation.
  Include one-use abstractions, single-child directories and stale pointers.
  For each candidate, distinguish identical behavior from superficially
  similar behavior with different security, transaction, tenant, product or
  runtime contracts. Compare structural ratchets before and after, and
  consolidate the authority rather than merely the syntax.

- [ ] Add or extend structural ratchets for file count, directory count,
  maximum path depth, single-child directories, repeated namespace segments,
  dependency fan-out/cycles, public API changes and duplicate implementation
  fingerprints. Ratchets must be measured from a pinned revision and must not
  encourage deleting meaningful boundaries or merging unrelated code.

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
  committed; on 2026-11-03 the file ran 24/24 after its private-probe and
  empty-scope bugs were fixed. `ux:baymard` remains NOT_RUN. Fix confirmed
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

- [ ] Verify the import-time Whyp oEmbed implementation on the pinned
  Brgen checkout: run the playlist TrackImport tests and
  `playlist/whyp_embed_resolver_test.rb`. The resolver now requests
  `https://api.whyp.it/api/oembed` only during explicit import, validates
  the returned HTTPS `whyp.it/embeds/track/...` URL, and persists it in
  `playlist_tracks.embed_url`; page rendering reads the stored URL and does
  no network work. Regression sources cover slug links, malformed/non-rich
  responses, unsafe hosts, status/size failures and private `token` /
  collection `in` preservation. The resolver, resolver test and migration
  pass `ruby -c` on the available Ruby 3.3.8, and an isolated fake-transport
  smoke passes slug resolution, parameter preservation and unsafe-host refusal.
  This is not pinned Ruby 4.0.5 or Rails evidence: the TrackImport and focused
  Rails tests remain NOT_RUN. Existing slug-only rows need an explicit
  re-import/refresh to populate the column; no live collection was imported.
- [ ] Re-run `MASTER/bin/operator measure` on the pinned checkout with a
  bounded timeout and identify which ratchet dominates after
  `SPONSORED_LINK_REL`. The previous 500-second attempt did not finish and
  is not a measurement result.
- [ ] Verify the Marketplace/Takeaway UX and schema batch on pinned Ruby
  4.0.5. Applied-filter chips now sit beside the result set; removing one keeps
  the other filters, and Clear filters preserves query, listing kind and sort.
  Listing tiles render their delivery promise once, with a regression for the
  single-line contract. Takeaway now has restaurant-scoped menu sections
  (existing names are reused case-insensitively), optional categories for old
  dishes, and restaurant cover images validated as JPEG/PNG/WebP up to 8 MB.
  Migration `20261102180000` adds the category table/reference without
  changing existing dish rows. Focused tests cover filters, delivery badge
  count, category ownership/reuse, cover validation and both restaurant/menu
  renders. Run `storefront_search_test.rb`,
  `storefront_card_ladder_test.rb`, `vertical_mutations_test.rb`,
  `engine_render_smoke_test.rb`, and the Takeaway model tests on the pinned
  checkout; verify migration on both fresh and upgraded databases and capture
  real responsive/browser evidence. All of these Rails tests and migrations
  remain NOT_RUN here; source and test files are not a PASS.
- [ ] Run the focused billing, API-key/API-lint, dating identity, Radio manifest
  and track-import regressions listed in the RAILS verification gate below;
  no result is inferred from their source files alone.


## Carried-forward requests from earlier sessions

- [ ] **Complete AI3 archive archaeology:** the extant provenance records are
  `MASTER/docs/history/recovery/legacy_manifest.yml` and
  `MASTER/docs/history/recovery/pub_restore.yml`. They classify the former
  standalone tree as absorbed but explicitly say its old Ruby CLI/configuration
  source is not preserved; the recovery record still lists
  `MASTER/data/recovery/ai3/legacy/ai3.rb` as missing. These are recovery
  inventories, not a completed no-port audit. Recover and compare the historical
  archive blobs, map each unique role against current MASTER owners, then record
  the actual operator decision or implement only grounded behavior. No AI3
  feature claim counts as working behavior without implementation and runtime
  evidence.

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
- [ ] **MASTER README translation and narrated preview:** create the requested
  `MASTER.norwegian.md` as a complete Norwegian translation of the canonical README,
  preserving technical meaning, links, commands and code; add a parity check so
  material English sections cannot silently disappear. The same delivery includes
  the requested face-speaking preview, mobile `README_ss.webp` and Norwegian
  counterpart, full-README TTS narration, and a real SSH/`bin/master` dmesg
  transcript. The `MASTER/tools/readme_take.rb` generator can produce
  `README.wav`, `loop.mp4` and `loop.gif`; it requires pinned local Ruby, a
  running face server, the TTS worker and FFmpeg, and defaults to highlights unless
  `--full` is passed. Review the full take, produce desktop/mobile and Norwegian
  previews, and capture only actual command output. Publish media under the
  generated-media policy; do not re-track ignored MP4/WAV without a separate
  storage decision.
remove second Norwegian request- [ ] **Dilla local sample-flip interface — implementation landed; validation open:**
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
- [ ] **Model routing — live provider proof:** on or after December 1, 2026, review the
  account/quota state before considering re-enabling Ollama. Prove signed-in
  `claude-cli:`, `codex-cli:` and `grok-cli:` selection, actual served model/provider
  and failure/retry behavior with live evidence, not just a routing log.
- [ ] **Personalized MASTER behavior:** test that stable operator preferences and
  corrections influence greeting, language, response style and workflow selection through
  bounded, provenance-bearing memory. Memory must be retractable and must never override
  `soul.yml`, `laws.yml`, executable laws or explicit current instructions.

## Verification run, after the fixes below land

One pass on one commit, recorded as PASS, FAIL, INCONCLUSIVE, BLOCKED or
TIMEOUT per command. Include each affected app's `bin/ci` and
`ruby MASTER/checks/runner.rb --all` in this same pass. The 2026-10-25 and
2026-10-26 connector sessions committed source and tests they could not run;
this pass is what measures them.

Measured on 2026-11-03 with Homebrew Ruby 4.0.5 (MASTER) and rbenv 4.0.5 (the apps),
each file in its own process; the commits that fixed what they found are on main from
d04a7bb8ff to d682846752.

- [ ] MASTER focused regressions: the recorded 2026-11-03 pass had 43
  files pass and four failures/errors in `test/test_law_parity.rb`, caused by the
  omitted `proximity` root. The canonical vocabulary now includes all thirteen
  roots and a regression asserts the DEFRAG/RELOCATE assignments. Re-run the
  focused Law parity, YAML registry and Law catalogue tests on pinned Ruby 4.0.5.
  The replay-reader fixtures now create owner-private event files and a private
  events directory to match the production log contract; rerun that focused test
  on pinned Ruby before closing it. Other recorded failures remain:
  The cycle-detector fixture now observes the current five-pass recurrence
  window; rerun it on pinned Ruby before closing the test. Also rerun
  `test_agy_reachability.rb` and `test_runs.rb`. The test-runner census now
  counts STUDIO's two maintained tests and includes the parked calibration
  regression files in the MASTER suite; execute those focused tests before
  closing this gate.
  `test_tools_media.rb` reads the current canonical `STUDIO/postpro` source,
  not a retired path; include it in the pinned suite instead of treating the
  source path as a defect.
- [ ] MASTER full suite: `MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 MASTER_TEST_PROGRESS_EVERY=25 rake test`,
  then `MASTER_TEST_JOBS=3 rake test`; check `.master/check/suite-report.json` for incomplete
  workers and mismatched start/result counts. Then run `rake audit` (the complete declared lint
  inventory), followed by `bin/check --profile=agent`. NOT_RUN.
- [ ] RAILS contracts: `ruby RAILS/test/run_all.rb` went from 34 red files to 6 after this
  session's fixes, each file rerun alone after its fix. Still red: `check_live_and_css_budget`
  (a fresh build measures brgen 289KB/217KB, amber 154/103, bsdports 91/62 — real growth,
  operator decision to cut or re-ceiling), `file_length_ratchet` (25 files over or without a
  ceiling, mostly the re-cut brgen partials and the merged amber/bsdports sheets) and
  `method_length_ratchet` (35 methods over 30 lines against 16 of ceiling) — both need a
  re-baseline decision or refactors; `studio_contract` (RAILS' artwork pipeline still
  requires the retired STUDIO postpro, so publishing generated artwork fails — restore it
  or drop the dependency); `viewport_spill_check` (needs a browser session to diagnose).
  `integrity_locale` and `function_layout`'s live case failed against week-old local
  servers with pending migrations; rerun them against the fresh ones. A full single-commit
  rerun of run_all is NOT_RUN. Also NOT_RUN: `bin/ci` per app, the focused brgen billing,
  API-key, API-lint, dating identity, Radio manifest and TrackImport tests, the share and
  job-concurrency tests, and a fresh test database for amber's `account_merges`. The
  takeaway engine suite ran 28/28 and amber's post tests 46/46.
- [ ] OPENBSD: `ruby OPENBSD/test/run_all.rb` 45 files, 0 red; `ruby OPENBSD/bin/rehearse`
  16/16; `test_pf_policy_check.rb` 11/11 and `test_evidence_tool.rb` 9/9. Left: validate
  native syntax on OpenBSD with `pfctl -nf /etc/pf.conf`.
- [ ] STUDIO: `rake check` passes; `test/dilla_test.rb` ran in full (17 runs, 386 assertions),
  and its one failure, a macOS /private/var path comparison in the test, is fixed (d433c7c066).
  Left: one uninterrupted `cd STUDIO && rake check test` on a single commit.
- [ ] Generated outputs match their sources: `RAILS/__shared/design_tokens.yml`,
  `RAILS/master/public/face.runtime.js`, `face.css`, and `rake docs:agent_contracts` followed by
  `rake lint:agent_contracts`. `build_all_css.rb` reports clean for 4 apps; the rest NOT_RUN.
- [ ] The route suites with Ollama cloud absent and only local `ollama:gemma3:4b` allowlisted.
  On the default configuration (`models.yml ollama.enabled: false`) `test_route_policy.rb`,
  `test_lane_selection.rb`, `test_fix_fresh_checkout_models.rb`, `test_compute_pool.rb`,
  `test_fallback_chain.rb`, `test_lane_pool.rb` and `test_ecosystem_features.rb` all pass;
  the allowlisted-local configuration itself is NOT_RUN.
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
- [ ] Rendered layout: the widths are captured. `bin/operator visual sweep` (the /fix
  screenshot_sweep stage) recorded 181 pages, 1751 screenshots and 697 dialog states on
  2026-11-03 with 0 failures (`MASTER/.master/visual_artifacts/sweep-20261103T002444Z`), and
  its findings so far are fixed (bsdports dark-OS contrast, amber escaped post markup). Left:
  review the remaining captures, the 64 parameter routes no visited page linked to (mostly
  signed-in pages; the sweep runs as a guest), and keyboard-only, zoom, forced-colours and
  reduced-motion passes.
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

## Cross-tree

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


## Renderer research disposition

The former WebGL/WebGPU repository catalogue and unapproved experiment matrix
were discovery notes, not implementation commitments. Their long candidate list
has been removed from the active backlog; the concrete per-product work and
browser proof requirements remain under **GPU rendering implementation**.
No renderer or dependency is authorized by a research list alone. Revisit a
candidate only when a real consumer, measured need, license review, accessible
fallback and device evidence are named.

## Open from the 2026-11-01 session — GPU rendering implementation

- [ ] Verify the Brgen Maps MapLibre clustering change in a real WebGL browser.
  Run `cd RAILS/brgen && bundle exec ruby -Itest test/controllers/maps_layers_test.rb`
  and the existing WebGL surface check. Inspect maps.brgen.no at mobile and desktop
  widths: cluster expansion, unclustered point popups, search updates, cross-city
  links, keyboard/list alternative, WebGL failure fallback, context teardown and
  console errors. The GitHub editing pass could not execute Rails or browser tests;
  these checks remain NOT_RUN, not PASS.
- [ ] MASTER execution observatory, memory/code constellation, particle-face work
  and system telemetry remain proposals. The older avatar-derived face request
  remains separately recorded above. Before implementation, inspect the relevant
  authority, face, browser, event, receipt and visual-conformance paths; preserve
  scoped source review, keep receipts as the source of execution truth, and do not
  simulate telemetry or add a second face renderer.
- [ ] The STUDIO/Dilla audio-reactive renderer and reproducible artwork export
  remain proposals. Map the existing audio clock, section manifest, render/export
  and `radio_brgen_tunnel.js` ownership boundaries first. Do not add a second
  audio engine or let frame timing drive audio.
- [ ] Amber 3D garment/product inspection stays deferred until optimized real
  garment assets and an honest fit-data contract exist. Preserve the original
  large Amber identity, neutral fashion surfaces and truthful product colours;
  do not use a decorative mannequin that implies virtual fitting, and retain the
  current non-WebGL product path.
- [ ] BSDPorts dependency visualization remains a proposal. Preserve its
  ultraminimal white search-first experience; add a graph only as an optional
  drill-down over actual package dependency data.
- [ ] Verify the BSDPorts dependency graph/controller work in a real browser and
  run `cd RAILS/bsdports && bin/ci`. Capture browser evidence; Brgen Maps browser
  proof is tracked in the first item above. Source and test files alone are not
  runtime or rendered evidence.

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
- [ ] Run the empty-state source and view proof on the pinned Ruby/Rails checkout:
  `ruby MASTER/tools/empty_state_lint.rb` plus the focused Amber/Brgen view
  suites. The String-based `actions:` branch and its deprecation tests are
  removed; `legacy_actions` now has a zero-baseline ratchet beside the existing
  missing-action and empty-collection checks. This GitHub-only pass did not run
  those commands; leave their result NOT_RUN until real output is captured.
- [ ] Run the token projection and CSS proof on the pinned Ruby/Rails checkout:
  `ruby MASTER/tools/rails/build_all_css.rb --check` and the shared
  `design_tokens_test.rb` suite. The canonical source and generator already
  distinguish dark elevated surfaces (`#1a1a1a`) from light paper surfaces
  (`#ffffff` / `#f2f2f2`); the committed `tokens.css` and the embedded
  family block in `RAILS/master/public/face.css` have now been reconciled
  with that projection. The builder and regression suite were NOT_RUN here.
  Preserve the existing 12px `radius-md` / 16px `radius-lg` distinction.
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
