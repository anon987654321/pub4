# HANDOFF

Recipient: Claude Opus 4.8, per user context on 2026-05-29.

This repository is `/root/pub4`, remote `anon987654321/pub4`, branch `main`. The user wants direct continuation, sequential execution, frequent pushes, and merges landing on `main`.

## Current Intent

Finish the strict `rules.yml` adherence pass across `MASTER` and `DEPLOY`, with special attention to Rails production readiness on OpenBSD. Keep the work practical: reduce real blockers, remove exposed secrets, add repeatable gates, tighten scanner false positives, and push coherent checkpoints to GitHub.

Do not overclaim production readiness. `brgen` is closest. `amber`, `bsdports`, `baibl`, `blognet`, and `hjerterom` still need target-host bundle/test/security/deploy smoke passes.

## Non-Negotiable Constraints

- TLS terminates at OpenBSD `relayd`.
- Rails production configs must keep `config.assume_ssl = true`.
- Rails production configs must not enable `config.force_ssl = true`.
- No Rails `config/master.key` may be tracked.
- Previously tracked Rails credentials must be treated as exposed and rotated outside git.
- Ruby target is 3.4 for Rails apps.
- Local host currently has Ruby 3.3.8, so full Rails runtime validation is blocked locally until Ruby 3.4 is available.
- Use `apply_patch` for manual edits.
- Do not revert unrelated user changes.
- Commit and push regular, validated checkpoints to `main`.

## Already Landed

Latest checkpoint was merged and pushed to `main`:

- Commit `0346ea68` fixed the MASTER web UI/voice path and landed the hjerterom deploy views.
- `MASTER/web/app/views/layouts/application.html.erb` now uses the particle/chat runtime surface.
- `MASTER/web/public/chat.js` now hands completed assistant text to the shared Osman voice queue.
- `MASTER/web/public/face.js` now exposes the shared voice hook and `_chatSpeakLast`.
- `MASTER/web/app/controllers/chat_controller.rb#tts` now serves Osman TTS to the public chat surface.
- `DEPLOY/rails/hjerterom` gained the missing box/volunteer/shift partials and turbo-stream views.

Earlier checkpoint was merged and pushed to `main`:

- Added `GPT.md`.
- Reworked `CLAUDE.md` and `GROK.md` as pointers to `MASTER/QUICKSTART.md` and `MASTER/data/*`.
- Quarantined PounceKeys keylogger scripts in `DEPLOY/quarantine/virus_museum/*.txt`.
- Removed tracked `config/master.key` from `brgen`, `amber`, and `bsdports`.
- Added `**/config/master.key` to `.gitignore`.
- Fixed YAML parse failures in `DEPLOY/rails/apps.yml`, `MASTER/data/patterns.yml`, and `DEPLOY/bp/mg_footwear.yml`.
- Fixed Ruby syntax blocker in `DEPLOY/rails/shared/app/helpers/schema_helper.rb`.
- Fixed JavaScript literal newline syntax issues in `DEPLOY/bp/04_pub_healthcare.js`, `DEPLOY/bp/ragnhild.js`, and `DEPLOY/bp/syre.js`.
- Fixed `DEPLOY/dilla/play.html` lang attribute.
- Fixed a real ERB logic bug in `DEPLOY/rails/brgen/app/views/posts/show.html.erb`.
- Hardened `amber` and `bsdports` production configs.
- Added `DEPLOY/rails/PRODUCTION_READINESS.md`.
- Fixed `MASTER/lib/master.rb` `load_rules` behavior so empty shards do not replace base `rules.yml`.
- Narrowed scanner `SQL_INJECTION` false positives.
- Adjusted web rules for ERB partials.
- Added `# frozen_string_literal: true` to 21 Ruby files.
- Added strict shell mode to selected scripts.

Previous validation:

- Ruby syntax: 1115 files, 0 failures.
- JavaScript syntax: 137 non-vendor files, 0 failures.
- YAML/JSON parse: 0 failures.
- `git diff --check`: clean.

## Current Unpushed Work

None at the moment. The latest production-gate and MASTER/UI checkpoint has already been pushed, so the next operator should start from the backlog below and the most recent commit above.

## Finish This Checkpoint First

If you need a verification pass, run:

```sh
DEPLOY/rails/check_production_gate.rb
git ls-files 'DEPLOY/rails/*/config/master.key'
ruby -c DEPLOY/rails/check_production_gate.rb
git diff --check
```

