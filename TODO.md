# pub4 outstanding work

- [ ] * Audit OPENBSD's top-level scripts for safe consolidation into `bin/`; preserve installer/source relationships and every path vm23 currently calls. Rewrite only where the shell contract permits.
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
agents to follow. The measured baseline was 83 tracked Markdown files; current
main has 77. The baseline is a progress measure, not a quota. Reduce duplicated
authority and stale instructions, not useful context for the sake of a lower
count.

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


## Priority 2 — Decisive stewardship

MASTER should decide and execute the strongest coherent solution within the
operator-approved scope, then prove it. Do not turn an implementation request
into another plan, proposal, patch sketch or backlog entry.

- Read the whole relevant surface, map ownership and dependencies, choose one
  coherent direction, and carry it through implementation, verification and
  correction. Do not ask for per-file permission when the task already
  authorises the outcome.
- Preserve intent, user data, security, privacy, working guarantees and public
  contracts. A defective implementation is not sacred: improve, merge, replace
  or retire it when evidence supports that decision.
- Continue every independent in-scope action when one item is blocked. Retain
  only an exact external blocker, its responsible actor and the evidence or
  consent required to resume.
- Keep consent boundaries real: credentials, private data, another person's
  device or account, external messages, publication, spending, destructive
  remote-host changes and irreversible shared state require their own explicit
  authority. Approval for one action does not approve another.
- The decision contract is now reconciled across
  `DO_THE_WORK_NOW`, `OPERATOR_AUTONOMY`, `PRESERVE_FIRST`,
  `MINIMAL_FOOTPRINT` and `COLLAPSE_BEFORE_ADDING`. `DO_THE_WORK_NOW` is
  registered in the Law catalogue and reaches both the session-start briefing
  and agent conduct context. Focused regression assertions are in
  `test_fix_protocol.rb`, `test_soul.rb` and `test_master_loop.rb`; execute
  them on pinned Ruby 4.0.5 before claiming runtime proof. Do not create a
  second stewardship hierarchy.

**Break the dead thing. Don't break the user's trust.**

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
## Structural baseline on main (502f80d736b6)

The current Git tree has **5,966 files**, **816 directories** and maximum
path depth **9**. Per-tree file counts: MASTER **2,231**; RAILS **3,368**;
OPENBSD **284**; STUDIO **69**; root-level files **14**. The tree contains
**77 Markdown files**. Exact-blob matching finds **50 duplicate-content groups
across 156 paths**, including **19 required empty `.keep` placeholders**.
These are investigation signals, not deletion instructions. Identical bytes do
not prove identical ownership or behavior: app-local migrations, version pins,
boot/config files, Rails entrypoint shims, licences and product assets may be
intentionally local. Refresh this census from a pinned revision at each
structural batch; never delete on hash equality or path depth alone.

### Remaining work

- [ ] **Cross-tree semantic ownership and duplication census.** Map each
  candidate's current path, owning tree/app/engine, Ruby constant or asset/view
  identity, callers/references, autoload/eager-load behavior, routes, migrations,
  serialization/public API effects, test coverage, compatibility needs,
  destination and rollback plan. Classify MERGE, MOVE, RENAME, INLINE, DELETE,
  RETAIN or INVESTIGATE. Cover repeated decisions, configuration defaults,
  status/error vocabularies, adapters, serializers, wrappers, registries,
  generated artifacts, test fixtures, documentation, one-use abstractions,
  single-child directories and stale pointers. Distinguish identical behavior
  from superficial similarity with different security, transaction, tenant,
  product or runtime contracts. Compare structural metrics before/after and
  consolidate authority, not syntax. The latest exact-blob census above is a
  starting index, not a delete list.

- [ ] **MASTER /fix ownership and convergence proof.** Reconcile production
  callers and state owners across `MASTER/lib/fix/fix_loop/`,
  `MASTER/lib/fix/fix_loop/pass_runner/`, `MASTER/lib/fix/repair_loop/`,
  `MASTER/lib/fix/scan/` and `Fix::Kernel` against
  `MASTER/docs/fix_coordinator_map.md`. The map now distinguishes Kernel
  coordination, per-pass `Fix::Transaction`, multi-file `Fix::Restructure`,
  Mission, journal, watcher, improvement, restructure sweep, Governor and
  model redaction. Retain the compatibility identities until caller and recovery
  parity are proved. Run focused interruption/recovery tests on pinned Ruby
  4.0.5, then prove budget/collapse behavior, zero-repair ledger honesty, the
  full adapter receipt-parity matrix and one real repository-wide `/fix` run.
  Tests are authored but unexecuted; do not claim completion from the map.

- [ ] **MASTER artifact preservation across formats.** Task contracts, resolved
  repository-relative scope and before/after SHA-256 receipts now enter FixPlan
  and Transaction; RepairAdapter invokes the HTML/ERB source verifier before
  accepting a candidate. Complete the preservation contract for DOCX, PDF,
  XLSX and PPTX with format-aware source verification and rendered-output
  comparison. Add baseline/candidate fixtures spanning HTML, Ruby, Rails
  interactions, long-form documents, spreadsheets and slide decks. A changed
  format without a verifier remains INCONCLUSIVE; archive-byte equality or
  successful parsing is not visual preservation. Keep intentional-change
  fixtures as well as regressions.

