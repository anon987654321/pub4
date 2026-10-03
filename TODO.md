## Completed in the 2026-09-28 backlog convergence pass
## Completed in the 2026-09-29 KISS convergence pass

- Removed the orphaned GitHub Actions mirror layer: the hosted workflow files are gone, `RAILS/test/premerge_mirrors_ci_test.rb` and workflow-specific dependency checks are gone, and `MASTER/bin/ci` plus `RAILS/bin/premerge` now describe only the local/vm23 verification path.

- Boot no longer runs the full constitutional self-test on every startup. `MASTER_BOOT_SELF_TEST=1` is an explicit diagnostic; `rake selftest`, the heartbeat job and the `/fix` verification path retain the actual self-audit instead of duplicating it in critical boot.
- `SINGULARITY` now owns rule/deploy identity. Cross-file top-level YAML registry duplication remains enforced by the separate `lint:data_singularity` gate, so generic keys such as `dimensions` cannot turn an unrelated registry into a boot failure.
- `models.yml`, `patterns.yml` and `soul.yml` each have one shared MASTER reader; their consumers reuse `Master.models_config`, `Master.patterns_config` and `Master.soul_config`. Redundant accessor memoization and reflective collaborator access were removed where the existing APIs already exposed the needed state.
- Scanner rules and FixLoop homeostat are accessed through public readers instead of instance-variable reflection; unused FixLoop Reflexion state was removed.
- The next work remains evidence-first: the real Mac runtime, Rails/browser gates, vm23/OpenBSD, Termux, money/staging, and snapshot regeneration are not claimed complete until watched results exist.


## Current recovery state — 2026-09-30

- 2026-09-30: model failover now promotes a successful automatic fallback to the
  runtime current model. Explicit `/model` pins remain pinned, while failed
  automatic lanes are quarantined and skipped. Single-shot and chat paths use
  the same promotion seam; operation-specific quality constraints remain intact.
  Live-provider outage proof is still a runtime evidence gate.

- Structural repository sprawl rollback is complete. main deliberately keeps the pre-sprawl topology; no mass flattening or moves should be reintroduced.
- The current main boot baseline includes the post-baseline Ruby/runtime fixes that are independent of topology: the stale builder rollback require is removed; PassRunner, swallow ledger, prompt syntax and runtime YAML fixes are restored.
- Source audit confirms these previously-open seams are already implemented in this tree and now require evidence rather than another implementation pass: CQS memoisation contracts, per-process resource RSS recording, TTS socket health reporting, browser-gate inconclusive semantics, reason-coded guest-page coverage, drag-only reorder controls, and offline send storage.
- 2026-09-30: interrupted browser-face turns now remain recoverable when the transport dies before any assistant content arrives. Completed or partially streamed turns are not blindly requeued.
- 2026-10-01: removed the unused `head_music` dependency and dead Dilla adapter branch. The MASTER lock no longer carries the ActiveSupport/i18n/tzinfo chain solely for that unused integration; the remaining Dilla gems are coltrane, midilib and wavefile.
- Remaining work is evidence- or operator-bound unless a future re-measurement proves otherwise: Mac runtime boot proof, Rails/browser rendered gates, vm23 deployment/DNS/resource checks, payment staging, Termux ear proof, Dilla asset/audio verification, registrar/money actions, visual/taste decisions, and final snapshots.
- backup/main-before-sprawl-rollback-20260930 preserves the pre-recovery tree; recovery/pre-sprawl-20260930 preserves the clean rollback point.

# pub4 backlog