Then commit and push to `main` if you make further changes.

## Next Waves

1. Rails runtime gate
   - Add or document a Ruby 3.4 execution path.
   - On an environment with Ruby 3.4, run `bundle check`, `bin/rails db:prepare`, `bin/rails test`, `bin/brakeman`, and `bin/bundler-audit` per app.
   - If a local Ruby 3.4 install is not appropriate, make the OpenBSD deploy scripts run these gates before restart.

2. DEPLOY de-duplication
   - Compare Rails app scaffold/config duplication.
   - Move shared behavior into `DEPLOY/rails/shared` only where it reduces real drift.
   - Do not introduce abstractions that make app-specific deploy behavior harder to reason about.

3. MASTER scanner accuracy
   - Re-run MASTER against `erb`, `scss`, `html`, `css`, and `js`.
   - Separate true violations from scanner noise.
   - Tighten rules where false positives are systematic.
   - Add fixture tests for every changed rule.

4. Frontend production pass
   - Audit ERB/SCSS/HTML/CSS/JS for syntax, accessibility basics, responsive breakage, and obvious unsafe rendering.
   - Prefer small fixes and repeatable checks over cosmetic churn.

5. Security sweep
   - Confirm no keys, tokens, generated secrets, database files, or quarantined executable malware are tracked.
   - Keep the virus museum inert: text files only, no executable permission, clear README.
   - Verify Rails credentials are rotated outside git.

6. OpenBSD deploy smoke
   - Run each deploy script on the OpenBSD target.
   - Verify `relayd` routes, TLS, `/up`, logs, db writes, background jobs, and service restart.
   - Confirm Rails sees forwarded HTTPS correctly through `assume_ssl`.

7. Production readiness decision
   - Update `DEPLOY/rails/PRODUCTION_READINESS.md` with exact pass/fail dates.
   - Do not mark an app production-ready until target-host tests, security scans, deploy, and smoke checks have passed.

## Full Backlog

This section mirrors the repo backlog and should be treated as the working queue after the current production-gate checkpoint lands.

### Critical

- Verify face renders at `https://ai.brgen.no/`: open a fresh private window, tap primer, confirm WebGL face and ecology particles appear.
- Council deliberation should live behind the single command/orders surface, not a revived `/triad` wrapper.

### postpro

- Sync `/home/dev/postpro` generated files to `/var/www/postpro` after each regen run. `regen.rb` handles this; `postpro_vps.rb` now auto-calls `gallery_lightbox.rb`.

### MASTER Git

- Cherry-pick `vps/refactor/seven-modules`: 9 commits onto `main`. Script: `~/pub4/tmp/cherry_seven_modules.rb`. Skip `f282ee20` and `b96d7f21`, whose doc-sync refs conflict with the `fix_loop` rename already on `main`. Remaining commits contain the `SILENT_RESCUE` rule, `Swallow.log` routing, ground enhancements, `CANON.md`, and Opus 4.7 patches. Run `ruby34 ~/pub4/tmp/cherry_seven_modules.rb` on the VPS, not Termux.
- Merge `cleanup-attempt-backup`: 2 commits not yet on `main`: `8a584e9` drops stale snapshot dumps, `0a4434c` drops stubs and relocates an analysis dump. Review diff, then merge.
- Abandoned worktree branch deletion was completed on 2026-05-28.

### MASTER Architecture

- Memory subsystem: `lib/ground/memory.rb` has active TFIDF/vector and `consolidate!` path. Full SQLite and cross-session merge remain deferred pending VPS council review.
- RepoEcology: `lib/judge/repo_ecology.rb` has active scan and `co_change_graph`; full Judge integration and co-change rule wiring remain deferred pending council review.
- TTS consolidation: four implementations exist. Pick one active backend, delete the others, and move subprocess logic from `bin/tts-worker` into `lib/voice/`.
  - `lib/voice/speech.rb`: primary, edge-tts via `bin/tts-worker`.
  - `lib/voice/tts_lofi.rb`: lofi filter chain.
  - `lib/voice/sonitex.rb`: sox pipeline.
  - `lib/voice/sonitex_sox.rb`: sox variant.
  - Known issue: `edge-tts` may be missing on VPS. Check `pkg_add py3-edge-tts` and `bin/tts-worker`.