- [ ] **MASTER scanner, check and nested-module ownership.** Trace production
  call graphs across `MASTER/lib/review/scan/`, `MASTER/lib/fix/scan/`,
  `MASTER/checks/` and `MASTER/checks/support/`. Keep Law (requirement),
  detector/check (measurement instrument) and evidence (observed result)
  separate; a Law/catalogue change must invalidate affected cached findings.
  Also inspect `MASTER/lib/cli/face/ascii/`,
  `MASTER/lib/cli/pipeline/proof/`,
  `MASTER/lib/cli/routing/model_router/`,
  `MASTER/lib/fix/scan/ast_fixer/` and
  `MASTER/lib/review/council/critique/`. Determine whether each directory
  represents a stable public namespace or only file grouping. Preserve the
  single face renderer, model-routing authority, AST transformation coverage,
  proof semantics and council behavior; do not move directories blindly.

- [ ] **RAILS shared view, asset and test ownership.** Inspect the mailer
  templates under `RAILS/__shared/app/views/shared/passwordless_mailer/`
  and `verification_mailer/`, shared icon partials under
  `app/views/shared/icons/`, repeated product asset/token imports and duplicate
  test support across `RAILS/__shared/test/`, `RAILS/test/` and app-local
  test trees. The former `_messages.html.erb` / `_reply.html.erb` source
  collision is fixed: `_reply` now has a directional arrow and a source
  regression. Keep its rendered/browser proof open. Preserve Rails lookup
  contracts and product identity; share foundations, not product compositions.
  Treat the 50 exact-blob groups as candidates for inspection only.

- [ ] **OPENBSD source/target boundary census.** Inspect `OPENBSD/bin/`,
  `OPENBSD/lib/`, `OPENBSD/checks/` and source-layout mirrors
  `OPENBSD/etc/`, `home/`, `usr/`, `var/`, `dev/`. Distinguish repository
  source organization from the target host filesystem contract. Consolidate
  deployment/backup/verification wrappers only after host-path, privilege,
  rollback and evidence behavior is proved. Never flatten required target
  filesystem paths.

- [ ] **STUDIO audio ownership.** Keep one Dilla generation entrypoint and one
  audio processing pipeline. Map the audio clock, section manifest, render/export
  and `radio_brgen_tunnel.js` ownership boundaries before any visual/audio
  rework. Do not introduce a second visualizer, audio engine or generator, and
  do not let frame timing drive audio.

- [ ] Verify from a local Claude Code session on macOS that project hooks load
  through the `.claude` symlink. The Git tree and symlink target were checked,
  but this session could not launch Claude Code.

- [ ] Add or extend structural ratchets for file count, directory count,
  maximum path depth, single-child directories, repeated namespace segments,
  dependency fan-out/cycles, public API changes and duplicate implementation
  fingerprints. Measure from a pinned revision; do not incentivise deleting
  meaningful boundaries or merging unrelated code.

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

- [ ] MASTER pinned-Ruby verification gate (Homebrew Ruby 4.0.5): rerun the
  focused regressions below first, then the serial and parallel full suites, audit
  and agent profile on the same clean commit. Record each command, exit status,
  actual failures and the suite report; never infer a pass from source changes.
  Focused regressions:
  - `test/test_law_parity.rb`, `test/test_yaml_registries.rb`,
    `test/test_law_catalogue.rb` and `test/test_soul.rb`: the recorded
    2026-11-03 pass had four Law parity failures/errors because DEFRAG and
    RELOCATE used the omitted `proximity` root. The canonical vocabulary now
    includes all thirteen roots and regression coverage checks the assignments,
    every registered root and the immediate-execution briefing.
  - `test/test_replay_reader.rb`: fixtures now create owner-private event files
    and a private events directory matching the production log contract.
  - `test/test_fix_loop_oscillation.rb`: its fixture now observes the current
    five-pass recurrence window.
  - `test/test_agy_reachability.rb`, `test/test_runs.rb` and the parked
    `design_calibration` regression files: the test-runner census now includes
    STUDIO's two maintained tests and those parked files.
  - `test/test_tools_media.rb`: it reads canonical `STUDIO/postpro`, not a
    retired path; execute it as a regression, not as evidence that the source
    path is broken.
  Then run:
  ```zsh
  MASTER_TEST_START_MARKERS=1 MASTER_TEST_JOBS=1 MASTER_TEST_PROGRESS_EVERY=25 rake test
  MASTER_TEST_JOBS=3 rake test
  rake audit
  bin/check --profile=agent
  ```
  Check `.master/check/suite-report.json` for incomplete workers and mismatched
  start/result counts. The focused runs, full suites, audit and agent profile
  remain NOT_RUN until real pinned-runtime output is captured.
- [ ] RAILS contracts: `ruby RAILS/test/run_all.rb` went from 34 red files to 6 after this
  session's fixes, each file rerun alone after its fix. Still red: `check_live_and_css_budget`
  (a fresh build measures brgen 289KB/217KB, amber 154/103, bsdports 91/62 — real growth,
  operator decision to cut or re-ceiling), `file_length_ratchet` (25 files over or without a
  ceiling, mostly the re-cut brgen partials and the merged amber/bsdports sheets) and
  `method_length_ratchet` (35 methods over 30 lines against 16 of ceiling) — both need a
  re-baseline decision or refactors; `studio_contract` was previously attributed to a
  missing/retired Postpro path, but `MASTER/contracts/studio.rb` now resolves the
  canonical `STUDIO/postpro/postpro.rb` entrypoint and its RAILS contract test checks
  that boundary. Re-run the named check on current main and fix its actual failure, if
  any; do not restore a duplicate or drop the integration on the stale diagnosis.
  `viewport_spill_check` needs a real browser session to diagnose.
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
- [ ] Run focused local tests for the curated manifest/import guard and the Rails-side Playlist view/controller suites; add full importer idempotency, ordering, checksum and failure-atomicity coverage, then execute them. The Node-side tunnel contract now runs green end to end (`node --test test/radio_brgen_tunnel.test.mjs`, 8/8, on Node 24 against the full checkout, after fixing the tagged-template TDZ in `radio_brgen_modes.js` and giving the tunnel its deterministic `initialTrackIndex` start); the Rails-side suites remain NOT_RUN here.
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
- [ ] Deferred experiments — keep these grouped until a concrete consumer,
  measured need and acceptance contract justify implementation:
  - MASTER execution observatory, memory/code constellation and expanded
    particle-face telemetry. Retain the separately recorded avatar-derived
    face request; use the existing one renderer and keep receipts as execution
    truth. No simulated telemetry or second renderer.
  - STUDIO/Dilla audio-reactive artwork export. Map the existing audio clock,
    section manifest and `radio_brgen_tunnel.js` boundary first; no second
    audio engine and no frame-driven audio.
  - Amber 3D garment inspection. Wait for optimized real assets and an honest
    fit-data contract; retain the large Amber identity, neutral fashion
    surfaces and working non-WebGL path. No decorative mannequin implying
    virtual fitting.