The single backlog for the repo. Authority: `MASTER/data/soul.yml` > `MASTER/data/rules.yml` > executable law (`MASTER/law/*.rb` and `MASTER/lib/review/scan/rules/*.rb`) > repo harnesses (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.cursorrules`, `.github/copilot-instructions.md`) > per-tree contracts. Feature truth is `RAILS/apps.yml`; aspiration is `RAILS/apps.horizon.yml`; executable behavior and git history outrank prose.

A finding is a hypothesis. Historical dated sections below are evidence records, not automatically-open work. An item is current only when it appears in the current plan or has been re-measured on the current `main` tree. Close an item by deleting it after the code and its proof land; keep historical evidence in git.

- Direct MASTER test entrypoints now activate the same private Ruby/Bundler context as `bin/cli` before loading SimpleCov or Minitest; Minitest is constrained to `~> 5.25`, preventing a host-installed 6.x release from bypassing the locked suite.

## Current state — 2026-09-29

- `main` is the authoritative repository baseline. There are no open pull requests.
- Ruby remains pinned to `4.0.5`; Bundler remains pinned to `4.0.5`. Rails surfaces remain pinned to the audited Rails 8.2.0.alpha source revision `c9e85dbe297e248dd2f217d04f84a94881ac046a`, with `load_defaults 8.2`.
- The Rails 8.2 source contracts are already executable: framework defaults, CSRF, enum persistence, commit-time job production, SQLite foreign-key rebuilds, Active Storage timing, lockfile source/revision and dependency-shape checks.
- `RAILS/bin/ci` is now the canonical local Rails verification entrypoint: contract suite first, then brgen, amber, bsdports and eritel CI. Eritel's standalone runner now carries the same bundle, style, security and test floor without pretending it has the shared apps' CSS/engine topology.
- Importmap integrity is now explicit on the three Propshaft/importmap store apps: `enable_integrity!` plus Propshaft `sha256` configuration. The shared external web-vitals CDN pin has an explicit `integrity: false` policy rather than an implicit assumption. The importmap contract and pin-source contract are executable.
- The PWA source/build seam is executable: the three store apps point at one shared Workbox source and the build contract explicitly excludes digested assets from precache. Existing generated-worker contracts remain the guard against stale hand-edited output.
- `RAILS/bin/triangle` remains the reproducible live-app bootstrap path, and a dedicated contract test now pins its apps.yml port discovery, database preparation, asset-manifest invalidation, named-surface selection and lifecycle behavior.
- Static marketplace safeguards are already present: Dintero checkout/split/refund contracts, persisted split contracts, ACTIVE seller gates, replay/schema tests, Stripe fail-closed payout behavior and affiliate disclosure/sponsored-link contracts. Production enablement still requires real staging evidence.
- The rendered/browser, MASTER four-tree /fix, vm23/OpenBSD, Termux/Edge TTS, payment-provider staging, Dilla/audio and final snapshot items remain evidence gates because their truth depends on a watched runtime, real credentials, hardware, or the final checkout. They are not marked green by source inspection.
- The hosted repository currently exposes `main` as the authoritative branch surface; older `origin/*` names may remain in an existing checkout until `git fetch --prune origin`. Do not treat stale remote-tracking refs as live branches or unfinished work.
- GitHub Actions workflows are not part of the repository verification surface. Manual local and vm23 execution remains the intended release proof.

## Current plan — ordered 2026-09-29

### Runtime evidence still required
- Run the full Rails 8.2 contract suite on a clean checkout, including `bin/rails herb:check`, the database migration exercise and the security/autoloading/routing/rendering/cache/job/mailer/Active Storage/PWA/system-test gates.
- Run `RAILS/bin/triangle up` from a fresh checkout and then a real rendered gate with Chrome, recording a measured result rather than an inconclusive precondition.
- Re-run the one-content-column/vertical consistency pass at mobile and 1440px widths; re-measure CSS budgets, magic values, type scale, leading, spacing, interaction contrast and unused selectors from the current assets; recompute the current `needs_id` guest-page census from live routes/data.
- Run the four-tree `MASTER /fix MASTER RAILS OPENBSD STUDIO` from a clean checkout and re-measure MASTER ratchets before changing any ceiling. Do not substitute static source proof for the watched run.
- Validate Dintero staging signatures/replay/capture/refund/per-line splits, Stripe Connect seller/balance/transfer behavior and the current Amazon/TradeDoubler boundaries with real staging credentials; missing credentials must remain fail-closed.
- Prove the real Termux Norwegian/English ear path and vm23 Edge TTS MP3/socket path, or record the exact hardware/runtime blocker.
- Verify the real vm23 Ruby package/interpreter seam, watched OpenBSD deployment, nsd/relayd state, bsdports repeated deploys, backup/restore consistency, storage and RAM headroom.
- Re-measure Dilla asset hashes, hocket/voicing/provenance/determinism defects and postpro/LoRA calibration before sound- or video-changing work.
- Regenerate the four tracked snapshots from the final checkout and commit them only after their contents are current.
- When an official Rails 8.2 release exists, compare it to the audited edge revision, re-lock and rerun the complete proof set before changing the production source pin.

### Research/reference guardrails
- Use official Rails and upstream Hotwire/importmap documentation, web.dev Baseline/Interop and upstream implementation history as compatibility authorities. CSS-Tricks and Awesome lists remain technique/discovery references, not security or browser-support authorities.
- Preserve executable regressions for transaction ordering, generated PWA output, SRI/importmap hygiene, replay safety and other production-critical boundaries as implementations evolve.

## External reference baseline — refreshed 2026-09-28

Rails:
- Edge Guides: https://edgeguides.rubyonrails.org/
- Rails 8.2 release notes: https://edgeguides.rubyonrails.org/8_2_release_notes.html
- Rails upgrading guide: https://edgeguides.rubyonrails.org/upgrading_ruby_on_rails.html
- Rails releases: https://github.com/rails/rails/releases
- Rails main: https://github.com/rails/rails
- Turbo Rails: https://github.com/hotwired/turbo-rails
- Stimulus Rails: https://github.com/hotwired/stimulus-rails
- Importmap Rails: https://github.com/rails/importmap-rails
- Solid Queue: https://github.com/rails/solid_queue

Web:
- Baseline 2026: https://web.dev/baseline/2026
- Accessibility: https://web.dev/learn/accessibility/
- CSS: https://web.dev/learn/css/
- Interop 2026: https://web.dev/blog/interop-2026
- Interop 2027: https://web.dev/blog/interop-2027-proposals

Community/reference:
- Awesome Ruby: https://github.com/markets/awesome-ruby
- Awesome Rails: https://github.com/gramantin/awesome-rails
- Awesome CSS: https://github.com/awesome-css-group/awesome-css
- Awesome UI: https://github.com/coderdiaz/awesome-ui
- Awesome Self-Hosted: https://github.com/awesome-selfhosted/awesome-selfhosted
- CSS-Tricks Anchor Positioning: https://css-tricks.com/css-anchor-positioning-guide/

Reference order: GitHub upstream implementation/release history → official Rails Edge Guides/release notes → current Hotwire/Rails ecosystem repos → web.dev/Baseline/Interop → current Awesome lists → CSS-Tricks for technique/inspiration.

---
## MASTER

1. **RubyLLM 2 compatibility is on main; retain provider-key contract coverage.** This historical entry is closed as an upgrade task; its remaining value is the provider/API regression coverage. The current production gate is the Rails 8.2 migration and the green brgen/amber suites.
3. **The /face ear on a real phone.** Entry: "The /face ear is unproven on a
   phone". Done when a Termux session transcribes one Norwegian and one
   English phrase through pulseaudio and a source-built whisper.cpp.
   Operator: the phone.
4. **The two faces at parity, behaviour first.** Entry: "The web and terminal
   faces differ". The terminal echo guard and interrupted-turn recovery are
   implemented and regression-tested. The remaining parity work is the
   browser-side IdeaPicture/voice-bed runtime path and executable depth-map
   comparison; neither is claimed complete without a watched browser/runtime
   result. Operator: anything that changes how either face looks.
5. **The Gemfile lock for both hosts.** The code-owned lock work is closed
   2026-10-01: platform-aware watcher declarations, complete checksums,
   removal of the unused `head_music` dependency chain, and a regression test
   all live on `main`. What remains is the watched vm23 bundle/restart proof.
   Operator: a console on vm23.

### RAILS

1. **Green contract suite** (instruments, 2), then **the CSS budget review**.
   Entry: "CSS budgets raised on 2026-09-25". Operator: whether 215/110/66 KB
   stand.
2. **The content column across the verticals.** Entry: "One chrome". Done when
   `vertical_consistency_test.rb` passes and a 1440px screenshot of tv shows one
   left edge. Operator: the screenshots before merge.
3. **Guest page probe coverage now names its unresolved causes.** Entry: "17 of the 42
   `needs_id` guest pages". `Deploy::LiveRecordIds.unresolved_reason` now gives
   the page-level reason for every unresolved route, so missing probes are evidence
   rather than an unexplained count. Live data seeds remain open for event, story,
   hashtag, partner, marketplace-deal, community-wiki and TV records where a real
   guest probe is still meaningful; password-reset tokens and requester-scoped
   conversation/listening-party pages remain structurally unprobeable.
4. **Marketplace money.** Entry: "Seller payouts need money". Operator: money.

### OPENBSD and vm23

Lines 1 to 4 need a console on vm23, so they batch into one watched session:
the operator opens it, and an agent reads the man pages there first. Lines 5
and 6 need the registrar or money.

1. **One `doas zsh OPENBSD/OPERATOR.sh` run.** Entry: "Waiting for the box".
   Done when `config_drift_gate.rb --remote` reports no drift.
2. **nsd back to one process, the old `nsd-resign` gone, amber.brgen.no's
   leftovers removed.** Entry: "vm23 carries three leftovers". After 1, which
   installs the repo's `nsd-resign`.
3. **bsdports survives its own deploy three times.** Entry: Deploy blocker 3.
4. **relayd restarts once per deploy, not five times.** Entry: "relayd
   restarts five times".
5. **bsdports.org delegation** before the certificate lapses on 2026-11-10.
   Entry: `bsdports_org_delegated_to_parking`. Operator: the registrar.
6. **Off-host backups and 2 GB of RAM.** Entries: `off_host_dr`,
   `multi_app_ram`. Operator: money.

### MASTER/tools

2. **The no-arg smoke test.** Closed 2026-09-26. The bare Dilla entrypoint has
   an opt-in bounded smoke seam and an end-to-end WAV/MP3 duration test.
3. **Restructuring rows 1, 6 and 15.** Entry: "dilla — restructuring". Each
   must leave the snapshot identical.
4. **Everything marked [risk], [yours] or "operator"** waits for his ear, and
   the crate backup waits for money (`off_host_dr`).

### The operator's queue

Only he can close these, and each is small once he sits down to it:
the rules.yml trim draft (MASTER); the CSS budget ceilings (RAILS);
`spine.lib_body_ceiling` and the rules.yml ratchet rows (MASTER); the two
`soul.yml` edits (refinement 8); the vm23 session above; the bsdports.org
delegation; the Replicate key or retiring replicate; and the rendered values
the "One chrome", ad system and layout sections bring back for a decision.

---

## MASTER

### Interactive interface convergence — 2026-10-02

- **One MASTER interface.** CLI, web and voice should consume one UI/state contract and one face language. No separate interaction model, wording, status grammar or visual vocabulary should survive merely because the transport differs.
- **Speech-first operator control.** MASTER must understand ordinary spoken work requests, execute them through the same operator path as typed requests, speak concise professional replies, detect ambiguity, ask one precise spoken question when required, and never require “press Enter” to finish speech. Keyboard input remains a fallback, not a prerequisite.
- **TTY as a first-class surface.** The CLI should borrow the strongest shell ergonomics without copying their ornament: ksh/ash restraint, zsh line editing and history, fish suggestions and completion, Oh My Zsh’s useful context, and Starship’s modular information budget. The prompt stays small, stable and immediately writable.
- **Working-state line.** Keep one ASCII `*` line directly below the shell prompt. MASTER may animate `* + x +` with elapsed time while working, then return the same line to the operator for typing. It must never repaint across wrapped input or leave cursor garbage in scrollback.
- **Quiet source.** Reduce line noise in MASTER and STUDIO source by preferring named intermediate values, multiline data and maintained parsing/formatting libraries over cryptic concatenation, regex-heavy rewriting and clever one-liners. AST- or parser-backed transformations should be the default where structure exists; hardcoded lexical fallbacks need an explicit reason.
- **Dilla UI sound layer.** Add small STUDIO/dilla-derived M4L-style device emulations for MASTER boot, listening, working, success, error and other meaningful state changes. They should feel like instruments: short, restrained, level-matched and declared from one sound vocabulary rather than scattered effect code.

#### Shell/runtime evidence extracted on 2026-10-02

- `NO_TRANSPORT_WRAPPER_IN_SOURCE` is now executable error law. Literal `<sub>...</sub>` transport markup around Ruby source made `/fix` fail at syntax preflight; the existing tree-boundary test is retained as a second guard.
- `CLI_TREE_TARGET_RESOLUTION` is now executable error law. `Scan::Request` was resolving `STUDIO/lora` with the current process directory instead of the repository root. Explicit `MASTER`, `RAILS`, `OPENBSD` and `STUDIO` targets now share the repository-root rule.
- `CLI_PROMPT_COMPOSITION` is an executable opportunity law. The prompt remains path + Git + meaningful phase/error + shell token, with the existing `*` working line beneath it; prompt Git state is now one bounded, cached probe.
- `VOICE_FAILURES_ARE_ACTIONABLE` is an executable opportunity law. Empty synthesis, dead sockets, playback failure and worker errors remain a bounded capability state with a retained reason and declared fallback.
- `CAPABILITY_STATUS_MUST_BE_TRUTHFUL` is an executable error law. `/status services` now derives voice state from retained Speech/Playback failures instead of an optimistic ready flag.

#### Shell study decision

The CLI refinement draws restraint from OpenBSD ksh and ash, line-buffer/history ergonomics from fish and zsh, optionality from Oh My Zsh, and explicit prompt cost budgets from Starship. MASTER keeps Reline as the line editor, does not grow a plugin/theme framework, and keeps detail behind explicit status/help commands.

The prompt budget is deliberately hard: one Git status query with a 150 ms subprocess limit and a short-lived 250 ms cache; long branch names are truncated before they can push the working line around.

#### Source closures from the 2026-10-02 runtime trace

The source-level failures from the Mac trace are now closed: /fix preflight has an independent safe unwrap for whole-file transport tags; natural-language analyze STUDIO/lora is a deterministic review route; /face takes a dedicated /dev/tty; failed audio playback falls through to the policy-mapped native Mac voice; and monotonic capability reduction is executable law with a regression test. Remaining proof is hardware/deploy evidence only where the checklist below explicitly names Mac or vm23.

#### Remaining proof

- Run `/fix MASTER RAILS OPENBSD STUDIO` after these changes and verify the clean Ruby preflight plus no transport-wrapper findings.
- Exercise `analyze STUDIO/lora`, `/status`, `/status security`, `/status services`, `/voice status`, `/face`, and one real speech turn on the Mac.
- Run the prompt/scan/voice contract suite on vm23 for provider and hardware-dependent behavior.

### Instruments and /fix — found 2026-09-25

- **21 ratchet rows are off.** `bin/operator measure` on 2026-09-25: 19 OVER
  and 2 SLACK, and `file_length` and `coverage_ratchet` unreadable. The
  largest are `spine.lib_body_ceiling` 47837/35302, `autofix_reach.bare_true`
  238/0, `growth.master` 749/646, `self_findings.law` 300/230,
  `growth.rails` 1986/1932 and `growth.master_tools` 100/69; the slack rows are
  `rule_reach` 14/70 and `rule_audit.silent` 39/43. None has been shown to be
  a spelling defect; the growth is several sessions' at once, which is why no
  one session has owned the raise. Per row: `bin/operator measure --why
  <row>`, fold what folds, then one sponsored raise naming what the rest buy.
  `spine.lib_body_ceiling` has no raise left (`consecutive_raises_allowed: 2`
  is spent), so a deletion pays for it first, and that is the operator's; so
  are the two slack locks, which sit in `data/rules.yml`. Read the numbers
  from `measure`, not from here — they move every few hours. Done when
  `measure` exits clean or each off row names its decision. A second seam
  from the 2026-09-23 pass belongs with it: `measure` could print the entry
  that owns each ceiling, so a red row points at a record instead of at
  nobody. Closed 2026-09-26: non-clean measure rows now print the source record
  that owns each ceiling.
- **The rules.yml trim draft was lost, and it can be rebuilt.** A draft that
  retired rules which fire on nothing, reach no configuration or misread
  their subject never reached a commit. Rebuild it as a diff from
  `bin/operator measure --why rule_reach` and `--why rule_audit.silent`, plus
  `duplicate_code` (0 of 25 samples were duplicated code) and the unread
  `biases` and `principle_priorities` blocks. Done when the diff sits in the
  operator's hands with one line of evidence per removed rule. Operator:
  `data/rules.yml` is immutable to agents, so he applies it.
- **/fix's own weaknesses.** Two surfaced on 2026-09-25. Detectors with high
  false-positive rates cost every pass: `CQS`
  (`lib/review/scan/rules/structural_rules.rb`) flags any method that writes
  an instance variable and has an explicit `return`, so guard-then-assign
  memoisation fires while `||=` does not; sample five findings per noisy rule
  and fix the rule, as the refinement section says. And the 2026-09-25 RAILS
  run lost its one applied repair to stagnation detection, not to the proof:
  `fix0: oscillation, pass 2` previously fired after the stream stage had applied a
  repair. The stream now refreshes touched findings and marks pass progress before
  stagnation logic; the CQS corpus and stream regression are executable contracts.

### Operator decisions

- **Whether the one scheme keeps an accent.** `vertical_accents` gives each
  vertical its own ink, and most of `magic_hex` and `contrast_below_aaa` is
  `--danger`. Decide whether one accent survives for interactive affordance; a
  link without colour needs an underline. Both ratchets count RAILS.
- **tv and maps hover fills fail AA under the vertical ink** (3.34 and 4.31
  against 4.5) and reach no pixel until their hover is wired. Pick the colours
  before wiring them; `$vertical-accent-ink` in brgen's `application.scss`
  records the measurement.
- **dilla is fenced, because it renders audio.** Narrowing dilla's
  `SILENT_RESCUE` sites.

### Needs vm23

- **One `MASTER/Gemfile.lock` for the Mac and the box, in a watched deploy.** The
  repository side is closed 2026-10-01: `MASTER/Gemfile` uses `install_if` for
  platform watcher dependencies, the lock records the supported watcher gems
  and complete checksums, `flay` is absent, and the dead `head_music` chain is
  gone. Apply during a deploy and verify with `rcctl restart master` and
  `vps state --remote` reading `tts_socket=true`.
  - **`rb-edge-tts` is now a released RubyGems dependency, exact-pinned at 1.0.1.**
    The Git checkout failure class is removed from the normal boot path. It still
    pulls EventMachine 1.2.7 into the `:tts` group for `bin/tts-worker`; keep
    that group isolated and verify `Speech.edge_tts_ready?` still works as a
    spawn probe rather than a boot-time `require`.
  - **`:dilla` no longer pulls `head_music` into the constitutional lock.** Closed
    2026-10-01: no live caller used the `DillaMusicGems` pitch-class adapter,
    so the dead integration was removed and its ActiveSupport/i18n/tzinfo chain
    disappeared from `MASTER/Gemfile.lock`. The dependency test pins the lean
    Dilla group and rejects the retired packages. Watched vm23 bundle/restart
    proof remains open.
  - **MCP compatibility is now on RubyLLM 2 + MCP 1.6.** The former
    `ruby_llm-mcp` compatibility item is resolved on `main`; keep the
    provider-key contract tests covering the current RubyLLM API.
- **After the next deploy, confirm `.master/tts-worker-*.log` stay
  `master`-owned.** `cable_bridge.rb`, one path a root `assets:precompile` could
  build a container through, is deleted, and `MasterContainerLoader.ensure!`
  refuses under an assets task. If the logs turn root again, the writer is
  elsewhere.
- **Deploy hazards.** Never stash the box's locks to fast-forward; a plain
  `git pull --ff-only` succeeds with them dirty. relayd has died mid-deploy with
  every app port open (`curl 000` on all hosts), so run `rcctl check relayd`
  after any deploy that restarts master.
- **What the 2026-09-14 merges carry to the box.** `MASTER/web/Gemfile.lock`
  drops `solid_cable`, so check the box's copy of that lock is clean before
  `git pull`, and MASTER web runs a migration dropping `solid_cable_messages`.
  brgen runs a migration that nulls orphaned `dating_profiles.neighborhood_id`
  and adds the foreign key. `nsd-resign` now reads `NSD_ZONES_DIR` and
  `renew-certs.sh` reads `RENEW_CERTS_ACME_CONF` and `RENEW_CERTS_SSL_DIR`, each
  defaulting to today's path, from the next `OPERATOR.sh` install.
### The faces, the ear, and TTS on the box

- Closed: `agent:mood` has a producer in `Homeostat#observe`, with the browser relay and event-bus contract covering the listener path.
- **The /face ear is unproven on a phone.** `lib/cli/face/ear.rb` streams a
  Termux microphone through PulseAudio's OpenSL ES source into whisper.cpp,
  and `lib/device/setup.rb` installs `termux-api sox ffmpeg pulseaudio` and
  builds whisper from source; `termux-speech-to-text` is the fallback. None of
  that has run on a real phone. Done when one Termux session hears a
  Norwegian and an English phrase through the streaming path, and the setup
  either builds whisper.cpp on the device or names the step that failed.
  Operator: the phone.
- **The web and terminal faces differ, and only the terminal says they
  should not.** Runtime event-bus parity is closed: the terminal subscribes to
  `llm:**`, `pipeline:**`, `phantom:**` and `council:**`, maps existing events
  into bounded motion reactions, and unsubscribes when the window closes. The
  `face/depth_map.rb` copies `generateFaceDepthMap` by hand; nothing on the web
  side points back, and nothing checks the copy. The terminal echo guard is
  now explicit and regression-tested: the ear only arms in `:idle` with an
  empty draft, and the post-listen cooldown prevents immediate re-arming.
  Measured 2026-09-25, in the order to close them. Behaviour first, no look
  involved: a failed turn is lost where the web queues it
  offline; and the web face lacks the terminal's
  `IdeaPicture` after a reply. Neither face plays the voice bed that
  `Voice::Policy#bed` declares. Then a test that paints both depth maps from
  one seed and compares them. What changes the look waits for the operator:
  state tint and mood colour, visemes beyond one mouth value, the provider
  chip, council lanes. Photo upload and camera vision are the browser's by
  nature and stay there. Done when each gap is closed or argued beside the
  code, and the depth-map test holds the copy.
- **vm23, after the next deploy:** re-probe the one-shot Edge fallback
  (`synthesize_edge_oneshot`) with a real MP3 write, and `test -S
  .master/tts.sock`; `/health` alone is a capability check.
### Tag legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise,
  horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## RAILS

### Instruments — found 2026-09-25

- **Historical: 7 of 132 was the 2026-09-26 measurement; stale after the latest Rails/defaults work. Re-run the current 131-file suite.**
  Measured under the historical pinned Ruby on 2026-09-26, down from 23. Every remaining failure is
  a CSS value or a stylesheet's size, so each is the operator's or the brgen
  CSS pass's: `breakpoint_lint` (a 1024px edge in brgen), `css_coverage_lint`
  (13 classes the markup asks for and no sheet defines — store-promo-*,
  author, msg-action, amber-look, dating-heart-* — and 22 more unused
  selectors), `gate_live_and_css_budget` (css_constitution over its magic_hex,
  type_scale, weight_ladder, child_margin, leading and flat_ui ceilings in
  brgen's marketplace block), `scale_lint` (off-scale spacing, leading and
  opacity in brgen, amber's 1.05 display leading, face opacity 30 against
  29), `vertical_consistency` (dating and tv widths), the `--bol-blue` literal
  in `marketplace_bol_visual_contract`, and `file_length_ratchet` (brgen's
  and amber's application.scss, seeds.rb, bergen_demo_data.rb, and
  dintero_checkout.rb with no ceiling). Two orphans feed css_coverage:
  `shared/_storefront_promo` (301184080) and `dating/home/_heart` (unrendered
  since 05f97fdd3) render nowhere. Done when `ruby RAILS/test/run_all.rb`
  exits 0.
- **Rendered gates measure nothing on a fresh checkout.** `RAILS/bin/triangle`
  runs brgen's `db:prepare` (`Triangle.migrate`, unbounded) before it boots
  the server and waits `BOOT_TIMEOUT` (180 s) for `/up`. On a new worktree
  the prepare is too slow to finish in any session's patience, so brgen never
  answers and every rendered gate reports inconclusive. Inconclusive is honest — `runner.rb`
  exits 3 — but it means no layout claim from a worktree has been measured.
  Half done 2026-09-26: `RAILS/bin/triangle up bsdports` boots one app, 120 s
  on a fresh worktree, and then `flow_journey` runs 3 of 26 journeys and
  `rendered_suite` measures 29 bsdports cells. What stays inconclusive, and why:
  `web_vitals_budget` reads only brgen; `visual_contract` navigated none of 24
  states even with `VISUAL_CAPTURE=1` and bsdports up, and its run rewrote the
  tracked `visual_contract/brgen-manifest.json` while measuring nothing;
  `deploy_drift` compares deploy stamps under `/var/db/pub4`, which exist only
  on vm23, so it is inconclusive off the box by design. What bsdports alone
  showed: the sign-in and password fields render at 9px on a phone, so iOS
  zooms on focus (a rendered value, the operator's), and the home snapshot
  drifts because the baseline was taken on an empty database and db:prepare
  seeds ports. Done when brgen boots the same way within a few minutes.
- **CSS budgets raised on 2026-09-25, for the operator to review.**
  `MASTER/gates/data/css_budget.yml` moved brgen 203→215 KB, amber 108→110 and
  bsdports 64→66, naming the design work each raise pays for: Radio
  discovery, the storefront promotional art, three marketplace layouts, the
  ambient chat desktop and the Material 3 bubbles. The raise was named rather
  than absorbed, but it is a raise. Operator: keep the ceilings, or say which
  surface gives bytes back.

### Audit findings — 2026-09-12

- **ruby_llm is one major version behind its only fix, and the ignore in
  `shared/config/bundler-audit.yml` is what stands in for it.**
  CVE-2026-67991 (ReDoS in `RubyLLM::Utils.underscore`, High) has no patched
  1.x: the advisory says `>= 2.0.0.rc1`, and 2.0.0 final shipped 2026-09-18 —
  the entry's own trigger has fired. It blocked every app deploy on 2026-09-16
  until the ignore landed. The entry argues the advisory cannot reach this tree —
  it is scoped to Ruby 3.1.x, while the repository now pins Ruby 4.0.5, and no user-supplied string ever
  becomes a class, agent or tool name here — but an ignore is a standing
  claim, not a fix. The RubyLLM 2.x migration is now the live baseline across
  MASTER and the Rails apps; keep service and provider-key contract tests
  proving that API rather than carrying an old `ruby_llm-mcp` compatibility
  plan. MASTER's `lib/io/ruby_llm_patch.rb` remains its own seam —
  monkey-patches `RubyLLM::Models` internals and carries 16 Tool classes, so
  it wants its own worktree run of `test_ruby_llm_patch.rb` and the
  dispatcher suite. Note the ignore's prose names only brgen and amber at
  1.16.0 while MASTER root (1.13.2) and web (1.15.0) are equally unpatched
  1.x — the argument covers them; the comment does not say so.

- **`constitutional_scan` is over shared's ceiling, and what is left is a
  design value or the scanner's reach.** On the aesthetic profile the budget
  counts, shared reads 11 against 8 and bsdports sits at its 3, the jox-logo's
  artwork coordinates. shared's remainder includes tiptap's 30px and vendored
  CSS, which only MASTER's scanner or its pen allowlist could exempt, both on a
  sacred path. The operator decides: change the values, or record new ceilings
  with a reason in `MASTER/gates/data/constitutional_budget.yml`.

### Instant — what the operator still decides

The "134 ways to feel instant" intake, once `RAILS/INSTANT.md`, closed on
2026-09-13. What was already built and what the tree refuses are both recorded
in `RAILS/shared/WIRING_NOTES.md` under "Speed proposals decided against". What
is left changes how a surface looks, or needs vm23.

- **Motion is a rendered value.** Cross-document view transitions (feed to post,
  the theme crossfade); Turbo's progress bar delay, set to 100 ms in
  `shared/frontend/hotwire.js` against Turbo's 500 ms default; feed skeletons
  shown only past ~200 ms; `:active` states; and `transition_normal`, 300 ms in
  `shared/design_tokens.yml`, against a proposed 200 ms ceiling.
- **Resolved 2026-09-25:** rejected optimistic like/vote actions now roll back
  and show the localized shared error toast. Cable disconnect feedback remains
  a separate open item for the client connection surface.
- **Resolved 2026-09-25:** responsive feed images now opt into the existing
  blurhash decoder while retaining responsive WebP/srcset delivery.
- **Needs vm23.** A p95 server-time ceiling per route means something only when
  measured on the box, warm and cold; and whether relayd serves HTTP/2 or
  compresses anything is a man-page-then-measure question there.
- **Seller payouts need money.** One Stripe Connect account per seller and a
  platform balance; `Marketplace::Payout` fails closed and stays pending with a
  reason until then.

### Deploy blockers

What stops a RAILS deploy from being one command. A blocker leaves when its
unblock criteria are met. Operator-side debt is the OPENBSD section.

**1. City vanity TLS** — operator; registrar action. Blocks the first install
of a new city apex, not deploys of the live apps. `OPERATOR.sh` stage 1 issues a
certificate for every apex in `ALL_DOMAINS`, and relayd will not load a keypair
whose certificate is absent — a `relayd.conf` naming one downs every site on the
box. Unblocked when every apex resolves and serves its own certificate and
`relayd -n` passes against the repo copy on the box before install.
`domain_alignment` checks the four live apexes.

**2. relayd restart after route changes** — operator. Built; open until a real
deploy exercises it on vm23. On 2026-08-10 a restart killed relayd's `ca`
process and every site for nine minutes, seconds after the deploy logged
`relayd(ok)`. `relayd_confirm_live` in `RAILS/_service.sh` re-checks 443 for
20 s after the restart and names the shape: 443 refused with the app port
answering is relayd, both refused is the app.

**3. bsdports stays down after its own deploy** — agent; fixed in source, needs
vm23 to prove. On 2026-09-15 two single-app deploys of bsdports (`02a056827` and
`86437202a`) passed CI, restarted and exited 0, and `vps-state` then read
`bsdports(failed)` with :47312 closed; `doas rcctl restart bsdports` brought it
back each time and it served. The rc.d flag had covered only the restart's
`/up` wait, so `resource_guard.sh` counted strikes through CI, migrate and
precompile and shed the first optional service, which is bsdports.
`vps-deploy` now holds the deploy flag for the whole deploy and runs `rcctl
check` on its own app before stamping it ok. A
deploy whose last app is down on exit is not a deploy. Unblocked when three
consecutive `vps-deploy bsdports` runs on vm23 leave it `ok` with the port open. amber's post-deploy `page_simulation` and
`flow_journey` fail meanwhile whenever bsdports is shed, and pass rerun once it
is up.

## OPENBSD

### Operator debt — still open

Each item carries a hidden HTML-comment marker on its own line under its heading;
`MASTER/lib/operator/operator_docs.rb:55` counts those markers for the
`MASTER/bin/operator status` debt line, so keep exactly one per open item.

#### `libvips_local_build`  — tag: operator-priority

<!-- open-debt -->

vm23 runs a locally built libvips with svgload; `pkg_add -u` swaps in the stock
package, which has none, and amber's garment cut-outs quietly stop regenerating.
`/etc/daily.local:71` detects it. After any `pkg_add -u` touching graphics, run
`make reinstall` in /usr/ports/graphics/libvips and confirm `vips -l` lists four
svgload operators.

#### `off_host_dr`  — tag: operator-priority

<!-- open-debt -->

One purchase, an off-host object store, closes three gaps. `OPENBSD/bin/dr-pull`
keeps seven verified pulls, but on the operator Mac. `MASTER/tools/dilla/samples/`
(84 MB, 75 MB of it `own/` recordings) is gitignored and on one disk, and dr-pull
cannot help because the crate is already on that disk. `Shared::DatabaseSnapshotJob`
writes `VACUUM INTO` copies beside the database, and `restore_litestream.sh` restores from
an empty litestream directory. litestream is absent by decision (not in ports).

#### `multi_app_ram`  — tag: operator-priority

<!-- open-debt -->

A provider resize of vm23; done when `sysctl hw.physmem` reads at least
2147483648 (1056952320 on 2026-09-11). The standing decision is 1 GB with one
resident worker, brgen_jobs. Reproduce a start by hand only with
`--health-check-timeout 300`, and do not stand a job worker down before
`bin/vps-deploy`, which does it.

#### `home_partition_full_from_git_history`  — tag: operator-priority

<!-- open-debt -->

A coordinated history rewrite: strip the 80–87 MB WAV renders under the old
`DEPLOY/dilla/renders/beats/` and the key purge in one force-push, with a vm23
re-clone in the same hour and every session quiescent. Not pressure: /home was
69 percent on 2026-09-11.

#### `bsdports_org_delegated_to_parking`  — tag: operator-priority

<!-- open-debt -->

Half done, measured 2026-09-26: the .org registry now delegates to ns.hyp.net
and ns.brgen.no, and ns.brgen.no answers 46.23.89.226. But ns.hyp.net itself
still serves Domeneshop's parked zone — NS ns1-3.expireddomain.hyp.net with a
six-hour TTL, A 185.134.245.114 — so resolvers that ask it cache the parking
page and this does not clear with time. At Domeneshop, make ns.hyp.net serve
the real zone (secondary from ns.brgen.no) or drop its parked copy; the
registration is paid to 2027-08-08. The deadline is the certificate
(`notAfter=Nov 10 2026`), because acme-client's HTTP-01 needs the name to resolve
here. Done when `ruby MASTER/gates/runner.rb dns_zones` passes. `ALLOW_BSDPORTS_DOWN=1`
on the uptime-check crontab line comes off the same day; `bin/deploy-smoke.sh`
names the delegation until then.

#### Four lapsed .uk cities — tag: operator-priority

Nominet reads brmingham.uk, glasgw.uk, lverpool.uk and mnchester.uk as
"Renewal required", expired 24–25 June 2026 and unrenewed three months on,
which is past Nominet's usual 90-day window, so treat them as abandoned. They
cost dns_zones nothing (it reads LIVE_DOMAINS, not ALL_DOMAINS) but still carry
nsd zones and acme-client blocks. Operator: renew them, or drop them from the
DNS source. `OPENBSD/RUNBOOK.md` says none has NS records at its registrar;
Nominet lists ns.brgen.no and ns.hyp.net for all four. lndon.uk was newly
registered at Domeneshop on 2026-09-23, delegated to both, and is not yet in
LIVE_DOMAINS.

### Waiting for the box

Each of these needs vm23: a root run, a man page read there, or a measurement
only the box can take.

- **One `doas zsh OPENBSD/OPERATOR.sh` run closes the drift.** Ask
  `SSH_HOST=dev@brgen.no ruby OPENBSD/gates/config_drift_gate.rb --remote`, never a
  list; the repo is the newer side everywhere. `emergency_cpu.sh` (the only thing
  `resource_guard.sh`'s crisis tier runs), `vps_weekly_integrity.sh`, its root
  crontab line and `/var/log/pub4/` are absent, so the weekly integrity pass has
  never run. The same run lands the job workers' login.conf classes and
  `smtpd.conf`'s `listen on egress`.
- **relayd restarts five times per `vps-deploy all`.** Each rc.d script and
  `start_all_apps.sh` run `rcctl restart relayd` once an app answers `/up`,
  dropping the one TLS listener; the 2026-08-10 nine-minute outage was that.
  `relayctl poll` is the documented alternative, and `relayctl table
  disable|enable` brackets one app; neither touches the listener. Read
  relayd.conf(5) and relayctl(8) on vm23 and bracket one app by hand first.
- **vm23 carries three leftovers the repo no longer has.** Two `nsd`
  processes run where `var/nsd/etc/nsd.conf` asks for `server-count: 1`; an
  older `/usr/local/bin/nsd-resign` sits where the repo's copy (which reads
  `NSD_ZONES_DIR`) should be; and amber.brgen.no keeps a zone, its signing
  keys and a certificate although nothing in `OPENBSD/` names that host any
  more. Read nsd.conf(5), nsd(8) and acme-client(1) on the box first. Done
  when `pgrep nsd` shows one server, `/usr/local/bin/nsd-resign` matches the
  repo, and no amber.brgen.no file remains under `/var/nsd` or `/etc/ssl`.
  Operator: a console on vm23.
- **The `rails` login.conf class caps datasize at 4096M on a 1 GB box**, and
  `openfiles-cur` inherits 128. Set per-app `datasize-cur` from each app's
  steady-state VSZ measured on vm23, not RSS: brgen reads 869 MB VSZ, and a
  number guessed from RSS kills a healthy app.

## MASTER/tools

Re-measured 2026-09-11 against the real crate. `samples/` is gitignored, so a
worktree shows an empty crate that is not; dilla is under active edit, so trust
symbol names over line numbers.

### Open from 2026-09-17 session

`dilla.rb` stays the engine. The takes are named doors into it: `demo2` and
`demo3` are Bed methods reached as `ruby dilla.rb demo2` / `demo3` (the take
scripts became them on 2026-09-20), and the old demo.rb shim is gone because
a bare invoke is what it ran. Do not triplicate the engine file.

- **README.mp4 split.** Half face, half a zsh prompt that launches
  `bundle exec ruby bin/cli`, muxed with `demo.wav` under `README.wav`. Both
  takes lived in `/tmp/new_takes/` and are gone, so they are shot again first.
  `?film=1` hides the mic; `face.css` film rules are still mixed with another
  session's 44px autofix and were not committed.
- **postpro on the MASTER web UI.** Not started. The face already has
  upload; the grader is `MASTER/tools/postpro/postpro.rb --preset cinematic`.
- **Papua masks as a light 3D field.** Eligible: frontal masks with two eye
  holes (`yam_mask_papua_new_guinea`, `highlands_mask`, `malangan_mask`).
  Not eligible: the Vanuatu figure, sulka headdress, gulf full-body, profile
  bird-beaks, yam helmets without a face. No LoRAs. Same anchor space as
  `face_2d_fallback.js`, sparse.
- **CLI eyes and ears.** The browser already has getUserMedia. The TTY does
  not. `Master::Io::Sense` was not written.

### The owner's calls

- **The crate holds `drums`, `dug` and `own`, and no 124 racks.**
  `74d9e4c1b` cleared it on 2026-08-16 on the operator's call; only he can say
  whether he expected the racks back. `samples/dug/` is down to one record, and
  the other 160 sources cannot be re-fetched to the same bytes.
- **Two ways into the crate.** The engine reads `samples/chopped/loops.json`
  through `RadioChop.registered_loops`; `lib/sampling.rb` writes `samples/dug/`
  from public-domain archives; `ruby dilla.rb live dig` (`lib/livesets.rb`) rips
  YouTube into `samples/chopped/` and warns on every run. Those two are the crate.
- **`ruby MASTER/tools/dilla/dilla.rb assets` exits 1**: three loops missing, seven files
  changed (re-synthesised one-shots).
  `dilla assets record` blesses whatever is on disk, so it is the operator's.
- **Two staging directories outside the repo.** `~/dilla-crate-incoming` holds two
  source FLACs and their demucs stems from an abandoned 61-track fetch;
  `~/Music/dilla_sines/` is a running installation beside three drifted twins of
  tracked scripts. Keep, move or delete is his, never an agent's.
- **Chop rows in `TRACK_PRESETS`**, when there are chops again. A slug with no row
  falls through to `:timeless`; the `sheger_*` derivation in `dilla.rb` is
  mechanical and whether it sounds right is his.
- **`semantic-techno` is measured, not heard.** Five 16-bar renders, a 32-bar
  detroit and hate's reference sit in `~/dilla-semantic-renders-2026-09-15/` with
  spectrograms and `measure.rb`. Two readings want his ear: industrial's kick
  holds the sub 4 dB over the others, and detroit's `lift` section drops the
  sub band only 1.1 dB when the bass leaves.
- **What the techno log asked for and the renderer does not yet do.** Feedback
  is one value per render (`SpaceFx.space_echo` takes a constant), so it cannot
  move on the 16-bar filter period; a profile cannot move `hate`'s tempo,
  because `HATE_BPM` is computed at load; and the energy vector is read from a
  section's state rather than from the audio `lib/listen.rb` could measure.
  Moving `render_hate_techno` and `render_industrial` onto `TechnoVoices`
  changes both sounds and stays his call.

### Guards

- The eight `sheger_*` rows are half alive: the preset rows are live and tuned,
  the bed aliases point at a cleared chop. A test pins both halves; delete
  neither.
- The monolith stays. `DILLA_SUPPORT_CEILING` (11, in `MASTER/tools/gate.rb`) leaves no room for a
  destination file, so any split starts by folding support code, and 14 support
  files use `__dir__`/`__FILE__`. `dilla parts` indexes the engine.
- Not worth chasing, each measured: merging the three techno renderers (three
  sounds); blanket rescues in MASTER/tools (optional probes and teardown); preset reach
  in `postpro`/`lora` (selected by name from argv; `vocab_check` owns it); the 37
  stale `sample_worth.json` slugs (pruned on the next chop); the sample rate
  declared under three names (all namespaced; `sampling.rb`'s 11,025 is
  deliberate); the `cohesion.rb` regroups; the three engine probes that skip
  under suite load while passing alone; and the four hand-packed RIFF headers
  (`wavefile` loads only when MASTER's bundle is present, so a writer through it
  still needs the four-line pack as its fallback).

## The layout pass — open

**Seventeen control classes paint a border beside a fill**, from `.deal-cat`
(`_marketplace.scss:48`) to `.pager-link`, which the 2026-08-04 decision traded
away (`WIRING_NOTES.md`). Whether that decision reaches controls is a rendering
call, and the operator's. The pass's doctrine lives in `WIRING_NOTES.md`.

## From the 2026-09-01 audit

- **The browser half of the gates runs nowhere unattended.** vm23 cannot host it
  (Chrome under 1 GB sheds amber and bsdports; the argument sits beside
  `PUB4_DEPLOY_BROWSER_GATES` in `vps-deploy`), so it needs a second host.
  `GATE_STRICT_ERRORS=1` can join the deploy line once someone has read one
  ledger's worth of errored gates.

---

# Forward work

Wishes and measured proposals not yet shipped; each section is dated.

## What /fix does not yet do — opened 2026-09-16

`/fix` became the whole improvement operation that day — it observes, lets the
council argue and propose five to twenty repairs an issue, cherry-picks one per
issue, repairs, and observes again, ending as DONE, PLATEAU, VALIDATION_FAILED
or BLOCKED — and `/scan` left the vocabulary. Three pieces of the handoff were
not built, each on purpose.

- **The council's cost inside a pass is unmeasured.** It asks one panel per pass
  over up to twelve files. On a spent OpenRouter balance the free lanes answer,
  but nobody has run a full `/fix` against a real target and priced it. Measure
  before raising `CouncilRound::FILES_PER_ROUND` or the pass budget.

Two lanes of the model pool are built and unproven: Replicate has no valid key
on this Mac or on vm23, and the local OpenAI-compatible lane was proved against
a running `mistralrs serve` only to the point of a 500 from mistral.rs itself.

## Found by the backlog pass — opened 2026-09-14

The agents that worked this file on 2026-09-14 and noticed these outside their
slices. Each is a hypothesis with its seam.

### MASTER

- **The CLI's last seams.** Rotate the web token printed at boot on 2026-09-13;
  it sits in two saved terminal transcripts in `~/Downloads` (operator). With
  `CLI::Propose` gone, `Ground::BiasGuard` has no runtime caller and the
  `biases` and `principle_priorities` blocks in `data/rules.yml` are unread;
  wiring or deleting them edits an immutable file, so it is the operator's.
- Closed: `solid_queue` and `solid_cache` are active web/runtime dependencies; `production.rb` enforces their adapters and the Rails apps carry their queue/cache schemas.

### RAILS

- **Drag-only reorder** (amber outfits, marketplace variants) is closed 2026-09-26.
  The shared Sortable controller now provides visible Move up/Move down buttons,
  ArrowUp/ArrowDown movement, focus retention, edge disabling and the existing
  PATCH persistence path; Amber and Marketplace supply Norwegian and English labels.
- **The remaining parameterised guest surfaces are now reason-coded.** The page
  simulation names why `Deploy::LiveRecordIds` could not resolve a route, while
  keeping actual seedable categories visibly open until they have a real row and
  a live response. Seams: `MASTER/gates/support/live_record_ids.rb` and
  `MASTER/gates/lib/live/page_simulation.rb`.
- **A post's link embed loads the provider's thumbnail before a tap.**
  `shared/_link_embed` renders the facade image straight from the provider's
  image host, so the reader's browser asks the provider before pressing play.
  Proxying the thumbnails is the owner's call.

## The refinement inventory — opened 2026-09-11, instrument pass 2026-09-14

`ruby MASTER/tools/refinements.rb` scans every tracked file in the four trees
and groups what it finds into batches: one rule, one kind of edit, a known file
list. `--items` prints every finding, `--tree` and `--rule` narrow it. The list
is not written down anywhere, because a written copy of a scan is stale the day
it is made. Run the tool.

The 2026-09-14 pass fixed rules rather than files: `magic_number` 4,679 to
3,108, `NO_PUTS` 941 to 91, `FILE_SPRAWL` 654 to 52, `SMALL_FILES` 280 to 152,
`CONFIG_HIERARCHY` 1,007 to 138, and `TRAILING_COMMAS` 510 to 74, because the
three apps' RuboCop forbids the comma the rule asked for. Re-run before quoting
a count. What is left:

- **`duplicate_code` matches the words copy, duplicate and "same as",** and 0 of
  25 samples were duplicated code. Retiring it edits `data/rules.yml`, which is
  immutable: the operator's.
- **Lint reach that surfaces rendered values.** ScaleLint reading the `font:`
  shorthand and `clamp()` finds 22 off-scale line-heights and 1 tracking against
  a ceiling of 0. `NO_LONG_TRANSITION` on seconds and JS `duration-value`,
  `LOGICAL_PROPERTIES` on every box property and `MEASURE_OPTIMUM` at any width
  surface 27 more and take `self_findings.law` past its ceiling. Both extensions
  wait for the values to be decided.
- **`NO_GOD_CLASS` (29)** wants each class read; it is not mechanical.
- **Sampled five and right:** `DOUBLE_BRACKET` (the eight files are ksh, which
  has `[[ ]]`, and they are rc.d files, so the edit is vm23's), `NO_ASCII_LINE_ART`,
  `SILENT_RESCUE` (one kill on a dead process should name its error),
  `NO_COLUMN_ALIGN` (`.muttrc` is a misread) and `FROZEN_STRING_LITERAL` (10
  remain, seven in MASTER and three in RAILS). `TAB_CHARACTER` is down to 1;
  `DOLLAR_PAREN` and `STRICT_MODE_ZSH` read 0.
- **Geometry.** wiki and post show want geometry surfaces with seeded ids, which
  needs triangle; `void_target` and the `list_marker_hang` note live in
  `data/rules.yml`.
- **`layout_snapshot --explain`** needs a map from computed values to tokens and
  is checkable only in a rendered run; centred body text inside `main` is a
  rendered question.

### Before working any other group

Sample five findings, open the five lines, and decide whether the rule is right
before opening the sixth. Where it is wrong, the fix is the rule and the
exemption it should carry — not the file. That is how the 981-finding design
backlog turned out to be 596 misreadings of correct markup, and it is why this
section leads with the instrument rather than the total.

## One chrome — opened 2026-09-11

Operator decision: every surface wears brgen's front page chrome — its shell,
its type, its flat light palette — and any other chrome may be discarded. That
settles three questions this repo kept reopening, and it applies to the six
verticals, to amber, and to MASTER's web face.

Measured in headless Chrome at 1440x900 against the four local surfaces, which
`RAILS/bin/triangle status` already had running. Two claims died on that
measurement and are recorded here so nobody re-derives them:

- **The verticals do not lack layouts.** All six render through brgen's
  `application.html.erb` by design — the Rails engine pattern — so they already
  carry the wordmark, the nav, the search palette, the theme and the footer.
  Counting `app/views/layouts/*.erb` per engine reads zero and means the
  opposite of what it looks like.
- **The per-vertical accent is live and correct.** tv resolves `--accent` to
  `#dc635c`, dating to `#009579`, playlist to `#0e8a94`, each the
  contrast-tuned light-mode variant. An earlier reading of `#000000` was taken
  off `documentElement`, and the accents are declared on `body` — the
  instrument, not the tree.

What is actually wrong, each seen rather than inferred:

- **The browsable verticals have no content column.** On `tv.brgen.no` the
  section intro starts at x=439, "POPULÆRE VIDEOER" at x=419, and the empty
  state is centred at 720. Three left edges on one page, where the front page
  holds a single column. This is the largest visible difference between a
  vertical and the front page, and it is a container, not a palette.
- **dating is a second chrome, and it goes.** `dating.brgen.no` renders
  full-bleed with the nav hidden, a neon heart and a 200px wordmark — the
  "immersive" variant in brgen's `application.scss`. Under the decision above it
  gets the nav and the column like everything else. messenger is the other
  immersive surface; same treatment.
- **amber speaks a different language entirely.** A serif tagline against
  brgen's sans, pastel-green wordmark at roughly 1.3:1 against its own
  background, a floating "Style notes" card aligned to nothing, and a hero SVG
  whose wordmark is clipped at the left edge of its own box. Its header mark
  sat flush at y=0 — 52px of mark inside a 44px bar with no block padding —
  and that one is fixed.
- **MASTER's web face shares 13 tokens with RAILS out of 87, and all 13 are
  motion and z-index.** No colour, no type. It renders black with a particle
  face and a terminal prompt where every other surface is flat light. Under the
  decision above the face keeps its canvas and the chrome around it becomes
  brgen's. The `#primer-voice` button can go; the full-viewport `#primer`
  behind it cannot, because a browser will not start an AudioContext without a
  gesture.

Order of work: the content column first, because it is one container shared by
six verticals and it is what makes them read as one product; then amber's type
and palette; then MASTER's chrome. Screenshot before and after — this section exists because two
confident readings of the source were both wrong.

## The ad design system, and the marketplace study — opened 2026-09-11

Operator direction. marketplace and takeaway take **www.kaufland.de** as their
shell, studied against nineteen more marketplaces rather than copied from one.
Beside that, an ad design system built on photography and bold typography,
because a marketplace front page is mostly large product images and large
type — and the same system makes brgen's own ads, for the front page, the
verticals and amber. Expected to take a while and to end up automated.

The stated target is worth keeping verbatim, because it names what this is
not: **Kaufland's catalogue + bol's cleanliness + eBay's marketplace depth +
Vinted's simplicity + brgen's local and social layer** — rather than a
Norwegian Amazon.

This is a program, not an item.

### The study — twenty marketplaces, and what each is for

Research each thoroughly, and record measurements rather than impressions: a
viewport, a screenshot, the grid's column count and gutter, the type scale of
a price, the aspect ratio of a card.

- **Kaufland** — the overall shell and catalogue UX. The model for our own.
- **bol** — visual cleanliness, and the closest thing to this fleet's flat taste.
- **Allegro** — search, filtering, and handling an enormous catalogue.
- **OTTO** — merchandising and category presentation.
- **Mercado Libre** — marketplace mechanics, seller and buyer interaction.
- **eBay** — seller ecosystem and discovery depth.
- **Walmart Marketplace** — the retail and marketplace hybrid.
- **Rakuten** — marketplace ecosystem.
- **Cdiscount** — European general merchandise.
- **ManoMano** — a category-specific marketplace done extremely well; structured category expertise.
- **Etsy** — seller identity and discovery; the human half.
- **Vinted** — frictionless second-hand, and effortless listing.
- **Back Market** — condition and quality communication; trust information.
- **Shopee** — mobile-first marketplace mechanics.
- **Taobao** — catalogue depth and social commerce.
- **JD.com** — product information and logistics.
- **Temu** — discovery and conversion mechanics.
- **Zalando** — fashion marketplace and personalisation. Read this one for amber too.
- **Mercari** — extremely simple peer-to-peer selling.
- **Newegg** — electronics and product comparison.

Check every idea against the tree before calling it missing. That habit is in
this file for a measured reason: of the last external enumeration, thirty-nine
items declared themselves done and another fourteen proved already true on a
grep. A list arriving from outside is a hypothesis about this repo.

### The external Kaufland patch, assessed 2026-09-11

A fifth log proposed the catalogue redesign as one patch: a Kaufland utility
strip and an `Alle Kategorien` control, a chrome repainted white with red, a
rebuilt product card, no hero, and the filters in a persistent left rail. Its
two structural parts stand in the tree: `live_search_results` lets a caller
place the search form and the results frame apart, and
`StorefrontCardLadderTest` holds every storefront tile to one field order.

What the patch still proposes is a rendered value: the white canvas, the red
accent, `object-fit: contain` on product photography, the card's borders and
type scale, and removing the hero. The storefront pen also declares Kaufland's
two shadows, on the category shortcut well and the product buy box, as the
family's one breach of the flat rule; they stay or flatten on the operator's
word. Fenced, as the section below says. Measure the information architecture
at a set viewport and bring the look back for a decision.

### The shape to aim for

One unit vocabulary, declared once and rendered by every surface that takes
ads: hero banner, category tile, offer tile, in-feed band. Each reads
`Shared::Affiliate` or a brgen-authored equivalent through the same interface,
so a house ad and an affiliate ad differ in their source and not in their
markup. Typography comes from the existing scale rather than a second one, and
each unit fixes one aspect ratio so the grid holds.

Automation is the last step. A unit a person can fill by hand and that looks
right is the thing to automate; automating the layout first produces a
generator for a design nobody approved.

### Fenced

Every colour, typeface and crop here is a rendered value and the operator is a
trained architect. Build the structure, measure the geometry, and bring the
look back for a decision rather than choosing it.

## Bottom chrome and the peel handle — opened 2026-09-11

Fixing the walk unmasked `rendered_geometry`, which had been reporting against
the same corrupted keys. Six hard findings, in two groups, and both want an
operator decision rather than a guess.

**Three occlusions, and they are a consequence of one chrome.** On
`brgen/dating` and `brgen/channels`, the `.tab-bar-peel` handle's centre pixel
is owned by a link in the page — the dating intro's trust footer, a channel
card's blurb. Fixed chrome cannot be scrolled out from under a blocker, so the
handle is dead for the life of the page. It appeared because dating and
messenger left the immersive list and got their bottom chrome back, over
content written when there was none.

The fix is a design decision that `_tab_bar.scss` has already half-stated:
"Content and bottom-pinned chrome reclaim the space via --tab-bar-h → 0". So
the intent is that content takes the space and the peel floats above it, which
is exactly the overlap the gate is reporting. Either the peel floats and this
finding is exempt, or bottom-reaching content clears it and the clearance
wants a token of its own — the peel's height is `--tap-min` and nothing
publishes it. `.install-prompt` needed the same clearance and now spells
`max(var(--tab-bar-h, 0px), var(--tap-min, 44px))` inline; if a token is
wanted, that is its first caller.

**Three contrast failures, all one shape: an accent used as ink on a light
surface.** messenger's `#6b7fd7` on white at 3.72, playlist's `#0e8a94` on the
tunnel's `#14141a` at 4.44, and the storefront cart count, which ran Amazon's
`#cd9042` at 2.74 and the marketplace accent at 3.48 before taking `--text` at
12.63 on 2026-09-11.

An accent is tuned to be legible as a fill carrying ink, which is the opposite
job from reading as small text on white. The hover slot is not the answer
either: marketplace's `#6f6149` clears at 6.03 but takeaway's `#c26a30` is
3.89, and they share one storefront bar. What the map wants is a fourth slot —
a darkened per-vertical ink for text-on-light, the way `--food-dash-ink` was
picked for takeaway's eta chip. Seven colours, and every one of them the
operator's.

## Operator-owned, recorded not opened — from the 2026-09-11 reassessment

Two refusals from that pass stay closed, argued beside the code they concern:
`Core::Constitution` keeps its own read of `rules.yml`, and cognition phases 3
to 8 wait for weeks of real event history. What needs the box, money or a
rendered decision, and is not already listed above:

- **Per-process resource evidence.** `resource_guard.sh` sheds on aggregate box
  load, so the log never says which process took the memory. Add per-process RSS
  for the managed services, record an exited process as unavailable rather than
  zero, and change no threshold in the same patch.
- **TTS daemon ownership.** Worker logs and sockets can be created as root while
  the daemon runs as `master`. Find the writer before adding a periodic chown,
  expose `tts_socket` in `bin/operator vps state --remote`, and make health
  distinguish process-up from socket-usable.
- **The face's shader brightness floor.** Probe the live face at production
  defaults against the README-sized render and change the shader, not a
  recorder-only uniform. A rendered value: bring the number back for a decision.
- **Deep visual gates need a browser.** The measure output has CSS budget rows
  that cannot be read without one, and an unreadable row must never count as
  green. Run the deep audit only when a browser is present, keep screenshots and
  geometry as the receipt, and report unavailable as unavailable.

## Wishes, not work

Directions rather than tasks. They belong to the operator, and nobody should open
one as a ticket without asking first.

- **The face's brightness is a look, not a bug.** It renders at 0.4% of pixels
  lit, and whether that is right is the operator's eye.
- **Retire the rolling pixel baseline.** `MASTER/gates/visual_contract.rb`
  re-baselines to zero on the next run by design, so a regression reports once
  and then becomes the reference. `layout_snapshot` commits reviewable JSON —
  71 tracked files — and is the candidate for the fleet's only visual baseline.
- **replicate has no Replicate access, so the whole tool is unreachable.** Fund it
  or retire it; leaving it is the inert-wiring defect with a price tag.
- **One box per city rather than one box for every city.** brgen's verticals are
  already engines and vm23 sits at its capacity ceiling, so a cell per city is
  the shape that scales. It is a business decision before it is an architecture.
- **MASTER should judge its own edits to the constitution**, with the diff
  attached — the governor governed. The constitution should also be short enough
  to read in one sitting and complete enough that nothing outside it governs.
- **Aegis's drift model is the one buildable piece** of the section below: a pure
  function from entry position, sea state, current and elapsed time to a
  probable-position ellipse. Everything else there waits on hardware.

---

## In-depth refinement — what survived 2026-09-14

Opened 2026-09-11 as a numbered inventory across the four trees. The 2026-09-14
pass closed the OPENBSD lists and the RAILS larger-than-a-sitting list by doing,
measuring or arguing each item (comments beside the code, the OPENBSD Refused
list and `RAILS/shared/WIRING_NOTES.md` carry the arguments). What remains needs the
operator, vm23, a browser or the dilla owner. Numbers are kept for citation.

### MASTER

5. **Operator: the Pixel Field palettes reach the chrome.** `topologies.yml` `palettes.operator.accent` is the fallback in `master_events.js#paletteForProvider`, which `visual_bridge.js:220` writes to `--master-accent`, which colours `.provider-chip` (`face.css:643`). Decide whether the chip takes a canvas colour or a CSS token.
8. **Operator: `soul.yml` is the last duplicate voice and still names `bin/cli` sacred.** `voice:` and `negotiable.tts_voice` repeat `voice.yml` `neural:`, and `absolute.sacred_paths` lists `bin/cli`. The file is `paths.immutable`, so both one-line edits are yours.

### MASTER — web face

141. **Operator: the FOUC guard's colours.** `index.html.erb` keeps `data-theme="dark"` and three inline `#000` rules as the paint before `face.css` loads. They move with the stylesheet, and the values are yours.
145. **vm23: `face.modules.bundle.js` is built and loaded by nothing.** `face.js` imports modules through `MASTER_ASSET_PATHS`; only the rake task, `face_boot.test.mjs`, `script/ci_web_probe`, `OPENBSD/etc/rc.d/master` and the OPENBSD deploy scripts name the bundle. Removing it edits rc.d, so do it with a `rcctl restart master` watched on vm23.
152. **Operator: the dashboard is a second chrome.** `views/dashboard/index.html.erb` links `/face.css` and draws its own panels. Fold it into the face or give it brgen's shell; either changes how it looks.
239. **vm23: CSP is report-only.** `content_security_policy.rb` enforces only when `PUB4_CSP_ENFORCE=1`, and only `OPENBSD/etc/master.env.sample` names it. Check `/etc/master.env` on vm23, set it, reload the face, and read the console for refusals before keeping it.

### RAILS — brgen core

Closed 2026-09-13 by doing, measuring or deciding; the declined proposals and
their reasons are in `RAILS/shared/WIRING_NOTES.md` under "Declined, with the
reason". What is left needs the operator, vm23, a browser, or is larger than a
sitting.

**Operator — the look.**

- **`.page-header` is five different elements across the verticals.** Measured
  at 1440px on 2026-09-12: absent on markedsplass and playlist, 0px wide on
  dating, 747px on takeaway, 600px on tv, and brgen's front page uses
  `.feed-header`. The contract in `shared/README.md` describes an element four
  of seven surfaces do not render. Whether the contract or the verticals are
  wrong is a layout call.

**vm23.**

- **After the next deploy, check:** a signed Stripe test event returns 200 at
  both `https://<city>/webhooks/stripe` and the markedsplass host; a Vipps
  checkout redirect lands on `*.vipps.no`; `/deals` with a badged deal; a kitchen
  status button redirects; editing a dating profile keeps its photos;
  `/etc/brgen.env` carries `VIPPS_CLIENT_ID`; `curl -I` shows `Server-Timing`
  under relayd's 8 KB header limit; migration `20260913140000` ran; after an
  amber drain, `SolidQueue::BlockedExecution` and `Semaphore` rows are not left
  behind; bsdports' next import rewrites every port's distfiles flag.

**Needs a browser or triangle.**

- **Signed-in personas** (`GATE_ADEQUACY.md` gap 1) need a seeded fixture user
  in triangle.

### OPENBSD

1062. **`.dash-stats dl` wants auto-fit and could not be verified for it.** Amber's
     stat grid is four columns, two below md, and nothing between — a tablet gets
     the phone grid. `repeat(auto-fit, minmax(<floor>, 1fr))` computes the count and
     adds the three-column step, which is the right shape. It was written and then
     reverted on 2026-09-12: the floor has to be measured against the real dashboard
     container, that page is behind a login the CDP probe cannot reach, and a floor
     guessed wider than the column silently drops desktop from four columns to
     three. Measure the container, then set the floor.

### MASTER/tools — dilla

Re-measured 2026-09-13. What is left accepts a changed input, so it is the
operator's:

859. **The crate on main disagrees with `data/assets.json`.** `DillaAssets.verify` there: `samples/{kembara_rindu,lo_borges,semua_untuk_mu}/loop.wav` missing, and seven one-shots under `samples/drums/` changed hash at the same size. Restore them, or `dilla assets record` to accept the new drums as the inputs.

### MASTER/tools — postpro, replicate, lora

907. **Chains are ungraded by default.** `generate` applies `HOUSE_POSTPRO` (`portrait`); `chain` grades its final frame only when `--postpro` is given or the last stage names a `postpro`. Whether chains share the house grade is a graded-look call.
926. **`lora/guides/*.m4a` are tracked TTS output** beside their `.txt` scripts. Keep them in git or untrack them; either is the operator's.
931. **`lora/_toolkit/judge_thresholds.yml` was calibrated on seven images;** `ragnhild/dataset/` now holds six. Recalibrating moves the quality floors.
932. **What the photography triage left open.**
   - postpro's one-shot path, which is the one replicate uses, skips the camera-profile pass that `process_file` runs. Adding it changes the graded look, so it is the operator's.
   - A chain's provenance names no model version, because MASTER's `replicate_client` predict returns none. It waits on that client.
   - Postpro on video is deep work: an ffmpeg path beside the vips one, a grain seed held steady across frames, halation that does not crawl, optional period artefacts (gate flicker, weave, telecine), shutter-angle emulation, one graded frame applied to all, a per-minute budget, and a stills-and-video parity test. The comment above `POSTPRO_USAGE` in `postpro.rb` states what a replacement must hold.
934. **Melody research for dilla, 2026-09-14.**
   - **Arch or falling phrases dominate.** Arch and falling contours beat V shapes and rises, and phrase-final notes last 1.58× the average (Essen corpus, PMC3174665). dilla's inverted and retrograde motif transforms can produce the rare shapes, and every sustain is gap × 0.82.
   - **Short, low-surprise, repeated phrases survive oral transmission** (β −0.30, −0.24, +0.09; PMC5403935).
   - **Surprise pleases after predictable context and displeases in unstable context** (Cheung 2019; Frontiers 2023, fnins.2023.1209398). dilla's melody is scale-locked, with no placed surprise.
   - **Human melodies are about 0.74 chord tones, not 1.0** (ar5iv 2001.02360). dilla adds a flat +0.3 per chord tone, with no target share and no beat weighting.
   - **Generated music fails on structure.** Mid- and long-range repetition runs 0.18 and 0.12 against 0.36 and 0.35 real (ar5iv 2008.01307). Raw metric targets track listeners poorly; distance to a reference corpus tracks them better (arXiv 2511.07268).
   - **Rules to encode:** peak mid-phrase; a held final note; big upward leaps in the low register, then a stepwise descent (jazzomat); one late surprise per phrase; a chord-tone share of 0.65–0.75; judge renders against dilla's own catalogue with MusDr or melody-features.

---

## Wiring, type and Rails leftovers — the 2026-09-11 second pass

Worked 2026-09-13 and 2026-09-14. Refusals are in `MASTER/AGENTS.md`, Refused, and
`RAILS/shared/WIRING_NOTES.md` ("Toggles redirect", "System tests stay on
Selenium").

### The operator's — behaviour the face or a page shows

2. **Face event vocabulary drift.** Fixed: `face_semantics.js`, `topology_registry.js`, and `data/topologies.yml` now use the published `phantom:*`, `pipeline:stage_*`, and `council:*` topics; the event-bus census and web UI contract test reject the obsolete aliases. Rebuild the face bundle at `assets:precompile` and run the browser gate on the real checkout.
29. **Identity, reputation, neighbourhoods and mentions are models without an inlet or a page.** `IdentityAssurer` is called only by a test; `IdentityAssurance` has no reader outside its model file, and `ReputationScore` is written by `content_score.rb` and `trust_score.rb` and read by nothing but tests; `Neighborhood` is read by dating profiles and the demo seeder; `Mention` rows are written by `Shared::Mentionable` and shown nowhere. Every one has a table behind it, so each is a product call per model.
R12. **Dating prompt order.** Prompts have a model, create and destroy routes, and a list on the card and the likes page, but no view creates one, so there is nothing to order until one does.
R23. **Native `<dialog>` for confirms.** The dating match overlay is a celebration card rather than a confirm. The report confirm, the takeaway cancel and amber's "let go" would each put a new modal surface on screen, and how it looks is the operator's.

### The operator's — each changes how a page looks

55. **Reading surfaces that do not wear `.prose`:** legal (`legal-prose`), mailer, listing description (`66ch` literal), dating bio, errors. Joining `.prose` brings measure, hanging, hyphenation, `text-wrap: pretty`, orphans, oldstyle numerals.
64. **Measures in px:** `.page-header` 660, bsdports header 660/62ch, amber `.item-detail` 700, playlist 720, forms 480/584, splash tagline 28em, errors 30em, print `.prose` 100%. Chrome widths (map HUD 280/320, dressing room 420, `--feed-max`) stay.
78. **Scale and rhythm:** `--line-height: 20px` absolute; `--text-display` is a ninth size and H1 is 1.75× body against a 2.0 law — decide which token is H1; `font-size` 1.17/0.92/0.6em; two paragraph rhythms; 500/700 weights unused; legal 1.62 and mailer 1.55 leading; `.post_body` 1.6 against `.prose` 1.5.
86. **Tracking:** `--tracking-tightest` (−0.03em in `shared/_typography.scss`) on the heavy headings of brgen, bsdports and shared.
95. **Families per surface:** MASTER's face still names Inter in `offline.html` and in `face_vision_c.js`'s vision 96, beside `face.css`'s Helvetica Neue Pro label and mono stacks.
B16. **Modulor:** if H1 stays 1.75×, lower the ratio in law or raise the title token.

### Needs vm23

C24. **Checkpoint WAL before `dr-pull`** (`PRAGMA wal_checkpoint(TRUNCATE)` or `.backup`), so the off-host copy is consistent.
C26. **If `/var/log` shows `database is locked`, raise `busy_timeout`;** confirm one writer per primary with `FALCON_WORKERS` at 1.

---

## Bughunt, restructure and harness gaps — what survived 2026-09-14

The 2026-09-11 bughunt, the "one job, one door" restructure list and the two
agent-harness comparisons were worked on 2026-09-13 and 2026-09-14. Refusals
sit in comments beside the code they concern, in the Refused lists in `MASTER/AGENTS.md` and `OPENBSD/CLAUDE.md`, and in
`RAILS/shared/WIRING_NOTES.md` ("Write races on SQLite"). One trap from the pass:
SQLite transactions here are `BEGIN IMMEDIATE`, so a finding about a uniqueness
race or a rolled-back callback is false until it names a second database.

### Needs vm23

- **After the next deploy, install and check on the box:** the four app/master
  rc.d scripts (deploy flag now spans the /up wait), `resource_guard.sh` (stale
  flag after 1800 s), `/usr/local/bin/{nsd-resign,drain-jobs.sh,core-reclaim.sh}`
  and `emergency_cpu.sh`, then read `/var/log/drain-jobs.log` and the next
  `nsd-resign` run in the daily mail for a FAIL line. brgen migrates
  `20260913130000_drop_unwritten_tv_video_counters`.

## MASTER as a continuity engine — ChatGPT intake 2026-09-15

A screenshot of a ChatGPT answer proposed an objective that stays alive for
months rather than a model that stays awake. OpenClaw's pieces —
Gateway-owned persistent sessions, queued and background work, isolated runs,
cron, event wakes and heartbeat awareness — would become an explicit
constitutional system with evidence, capability boundaries, verification and
durable personal state: one memory and event spine across coding, research,
projects, household, finance, security, wellbeing, devices and personal
organisation, separated by explicit authority boundaries.

Much of it is built under other names; verify each before building on it:
`Fix::Heartbeat` (scheduled jobs, `run_due!`), `Cognition::Mind` (persistent
state over `.master/`, `tick!` and `reflect!`), `Ground::PersonalWorkspace`
(per-subject `USER.md` and `MEMORY.md`), `Ground::StandingOrders`, the event
bus.

Closed 2026-09-25: `lib/core/execution` and its state-machine, verifier,
presence, evidence, curriculum and benchmark scaffolding were removed after a
production-call-site audit found no runtime consumers; dead `ModelControlPlane`
went with it. The surviving `Core::Fold` remains the sole execution loop.

Closed 2026-09-16: `Ground::StandingOrders` is the ledger the intake asked for
— an order carries an owner, an authority domain, a wake (schedule, event or
heartbeat), the evidence each run and check printed, and a verify command whose
exit decides whether it is met, all persisted in `.master/` — and
`Tool::Domain` is the boundary, with `/orders consent|revoke <domain>` and
finance, household and devices starting off.

The fences: MASTER is never wired in as an OpenClaw or OpenCrabs backend, only
learned from; progress is command output, not a claim (`anti_simulation`); and
finance, household and devices each need the operator's consent per domain.

## MASTER as a semantic system — ChatGPT intake 2026-09-14

Checked the same day. Of 28 UI, type and layout proposals, 12 were built under
other names, 12 partly, 3 missing and 1 an operator wish; of 7 on the local
model tier and 7 on the scan ladder, most partly built. Landed 2026-09-14/15:
six rendered detectors and the snapshot's diff classes in `RAILS/gates`, the
drag `touch-action` check, `/review`'s counts, the keyless and offline local
tier, a schema-held fold every model is asked the same way, `keep_alive` and
a sized `num_ctx`, local models ranked by what fits. Not built, by the rules in
`MASTER/AGENTS.md`: a per-surface UI record or a model capability profiler with
no named reader, and an intent-to-deliver pipeline that renames stages
`/review` already has. Open:

- **Prove the new rendered detectors on vm23.** Wrapped labels at phone width,
  first-screen weight, a secondary action heavier than the primary, duplicate
  navigation and search, column width drift, an action lost in a card, æøå
  drawn from a fallback, reading type that shrinks as the viewport widens. All
  are soft. Count each surface's findings on the first run and the probe cost of
  the extra awaited script, then decide which harden. Seams:
  `MASTER/gates/support/rendered_geometry/`, `geometry_probe/glyphs.js`,
  `MASTER/gates/lib/rendered/reflow.rb`.
- **Interaction states beyond focus.** Forcing `:disabled`, `:active` and
  `aria-busy` over CDP and measuring them waits on "Motion is a rendered value"
  and the feedback items in the RAILS section. Seam:
  `MASTER/gates/lib/rendered/keyboard_flow.rb`.
- Closed: `Core::Model.offer` derives the per-turn verb and git-operation schema from `Proof#scope`, and `CoreBridge` tests verify that an unproved first turn cannot offer `done` or `git commit`.

## ChatGPT proposed forward work — intake 2026-09-11

478 items, worked 2026-09-13. About 306 were built, false or already open
elsewhere; 43 were done with a test each; about 110 were refused, with the
arguments in the Refused lists in `MASTER/AGENTS.md` and `OPENBSD/CLAUDE.md` and in comments beside the code; seven product wishes went to `RAILS/apps.horizon.yml`.
The trap worth keeping: the intake asks for a gate over mechanisms the tree has
under other names, so grep for the mechanism, never the proposal's word.

- **Rendered journeys nobody walks.** Turbo-frame navigation, focus after a Turbo
  visit, the `noscript` pager paths, and messenger reconnect keeping scroll
  position and jump-to-newest. Extend `journey_invariant`, `keyboard_flow` or
  `mobile_flow`; rendered gates run on the deploy host, not on a shared Mac.
- **Prove the new box checks on vm23 after the next deploy.** Run
  `health_check.rb --all-ready-apps`: the permission audit (`/etc/*.env`,
  `/home/*/app/storage`, tts-worker log owner) and the `df -ik` disk check must
  pass, and `/health` `deploy.git_sha` must name the booted commit. No reboot of
  vm23 has been verified end to end; do one in a window the operator picks.

## MASTER/tools/dilla mix and reference research — ChatGPT intake 2026-09-11

Closed 2026-09-13. The measuring half was built or refused, and the refusal is in
`MASTER/AGENTS.md`, Refused.
One decision stays with the operator.

- **Sound changes the intake proposed.** A `ROUGH_HEWN` or `DENSE_EXPERIMENTAL`
  profile, a mastering stage split from the mix bus, stem-group routing,
  deliberate mono-source widening, per-channel strip variance, MPC-style shift
  timing, and sample-start offsets independent of drum timing each change how a
  take sounds. Decide which, if any, to try. Seams: `lib/sound.rb`,
  `lib/sound.rb`, `lib/groove.rb`, `DILLA_STYLE_DEFAULTS`.

## MASTER web UI — future-human face — ChatGPT intake 2026-09-11

Closed 2026-09-13 except the operator's look and voice and one check that needs
a browser on vm23. The refusal is in `MASTER/AGENTS.md`, Refused: the face's design is the
operator's.

- **Morphology.** Whether the face moves toward a far-future-human form — larger
  cranium, smaller lower face, wider orbits, seeded developmental asymmetry,
  slow drift, generations 0 to 4 — and how far; and any blind test of
  recognisability or perceived intelligence. Seams: geometry in
  `web/public/face.part1-3.txt`, `VOICE_IDLE_SIGNATURES` in `face.part1.txt`.
- **Expression, motion and layout.** Continuous affect instead of named
  expressions, a motion grammar with per-region time constants, speaking motion
  kept below lip-sync, states that read without colour, and a
  face-conversation-input hierarchy on one spacing, radius and duration scale.
  Seams: `face.part3.txt`, `face.part5.txt`, `face_semantics.js`, `face.css`.
- **How MASTER says technical text.** `Speech#clean_text` drops code blocks and
  links but speaks paths, identifiers and figures nearly as written. Whether to
  respell them, and any rate, pitch or pause policy beyond `voice.yml`
  `default_rate` and `default_pitch`, is a voice decision. Seams:
  `lib/voice/speech.rb`, `lib/voice/lexicon.rb`.
- **A real-browser smoke on ai.brgen.no.** `health_check.rb` proves TTS answers
  and `deploy_smoke_gate.rb` proves `face.runtime.js` exists; nothing proves the
  deployed face paints, speaks one phrase with moving visemes, and falls back to
  2D with WebGL off. Needs a browser on vm23, where rendered gates belong.

## performance

Both 2026-09-11 performance intakes (980 items) closed on 2026-09-13: six
measured costs fixed, the rest declined as unmeasured. The rule for the next
proposal is "No performance machinery ahead of a measured slowness" in
the Refused lists in `MASTER/AGENTS.md` and `OPENBSD/CLAUDE.md`.

- **`dilla.rb live` is not real-time.** Last measured: synthesis 1.58x real-time,
  the effects chain drags it to 0.34x. Re-measure first; any speedup must leave
  the rendered sound identical, and `dilla.rb` is under another session’s edit.

## Brgen monetization

The 289-item intake of 2026-09-11 is twelve rows under `horizon.brgen.monetization`
in `RAILS/apps.horizon.yml`, fences included. One decision is the operator's and
blocks all of it: which model comes first — the intake ranked verified business →
subscriptions → promoted listings → analytics → credits, with 0% commission — and
whether the shared Commerce/Entitlements domain is worth building before liquidity.

## Tree grammar

The grammar itself is written in `TREE.md`; the Rakefile split and a MASTER
`docs/` move are refused in `MASTER/AGENTS.md`, Refused. The `MASTER/bin/` fold lives in
the MASTER sections above. One item survives.

- **Seven loose files remain at the OPENBSD root:** `OPERATOR.sh`, `_net.sh`,
  `backup_priv.sh`, `emergency_cpu.sh`, `ptr_openbsd_amsterdam.rb`,
  `relayd_prune_keypairs.rb` and `sync.rb`. The gates and most verbs already
  moved. vm23 procedures and `resource_guard.sh`'s crisis tier call some by
  path, so grep `/home/dev/pub4/OPENBSD/` on vm23 first, then move the verbs
  under `bin/` in one commit with `PATH_OWNERSHIP.yml`; `OPERATOR.sh` may stay
  as the documented door.

## dilla — measured defects, blocked on `dilla.rb`

Measured 2026-09-13 against the committed engine. Each fix is an edit to
`MASTER/tools/dilla/dilla.rb`, which another session holds dirty; none changes a sound
default unless marked.

- **Hocket voices all play one patch.** `render_hocket_lead!` calls
  `voice_stack_lead!` first, which always returns a path, so the per-voice
  `EP_GM_PROGRAMS[i]` fallback never runs; under VoiceStack every hocket voice
  picks patches from the same `seed_for("vsmodel#{voice.index}")`. The album
  signature's `HOCKET=3` is a note census, not an ensemble. Fix: pass the hocket
  index into the stack's patch seed or program. Sound change — operator hears the
  A/B.
- **`VoiceStack` plans `cutoff_scale` and nothing applies it** (`lib/sound.rb`
  plans it; the only other reader is `describe`). Wire it into
  `render_lead_voice!`'s filter or delete the field.
- **`insert_secondary_dominants` and `insert_backdoor` write one-note chords**
  (`lib/harmony.rb:351,368`). `apply_voicing` returns any chord without a
  third unchanged, and both pass it a single pitch, so `V7/ii` and `bVII7` land
  on soul profiles as a lone note unless `validate_and_fix` repairs them —
  measure that, then voice them fully or delete them. Sound change — operator.
- **Logs and provenance print load-time device ENV.** `ringtone_layer_describe`
  and the sidecar can report `COPY_MACHINE=6` on a slot `apply_album_slot!`
  forced to 0. Snapshot after the last `force_env!`.
- **Names.** `demo-all` and `catalogue` both play the catalogue, `showcase` is a
  third medley, and `demo` names only a help section. Settle on one door per
  job and alias the old names one release. No MASTER or RAILS caller.
- **A bed pass does not repeat at one seed.** `bed render seed 4242` twice on
  the same code differs by about 0.1 s in length and in the order its parallel
  renders start, so the snapshot harness cannot hold the bed to identical
  commands; its loudness and a bit-identical run are the only evidence.
  `each_parallel` seeds each item, so the drift is elsewhere: find it before
  trusting a bed snapshot.
- **No smoke test for the no-arg path.** `test_dilla_bed` checks the bed's
  source text; nothing yet runs `Bed.catalogue!` end to end with a
  two-piece order into a tmpdir and asserts demo.wav, demo.mp3 and the join's
  length. It needs a render, so it runs on a quiet machine.

## dilla — operator decisions

Each changes how a default render sounds. The first is the operator's own
direction of 2026-09-12 and waits only on `dilla.rb`; the rest wait for the
operator's ear.

- **One DNA, devices on.** Fold `ALBUM=1`'s table, `RINGTONE_LAYER` and `DILLA_FULL` into
  `DILLA_STYLE_DEFAULTS` so a single `dilla` render and a demo slot share one
  table: `HOCKET=3`, `LPG`, `COPY_MACHINE`, `VOICE_STACK`, `MIDI_BAG` (predicate
  to `!= "0"`) on; subtractive flags stay; `RENDER_MODE=album` and the other mode
  keys go. Blast radius: `Shared::DillaProcessor` renders in RAILS and its 900 s
  timeout. Gate on a 16-bar MixScore inside the keepers.
- **Demo evenness.** `DEMO_STEADY` default for the catalogue, a fixed rap
  cadence instead of `DEMO_RAP_EVERY=2`, `DEMO_TECHNO_SHARE=0.34` (a second
  renderer in one wav), one tonic family across parts, a BPM band or pulse-aligned
  joins, device rotation on coprime periods, real images for `WAV_MAP` instead of
  the generated mandelbrot.
- **Engineer colour, sourced.** Tempo-relative bus-compressor release that keeps
  LRA (Cooley/STC-8), cassette on some album grades with air at 0, a 40 Hz
  kick-gated oscillator and SPX900-style Symphonic on the dug loop (Fairall),
  independent 2nd/3rd/tape harmonic amounts on the master (HEDD), EQ before
  compression and a slow, gentle start (Daddy Kev).
- **Harmony languages.** An `esen_parallel_dorian` language (parallel m11 cells,
  common-scale-tone lead, same-function half-step resolution, fast harmonic
  rhythm) with its own HarmonyScore profile; one `delay_tension!` operator for
  Bach 4–3 and the Dilla hang; `THEORY_BACH` and the Dilla pedal gated by
  language tag instead of track-name regex and `VOICING=drop2`; Picardy and
  Neapolitan on Bach languages only; cap borrowed-chord surprises at one per cell.

- **Which of the live player's progressions to keep.** "dilla_live.rb had some
  nice chord progressions though (and some not so nice)" (2026-09-14). It played
  the catalogue: the seven verified slots, then the twelve improvisations, each
  slot on a fixed pad patch (slots 3 and 12 on `moog_bass`, 5 and 14 on `acid`,
  9 and 18 on `poly_lead`), so a progression that sounded bad may have been its
  patch. No record names one he liked or disliked. The indirect evidence favours
  `db_major_minor_fall`, `pedal_e_descent` and `d_add9_soul_arc` (promoted,
  kept takes), and among the improvisations the minor-ninth ones —
  `dilla_planing_m9`, `dilla_maj9_walk`, `dilla_slash_pedal`,
  `royksopp_dorian_lift` — which match the 08-31 cells he said "i like it" to.
  Against: the two Bach rules (plain triads), the two Flying Lotus quartal
  stacks, and slots 1 and 2 playing the same two chords back to back. His ear
  marks the keepers; a `keep` flag per slot in `VERIFIED_PROGRESSION_SLOTS` and
  per language in `DillaImprovisation`, with a pinned `IMPROV_SEED`, is where
  the answer goes.

## dilla — restructuring, 1–45 — approved 2026-09-13

The operator approved all forty-five ("APPROVE ALL", "dont forget to implement
all these"). Landed and deleted from this list: 3 (lib/ in six subjects), 11
(root YAML in data/), 14 (`sh!` for render steps, `ToolRun` for every other
tool call, each with a deadline), 33 (help from the command table), 18 (all
randomness through `seed_for`), 37 (live/ gone), 38 (scripts/ gone). Every change here must leave a snapshot identical, which the
harness in `MASTER/tools/test/support/dilla_snapshot/` proves; a row that changes
sound says so. Delete a row when it lands.

- **1. Build tables on first use**, so section order stops mattering. Unblocks
  every split.
- **2. The engine in modules**, not ~1,000 methods on `Object`.
- **4. One settings object per render** instead of ENV (1,200 reads, 224
  writes); the demo retry saving and restoring ENV is the symptom.
- **5. One precedence order for defaults**: the twelve `*_DEFAULTS` tables,
  `apply_best_defaults!`, `apply_dilla_style!`, `force_env!`.
- **6. Progression tables to YAML.** `module Bed` reads `CHORD_PROGRESSIONS`
  as a constant now, so the move no longer breaks a text scan.
- **7. One chord and progression registry**: `CHORD_PROGRESSIONS`,
  `DEVICE_PROGRESSIONS`, `ARTIST_VERIFIED_PROGRESSIONS`, `DillaImprovisation`,
  generated styles; `PAD_CHORD_LOOKUP` keeps the first name, hence the `imp`
  suffix.
- **8. One synth patch registry**: `SYNTH_PATCH_CATALOG`, the patch section,
  `lib/sound.rb`, and now the bed's families and patches in `data/bed.yml`.
- **9. One drum-grid registry**: `DRUM_PATTERN_SETS`, producer DNA, the lofi
  presets, and the bed's `samples/midi` grid banks. It also settles the snare:
  the bed rushes it, `dilla_drag` drags it (the reason sits in `data/bed.yml`).
- **10. One preset lookup**: `TRACK_PRESETS`, `profile_preset`, style defaults.
- **12. Kept records apart from runtime state in `project/`**; renders still
  dirty `session.json` and `liveset.jsonl`.
- **13. One loudness module.** Stage 1 landed: `FfmpegProbe` in lib/listen.rb
  measures, and `build_harmony_loud` and `audio_duration_sec` read a file's
  length through it. The ~20 methods that set level remain.
- **15. One output-path function.** Parts still go to `scratch/all_tracks_demo`.
- **16. One job runner with locks and signals**; `pkill` cannot stop
  `demo-all` and the lock exits 0 (see measured defects above).
- **17. A real mixer with dB staging** in place of ENV multipliers.
- **19. A cache policy for `scratch/`.**
- **20–26. Subsystem homes** for drums, leads, effects, mastering, analysis,
  rap vocals and the crate. lib/ holds six subjects; the matching sections of
  `dilla.rb` have not moved into them.
- **27. MIDI export and speech** leave as self-contained pieces.
- **28. One sequence runner** under demo, stream, showcase, album, setlist,
  live and the bed catalogue.
- **29. `live` on that runner.** It is `ruby dilla.rb live` now, not yet on a
  runner.
- **30. Retire overlapping players**: `lib/sine_stream.rb` against `live`.
- **31. Genres as parameters over one pipeline** (43 `render_*` methods); read
  all three techno renderers before merging them.
- **32. Niche renderers** (electronium, punk guitar, organic) to plugins or
  deleted.
- **34. Knob tiers**: public, expert, internal.
- **35. `ENV_AND_RENDER.md` generated from the knob ledger.**
- **36. Split the probe test file by subject**, behaviour checks over source
  text.
- **39. Real-time DSP for `live`**: effects run at 0.36–0.62x; it needs 1x.
- **40. Score first**: every renderer writes a timed event score that one
  offline renderer and the live player both play.
- **41. Text drum patterns** (`"bd*2 [~ sn]"`) in place of 16-step arrays.
- **42. Effects as chain objects with a text form**, shared by render and live;
  folds 22.
- **43. A saved session document as the render recipe**, in place of the ENV
  snapshot in provenance.
- **44. `live` as a background player** the CLI sends commands to.
- **45. Ableton Link tempo sync** for live playback.

## dilla — unbuilt opt-in devices

None exists as code, so none can be wired; each wants `dilla.rb` to read its knob,
the CopyMachine shape (`plan` → `describe` → `build!`, tests on the plan), and a
16-bar probe. Refused proposals are recorded at the end of "A hundred livesets" below,
and connecting existing devices to livesets is that section's list. In order of
leverage:

- promote `radio_chop`'s drum stem, which survives only in `scratch/chop_work/`,
  beside its rack in `samples/` (crate policy strips drums, so the operator says
  whether);
- `MIDI_BAG_TIMING=hats|kick|lead|chops` and a velocity morph;
- `GRANULAR=file` scan of a dug loop (scan position, grain size, spray; pitch held);
- a spectral resonator snapping partials to the sounding chord;
- a modal (Rings-lite) resonator on a chop;
- a named warp family on the crate (beats, tones, texture, re-pitch, complex);
- then wavefolder and 2-op FM on AnalogSynth, PitchLoop-style delay-line
  pitch, crate-sourced IR, wav_Map path morph and mip-mapped tables, MIDI
  transforms (strum, ornament, recombine, chop, note chance), weighted-next-section
  follow actions.
## dilla — a hundred livesets

Written after the three sets in `lib/livesets.rb` landed, and after the
operator said what the lost Ableton sets were made of: Goldbaby drums, a master
chain of many Sonitex instances and several Nasty VCS on *summing phasy*, one
sweet sample, and Dilla's rule — make old things sound new and new things sound
old. The sets exist to replace a life's work that a robbery took. Three is not a
catalogue, and this is the list of what would make it one.

One fact shapes most of what follows. `dilla.rb` already carries the sound
design: devices (`COPY_MACHINE`, `HOCKET`, `VOICE_STACK`, `LPG`, `BUS_PATCH`,
`WAV_MAP`, `MIDI_BAG`), section maps, four mix buses, a modulation matrix,
hundreds of chord progressions, dozens of track presets, and the support
modules under `lib/`. The three sets reach for about six of its knobs and re-synthesise from
scratch what the engine would have handed them. So a large share of this list is
not *build* — it is *connect*, which is this repo's dominant defect written down
in `MEMORY` as inert config and dead wiring.

**[cheap]** is an afternoon. **[deep]** is a project. **[yours]** is a decision
rather than work. **[risk]** changes a rendered sound and so is not mine to
choose. Numbers are for citation, not for order.

### A · The catalogue: sets to build (1–19)

1. **`vocal_chop_beats.als.rb`** [cheap] — `lib/sampling.rb` already separates
   a vocal stem and refuses any rack that cannot name its source. Thirteen racks
   can. A set built on the voice rather than the instrumental is one new file
   against work already done.
2. **`drum_break_beats.als.rb`** [deep] — `radio_chop` runs `htdemucs_6s` and
   throws the drum stem away. Keeping it gives every record in the crate its own
   break, which is the other half of the sampling tradition and currently
   discarded at the moment it is most expensive to compute.
3. **`two_deck.als.rb`** [deep] — two beds at once. `Rack.grid` already derives a
   tempo from a loop's own duration, so beat-matching two racks is arithmetic
   that exists. A DJ shape rather than a beat: one record under another, one
   leaving as the other arrives.
4. **`interlude.als.rb`** [cheap] — twenty to forty seconds, one idea, no
   arrangement. *Donuts* is thirty-one pieces in forty-three minutes. The sets
   are all ninety-six or a hundred and eighty seconds because that was the first
   number typed, not because anything measured it.
5. **`beat_tape.als.rb`** [deep] — one render containing six linked pieces with
   transitions between them: a side of a tape rather than a track. The unit the
   lost sets probably were.
6. **`spoken_word.als.rb`** [deep] — `lib/sampling.rb` exists. A bed under speech
   is the oldest form in the tradition and the one the crate is best suited to.
7. **`jazz_trio.als.rb`** [deep] — `chord_based_beats` voices its chords as
   detuned sines because that was the cheapest honest thing. `lib/harmony.rb`
   and `lib/sound.rb` and the four cached soundfonts exist. The same
   progressions through a real instrument is a second set, not a change to the
   first.
8. **`tape_loop.als.rb`** [deep] — a physical loop degrading each pass:
   `lib/sound.rb` is already written and the set would be the first
   caller that makes its behaviour audible over time rather than statically.
9. **`long_form.als.rb`** [cheap] — twenty minutes rather than three. The pad
    set is already the shape; only `TOTAL` and the swell period stand in the way,
    and a set you can leave running is a different use than a set you audition.
10. **`playlist.als.rb`** [deep] — never ends. `dilla.rb live broadcast` rotates four
    processes with hard cuts between them; a set that crossfades its own
    successor is the thing that was actually wanted.
11. **`field.als.rb`** [yours] — a bed that is a place rather than a record.
    Needs recordings that do not exist yet, and making them is a day out with a
    recorder, which is the cheapest new material this project could get.
12. **`minimal.als.rb`** [cheap] — one voice, no kit, no bed, no console stack.
    Useful mostly as a control: everything else in the room is additive and
    nothing measures what each addition is worth.
13. **`flip.als.rb`** [cheap] — `lib/sampling.rb` chops against chords and is
    one of the engine's better ideas. No set reaches it.
14. **`dfam.als.rb`** [cheap] — `lib/sound.rb` models a semi-modular drum
    voice and is likewise unreached from the livesets.
15. **`gospel.als.rb`** [cheap] — the eight-bar climb specialised: slower harmonic
    rhythm, the climb as the whole arrangement rather than a row sampled out of a
    table of four hundred.
16. **`techno.als.rb`** [yours] [risk] — the crate rules exclude industrial
    techno and the standing goal is a genre-agnostic engine where techno, soul
    and jazz are parameters rather than forks. Those two are in tension and only
    the operator can resolve it.
17. **B-side sets** [cheap] — the same seed through a deliberately different
    room. Costs one environment variable if the console parameters become data;
    see 31.
18. **Tempo families** [cheap] — the beat sets both sit at 82–104 because that
    is where the crate lands after drag. A set at 60 and a set at 140 would say
    whether the room survives outside its comfortable octave.
19. **A set per crate region** [deep] — `project/sample_worth.json` scores every
    rack on seven terms. The sets use only the aggregate. Sets keyed to *voicing
    density* or *chord-register presence* would each sound like a different
    record collection, which is what a shelf of Ableton sets actually was.

### B · The room is sitting on an engine it does not call (21–36)

21. **`COPY_MACHINE`** [cheap] — the bed played six times at once at different
    speeds, with `_FAMILY=harmonic|chromatic|spray`. This is precisely what
    `sampled_based_beats` hand-rolls with `asetrate` and three voices, done
    better, already tested, and reachable.
22. **`VOICE_STACK`** [cheap] — four voices each playing all of it, differing in
    register, tuning and timbre, with a macro that picks a model and a patch from
    212. The pad set's four-interval voicings are a poor cousin of this.
23. **`HOCKET`** [cheap] — one line split across voices with `round_robin`,
    `pendulum`, `shift_register` modes. Nothing in the livesets splits anything.
24. **`LPG`** [cheap] — a Buchla low-pass gate, measured at 17.5 dB more high-band
    fall than body over a decay. It is what makes a note read as *struck*, and the
    chord set's whole problem is that its notes read as *triggered*.
25. **`BUS_PATCH`** [cheap] — a whole modulation patch on a bus: one source per
    destination, depths biased low, at least one inverted, `BUS_PATCH_SEED` to
    pin it. Movement over ninety-six seconds is the sets' weakest dimension and
    this is the built answer.
26. **`WAV_MAP`** [cheap] — a picture read as an oscillator in the track's key.
    Not a gimmick if the picture is a photograph of the thing the piece is about.
27. **`SECTION_LAYERS=full`** [cheap] — the harmony bus leaves in the intro and in
    any breakdown over eight seconds. The sets each hand-roll one volume
    automation across a fixed bar range and call it an arrangement.
28. **`FORM_FIT`** [cheap] — stretch a form across the track rather than cycling
    it, on by default past 64 bars. The pad set at 180 seconds is four intros
    cycling and does not know it.
29. **`DILLA_MIX_BUSES` and `CONSOLE_STACK`** [cheap] — four buses and a summing
    stack measured at 23 dB less third harmonic at three stages than one. The
    sets do their own flat `amix` with hand-tuned weights that had to be
    re-measured by hand this session when the kit changed.
30. **`FROZEN_STATE` / `DILLA_FROZEN`** [cheap] — the engine's own A/B pin. The
    sets grew a parallel seed mechanism because nobody checked whether one
    existed.
31. **Make the console parameters data, not call sites** [cheap] — `Livesets.sonitex`
    and `Livesets.vcs` are invoked eleven times across three files with literal
    numbers. A named table (`warm`, `dry`, `blown`, `phasy`) turns "which room"
    into a knob, which is what 18 and most of section G need.
32. **`lib/sound.rb`** [cheap] — eight emulations, four of which measuring
    proved dead. The live rack re-implements two of the four that work.
33. **`lib/groove.rb` and `GROOVE_DNA=donuts`** [deep] — `drunk_kit`'s
    jitter figures are hand-chosen constants. A DNA table already describes this
    and would let a set be *in the manner of* rather than *approximately drunk*.
34. **`lib/ledger.rb`** [cheap] — nineteen documented knobs the sets do not read,
    so a set cannot be steered without editing it.
35. **`lib/listen.rb` and the scoring modules** [deep] — `mix_score`,
    `groove_score`, `harmony_score` and `spectral_audit` can each judge a render.
    Nothing judges a pass. A set that scored itself and refused to journal a bad
    take would make the catalogue self-curating.
    Harmony and groove are scored from the note plan, not the render; measure
    them from audio beside the loudness and width `listen.rb` already takes, with
    targets drawn from takes the operator kept.
36. **`RINGTONE_LAYER` and `PAD_LAYERS`** [cheap] [risk] — known-good layers with
    known switches, unreached from the livesets.

### C · Drums (37–46)

37. **Run `lib/sampling.rb`** [cheap] — it cuts a kit from `samples/own/` by
    running demucs and keeping only the drum stem. It has never been run: there is
    no `provenance.json`, and `samples/drums/custom/` is the downloaded
    `03-soulful-vintage`. Our own drums are one command away and beat re-buying
    anything.
38. **Re-acquire Goldbaby** [yours] — nothing on this machine is named it. The
    licences presumably survive the robbery even though the sets did not; the free
    packs would do to start. This is the single named ingredient of the lost
    chain that is simply absent.
39. **More than one sample per role** [cheap] — `LIVE_KIT` plays one `kick.wav`
    for every kick in the piece. Real machines and real drummers do not repeat a
    waveform, and round-robin over a folder is the difference between a kit and a
    trigger.
40. **Velocity, not just position** [cheap] — `drunk_kit` jitters *when* a hit
    lands and never *how hard*. Dilla time is both, and the level dimension is the
    one that reads as a human.
41. **Ghost notes from the snare recording** [cheap] — a ghost is a quiet short
    snare, not a separate file. Deriving it would remove a role from `KIT_ROLES`
    and make more kit directories qualify.
42. **The two-kick habit** [cheap] — the engine already alternates a second kick
    body (`kit[:ind_kick]`). The live rack does not.
43. **Kit-aware mix weights** [cheap] — the sampled bus gain was matched by
    rendering and measuring, by hand, once. A calibration step that measures each
    kit on install and stores its trim is the version that survives a new kit.
44. **Swing that is not jitter** [cheap] — the hat pattern adds a flat 34 ms to
    odd steps. That is a swing setting, the exact thing the comment above it says
    this is not.
45. **Name a `DRUM_LOOP` replacement** [yours] [risk] — it currently falls back to
    `~/Downloads/techno_drums.mp3`, outside the repo and against the crate rules.
46. **A kit from the crate itself** [deep] — every rack has a discarded drum stem
    (see 2). A kit cut from the same record as the bed would glue in a way no
    imported kit can.

### D · The crate, and not losing it twice (47–58)

47. **Record the source URL at fetch time** [cheap] — forty-one of forty-two
    sources are gone with no URL anywhere. This is the same failure that took the
    Ableton sets: irreplaceable material with no way back. It is a one-line change
    and it is the most important item on this page.
48. **Write provenance before the audio** [cheap] — a sidecar written first
    cannot be outlived by what it describes, which is how `henrik_debich` alone
    survived.
49. **Checksum the racks and deduplicate** [cheap] — 161 rows, 123 unique wavs, 38
    phantoms in 28 collision groups. Dropping duplicates is measurement, not
    judgement.
50. **A silence floor on the downbeat measure** [cheap] — the rotation fix for the
    153 mis-cut racks is blocked on this, because a quiet tail currently scores as
    a bar line and one rack starts at −57 dB.
51. **Then rotate the 153** [deep] — content-preserving, since a rack is one whole
    period.
52. **Back the crate up off this machine** [yours] — `samples/` is gitignored by
    path, the renders are gitignored, and the one copy of both is a laptop. The
    robbery is the argument.
53. **A crate manifest that is not the audio** [cheap] — titles, seams, keys,
    worth scores and URLs in one committed file, so a lost crate can be re-cut
    rather than merely mourned.
54. **Dig more** [cheap] — `samples/dug/` holds one file. `dig`, `dig-seams` and
    `dig-cc` exist and work.
55. **Attribution as a build artifact** [cheap] — `credits` exists. A set that
    plays CC-BY material should be able to print what it owes without being asked.
56. **Key-aware bed selection** [cheap] — all 161 racks now carry `key`; nothing
    reads it. Two decks (3) and any harmony over a bed need it.
57. **Retire `sample_worth`'s single number** [deep] — it is seven terms collapsed
    to one, and the collapse is where a set loses the ability to ask for a
    *kind* of record rather than a *good* one.
58. **A rack the operator marked** [cheap] — no way exists to say *this one*. A
    starred flag in the worth table would outrank every automatic score, which is
    the correct hierarchy.

### E · Playing them, not running them (59–70)

59. **A set should not exit** [cheap] — every set renders a fixed block and stops.
    A performance does not.
60. **Change something while it plays** [deep] — the engine already has
    `asendcmd` modulation and a `modulate` command; `MOD_RATE_HZ` names its
    resolution. The live rack builds one static graph.
61. **MIDI in** [deep] — the difference between a generator and an instrument.
62. **A pass you can nudge** [cheap] — drag, kit, weights and drop points are
    all decided before the first sample and cannot be touched after.
63. **Cue the next bed** [cheap] — `pick_bed` chooses once, silently. Being able
    to see and reject the next choice is most of what a DJ does.
64. **Mute groups** [cheap] — kit, bed, phrase, crackle. Four switches would make
    the sets performable with nothing else on this list done.
65. **Tap tempo** [cheap] — the grid is derived from the record. Sometimes the
    record is wrong.
66. **A set that listens** [deep] — `LISTEN_PASSES` exists in the engine.
67. **Two sets at once** [deep] — `broadcast.sh` runs one at a time by design; the
    interesting case is a pad set under a beat set.
68. **Stop cleanly** [cheap] — killing audio this session meant killing processes.
    A set should end on a bar.
69. **A visible transport** [cheap] — bar number, section, next change. The banner
    prints once and then ninety-six seconds pass in silence.
70. **The rig on the box** [yours] — `radio.brgen.no` is the label. A set
    rendering nightly on vm23 into the catalogue is a different project than a set
    played on a laptop, and the capacity ceiling there is real.

### F · Keeping, naming, releasing (71–82)

71. **Every take, not the kept ones** [yours] — `--keep` is opt-in and a good pass
    is recognised after it has gone. Ring-buffering the last ten renders costs
    disk and no decisions.
72. **A take is not a wav** [cheap] — `renders/live_<seed>/` holds an ignored wav
    and a tracked json. That asymmetry is right and should be stated somewhere a
    reader finds it.
73. **Replay verification in the suite** [cheap] — three determinism defects were
    found this session by rendering one seed twice and comparing hashes. Nothing
    stops a fourth.
74. **Name the takes** [cheap] — a seed is not a title. `dilla` already generates
    track names.
75. **Stems** [cheap] — `VOICE_STACK_STEMS` exists for the engine. A kept take
    that cannot be remixed later is a photograph, not a session.
76. **Export the set, not the audio** [deep] — the thing that was lost was
    editable. A take that reopens as parameters is the only real answer to the
    robbery, and the `.als.rb` naming already claims it.
77. **A catalogue file** [cheap] — `project/liveset.jsonl` is a log. A catalogue
    is the subset worth keeping, in order, with titles.
78. **Mark the three that must not be shared** [cheap] — the existing label rules
    already distinguish them and the live rig knows nothing about it.
79. **Loudness for the destination** [cheap] — every set ends in `dynaudnorm` and
    a limiter at a hand-picked `volume=`. Integrated LUFS is a solved measurement
    and lies about speech over music, which matters for 7.
80. **A sleeve** [yours] — `MASTER/tools/postpro` grades images and `replicate` generates
    them. A catalogue with covers is a release.
81. **Publish the tracklist** [yours] — `radio.brgen.no` exists and is empty of
    this.
82. **Delete nothing automatically** [cheap] — the scratchpad sweeps audio, and a
    long render that lands there is gone. Renders must be written outside it and
    be resumable.

### G · The master chain, against the one that was lost (83–92)

83. **Verify `vcs` against the plugin** [yours] — `Livesets.vcs` is `aphaser` into
    `aecho` and was written toward *summing phasy* from description alone. Nobody
    has A/B'd it against the real thing, and the operator is the only person who
    can say whether it is close.
84. **Count the instances honestly** [cheap] — the sets run five or six Sonitex
    stages and five or six VCS stages. *Tons* was the word used about the lost
    chain. Whether more is more here is measurable and unmeasured.
85. **Order matters and is unrecorded** [yours] — where in the chain each instance
    sat is not something the sets can guess.
86. **Per-channel versus master** [cheap] — the current placement is at every
    summing point, which is defensible and is not what a plugin chain on a master
    bus does.
87. **Gain staging as a measurement, not a constant** [cheap] — `vcs` carries a
    `volume=1.9` makeup that exists because three instances were throwing away
    22 dB. That is the right fix and the wrong form: it should be derived.
88. **`sonitex` runs its crusher at half strength** [cheap] — `Livesets.sonitex`
    takes `mix: 0.5` as its default and no caller passes another, so every stage
    is fifty per cent dry. Whether full strength is better is an ear question.
89. **The 1260 is a sample rate as much as a bit depth** [deep] — `acrusher` also
    carries `samples` (1 to 250, currently 1, meaning off) and an `lfo`. Bit
    reduction alone is the cheapest third of what a 12-bit sampler does.
90. **Tape before the console** [cheap] — `lib/sound.rb` is written and
    unused in the livesets, and tape is where the lost chain's *old* came from.
91. **A dry control** [cheap] — no set can be heard without the room. Nothing
    proves the room is an improvement.
92. **Measure THD, not taste** [cheap] — `CONSOLE_STACK`'s documentation cites a
    measured 23 dB figure. The live rack cites nothing.

### H · Instruments before findings (93–100)

94. **A graph that builds is not a graph that sounds** [cheap] — two defects this
    session were empty filter strings from Ruby comments inside line continuations,
    which ffmpeg reported as `No such filter: ''`. A lint over the built graph
    would have caught both before the render.
95. **`aloop` is not reproducible at scale** [deep] — proven at 1.5 million
    samples, fine at 120 000, bisected to the filter. The workaround is in
    `ambient_pads`; the boundary is unknown and the other sets sit on the wrong
    side of not knowing.
96. **Every generator needs a seed** [cheap] — `anoisesrc` seeds from the clock.
    One audit over the tree for unseeded sources would close the class rather than
    the instance.
97. **PRNG draw order is an interface** [cheap] — adding a `rand` above an
    existing one silently invalidates every journalled seed. Nothing states this
    and nothing tests it.
98. **A/B by rendering, always** [cheap] — the kit change was verified by
    rendering seed 777 against `HEAD` and comparing SHA256. That is the standard
    and should be a script rather than a habit.
99. **Level-match before judging** [cheap] — the louder arm wins every informal
    comparison, and three of this session's comparisons needed a measured trim
    before they meant anything.
100. **Ask what the lost sets sounded like, in more detail** [yours] — tempos,
    lengths, whether any were performance sets rather than beat sketches, what a
    typical one had on its channels. Four sentences from the operator are worth
    more than any twenty items above them.

### What the engine refuses

These were proposed by the Ableton, ringtone.tools, KVR and harmony intakes of
2026-09-12 and are settled. dilla does not port Plaits: sixteen engines beside
AnalogSynth, DFAM and WavMap would be a second synthesiser, so VoiceStack models
resolve to the patch catalogue instead. It does not become a Max for Live device,
host a plugin, vendor a C++ Rings, or extend the note-event contract for MPE,
because every renderer reads that contract and the musical need is met by
ornament, LPG and VoiceStack drift. Neural synthesis is out while a take must
reproduce from its provenance. A second tape model, a second SP-1200, a third
thickener, a Generate panel, a hanging-note stopper for an engine with no
note-off, particle sequencers, attractor oscillators and monitor-controller
emulation all duplicate something here or solve a problem this engine does not
have. MixScore keeps its keeper range of −18 to −15 LUFS against the beat-scene
−8.5 target, negative harmony stays blocked, Coltrane changes stay a language
rather than a beautifier, a supersaw lives only behind warp, and wav_Map never
becomes the default pad. The deleted industrial `afftfilt` chain comes back only
with a caller and a test.

## Rule candidates from the book pass — deferred 2026-09-17

The 2026-09-17 pass over Clean Code, Refactoring, The Pragmatic Programmer,
Ousterhout, DDD, Kleppmann and the type/design canon found the 242-rule corpus
already covers nearly all of it — all 22 Fowler smells, the Pragmatic
orthodoxy, and typography as measured thresholds rather than prose
(`design` config in `data/rules.yml`). Three line-detector survivors landed in
`MASTER/law/ruby.rb` (FILTER_MAP, EXPLICIT_HTTP_TIMEOUT,
MIGRATION_NOT_NULL_NO_DEFAULT). What remains needs an instrument the scanner
does not have; each is opened at the seam it needs, not as a grep.

- **TEMPORARY_FIELD** [AST] — a field set only to be read by one other method
  is a parameter wearing a costume (Fowler). Detecting it means seeing the
  write site and every read site together; line detectors cry wolf on
  legitimate memoisation.
- **PASS_THROUGH_METHOD** [AST] — a method that only delegates to one other is
  either indirection earning nothing or a boundary the caller should hold
  (Ousterhout). Needs the call graph, not the spelling; `delegate` and engine
  mounting are deliberate indirection.
- **ATTR_WRITER_SURFACE** [graph] — a writer with no reader is half an
  interface. Census must include `Gemfile.lock` dependents and vendored
  `RAILS/shared` copies on the VPS, or every engine export reads as dead.
- **NO_NIL_FOR_ABSENCE** [model] — nil where a typed absence is meant
  (`nil` vs `[]` vs `NONE`). Judgement about intent, so it is a model lane,
  and lanes are down.
- **SYNONYM_VERBS** [model] — `fetch`/`get`/`load`/`find` meaning one thing
  across a file invites drift. A synonym list is taste until a model can tell
  the deliberate aliases (`render`/`draw`) from the accidental ones.
- **MONOTONIC_ELAPSED** [cross-line] — `Time.now` subtraction measuring
  elapsed time should be `Process.clock_gettime(Process::CLOCK_MONOTONIC)`.
  The detector must see both timestamps in the same expression; a lone
  `Time.now` is usually a timestamp, not a stopwatch.
- **FINISH_WHAT_YOU_START** [long-lived FP] — every `start`/`open`/`begin`
  wants its finish (Pragmatic). The tree holds deliberate long-lived handles
  (TTS socket, watcher threads) that would fire on every boot; the detector
  needs a liveness model before it can name the leaks.


## Semantics pass — opportunities opened 2026-09-23

The four-tree analysis found the same shapes recurring across trees. Each
entry below is the shape, the evidence, and the seam it wants.

- **Every tree has one fail-open seam where absence reads as success.** The
  rendered RAILS seam is now explicit: missing Chrome marks browser gates
  inconclusive and `runner.rb` exits 3. MASTER now has an explicit
  publisher/listener census at `tools/event_bus_reach.rb`, exposed as
  `bin/operator event-bus [--strict] [--json]`. It parses Ruby publishers and
  subscribers structurally and records browser listeners and event references,
  including event names embedded in JS regexes. The known unpublished topics
  `agent:mood`, `phantom:retry` and `pipeline:start` are therefore discoverable
  without a hand-maintained orphan list.
- **A restated value drifts; a derived one cannot.** `voice.yml` vs
  `Policy::FALLBACK`, replicate's `MODEL_CAPABILITIES` vs live provider
  schemas, and brgen's inline social routes vs `shared/config/routes/social.rb`
  remain. The rules.yml/law/registry subclaim is now covered by the existing
  `RuleRegistryAudit` plus `/rules sources`, which names YAML-only, Law-only
  and shipped-registry-only IDs while respecting `folded_into`. The relayd
  keypair list versus `apps.yml` remains. The seam: one generator from the
  primary source, in the shape `rake docs:agent_contracts` already sets —
  or a check that reads both and refuses disagreement, like
  `test_yaml_registries.rb` could do for the fallback rates.
- **The top of the gate ladder is dark.** The council answers "Insufficient
  credits" and `bin/operator gate` exits 3 skipping it, every run. A
  deterministic checklist critic as the bottom tier of the council would
  keep the ladder's top honest while the provider is unreachable — a design
  decision, the operator's.
- **lora and replicate check nothing they cannot reach.** lora's ~4.8k LOC is
  parse-checked only; replicate's `schema_audit` needs network and token, so
  it never runs in rake. The seam: a recorded-schema snapshot committed under
  `MASTER/tools/replicate/data/` so the audit diffs offline, and one loaded-module
  smoke test for lora's toolkits that does not need a provider.
- **Engines are namespaces pretending at detachability.** Sixteen engine
  views call `main_app.`, every engine model names host `User` by
  `class_name:`, fourteen host reflexes reach into engine scopes. The seam
  is not the refactor: a RAILS gate asserting engine-to-host references are
  counted and budgeted, in the shape of `app_duplication_test.rb`, so the
  boundary's real size is measured before anyone moves it.
- **One box, one disk, no second copy anywhere.** vm23's SQLite backups land
  on the operator Mac; litestream never worked. The seam is money — a second
  VPS or object storage for `VACUUM INTO` output — the operator's to buy,
  and until then the runbook should say plainly that production's only
  second copy lives on one laptop disk.

## Brgen + Amber city-scale parity — verified frontier

The current tree already carries much of the claimed daily-use core: posts, follows, chronological and affinity feeds, reposts, crossposts, bookmarks, blocks, reports/moderation queues, notifications, search, stories, DMs, groups, replies, reactions, typing, receipts, forwarding, disappearing messages, Web Push, bot participation, Vipps identity, Active Storage media, TV upload/variants, watch-time ranking, sounds and duets. Do not rebuild those nouns under a second architecture.

The remaining hard product frontier is media delivery rather than basic upload: HLS/transcode orchestration, object storage, CDN delivery, and live streaming infrastructure. ffmpeg is already an OpenBSD package target; the missing live piece is a media server/delivery tier. Keep the current one-box OpenBSD deployment as the measured baseline and do not assume Falcon/Solid Cable/SSE capacity from marketing numbers.

Messenger transport is also not yet one shared SSE transport. Brgen production chat currently uses Turbo Streams over Solid Cable; MASTER's SSE endpoint is its own face/event-bus pipe. A transport unification needs a measured benchmark and a migration plan, not a rename.

### M0 — foundation before new scale

1. Measure Brgen messenger connection and broadcast capacity on vm23 with representative concurrent clients, message rates and reconnects. Record p50/p95 delivery latency, resident memory, CPU and dropped/retried events.
2. Measure MASTER `/events/stream` separately. It is not a proxy for Brgen messenger capacity.
3. Choose the external media storage and CDN contract before adding HLS. Active Storage is already the upload boundary; keep media ownership behind that boundary.
4. Add HLS transcode jobs only after storage/delivery is chosen. ffmpeg is the local transcoder dependency; a media server remains a separate live-stream dependency.
5. Keep ranking chronological or affinity-first until real city-scale telemetry exists. The existing watch-time and taste rankers are signals, not evidence that a global FYP is useful.
6. Finish moderation as a product loop: preserve notices, decisions, clear statements of reasons, user-facing outcome notifications, and an internal appeal path. DSA obligations scale with the service's legal category and size; do not declare compliance from the report queue alone.
7. Treat E2EE/MLS and WebRTC/SFU as explicit architecture projects. Do not add client-side cryptography or group-call signaling ad hoc to the existing message model.
8. Keep the differentiating agent surface on the existing bot/message/MASTER path: agents can already be conversation participants. Build actions, permissions, provenance, quotas and human escalation before adding more bot personas.

### Sequencing

M0 capacity and storage decision -> social/messenger hardening -> identity/payment activation -> video/HLS -> agent actions in chat -> live audio/video -> E2EE and any telemetry-supported ranking work.

The explicit non-goals remain streaks and dark-pattern retention, behavioral ad targeting, a global algorithmic feed before there is useful data, and a second billing or messaging architecture alongside the existing one.

---

## pub4 clean rewrite — single-repo architecture reset — 2026-10-02

This is the architectural reset plan for `pub4`. `pub4` remains the source repository and is never rewritten by the migration. The first objective is a clean four-tree system; the second is to repair namespaces, dependencies, tests and runtime behavior against that simpler architecture.

### Target architecture

Keep exactly four root systems:

```
pub4/
  MASTER/
  RAILS/
  OPENBSD/
  STUDIO/
```

Their responsibilities are deliberately narrow:

```
MASTER   = brain / constitution / observation / repair
RAILS    = product / people / data / presentation
OPENBSD  = machine / network / security / deployment
STUDIO   = sound / image / media / export
```

Siblings communicate through explicit contracts and adapters, never through internal imports.

```
MASTER -> RAILS
MASTER -> OPENBSD
MASTER -> STUDIO

RAILS    -/-> MASTER internals
OPENBSD  -/-> MASTER internals
STUDIO   -/-> MASTER internals
RAILS    -/-> OPENBSD internals
STUDIO   -/-> RAILS internals
```

### MASTER target

MASTER becomes a small kernel instead of a framework-shaped collection of managers.

```
MASTER/
  bin/
    master
    gate
    test

  lib/
    master.rb
    core/
      world.rb
      constitution.rb
      effect.rb
      result.rb
    observe/
      scanner.rb
      corpus.rb
      finding.rb
    fix/
      loop.rb
      planner.rb
      repairer.rb
      verifier.rb
    io/
      filesystem.rb
      process.rb
      git.rb
      http.rb
    model/
      router.rb
      provider.rb
    runtime/
      session.rb
      events.rb

  law/
  data/
    soul.yml
    rules.yml
    limits.yml
    models.yml
    principle_map.yml

  test/
  tools/
  web/
  gates/
  plugins/
```

The core dependency direction is:

```
data / law
    |
  core
    |
  +----------+----------+
  |          |          |
observe     fix         io
  |          |          |
  +----------+----------+
             |
          runtime
       /      |      \\
   terminal  web    tools
```

The architectural rules are:

- observation does not mutate;
- planning does not mutate;
- repair mutates;
- verification does not mutate;
- `/fix` owns collect -> observe -> prioritize -> propose -> repair -> verify -> repeat;
- `/scan` is vocabulary inside observation rather than a second lifecycle;
- sacred-path ownership has one source in `soul.yml`;
- no obsolete `paths.immutable` authority;
- semantic sampling is reported explicitly as sampling, never called “clean”;
- deterministic mechanical rules, structural rules and model/semantic rules remain distinct;
- manager/coordinator classes that only forward are candidates for collapse;
- the target is materially smaller than current MASTER, while preserving proven behavior and regression coverage.

### RAILS target

RAILS remains a product monorepo, but each application is an ordinary Rails application with a small shared product layer.

```
RAILS/
  brgen/
    app/
      models/
      queries/
      services/
      policies/
      channels/
      jobs/
      controllers/
      views/
      javascript/
      stylesheets/
    config/
    db/
    test/
    public/

  amber/
    app/
      models/
      queries/
      services/
      policies/
      channels/
      jobs/
      controllers/
      views/
      javascript/
      stylesheets/
    config/
    db/
    test/
    public/

  shared/
    messaging/
    identity/
    notifications/
    moderation/
    media/
    search/
    location/
    events/

  contracts/
    master/
    openbsd/

  tools/
```

Brgen owns its product nouns: listing, message, thread, place, order, radio, match, post, comment, vote, profile and notification.

Amber owns its product nouns: garment, wardrobe, outfit, brand, designer, retailer, look, image, recommendation and profile.

Messaging is a domain subsystem, not a generic infrastructure abstraction:

```
shared/messaging/
  conversation.rb
  participant.rb
  message.rb
  attachment.rb
  event.rb
  delivery.rb
```

MASTER integration stays narrow and structured:

```
RAILS -> MASTER
  ask
  observe
  recommend
  explain
  summarize

MASTER -> RAILS
  structured result
```

The shared visual system remains one interaction grammar: shell -> navigation -> context -> artifact -> actions -> detail. Product surfaces can differ in content and tone without creating parallel design systems.

### OPENBSD target

OPENBSD describes the machine and deployment reality. It does not become another application framework.

```
OPENBSD/
  etc/
    rc.conf.local
    pf.conf
    relayd.conf
    nsd.conf
    acme-client.conf

  host/
    hostname
    network
    users
    disks

  services/
    rails
    master
    relayd
    nsd
    smtp

  deploy/
    bootstrap.zsh
    deploy.zsh
    rollback.zsh
    verify.zsh
    upgrade.zsh

  security/
    pledge/
    unveil/
    permissions/

  observability/
    health.zsh
    logs.zsh
    processes.zsh
    storage.zsh

  test/
    boot/
    network/
    security/
    services/
    deployment/
```

Deployment is one explicit lifecycle:

```
build
  -> stage
  -> verify
  -> install
  -> restart
  -> probe
  -> confirm
```

OPENBSD remains the authority for PF, relayd, NSD, rcctl, pledge, unveil, filesystem permissions and service ownership. MASTER may inspect and reason about those facts, but must not silently redefine them.

### STUDIO target

STUDIO is a media workshop, not the dumping ground for interesting code.

```
STUDIO/
  dilla/
    lib/
      clock.rb
      transport.rb
      rhythm.rb
      synth.rb
      bass.rb
      drums.rb
      sampling.rb
      effects.rb
      mixer.rb
    patches/
    sets/
    renders/
    test/

  visual/
    generators/
    shaders/
    compositions/
    renders/

  media/
    audio/
    images/
    video/

  postpro/
    processors/
    presets/
    pipelines/

  export/
    web/
    stems/
    masters/

  contracts/
    master.yml

  test/
```

Dilla should have a simple runtime model:

```
clock
  -> pattern
  -> instrument
  -> event
  -> mixer
  -> output
```

MASTER may request a composition or transformation. STUDIO owns synthesis, sequencing, rendering and export.

### Migration rules

1. `pub4` is immutable source material during the rewrite.
2. Preserve behavior before deleting implementation.
3. Move physical boundaries first; repair Ruby namespaces and load paths second.
4. Keep regression tests with the behavior they protect.
5. Delete only after the replacement has executable proof.
6. No duplicate authority is introduced to make migration easier.
7. No GitHub Actions are added; local and vm23 proof remains the release path.
8. Generated assets, vendored material, snapshots and machine state are not treated as authored application source.
9. No “migration complete” claim is allowed from directory movement alone.
10. Every architectural deletion must leave either a surviving replacement or a recorded, deliberate non-goal.

### Mechanical reset

The first pub4 pass may be performed as a clean orphan-history rewrite:

```
old pub4 tip
    -> preserve as a pre-rewrite tag
    -> create orphan main
    -> clear tree
    -> migrate selected pub4 source
    -> establish the four-tree target
    -> commit
    -> force-push pub4/main
```

The previous pub4 history should remain recoverable by tag, but must not determine the new architecture.

### Migration order

Phase 1: repository shape.

Create the four target roots, remove history-shaped clutter, establish ownership and contracts, and make the new README/architecture documents describe reality.

Phase 2: MASTER.

Extract `core`, `observe`, `fix`, `io`, `model` and `runtime`. Collapse duplicate orchestration. Make constitution/sacred-path ownership canonical. Carry over the useful law, gates and tests.

Phase 3: RAILS.

Keep `brgen` and `amber` intact as Rails applications. Reduce `shared` to genuine product primitives. Move engine-style cross-host coupling behind explicit contracts. Keep current product behavior before improving scale.

Phase 4: OPENBSD.

Separate host configuration, security, deployment, services, verification and observability. Remove wrapper layers that merely invoke other wrappers. Preserve vm23 operational knowledge as executable checks and runbooks.

Phase 5: STUDIO.

Make Dilla, postpro, LoRA and image/audio generation first-class media tooling. Move media ownership out of MASTER. Preserve working renderers and provenance before collapsing abstractions.

Phase 6: proof.

Run syntax, unit tests, application tests, browser/rendered gates, OpenBSD/vm23 checks and STUDIO audio/media proofs. Regenerate snapshots only from the resulting checkout. Record measured failures rather than converting them into prose optimism.

### First convergence gates

The new pub4 is not considered structurally converged until all of these are true:

- exactly four product/system roots: MASTER, RAILS, OPENBSD, STUDIO;
- no sibling imports of another tree's internal implementation;
- one source for constitutional/sacred-path rules;
- MASTER core has no dependency on higher layers;
- observation and repair have separate mutation contracts;
- RAILS shared code is demonstrably shared rather than merely centralised;
- OPENBSD deployment has one authoritative path;
- STUDIO owns all media-generation implementation;
- generated and vendored material is excluded from authored-source analysis;
- tests cover every migrated critical boundary;
- semantic scan coverage is reported honestly;
- snapshots match the actual checkout;
- pub4 remains untouched and recoverable.

### Work that remains after the reset

The reset itself is mechanical. The difficult part is the second pass: repairing require paths and namespaces, resolving dependency direction, collapsing duplicate abstractions, restoring application boots, and running the new architecture through its own tests.

Do not recreate pub4's current architecture inside pub4 merely to achieve a quick green build. A temporary compatibility seam is acceptable only when it is explicit, isolated and scheduled for removal.

The desired outcome is not “pub4 moved to another repository”. It is a smaller system that retains the valuable behavior of pub4 without retaining its accumulated architecture.

## MASTER interface research backlog — 2026-10-02

A candidate backlog of interface improvements gathered from the current MASTER face, current web/CLI interaction failures, open-source GitHub UI/agent/graphics practice, browser-platform work, realtime voice research and Hacker News discussion. These are hypotheses, not claims of shipped behaviour; each item closes only after implementation and executable or watched evidence.

Reference starting points: Browser Use — https://github.com/browser-use/browser-use ; OpenHands — https://github.com/All-Hands-AI/OpenHands ; tldraw — https://github.com/tldraw/tldraw ; CopilotKit — https://github.com/CopilotKit/CopilotKit ; llama.cpp — https://github.com/ggml-org/llama.cpp ; Bubble Tea — https://github.com/charmbracelet/bubbletea ; React Three Fiber — https://github.com/pmndrs/react-three-fiber ; VAD Web — https://github.com/ocavue/vad-web ; arXiv and Hacker News remain discovery/reference sources, not compatibility authorities.

### Voice / turn-taking
- [ ] UI-001: Remove the Enter-after-speech requirement from normal voice use.
- [ ] UI-002: Commit spoken turns from semantic silence.
- [ ] UI-003: Use VAD as the primary speech-boundary signal.
- [ ] UI-004: Use linguistic endpointing as a secondary speech-boundary signal.
- [ ] UI-005: Use Smart Turn only as an endpoint refinement layer.
- [ ] UI-006: Show a minimal live hearing pulse during capture.
- [ ] UI-007: Render live transcript as ephemeral state rather than a form.
- [ ] UI-008: Visually stabilize transcript text as recognition confidence improves.
- [ ] UI-009: Commit a sufficiently confident transcript without confirmation.
- [ ] UI-010: Provide a tiny undo path for a misheard voice turn.
- [ ] UI-011: Let stop/wait utterances interrupt MASTER naturally.
- [ ] UI-012: Let backchannels animate attention without creating a full response.
- [ ] UI-013: Distinguish backchannels from genuine turn-taking.
- [ ] UI-014: Distinguish thinking pauses from the user yielding the floor.
- [ ] UI-015: Make turn ownership visually obvious at every moment.
- [ ] UI-016: Model the microphone as listening, processing or closed.
- [ ] UI-017: Make closed microphone state deliberately visible.
- [ ] UI-018: Make processing state distinct from active listening.
- [ ] UI-019: Calibrate silence thresholds to individual utterance length.
- [ ] UI-020: Adapt VAD thresholds continuously to room noise.
- [ ] UI-021: Use continuation words to extend the endpoint window.
- [ ] UI-022: Use prosodic punctuation as endpoint evidence.
- [ ] UI-023: Use speech duration as endpoint evidence without hard-cutting turns.
- [ ] UI-024: Use energy decay as endpoint evidence.
- [ ] UI-025: Use spectral change to distinguish breath from room noise.
- [ ] UI-026: Use a first successful utterance to calibrate the microphone path.
- [ ] UI-027: Persist safe local VAD calibration where appropriate.
- [ ] UI-028: Make turn-taking transport-independent across recognizers.
- [ ] UI-029: Expose one canonical voice-turn event vocabulary.
- [ ] UI-030: Make voice completion initiate model generation immediately.
- [ ] UI-031: Never wait for a keyboard event after a completed spoken turn.
- [ ] UI-032: Let typing temporarily suspend automatic listening.
- [ ] UI-033: Return automatically to listening after typed interaction when safe.
- [ ] UI-034: Keep explicit keyboard interruption available without making it mandatory.
- [ ] UI-035: Treat barge-in as a first-class conversation state.

### Web speech / audio
- [ ] UI-036: Move local VAD inference into a Worker.
- [ ] UI-037: Use AudioWorklet for low-latency microphone measurements.
- [ ] UI-038: Keep audio capture off the main rendering path.
- [ ] UI-039: Unify browser STT and local STT behind one interface.
- [ ] UI-040: Unify microphone capability detection behind one interface.
- [ ] UI-041: Unify TTS capability detection behind one interface.
- [ ] UI-042: Publish canonical speech:start events.
- [ ] UI-043: Publish canonical speech:partial events.
- [ ] UI-044: Publish canonical speech:end events.
- [ ] UI-045: Publish canonical speech:abort events.
- [ ] UI-046: Publish canonical tts:start events.
- [ ] UI-047: Publish canonical tts:end events.
- [ ] UI-048: Publish canonical tts:interrupt events.
- [ ] UI-049: Expose actual capture state to the face.
- [ ] UI-050: Expose actual TTS playback state to the face.
- [ ] UI-051: Smooth audio signals before driving geometry.
- [ ] UI-052: Keep transients separate from smoothed energy.
- [ ] UI-053: Feed RMS into AudioState.
- [ ] UI-054: Feed peak level into AudioState.
- [ ] UI-055: Feed bass energy into AudioState.
- [ ] UI-056: Feed mid-band energy into AudioState.
- [ ] UI-057: Feed high-band energy into AudioState.
- [ ] UI-058: Feed spectral centroid into AudioState.
- [ ] UI-059: Feed onset detection into AudioState.
- [ ] UI-060: Feed speech activity into AudioState.
- [ ] UI-061: Feed sentence position into AudioState.
- [ ] UI-062: Feed speaker identity into AudioState.
- [ ] UI-063: Make speech and music use distinct visual grammars.
- [ ] UI-064: Keep an optional local audio signal lab for developers.
- [ ] UI-065: Render the live Web Audio graph in the signal lab.
- [ ] UI-066: Show analyser data beside the live graph.
- [ ] UI-067: Keep signal-lab tooling out of production chrome.
- [ ] UI-068: Detect suspended AudioContext state explicitly.
- [ ] UI-069: Recover AudioContext after the first permitted gesture.
- [ ] UI-070: Never make a primer screen the only way to unlock audio.

### Face anatomy / rendering
- [ ] UI-071: Make the face the primary visual object rather than a chat background.
- [ ] UI-072: Define one canonical facial silhouette.
- [ ] UI-073: Keep exactly one authoritative face renderer.
- [ ] UI-074: Keep one authoritative face geometry source.
- [ ] UI-075: Separate identity geometry from animation state.
- [ ] UI-076: Separate expression from lighting.
- [ ] UI-077: Separate lighting from particle density.
- [ ] UI-078: Separate particle density from resolution.
- [ ] UI-079: Preserve crisp one-pixel particle rendering.
- [ ] UI-080: Use temporal coherence to prevent particle boiling.
- [ ] UI-081: Make cheeks structurally readable.
- [ ] UI-082: Make the jaw structurally readable.
- [ ] UI-083: Make the brow structurally readable.
- [ ] UI-084: Make the eye sockets structurally readable.
- [ ] UI-085: Make pupils structurally readable.
- [ ] UI-086: Make the mouth structurally readable.
- [ ] UI-087: Make the nose structurally readable.
- [ ] UI-088: Make the forehead contour continuous.
- [ ] UI-089: Strengthen anatomical negative space around eyes.
- [ ] UI-090: Strengthen anatomical negative space around the mouth.
- [ ] UI-091: Use controlled parallax to communicate depth.
- [ ] UI-092: Use brightness as the primary depth carrier.
- [ ] UI-093: Keep depth cues stable across aspect ratios.
- [ ] UI-094: Reduce random particle motion that breaks anatomy.
- [ ] UI-095: Use bounded idle motion.
- [ ] UI-096: Use asymmetric idle motion.
- [ ] UI-097: Make idle motion slower and more biological.
- [ ] UI-098: Use nonperiodic blink intervals.
- [ ] UI-099: Use tiny bounded saccades.
- [ ] UI-100: Use phoneme-aware mouth motion.
- [ ] UI-101: Use acoustic energy only as a secondary mouth signal.
- [ ] UI-102: Use semantic intent for expression targets.
- [ ] UI-103: Prevent expression from overwriting identity.
- [ ] UI-104: Anticipate speech animation by a small safe time window.
- [ ] UI-105: Make listening animation react to the user.

### Eyes / attention / body
- [ ] UI-106: Model gaze as a state machine.
- [ ] UI-107: Look toward the prompt while the user types.
- [ ] UI-108: Look toward the speaker during listening.
- [ ] UI-109: Look toward the visual task surface during execution.
- [ ] UI-110: Return gaze toward the user after task completion.
- [ ] UI-111: Use a tiny attention shift when a tool begins.
- [ ] UI-112: Use a tiny attention shift when a tool completes.
- [ ] UI-113: Use a subtle blink after long reasoning intervals.
- [ ] UI-114: Use stillness before visual error states.
- [ ] UI-115: Use a question brow response.
- [ ] UI-116: Use a command-focused gaze.
- [ ] UI-117: Use a subtle success widening.
- [ ] UI-118: Use reduced-motion gaze rules.
- [ ] UI-119: Weaken cursor-driven eye tracking.
- [ ] UI-120: Use semantic attention instead of pointer proximity alone.
- [ ] UI-121: Add a neck silhouette beneath the head.
- [ ] UI-122: Keep shoulders nearly invisible at idle.
- [ ] UI-123: Make body motion low-frequency.
- [ ] UI-124: Use shoulders as a breathing carrier.
- [ ] UI-125: Use head tilt for conversational emphasis.
- [ ] UI-126: Use torso expansion for sustained speech.
- [ ] UI-127: Use posture to distinguish listening from reasoning.
- [ ] UI-128: Anchor the body to an internal physical center.
- [ ] UI-129: Add a restrained virtual ground plane in cinematic profiles.
- [ ] UI-130: Use internal self-shadowing for body depth.
- [ ] UI-131: Let body posture survive window resizing.
- [ ] UI-132: Keep identity geometry aspect-ratio independent.
- [ ] UI-133: Add upper-bust mode for large screens.
- [ ] UI-134: Add portrait mode for phones.
- [ ] UI-135: Prototype restrained side-profile transitions.
- [ ] UI-136: Keep depth of field optional.
- [ ] UI-137: Use stable lighting direction.
- [ ] UI-138: Let posture changes be gradual.
- [ ] UI-139: Let posture survive recognizer restarts.
- [ ] UI-140: Let posture settle after tool completion.

### Particles / fields
- [ ] UI-141: Define an explicit skin particle field.
- [ ] UI-142: Define an explicit internal neural field.
- [ ] UI-143: Define an explicit peripheral ambient field.
- [ ] UI-144: Define an explicit speech signal field.
- [ ] UI-145: Define an explicit task field.
- [ ] UI-146: Define an explicit memory field.
- [ ] UI-147: Define an explicit tool field.
- [ ] UI-148: Define an explicit error field.
- [ ] UI-149: Give every field a strict visual budget.
- [ ] UI-150: Prevent all particle fields from animating simultaneously.
- [ ] UI-151: Prefer particle persistence over particle count.
- [ ] UI-152: Use flow fields for large-scale movement.
- [ ] UI-153: Reserve curl noise for ambient motion.
- [ ] UI-154: Use signed-distance masks for facial boundaries.
- [ ] UI-155: Use depth-aware density for anatomy.
- [ ] UI-156: Keep GPU buffers allocated across frames.
- [ ] UI-157: Avoid per-frame geometry allocations.
- [ ] UI-158: Avoid per-frame object creation in visual hot paths.
- [ ] UI-159: Use deterministic random seeds in visual tests.
- [ ] UI-160: Make particle quality a capability profile.
- [ ] UI-161: Add a battery particle profile.
- [ ] UI-162: Add a television particle profile.
- [ ] UI-163: Add a reduced-motion particle profile.
- [ ] UI-164: Add a studio particle profile.
- [ ] UI-165: Prototype reaction-diffusion only as an optional effect.
- [ ] UI-166: Prototype cellular automata only as an optional effect.
- [ ] UI-167: Test metaball-like internal cohesion without visible blobs.
- [ ] UI-168: Use particle flow direction for system phase.
- [ ] UI-169: Use density to represent system state without implying certainty.
- [ ] UI-170: Use spatial convergence for retrieval activity.
- [ ] UI-171: Use radial outward motion for tool execution only when justified.
- [ ] UI-172: Use collapse/settle motion for completion.
- [ ] UI-173: Use quiet contraction for sleep.
- [ ] UI-174: Use gradual expansion for wake.
- [ ] UI-175: Use peripheral particles for high-frequency audio.

### Audio / music visualisation
- [ ] UI-176: Create one canonical AudioField abstraction.
- [ ] UI-177: Feed AudioField with RMS.
- [ ] UI-178: Feed AudioField with peak.
- [ ] UI-179: Feed AudioField with spectral bands.
- [ ] UI-180: Feed AudioField with spectral centroid.
- [ ] UI-181: Feed AudioField with transient/onset events.
- [ ] UI-182: Feed AudioField with speech activity.
- [ ] UI-183: Feed AudioField with speaker identity.
- [ ] UI-184: Feed AudioField with playback state.
- [ ] UI-185: Feed AudioField with sentence state.
- [ ] UI-186: Give speech visualisation an anatomical vocabulary.
- [ ] UI-187: Give music visualisation an environmental vocabulary.
- [ ] UI-188: Do not turn every audio source into an equalizer.
- [ ] UI-189: Use low frequencies for body mass.
- [ ] UI-190: Use mid frequencies for facial detail.
- [ ] UI-191: Use highs for peripheral activity.
- [ ] UI-192: Use onsets for discrete visual accents.
- [ ] UI-193: Use speech boundaries for compositional transitions.
- [ ] UI-194: Add audio smoothing controls only to developer profiles.
- [ ] UI-195: Keep transient signals separate from RMS.
- [ ] UI-196: Make audio analysis deterministic in recorded tests.
- [ ] UI-197: Add microphone signal recording for local diagnostics only.
- [ ] UI-198: Make diagnostic audio recording explicitly opt-in.
- [ ] UI-199: Keep diagnostic audio files out of git.
- [ ] UI-200: Add live spectrum inspection to the studio tooling.
- [ ] UI-201: Add Web Audio node-graph inspection.
- [ ] UI-202: Add audio-latency probes.
- [ ] UI-203: Add playback-buffer probes.
- [ ] UI-204: Add underrun probes.
- [ ] UI-205: Add device sample-rate reporting.
- [ ] UI-206: Add channel-layout reporting.
- [ ] UI-207: Add analyser-window reporting.
- [ ] UI-208: Add a canonical audio visual event schema.
- [ ] UI-209: Map TTS sentence boundaries into AudioField.
- [ ] UI-210: Map microphone onset into AudioField.

### HTML / CSS / browser primitives
- [ ] UI-211: Reduce default web chrome to brand, face, mic state and prompt.
- [ ] UI-212: Use semantic HTML as the primary interface substrate.
- [ ] UI-213: Use dialog for true blocking modal states.
- [ ] UI-214: Use Popover API for transient menus.
- [ ] UI-215: Use native disclosure primitives where appropriate.
- [ ] UI-216: Use View Transitions for navigation where supported.
- [ ] UI-217: Use CSS container queries for adaptive controls.
- [ ] UI-218: Use :has() only where it reduces imperative state wiring.
- [ ] UI-219: Use @property for typed animated CSS values where useful.
- [ ] UI-220: Use logical CSS properties throughout.
- [ ] UI-221: Use dynamic viewport units correctly.
- [ ] UI-222: Treat keyboard insets as first-class layout state.
- [ ] UI-223: Keep touch targets at least 44px without bulky chrome.
- [ ] UI-224: Remove wrappers whose only purpose is styling.
- [ ] UI-225: Remove duplicate style ownership.
- [ ] UI-226: Keep generated CSS regions generated.
- [ ] UI-227: Keep face-specific styles in one canonical stylesheet.
- [ ] UI-228: Keep initial CSS small.
- [ ] UI-229: Preload only truly critical face CSS.
- [ ] UI-230: Do not prefetch heavy renderer assets unnecessarily.
- [ ] UI-231: Keep JS enhancement after semantic HTML is available.
- [ ] UI-232: Keep the no-JS shell useful.
- [ ] UI-233: Keep server-rendered navigation where practical.
- [ ] UI-234: Use progressive enhancement rather than SPA-by-default.
- [ ] UI-235: Use content visibility only when it measurably helps.
- [ ] UI-236: Use containment around expensive visual regions.
- [ ] UI-237: Use will-change only for measured hot elements.
- [ ] UI-238: Remove speculative will-change declarations.
- [ ] UI-239: Keep transitions short and purposeful.
- [ ] UI-240: Reserve long transitions for spatial continuity.
- [ ] UI-241: Respect reduced motion.
- [ ] UI-242: Respect reduced transparency.
- [ ] UI-243: Respect forced colours.
- [ ] UI-244: Respect high-contrast preferences.
- [ ] UI-245: Keep text rendering intentional.

### Prompt / interaction surface
- [ ] UI-246: Make voice and typing one coherent interaction surface.
- [ ] UI-247: Let typed text suspend automatic mic capture.
- [ ] UI-248: Return to voice automatically after typed replies when safe.
- [ ] UI-249: Make Enter send typed text.
- [ ] UI-250: Make Shift+Enter insert a newline.
- [ ] UI-251: Use the mobile send key hint in single-line mode.
- [ ] UI-252: Make transcript and typed draft distinct internally.
- [ ] UI-253: Present transcript and typed draft as one surface externally.
- [ ] UI-254: Let typed text appear immediately.
- [ ] UI-255: Do not wait for server state before painting user input.
- [ ] UI-256: Let attachments occupy the same interaction plane.
- [ ] UI-257: Let image previews remain compact.
- [ ] UI-258: Let voice transcripts morph into final messages.
- [ ] UI-259: Make the prompt rise slightly while listening.
- [ ] UI-260: Make the prompt settle while processing.
- [ ] UI-261: Make the prompt remain quiet while MASTER speaks.
- [ ] UI-262: Make the prompt reappear naturally after speech.
- [ ] UI-263: Hide unnecessary chrome while speaking.
- [ ] UI-264: Make mic status visible without dominating the face.
- [ ] UI-265: Make the prompt readable over all face states.
- [ ] UI-266: Prevent prompt overlap with mobile keyboards.
- [ ] UI-267: Prevent prompt overlap with safe-area insets.
- [ ] UI-268: Prevent prompt overlap with captions.
- [ ] UI-269: Keep the prompt accessible through keyboard navigation.
- [ ] UI-270: Keep the prompt discoverable to screen readers.
- [ ] UI-271: Ensure focus does not jump after voice submission.
- [ ] UI-272: Allow explicit cancel of a pending voice turn.
- [ ] UI-273: Allow explicit retry of a failed transcription.
- [ ] UI-274: Keep retry distinct from resubmit.
- [ ] UI-275: Keep submit distinct from cancel.
- [ ] UI-276: Use one event for committed user turns.
- [ ] UI-277: Use one event for discarded drafts.
- [ ] UI-278: Use one event for interrupted turns.
- [ ] UI-279: Show interrupted turns as recoverable.
- [ ] UI-280: Do not visually duplicate partial replies.

### Agent / task UI
- [ ] UI-281: Stop representing every tool operation as chat prose.
- [ ] UI-282: Give long-running tasks a persistent visual identity.
- [ ] UI-283: Render task progress as a compact timeline.
- [ ] UI-284: Represent tools as stateful objects.
- [ ] UI-285: Give tools queued, active, complete, failed and waiting states.
- [ ] UI-286: Make approval gates visually unmistakable.
- [ ] UI-287: Show precisely what human input is required.
- [ ] UI-288: Hide implementation noise behind semantic labels.
- [ ] UI-289: Persist long-running tasks across refresh.
- [ ] UI-290: Allow multiple tasks to coexist.
- [ ] UI-291: Give active tasks persistent anchors.
- [ ] UI-292: Allow task branches without duplicating entire transcripts.
- [ ] UI-293: Support branch switching without scrolling giant conversations.
- [ ] UI-294: Support explicit task forking.
- [ ] UI-295: Support returning to a previous task branch.
- [ ] UI-296: Keep face identity stable across task branches.
- [ ] UI-297: Let task state modify visual context without modifying identity.
- [ ] UI-298: Show retrieval activity as subtle evidence.
- [ ] UI-299: Represent external research as evidence objects.
- [ ] UI-300: Make evidence objects linkable.
- [ ] UI-301: Make evidence objects timestamped.
- [ ] UI-302: Make evidence provenance inspectable.
- [ ] UI-303: Expose confidence only when grounded in a real metric.
- [ ] UI-304: Never turn internal uncertainty into fake emotional colour.
- [ ] UI-305: Represent waiting-for-human as a distinct state.
- [ ] UI-306: Represent waiting-for-network as a distinct state.
- [ ] UI-307: Represent waiting-for-model as a distinct state.
- [ ] UI-308: Represent tool retry as a distinct state.
- [ ] UI-309: Represent successful completion as a settling state.
- [ ] UI-310: Represent cancellation as a settling state.
- [ ] UI-311: Make failed operations recoverable when safe.
- [ ] UI-312: Expose destructive operations explicitly.
- [ ] UI-313: Keep approval UI semantically minimal.
- [ ] UI-314: Persist user decisions that are genuinely reusable.
- [ ] UI-315: Do not persist accidental modal choices.

### Spatial / canvas / memory
- [ ] UI-316: Add an optional infinite workspace behind the face.
- [ ] UI-317: Keep the face stable while work happens around it.
- [ ] UI-318: Represent active tasks as spatial nodes.
- [ ] UI-319: Represent evidence as spatial nodes.
- [ ] UI-320: Represent files as spatial nodes.
- [ ] UI-321: Represent tools as spatial nodes.
- [ ] UI-322: Represent memory clusters as spatial nodes.
- [ ] UI-323: Represent user notes as spatial nodes.
- [ ] UI-324: Allow spatial grouping of context.
- [ ] UI-325: Let voice commands manipulate spatial context.
- [ ] UI-326: Support 'put that over there' semantics.
- [ ] UI-327: Support comparison relationships between objects.
- [ ] UI-328: Support pinning objects by voice.
- [ ] UI-329: Support removing temporary objects by voice.
- [ ] UI-330: Make face gaze track the active spatial object.
- [ ] UI-331: Persist meaningful spatial relationships.
- [ ] UI-332: Keep spatial state separate from conversation text.
- [ ] UI-333: Let users switch between face and canvas modes.
- [ ] UI-334: Use canvas mode only when it improves comprehension.
- [ ] UI-335: Keep minimal mode free of canvas overhead.
- [ ] UI-336: Prototype tldraw-like primitives without adopting its architecture wholesale.
- [ ] UI-337: Use stable object IDs.
- [ ] UI-338: Use object provenance.
- [ ] UI-339: Use object versioning.
- [ ] UI-340: Use object selection semantics.
- [ ] UI-341: Use keyboard navigation in workspace mode.
- [ ] UI-342: Use screen-reader summaries of workspace state.
- [ ] UI-343: Add minimap only for genuinely large workspaces.
- [ ] UI-344: Keep spatial chrome hidden until needed.
- [ ] UI-345: Animate object creation gently.
- [ ] UI-346: Animate object removal gently.
- [ ] UI-347: Animate relationship creation clearly.
- [ ] UI-348: Show active tool focus spatially.
- [ ] UI-349: Show memory retrieval convergence spatially.
- [ ] UI-350: Show research evidence grouping spatially.

### Rails / Propshaft / assets
- [ ] UI-351: Keep the Rails view as the canonical semantic shell.
- [ ] UI-352: Keep Propshaft as the authoritative asset identity layer.
- [ ] UI-353: Keep face_assets.yml as the one face-asset declaration.
- [ ] UI-354: Generate asset manifests from the single declaration.
- [ ] UI-355: Generate derived preload lists from the manifest.
- [ ] UI-356: Generate asset path maps from the manifest.
- [ ] UI-357: Eliminate duplicate hand-maintained asset lists.
- [ ] UI-358: Fingerprint every production face asset.
- [ ] UI-359: Keep generated face bundles reproducible.
- [ ] UI-360: Gate generated runtime equality against its source parts.
- [ ] UI-361: Fail deploys on stale generated face artifacts.
- [ ] UI-362: Keep heavy face assets independently cacheable.
- [ ] UI-363: Keep initial HTML tiny.
- [ ] UI-364: Keep initial CSS tiny.
- [ ] UI-365: Defer expensive visual modules.
- [ ] UI-366: Feature-detect GPU capabilities before loading renderer paths.
- [ ] UI-367: Keep WebGL as a compatibility floor.
- [ ] UI-368: Experiment with WebGPU without replacing WebGL.
- [ ] UI-369: Make renderer selection capability-driven.
- [ ] UI-370: Record renderer capability in boot receipts.
- [ ] UI-371: Keep service-worker cache state tied to asset identity.
- [ ] UI-372: Invalidate stale face caches deterministically.
- [ ] UI-373: Keep source files readable.
- [ ] UI-374: Never debug generated bundles before inspecting sources.
- [ ] UI-375: Keep public generated artifacts excluded from authored-source cleanup.
- [ ] UI-376: Make face loader boundaries explicit.
- [ ] UI-377: Make boot stages explicit.
- [ ] UI-378: Keep one canonical face bootstrap.
- [ ] UI-379: Delete obsolete loaders once the replacement is proven.
- [ ] UI-380: Keep semantic HTML available if JS fails.
- [ ] UI-381: Keep fallback rendering separate from the canonical face canvas.
- [ ] UI-382: Never create two competing face renderers.
- [ ] UI-383: Never let fallback code take the primary face context.
- [ ] UI-384: Test asset maps against every declared asset.
- [ ] UI-385: Test unused asset declarations.

### Performance / future renderer
- [ ] UI-386: Set a measurable 60fps face target.
- [ ] UI-387: Set a measurable main-thread budget.
- [ ] UI-388: Set a measurable GPU budget.
- [ ] UI-389: Set a measurable memory budget.
- [ ] UI-390: Track render time per frame.
- [ ] UI-391: Track audio processing cost.
- [ ] UI-392: Track DOM update cost.
- [ ] UI-393: Track network stall cost.
- [ ] UI-394: Track asset parse cost.
- [ ] UI-395: Track GPU upload cost.
- [ ] UI-396: Detect sustained frame degradation.
- [ ] UI-397: Downgrade particle quality before reducing anatomical clarity.
- [ ] UI-398: Use fixed-size GPU buffers where practical.
- [ ] UI-399: Avoid reallocating typed arrays in render loops.
- [ ] UI-400: Move nonvisual computation into Workers.
- [ ] UI-401: Use OffscreenCanvas when the capability and workload justify it.
- [ ] UI-402: Keep image processing off the main thread.
- [ ] UI-403: Consolidate high-frequency animation loops.
- [ ] UI-404: Use event-driven wakeups for low-frequency effects.
- [ ] UI-405: Let idle MASTER genuinely idle.
- [ ] UI-406: Make battery mode a renderer policy.
- [ ] UI-407: Make television mode a renderer policy.
- [ ] UI-408: Make studio render mode deterministic.
- [ ] UI-409: Add adaptive quality hysteresis so quality does not flicker.
- [ ] UI-410: Record quality-mode transitions.
- [ ] UI-411: Add a performance receipt for face startup.
- [ ] UI-412: Add a performance receipt for first paint.
- [ ] UI-413: Add a performance receipt for first listening.
- [ ] UI-414: Add a performance receipt for first response.
- [ ] UI-415: Prototype WebGPU as a separate renderer backend.
- [ ] UI-416: Keep WebGPU and WebGL behind the same renderer interface.
- [ ] UI-417: Use WebGPU compute for experimental large particle fields.
- [ ] UI-418: Use storage buffers for experimental face state.
- [ ] UI-419: Prototype GPU audio aggregation.
- [ ] UI-420: Prototype GPU optical-flow effects.

### CLI face / terminal
- [ ] UI-421: Make the CLI face compositionally match the web face.
- [ ] UI-422: Keep terminal rendering native rather than mimicking WebGL.
- [ ] UI-423: Translate semantic states into terminal-native visual grammar.
- [ ] UI-424: Strengthen the frontal head contour.
- [ ] UI-425: Reduce procedural blob appearance.
- [ ] UI-426: Give eyes explicit negative space.
- [ ] UI-427: Give mouth explicit negative space.
- [ ] UI-428: Strengthen jaw boundary contrast.
- [ ] UI-429: Preserve anatomical proportions across terminal sizes.
- [ ] UI-430: Use truecolor when supported.
- [ ] UI-431: Use grayscale hierarchy when colour is unavailable.
- [ ] UI-432: Use half-block rendering as an optional capability.
- [ ] UI-433: Keep Braille as the high-resolution fallback.
- [ ] UI-434: Choose density from terminal geometry.
- [ ] UI-435: Use deterministic seeds in CLI tests.
- [ ] UI-436: Use slower motion than the web face.
- [ ] UI-437: Remove ornamental terminal motion that harms readability.
- [ ] UI-438: Make listening visibly distinct from reasoning.
- [ ] UI-439: Make speaking visibly distinct from listening.
- [ ] UI-440: Make idle almost still.
- [ ] UI-441: Shrink the persistent control strip.
- [ ] UI-442: Never tell a voice user to press Enter after a natural pause.
- [ ] UI-443: Keep Enter as an explicit typed-input affordance.
- [ ] UI-444: Keep an explicit interrupt key for cancellation.
- [ ] UI-445: Let natural silence end the CLI speech turn.
- [ ] UI-446: Make the CLI submit automatically after endpointing.
- [ ] UI-447: Show partial transcription without hijacking typed input.
- [ ] UI-448: Show final transcription as the committed user turn.
- [ ] UI-449: Make microphone unavailable state explicit.
- [ ] UI-450: Make speech unavailable state explicit.
- [ ] UI-451: Make TTS unavailable state explicit.
- [ ] UI-452: Keep typed fallback immediate.
- [ ] UI-453: Keep CLI face state derived from the same semantic state model.
- [ ] UI-454: Share event names with the web face.
- [ ] UI-455: Share voice-turn semantics with the web face.

### State architecture / accessibility / governance
- [ ] UI-456: Define one canonical InteractionState.
- [ ] UI-457: Define one canonical TurnState.
- [ ] UI-458: Define one canonical AudioState.
- [ ] UI-459: Define one canonical VisualState.
- [ ] UI-460: Define one canonical TaskState.
- [ ] UI-461: Define one canonical ToolState.
- [ ] UI-462: Define one canonical MemoryState.
- [ ] UI-463: Make web and CLI consume the same semantic states.
- [ ] UI-464: Give each renderer a separate projection layer.
- [ ] UI-465: Keep business logic out of visual modules.
- [ ] UI-466: Keep visual code event-driven.
- [ ] UI-467: Do not make cognition depend on rendering details.
- [ ] UI-468: Do not make CSS infer core application state.
- [ ] UI-469: Expose semantic state through DOM for assistive technology.
- [ ] UI-470: Keep live regions for consequential state changes.
- [ ] UI-471: Do not hide all useful status from sighted users.
- [ ] UI-472: Do not rely on colour alone for microphone state.
- [ ] UI-473: Announce only meaningful voice-state changes to screen readers.
- [ ] UI-474: Respect reduced motion across all projections.
- [ ] UI-475: Respect forced colours across all projections.
- [ ] UI-476: Respect high contrast across all projections.
- [ ] UI-477: Respect large system fonts.
- [ ] UI-478: Respect browser zoom.
- [ ] UI-479: Keep focus stable after voice turns.
- [ ] UI-480: Keep keyboard fallback complete.
- [ ] UI-481: Keep screen-reader navigation coherent.
- [ ] UI-482: Ensure canvas semantics have parallel DOM descriptions.
- [ ] UI-483: Keep error messages actionable.
- [ ] UI-484: Keep recovery messages brief.
- [ ] UI-485: Make safe recovery automatic.
- [ ] UI-486: Make destructive recovery explicit.
- [ ] UI-487: Make stop actions easy.
- [ ] UI-488: Make interruption immediate.
- [ ] UI-489: Make resumption automatic after safe interruptions.
- [ ] UI-490: Define the interaction states: idle, waking, listening, holding, yielded.
- [ ] UI-491: Exclude MASTER TTS from barge-in recognition reliably.
- [ ] UI-492: Improve self-echo suppression beyond transcript substring matching.
- [ ] UI-493: Make headphones and external microphones inform capture heuristics.
- [ ] UI-494: Treat browser recognition segment boundaries as implementation details.
- [ ] UI-495: Never discard a live transcript on recognition.onend.
- [ ] UI-496: Resume recognition after benign recognizer restarts.
- [ ] UI-497: Bound recognizer restart loops on unreliable devices.
- [ ] UI-498: Make retry behaviour observable through dmesg-style events.
- [ ] UI-499: Measure end-to-send latency for every voice turn.
- [ ] UI-500: Record speech-start, speech-end and send timestamps separately.