- Swarm worker coordination: `lib/judge/swarm/` declares Analyst, Coder, Researcher, and Reviewer workers, but voting logic, consensus pattern, and worker failure fallback are unimplemented. Implement worker pool initialization, role dispatch, majority or role-weighted consensus, and graceful fallback.
- Rule detector audit: 12 rule submodule files each implement their own `detect_` logic. Cross-reference every `id` in `MASTER/data/rules.yml` against detector coverage, flag zero-detector dead specs and duplicate detectors, and consolidate canonical detectors where possible.
- Pipeline context hardening: `lib/now/pipeline.rb` passes a plain hash through 11 stages. Replace with the existing or intended typed context shape, update stages to struct-style access, and keep typo failures loud.
- Datalog/cybernetics/homeostat scope: read `lib/loop/crdt_loop.rb`, `lib/loop/cybernetics.rb`, `lib/loop/homeostat.rb`, and datalog-related files under `lib/judge/`. Grep callers, determine what is wired, finish incomplete wired paths, and delete unwired dead scope only after proving no plausible caller.

### MASTER Constitutional Gaps

- Prediction engine: read `rules.yml prediction_engine`; ensure `Judge::Scan::Scanner#prediction_thresholds` and `should_autofix?` gate autofixes below threshold.
- Structural ops command surface: wire `rules.yml structural_ops` operations as single command-router/orders callables in `lib/ground/orders/`: merge, defrag, decouple, hoist, flatten, delete, expand, reduce_noise. Do not re-add thin `/triad` or `orient` wrappers.
- HALLUCINATION rule: lexical/semantic detector stub exists in scanner. Full implementation remains deferred pending council and deep scan.
- Self-test wiring: `rules.yml self_test.laws_apply_to_self` specifies per-law scans, but no Ruby class reads and executes them.

### MASTER Module Cleanup

- Rename `lib/ops/` to `lib/loop/ops/`; rename `Master::Ops` to `Master::Loop::Ops`; update `master.rb` and `work_commands.rb`.
- Move orphaned root `lib/*.rb` files to owning modules and keep removed wrapper files out: `master.rb`, `builder.rb`, `plugin.rb`, `result.rb`, `learnings.rb`, `memory.rb`, `unwrap_error.rb`, `master_paths.rb`, `pressure_engine.rb`.
- Selective data merges: `patterns.yml` should absorb `infer_patterns.yml`, `repo_topic_clusters.yml`, and `prompt_archaeology.yml` with namespacing.
- Token prompt caching was completed on 2026-05-28: `lib/judge/llm_dispatcher.rb` wraps Claude system prompts in `Content::Raw` with ephemeral cache control, cost math updated, and `cache:hit` event published.

### MASTER Web

- Audit `app/assets/app.js`, `chat.js`, `application.css`, and `canvas.css`; they appear unreferenced by views. Delete or wire them.
- Verify the deployed `cognition_ecology.js` z-index fix: particles should be visible over the face in the browser.

### Infrastructure

- TTS broken risk: `bin/tts-worker` may be missing or `edge-tts` not installed. Fix or document.
- Review `smtpd.conf` only if mail relay is needed.
- Standing rule: any file installed on VPS must be saved to `DEPLOY/openbsd/` and committed.

### DEPLOY Rails: brgen

- Direct/private messages: add connector-safe direct messages with model, controller, and Turbo Stream view.
- Add tests for `Shared::ReactionToggle`, `Shared::FollowToggle`, and `Shared::EventEmitter`.
- Smoke test all subdomain surfaces: `tv`, `dating`, `playlist`, `takeaway`, and marketplace aliases.
- Exercise marketplace cart/order, messaging, voting, reactions, and TV live-stream flows.

### DEPLOY Rails: amber

- Install the Rails 8 bundle under Ruby 3.4 and run the app test/lint/security suite.
- Rotate credentials.
- Verify wardrobe upload, Active Storage variants, AI endpoints, declutter flows, and visitor/public access boundaries.
- Complete missing wardrobe upload UI, garment segmentation/background removal integration, outfit generation, style timeline, underused item surfacing, wardrobe analytics, closet tips, social feed, and affiliate commerce links as product work.

### DEPLOY Rails: bsdports

- Install the Rails 8 bundle under Ruby 3.4 and run the app test/lint/security suite.
- Rotate credentials.
- Verify ports import/search, watch/unwatch, comments, Solid Queue, and `/up` behind `relayd`.
- Complete dependency tree visualization, scheduled ports-tree re-import job, WCAG AAA pass, and AI exploration assistant.