- [ ] Verify BSDPorts' source-implemented dependency graph in a real browser
  and run `cd RAILS/bsdports && bin/ci`, including the dependency graph/tree
  model tests. `Dependency.graph_for` is bounded to 60 nodes and six levels;
  the text dependency tree remains the accessible source of truth and the SVG
  is an optional drill-down. Capture mobile/desktop browser evidence and
  context/console behavior. Brgen Maps browser proof remains in the first
  item above; source and test files alone are not runtime or rendered evidence.

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

## Open from the 2026-11-04 session — blockers and their candidate fixes

The operator asked for these on 2026-11-04 after a MASTER launch on vm23
pushed swap from 217 MB to 60 MB free and brgen.no timed out until the process
was killed. They are candidates, not commitments. Asterisked rows are the
recommended first ten.

### vm23 memory (1 GB RAM, swap near full)

- [ ] * Upgrade vm23 to 2 GB at the provider (operator action).
- [ ] Add a second 1 GB swap file as a stopgap (`swapctl -a`).
- [ ] * Run amber, bsdports and brgen jobs in-process, as mrdamascy does; retire the `*_jobs` services (~250 MB).
- [ ] Or fold all four apps' jobs into one shared worker process.
- [ ] Tune Falcon to one worker and fewer threads per app.
- [ ] Set `RUBY_GC_HEAP_GROWTH_FACTOR` and malloc arena limits per app.
- [ ] Measure YJIT's memory cost per app; enable it only where it pays.
- [ ] Nightly cron restart to reclaim fragmented heaps.
- [ ] Per-service `login.conf` datasize caps so one app cannot sink the box.
- [ ] Serve bsdports as pre-rendered static HTML through httpd.
- [ ] Serve mrd.brgen.no's demo pages statically; keep checkout dynamic.
- [ ] Move the `master` web control plane off vm23.
- [ ] Move amber to its own small VM.
- [ ] * Precompile assets on the Mac and ship them; no asset build on vm23.
- [ ] * Vendor gems on the Mac for OpenBSD/amd64; no `bundle install` compiles on vm23.
- [ ] Cache built native gems (nokogiri and others) and reuse the `.so` files.
- [ ] Stop each app's web server during its own deploy rather than run two copies.
- [ ] Report memory pressure to brgen's internal status page.
- [ ] Smaller SQLite cache sizes per database.
- [ ] Drop unused middleware and engines per app in production.
- [ ] Trim production Gemfile groups.
- [ ] Lazy-load heavy engines (marketplace, dating) on first route hit.
- [ ] Record per-app RSS after boot as a ratchet in OPENBSD tests.

### Redeploy safety

- [ ] Deploy one app per day with a memory check before and after.
- [ ] * Build a deploy artifact on the Mac (code, gems, assets); vm23 only unpacks and restarts.
- [ ] Blue-green on disk: unpack beside the live copy, swap a symlink.
- [ ] Rehearse with `OPENBSD/bin/rehearse` before every deploy.
- [ ] Watchdog that aborts a deploy when swap drops under 150 MB.
- [ ] Deploy at the lowest-traffic hour.
- [ ] One-command rollback: symlink back and restart.
- [ ] vps-deploy stops and restarts the matching `*_jobs` service itself.
- [ ] Post-deploy smoke test over every route-manifest page.

### Permission and classifier blocks

- [ ] Allow `zsh OPENBSD/lib/ssh_vm23.sh *` in `~/.claude/settings.json`.
- [ ] * Narrow wrapper `OPENBSD/bin/vm23-service <app> stop|start`, allowed alone.
- [ ] Record the standing vm23 authority in `MASTER/data/operator_seams.yml`.
- [ ] Wrap routine remote operations as `operator` subcommands.
- [ ] Prepare one-off remote commands for the operator to run with `! ssh ...`.

### MASTER's one-session lock

- [ ] Release the lock after N idle minutes; the session keeps running.
- [ ] Headless runs submit their goal to the running session over the bridge.
- [ ] One lock scope per checkout.
- [ ] `/handoff` releases the lock cleanly.
- [ ] Name the holder's mode and last activity in the refusal message.

### MASTER working TODO.md unattended (first pass)