### DEPLOY Rails: baibl

- Install the Rails 8 bundle under Ruby 3.4 and run the app test/lint/security suite.
- Rotate credentials.
- Verify scripture search, book/chapter navigation, Hotwire flows, PWA manifest/service worker, and production host behavior.
- Gemfile audit: `baibl` removed `pg_search` from model; confirm the gem is removed from `Gemfile` too.
- Complete or correctly mark book/chapter navigation, collaborative annotations, cross-reference layer, historical and linguistic context layers, and REST API.

### DEPLOY Rails: blognet

- Install the Rails 8 bundle under Ruby 3.4 and run the app test/lint/security suite.
- Rotate credentials.
- Verify blog/post/category/comment flows, Action Text/Active Storage, RSS/Atom, public/private tier behavior, and production host behavior.
- Complete author profiles, structured article metadata, semantic search, membership/paywall, AI narration, citations, editorial workflow, and Foodielicious vertical features.

### DEPLOY Rails: hjerterom

- Install the Rails 8 bundle under Ruby 3.4 and run the app test/lint/security suite.
- Rotate credentials.
- Finish full-screen Mapbox front page with animated Hjerterom heart logo markers. Token comes from `MAPBOX_API_KEY`.
- Controllers landed; views still need verification/completion for boxes, volunteers, and shifts surfaces:
  - `app/views/boxes/`: show, new.
  - `app/views/volunteers/`: index, show, new, `_form`, shift list partial.
  - `app/views/shifts/`: index, `_form`.
- Complete donation/food item intake, weekly food parcel coordination, volunteer shifts/availability, notifications, donor management, beneficiary matching, reuse tracking, route optimization, reporting jobs, and operational forecasting.

### DEPLOY Rails Cross-App

- Add or verify `bin/ci` for each Rails subapp: RuboCop, Brakeman, bundler-audit, and Minitest.
- Keep `DEPLOY/rails/check_production_gate.rb` green.
- Keep Rails `force_ssl` disabled because TLS terminates at `relayd`.
- Keep Rails `assume_ssl` enabled.
- Keep `config/master.key` untracked across all apps.
- Add shared `DEPLOY/rails/env.sample` listing every env key across all six apps and which app needs it.
- Add `bin/deploy-diff`: SSH-compare key VPS config files against `DEPLOY/` counterparts before deploy.
- Add `rcctl check` health report: check `master`, `relayd`, `nsd`, app services, and report in a concise operator format.
- Enforce local lint before any `scp` to VPS, especially under `MASTER/web/`.

### Agent Wishlist

- Two-stage council: implement independent round one and dissent-only round two when dissent exceeds 30%, per `workflow.yml`.
- Phantom recovery: `rules.yml phantom_recovery.detectors` are read by `Master::PhantomRecovery`; extend recovery beyond basic gaslighting/repetition/bad-XML handling when justified.
- `/diag` cache hit display: render `cache:hit` event data in CLI cost output.
- Evidence scoring gate: enforce `rules.yml evidence_scoring` before autocommit; block below pass threshold 80.
- Reverse introspection: every 10 commits, sample 5 and ask MASTER if it would approve them now.
- `view_thread` persistence: emit `thread:decision` events to `data/threads/${session_id}.jsonl`.
- Gemini prompt caching: extend caching support beyond Claude where provider API supports it.
- Single `bin/probe` entrypoint for audit/preflight/smoke/security checks.
- Auto-generate `data/TODO_from_yml.md` from `soul.yml`, `rules.yml`, and `workflow.yml` scaffolded/not-implemented markers.

## My Wishlist

- Make `MASTER` the boring, trusted source of truth: fewer dramatic findings, more precise findings, fixtures for every rule class, and zero surprise parser crashes.
- Make `DEPLOY/rails/check_production_gate.rb` the first hard gate, then grow it only with checks that reflect actual deployment invariants.
- Treat OpenBSD and `relayd` as first-class architecture, not an afterthought. Rails should be proxy-aware, not TLS-owning.
- Keep Rails apps individually understandable. Share deployment grammar and boring baseline code, but do not erase app identity.
- Keep the quarantine museum useful for research while making accidental execution impossible.
- Build toward a clean answer to: "Can I deploy this app today?" The answer should come from commands, not confidence.

## Immediate Caution

The phrase "Claude Opus 4.8 released today" is user-provided context in this file. Do not rely on it as an externally verified fact unless you separately verify it.