- [ ] * Split this file into one YAML entry per item: id, scope, size, acceptance check.
- [ ] * Give each item a machine-checkable "done when" command.
- [ ] One item per run; queue the next only after a green check.
- [ ] Rank items by size and certainty; take the smallest verifiable first.
- [ ] Verify-only mode: run the named checks and report without editing.
- [ ] Receipt per item: commands, output digests, PASS/FAIL/NOT_RUN.
- [ ] * Second-key review of each MASTER commit before push.
- [ ] * Strong model for edits, cheap models only for triage.
- [ ] Per-run spend and wall-clock caps with a clean stop.
- [ ] Golden fixtures as MASTER's own regression suite.
- [ ] Proposal mode writing patches to `.master/proposals/` for review.
- [ ] Success rate per item type; grant autonomy only where it lands reliably.
- [ ] Every refusal records its reason in `swallowed_errors.jsonl`.
- [ ] Read other writers' recent commits before editing.
- [ ] Nightly launchd run on the Mac, one item, morning summary.
- [ ] Stall alarm: two minutes without output stops and reports.

### MASTER on vm23 (only if wanted later)

- [ ] Git identity or deploy key for `dev`.
- [ ] Separate working checkout, not the deploy tree.
- [ ] `.master/` owned by one user and group, `ug+rw`.
- [ ] `ulimit -d`, `nice 20` and a swap watchdog around every run.
- [ ] Quitting the screen kills the whole process group.
- [ ] Verify-only on vm23; never edits.
- [ ] Prefer a cheap Linux cloud worker over the production box.

### Shared checkout and push races

- [ ] Give GLM its own clone; push-only into main.
- [ ] `push_only.rb` as the only push path for every agent.
- [ ] Pre-commit refusal to stage files with another writer's uncommitted edits.
- [ ] Per-tree edit lock naming the agent.
- [ ] `.master/agents_active.yml`: each agent's current scope.
- [ ] commit-msg hook enforcing `commit_format.yml`.
- [ ] Decide GLM's voice opt-in revert; lock the answer with a test.
- [ ] Daily review of non-Claude commits against the Laws.

### Failing RAILS contracts

- [ ] Fix `child_margin` findings file by file.
- [ ] CSS weight: cut unused selectors by coverage before raising a budget.
- [ ] Re-run `integrity_locale` after the mrdamascy README change.
- [ ] Split the longest files and methods named by the length ratchets.
- [ ] Triage `scale_lint`, `social_frontpage`, `maps_engine_wiring`, `generated_asset_check`, `link_converter`, `layout_check_enforcement`.
- [ ] Nightly RAILS suite with posted deltas.

### Markup cleanup, phase 3 remainder

- [ ] Convert marketplace listing, messenger thread, `posts/new`, amber feed header, amber post page, login wrappers.
- [ ] Replace `button-small`, `cluster`, `mt-8`, `text-sm`, `link-inherit` with element and role selectors.
- [ ] Lint presentational class names in ERB.
- [ ] Lint `div` chains deeper than three.
- [ ] Recapture and diff against the 196-shot baseline after each view.

### Product decisions (operator)

- [ ] Distance: district names instead of kilometres (recommended), or rounded client-side, or detail page only.
- [ ] Expiring posts: per-post opt-in, or hide from feeds but keep on profile, or stories only.
- [ ] Voice: restore on-by-default with a per-user opt-out.

### GIF to MP4

- [ ] Convert in the browser with WebCodecs at upload.
- [ ] Or batch-convert on the Mac.
- [ ] Or Solid Queue in-process, ffmpeg one at a time.
- [ ] Or a niced, capped cron sweep.
- [ ] Or serve GIFs lazily with a poster frame and tap to play.

### Hooks and visibility

- [ ] One `/internal/status` page: deploy commit, memory, swap, jobs, errors.
- [ ] Push notification when vm23 swap drops under 150 MB.
- [ ] Weekly digest: landed, failed, waiting on the operator.
- [ ] "Blocked on the operator" list kept current in `operator_seams.yml`.

## Open from the 2026-11-04 session — /fix that does what Claude does, unattended

Goal: /fix takes this file and the backlogs and finishes items without a
person, at the standard a supervised Claude session meets. Existing pieces to
build on, not duplicate: `Mission`, `Supervisor`, `TaskSteward`,
`TaskContract`, `OutcomeLearning`, `RepairMemory`, `RunBudget`, `RunPulse`,
`Transaction`, `Checkpoint`. Asterisked rows come first.

### Work intake

- [ ] * `MASTER/data/backlog.yml` generated from this file: id, tree, scope paths, size, risk, acceptance command, operator-only flag.
- [ ] * Each item becomes a `Mission` with a `TaskContract`; the steward wakes it until done or refused.
- [ ] Parse inline unresolved-marker comments into the same backlog with source anchors.
- [ ] Pull failing contract names from the last RAILS and MASTER runs into the backlog.
- [ ] Classify items: verify, mechanical, design, product decision, operator-only. /fix never takes the last two.
- [ ] Split items larger than one commit into child missions before starting.
- [ ] Dedupe against `git log` subjects so landed work is not redone.
- [ ] Remove the TODO.md entry in the same commit that lands its evidence.

### Planning like a session

- [ ] * Plan stage: read the files the item names, write a short plan with expected diff size and checks, then act.
- [ ] Explore stage with read-only tools (grep, file reads, route manifest) before any edit.
- [ ] Ask "does this already exist?" by searching for the named feature before building.
- [ ] Prefer the smallest change that meets the acceptance check.
- [ ] Re-plan once on failure with the failure output attached; refuse after the second.
- [ ] Carry a scratch notes file per mission across wakes.

### Tools /fix needs that Claude uses

- [ ] * Tool loop: read, grep, edit-by-exact-string, write, run-command, with a command allowlist from `law_runtime.yml`.
- [ ] Exact-string edits with uniqueness checks instead of whole-file rewrites.
- [ ] Run focused tests (`ruby -Ilib -Itest <file>`) and the app's `bin/rails test <file>` with the known env.
- [ ] Ferrum screenshots plus overlay diffs for visual items.
- [ ] Route manifest regeneration and locale contract checks as tools.
- [ ] `operator lint --changed-lines` as a tool, run before every commit.
- [ ] Temp-index commit helper for files another writer has touched.
- [ ] `push_only.rb` as the only push tool.
- [ ] Read-only ssh probes to vm23 (status, memory) through a fixed command list.

### Verification and honesty

- [ ] * No commit without a green acceptance command captured in the receipt.
- [ ] Receipts state PASS, FAIL, NOT_RUN or INCONCLUSIVE per check, never inferred.
- [ ] Run the touched tree's focused suite before and after; refuse on new failures.
- [ ] Visual items require a before/after screenshot pair.
- [ ] Independent verifier model reads the diff and the receipt, not the plan.
- [ ] Mutation spot-check: revert the fix and confirm the test fails.
- [ ] Re-run flaky failures alone before blaming the change.
- [ ] Record unrun checks as debt in the backlog, not as passes.

### Model use

- [ ] * Route edits to the strongest available model; triage and summaries to cheap ones.
- [ ] Measure land rate per model per item class; route by measured rate.
- [ ] Cache each prompt's context pack so retries cost less.
- [ ] Hard spend cap per mission and per night.
- [ ] Fall back to verify-only when no strong model is available.
- [ ] Keep `RepairMemory` declines so the same finding is not re-sent.

### Safety and boundaries

- [ ] Never touch `soul.yml` or `laws.yml`; write guard already exists, extend its tests to the new tools.
- [ ] Never stage other writers' uncommitted hunks.
- [ ] Never restart services or deploy; deploy stays an operator seam.
- [ ] Memory guard on the Mac: one /fix, at most two suites, per the 8 GB limit.
- [ ] Refuse items that touch money, auth or private data without operator review.
- [ ] Every run happens in a lock that names itself and expires.
- [ ] Roll back the mission's commits as one unit on operator request.

### Coexisting with other writers

- [ ] Fetch and rebase-by-tree before each commit; skip if origin already carries the tree.
- [ ] Detect a busy tree (uncommitted edits by others) and pick an item in another tree.
- [ ] Publish the active mission to `.master/agents_active.yml`.
- [ ] Respect GLM's in-flight scope; never edit the same file within an hour of its commit.

### Long-running operation

- [ ] * launchd job on the Mac: nightly window, one mission at a time, stops at a spend or time cap.
- [ ] `Supervisor` resumes a mission after crash from its `Checkpoint`.
- [ ] Stall alarm after two minutes without progress; stop and record why.
- [ ] Stream progress live (`RunPulse`): % complete and ETA per mission and per night.
- [ ] Morning summary: landed commits, refusals with reasons, items waiting on the operator.
- [ ] Push notification on failure or when an operator decision blocks progress.

### Learning

- [ ] `OutcomeLearning` per item class: what landed, what was refused, why.
- [ ] Store operator corrections as rules in `project_context.yml` and load them each run.
- [ ] Turn every operator rejection into a regression fixture.
- [ ] Weekly self-review: lowest land-rate classes become /fix's own backlog items.
- [ ] Compare /fix's commits against Claude's on the same item class and close the gap.

### Proving it

- [ ] Golden backlog: twenty past items with known good commits; /fix replays them and is scored.
- [ ] Start with verify-only items; promote to mechanical, then design, by measured rate.
- [ ] Shadow mode: /fix proposes, Claude or the operator lands, and the diff is scored.
- [ ] Publish the score per class in the morning summary.
- [ ] Unattended autonomy per class only after ten consecutive clean lands.

## Open from the 2026-11-04 session — MASTER's CLI, web, voice, face and manner

Candidates the operator asked for. Build on what exists: dmesg-style output,
`lib/cli/face/` (ASCII contours, mouth, pose, motion, transcriber), rb-edge-tts
with voice rotation and the dilla fx rack, `RAILS/master` face page,
`turn_router`, `attention_context`, `context_layers`. Asterisked rows first.

### CLI

- [ ] * Result first: every reply opens with the outcome in one line, detail after.
- [ ] * Live status line: mission, step, % complete, ETA, spend, model.
- [ ] Collapse tool output by default; `/expand <n>` opens one block.
- [ ] Colour only for state (ok, warn, fail); everything else plain, `NO_COLOR` honoured.
- [ ] Width-aware wrapping at the terminal's measure, 72 columns minimum.
- [ ] `/status` shows lock holder, running missions, vm23 health, last push.
- [ ] `/undo` reverts the last MASTER commit in one step.
- [ ] `/why` explains the last decision with the Law and evidence it used.
- [ ] Tab completion for commands, paths, Law ids and mission ids.
- [ ] History search (ctrl-r) across sessions.
- [ ] Multi-line input with a clear send key.
- [ ] Paste detection: large pastes become an attachment, not a prompt.
- [ ] Esc queues the new message after the current step, never cancels silently.
- [ ] Progress for long commands streams failures as they land.
- [ ] Errors say what failed, why, and the next command to try.
- [ ] Every command has `--help` with one real example.
- [ ] Startup under one second with `--fast`; full boot reports what it skipped.
- [ ] `/diff` shows the working changes of the current mission.
- [ ] Session resume shows the last three turns and the open mission.
- [ ] Quiet mode for scripts: JSON only, no face, no TTS.
- [ ] Measure and ratchet time-to-first-token in the CLI.

### Web UI (RAILS/master)

- [ ] * One page: conversation, face, mission list, live log; no navigation needed for daily use.
- [ ] * Live mission board over Turbo Streams: queued, running, landed, refused.
- [ ] Morning summary page with landed commits and operator decisions as buttons.
- [ ] Approve or reject a proposal from the browser; the decision feeds `OutcomeLearning`.
- [ ] Diff viewer with syntax colour and per-hunk accept.
- [ ] Screenshot before/after slider for visual missions.
- [ ] vm23 health panel: memory, swap, per-app status, deployed commit.
- [ ] Mobile layout first; works one-handed on a phone.
- [ ] Push notifications for decisions and failures (PWA).
- [ ] Keyboard shortcuts matching the CLI commands.
- [ ] Dark and light from the system setting; Swiss sans and mono only.
- [ ] Offline read of the last summary.
- [ ] Accessible: focus order, labels, reduced motion respected by the face.
- [ ] Session list with search and resume.
- [ ] Spend chart per day and per model.
- [ ] Auth by passkey; the page holds no secrets.

### TTS

- [ ] * Speak the result line only by default; full text on request.
- [ ] * Interruptible: speaking stops the moment the operator types or talks.
- [ ] Stream synthesis sentence by sentence to cut latency.
- [ ] Cache synthesized phrases that repeat (status words, greetings).
- [ ] Read code, paths and hashes as short spoken forms ("commit e5ee").
- [ ] Never speak secrets, tokens or long numbers.
- [ ] Prosody from content: lower pitch for failures, brighter for lands.
- [ ] Norwegian voice for Norwegian text, detected per sentence.
- [ ] Volume and speed per context (night quieter, summaries faster).
- [ ] Loudness normalised to one target so voices don't jump.
- [ ] Earcons: short distinct sounds for land, fail, decision needed.
- [ ] Measure and ratchet time-to-first-audio.
- [ ] Local fallback voice when edge TTS is unreachable.
- [ ] Voice on by default; per-channel opt-out, never opt-in.

### Face

- [ ] * Lip sync from the TTS phoneme timing, not amplitude alone.
- [ ] * Expression follows state: thinking, working, success, failure, waiting on the operator.
- [ ] Gaze towards the area of the screen being talked about.
- [ ] Idle motion: breathing and blinks with natural random timing.
- [ ] Attention cue when a decision is needed.
- [ ] One renderer for CLI and web; the ASCII contract stays the single source.
- [ ] Frame budget: drop detail before dropping frames.
- [ ] Respect reduced motion: still face with expression changes only.
- [ ] Resize cleanly from 40 to 200 columns.
- [ ] Face snapshot tests per expression in CLI and web.
- [ ] Mouth shapes for Norwegian vowels.
- [ ] Listening pose while the operator speaks.
- [ ] Optional microphone level drives a listening nod.

### Conversation

- [ ] * Answer the question asked before anything else.
- [ ] * One clarifying question at most, only when the answer changes the work.
- [ ] Remember the operator's standing rules from `project_context.yml` and apply them silently.
- [ ] Never repeat facts the operator already knows; refer to them instead.
- [ ] Short by default; offer depth rather than dump it.
- [ ] Recommend one option when there is a choice, with the reason.
- [ ] Admit uncertainty with what would resolve it.
- [ ] Correct its own earlier mistakes plainly and early.
- [ ] Track open threads across the session and close them.
- [ ] Recognise "status?", "go", "keep going" and similar as complete instructions.
- [ ] Mid-task messages queue, not cancel.
- [ ] Summarise long work as result, evidence, next step.
- [ ] Speak Norwegian when spoken to in Norwegian.
- [ ] Never quote the operator back verbatim in config or replies.
- [ ] Handle interruptions without losing the current mission.
- [ ] Turn evaluation: replay twenty past conversations and score answers against what the operator wanted.

### Social intelligence

- [ ] * Read urgency and frustration from wording; respond shorter and act faster.
- [ ] * Notice repeated complaints ("stop asking me") and fix the cause, not the symptom.
- [ ] Know who is who: the operator, Ragnhild for amber, the Bergen crew; pronouns as stated.
- [ ] Credit other writers' work accurately and critique it fairly.
- [ ] Ask before outward-facing actions; never ask for routine ones the operator has granted.
- [ ] Celebrate lands briefly; never over-praise.
- [ ] Tone matched to time of day and the operator's energy.
- [ ] Bad news first, with the fix attached.
- [ ] Keep promises: anything "I'll do" becomes a tracked mission.
- [ ] Notice when the operator goes quiet mid-task and leave a resumable summary.
- [ ] Respect the operator's taste rules (flat brutalist, no serifs, no artist names in dilla).
- [ ] Learn preferences from accepted vs rejected proposals.
- [ ] Never guess pronouns; use the stated ones or they/them.
- [ ] Weekly reflection: what annoyed the operator this week and what changed because of it.

## Open from the 2026-11-04 session — /fix gets better at design

/fix already carries `design_audit`, `design_loop`, `layout_score`,
`typography_audit`, `scale_snap`, `tap_target_pad`, `taste_memory`,
`ux_refinement_catalog`, the `visual_*` family and `dead_css_*`. Most rows
below wire, measure or tighten those rather than add new modules.
Asterisked rows first.

### Seeing

- [ ] * Every design mission captures 390, 768 and 1280 px before and after; no visual commit without the pair.
- [ ] * Opacity-stack overlays across pages of one app (the 2026-11-03 method) as a standing consistency score.
- [ ] Canny edge stacks to expose misaligned columns and gutters.
- [ ] Capture dialog, menu, error, empty and loading states, not only default pages.
- [ ] Capture `?view=media` and other query-driven modes from the route manifest.
- [ ] Dark-mode capture for every page.
- [ ] Capture with Norwegian and English copy; flag overflow from the longer one.
- [ ] Capture at 200% text zoom; flag clipped or overlapping text.
- [ ] Capture with reduced motion and forced colours.
- [ ] Keyboard-only walk: record focus order and visible focus per page.
- [ ] Touch walk at 390 px: every target at least 44 px, measured from the render.
- [ ] Record scroll-length per page; flag pages that grew more than 20%.

### Measuring

- [ ] * Spacing rhythm score: every vertical gap on the 4/8 px scale, measured from computed styles.
- [ ] * Type scale score: every rendered font size and line height maps to a token.
- [ ] Colour score: every rendered colour maps to a token; contrast WCAG AA at minimum.
- [ ] Alignment score: left edges per page cluster on few columns.
- [ ] Density score: content area to chrome ratio at 390 px.
- [ ] Measure line length in characters; flag over 75 or under 30.
- [ ] Count distinct button shapes per app; target one per role.
- [ ] Count distinct border radii, shadows and borders; target the token set.
- [ ] Detect divitis: wrapper depth and non-semantic containers per view.
- [ ] Detect presentational class names in ERB.
- [ ] Layout shift (CLS) and largest paint per page from the capture run.
- [ ] CSS weight per app and unused selector share from coverage.
- [ ] Icon consistency: stroke width and optical size per icon set.
- [ ] Ratchet each score per app; a design commit may not lower any.

### Judging

- [ ] * A vision critique pass per page against the house style (flat brutalist, Swiss sans + mono, no serifs) with findings tied to elements.
- [ ] * Pairwise judge: show before and after, ask which is better and why; reject commits that lose.
- [ ] Reference board per app: approved screenshots the judge compares against.
- [ ] Heuristic checklist from Baymard and Nielsen run per page type (form, list, detail, checkout).
- [ ] Copy critique: plain words, active verbs, no needless words, nb and en.
- [ ] Hierarchy critique: one primary action per view.
- [ ] Empty-state critique: every list says what to do next.
- [ ] Error-state critique: every error says what happened and how to fix it.
- [ ] Separate the judge model from the editing model.
- [ ] Record the judge's reasons with the commit.

### Editing

- [ ] * Edit tokens and shared partials before page-level CSS; a fix in one place beats twenty.
- [ ] * Exact-string edits with a capture after each; revert on any score drop.
- [ ] Prefer removing CSS to adding it; report net lines.
- [ ] Replace wrapper divs with semantic elements as a mechanical transform with a render check.
- [ ] Rename presentational classes to role names, moving style into SCSS.
- [ ] Snap stray values to the nearest token (`scale_snap`) with a diff preview.
- [ ] Pad tap targets (`tap_target_pad`) only where the measure fails.
- [ ] Fix contrast by moving to the nearest passing token, never ad-hoc colours.
- [ ] Merge near-duplicate components found by the overlay.
- [ ] Batch one design rule across all apps in one mission, one commit per app.
- [ ] Never edit the operator's hand-written CSS outside rule-derived changes.

### Taste

- [ ] * Feed accepted and rejected design commits into `taste_memory` with the screenshots.
- [ ] Store the operator's design directives as checkable rules (no serifs, one font, flat).
- [ ] Learn per-app identity: brgen, amber, bsdports and mrdamascy stay distinct where they should.
- [ ] Score proposals against the taste memory before the judge sees them.
- [ ] Show the operator a contact sheet of proposed changes; one tap approves the batch.

### Process

- [ ] * Design missions run on a local server with fresh assets, never stale precompiled ones.
- [ ] Reset the test DB and seed demo content before capture so pages are full.
- [ ] Capture and score in one background job; edits wait for the baseline.
- [ ] One app at a time on the 8 GB Mac.
- [ ] Contact sheet per mission in the morning summary.
- [ ] Golden design set: ten past design commits /fix must reproduce or beat.
- [ ] Track design score per app over time in a chart on the master web UI.
- [ ] Stop and report when two edits in a row fail the judge.

## Open from the 2026-11-04 session — radically simplify and reorganise pub4

Measured 2026-11-04: MASTER 2,232 tracked files (lib 801 files, 144,904
Ruby lines, 215 of them under `lib/fix`; test 822; data 93 YAML), RAILS
3,443 (brgen 1,011, `__shared` 603, five `brgen_*` engines at the top
level), OPENBSD 286, STUDIO 69, 81 Markdown files. These are candidates
that need the semantic census above before any move. Asterisked rows first.

### Repository root

- [ ] Fold `TREE_CONTRACTS.md` into each tree's own README.

### MASTER

- [ ] * Collapse `lib/fix` (215 files) into a handful of subsystems: intake, plan, edit, verify, commit, learn, visual.
- [ ] * Merge `lib/review/scan`, `lib/fix/scan` and `checks/` into one detector registry.
- [ ] Merge `lib/io` and `lib/ground` where both wrap external tools.
- [ ] Move the face (`lib/face`, `lib/cli/face`) into one module with one renderer.
- [ ] Move `lib/music` to STUDIO; MASTER calls it, not owns it.
- [ ] Move `lib/finance`, `lib/mobile`, `lib/device` behind plugins or delete if unreached.
- [ ] Delete modules with no production caller (reachability scan), one batch per commit.
- [ ] Fold the 93 data YAML files into fewer files by owner: soul, laws, runtime, models, design, voice.
- [ ] One config loader for all data files.
- [ ] Merge `contracts/`, `convergence.yml` and `PATH_OWNERSHIP.yml` into the data tree.
- [ ] Move `docs/` and `man/` into one `doc/` with generated man pages.
- [ ] Prune `tools/` (135 files): delete one-off scripts, promote the rest to `bin/operator` subcommands.
- [ ] Collapse `bin/` (30 files) to `master`, `operator` and `fix`.
- [ ] Test tree mirrors lib tree one to one; delete tests for deleted code.
- [ ] Replace per-file tests of tiny helpers with table-driven tests.
- [ ] Remove compatibility constants once the receipt-parity tests pass.
- [ ] Drop `plugins/` that nothing loads.
- [ ] Cap file length at 300 lines and method length at 20 with the existing ratchets.
- [ ] Rename vague modules (`gap`, `phoenix`, `unwrap_error`) to what they do.

### RAILS

- [ ] Replace the `_*.sh` root scripts with one Ruby `bin/rails-ops` tool.
- [ ] Delete `__other` after checking every reference.
- [ ] Merge `apps.yml` and `apps.horizon.yml`.
- [ ] Move `coverage/`, `visual_completion.yml` and `crawl_manifest.yml` under `RAILS/test/` or an ignored build directory.
- [ ] Move `RAILS/screenshot_*.png` into `RAILS/screenshots/` (still ignored).
- [ ] One Gemfile base in `__shared` that apps extend.
- [ ] One `config/` base in `__shared` (initializers, puma/falcon, locales) with per-app overrides.
- [ ] Move shared test support into `__shared/test/support`; delete the copies.
- [ ] One SCSS foundation in `__shared`; apps keep identity tokens only.
- [ ] One Stimulus controller set in `__shared/frontend`; delete per-app forks.
- [ ] Shared mailer layouts and templates; apps override copy only.
- [ ] Rename `__shared` to `shared` once tooling follows.
- [ ] Generate per-app boilerplate (bin, config.ru, boot) from one template.
- [ ] Delete dead routes and controllers found by the route manifest and coverage.
- [ ] Collapse migrations per app into a schema load plus recent migrations.
- [ ] Move seeds to fixtures-based demo data in one shared loader.
- [ ] Merge `RAILS/test` contract tests into MASTER checks or the apps' own tests.
- [ ] Drop `package.json` and `package-lock.json` if importmap covers everything.
- [ ] Merge `RAILS/docs` into the app READMEs.

### OPENBSD

- [ ] * Mirror the box: `etc/`, `usr/`, `var/`, `home/` hold only what is installed; everything else moves to `bin/` or `lib/`.
- [ ] Merge `deploy_inventory.json` and `vm_resource.yml` into `data/`.
- [ ] Merge `RUNBOOK.md`, `README.md` and `CLAUDE.md` into one README.
- [ ] One deploy entry point (`bin/vps-deploy`); retire the others.
- [ ] Generate relayd, httpd and rc.d files from `data/` (DNS already works this way).
- [ ] Delete `dev/` if it is scratch.

### STUDIO

- [ ] Move `photograph.rb`, `subprocess.rb` and `output_paths.rb` into `lib/`.
- [ ] Merge `agent-guidance` and `docs` into the README.
- [ ] Decide whether `replicate` belongs in STUDIO or MASTER.
- [ ] One CLI entry for dilla and postpro.

### Cross-tree

- [ ] One Ruby version across trees and vm23 (3.4 vs 4.0 still diverge).
- [ ] One lint configuration at the root.
- [ ] One place for generated artefacts, ignored by git.
- [ ] Delete exact-duplicate files beyond the necessary `.keep` placeholders.
- [ ] Measure and ratchet tracked file counts per tree downwards.
- [ ] Each tree keeps one README with a three-line purpose at the top.
- [ ] Move every generator's output path into one manifest.
- [ ] Remove the snapshot pre-push step once snapshots are release artefacts.

## pub5 — a ported fresh start (planned 2026-11-04)

pub5 is a new repository built by porting pub4, not rewriting it: every
behaviour is locked as an executable contract in pub4 first, then rebuilt
smaller against that contract. Target about 2,700–3,300 files from about
6,000 (MASTER 700–900, RAILS 1,800–2,200, OPENBSD 100–150, STUDIO 40–50).
Rule for the whole port: same behaviour, less code; new features wait.

### Phase 0 — lock behaviour in pub4

- [ ] * Route contracts: per app and route, the anonymous GET status, redirect target, title, landmarks and form actions, recorded from a running app and checkable against any base URL.
- [ ] Signed-in route contracts with a seeded demo user.
- [ ] Golden screenshots for every manifest route and dialog state at 390, 768 and 1280 px.
- [ ] One proof fixture per Law generated from `laws.yml`, runnable against either repo.
- [ ] Data export/import round-trip test per app schema.
- [ ] MASTER CLI command contract: command, exit code, output shape.
- [ ] One acceptance command that runs all of the above against a target repo or URL.

### Phase 1 — skeleton

- [ ] Root README and `AGENTS.md` only; one Ruby version reconciled with vm23; one lint config; one test command; commit-format hook from the first commit; generated output outside git.

### Phase 2 — OPENBSD

- [ ] Port with configs generated from `data/` and one Ruby deploy tool that ships a Mac-built artifact.

### Phase 3 — RAILS

- [ ] Shared base (tokens, SCSS foundation, Stimulus, auth, embeds, PWA), then bsdports, mrdamascy, amber, brgen core, and each brgen engine under `brgen/engines/`. Each app goes live only when its contracts and screenshots pass.

### Phase 4 — STUDIO

- [ ] dilla and postpro behind one CLI.

### Phase 5 — MASTER

- [ ] Port last; pub4 MASTER governs until pub5 MASTER passes every Law fixture. `soul.yml` and `laws.yml` move byte for byte.

### Conditions

- [ ] Freeze pub4 for other writers, or route them to pub5, before Phase 1.
- [ ] pub4 stays as a read-only archive; pub5's first commit names the pub4 commit it ported from.
