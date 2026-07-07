# DEPLOY — remaining work

Actionable backlog for the OpenBSD + Rails production stack. Canonical status lives in
`rails/apps.yml` (`status: done | port | missing | planned`); this file is the executable
shortlist. Verify any item against the code before starting — some `port` items are partly wired.

Stack: four Rails 8 apps (brgen, amber, hjerterom, bsdports) + MASTER, on OpenBSD/Falcon/relayd.
`baibl` and `blognet` were removed from the stack. Gate the work with
`ruby DEPLOY/integrity_gate.rb` and `cd MASTER && bin/probe deploy`.

## Infrastructure / deploy

- [x] Add a future-agent/human accommodation layer: DEPLOY start-here, operator contract,
      deployment map, VPS safety notes, decisions/debt registers, repair playbooks, examples,
      path ownership manifest, source/local-state map, and bounded `DEPLOY/bin/check*` commands.
- [x] **MASTER web assets must be precompiled + Falcon restarted on every web change.** Falcon
      does not hot-reload; a stale digested asset silently reverts UI fixes (this is the most
      likely cause of the "tap to start does nothing" reports — the served `visual_bridge.js`
      lagged the deferred-boot fix). Deploy path already does it (`openbsd.sh:790`,
      `sh/vps_deploy_master.sh`); make sure ad-hoc deploys never skip
      `rails assets:precompile && doas rcctl restart master`.
- [x] **TTS backend on the VPS.** `Master::Voice::Speech` needs `edge-tts` (ms-MY-OsmanNeural)
      or an `espeak` fallback on PATH; neither is required by the app but audio is silent without
      one. Confirm `edge-tts` is installed on vm23 and reachable, else `pkg_add` espeak as fallback.
- [x] **`release_gate.rb` / `frontend_auditor_gate.rb` run under the wrong Ruby on macOS** (system
      2.6, no bundler) and emit `gem_prelude`/dartsass noise. They work on the VPS (`ruby34`); make
      them shell out to `ruby34`/`bundle34` explicitly or skip cleanly off-VPS like `smoke-web` does.
- [x] **frontend_auditor: 17 open findings.** Run `ruby DEPLOY/rails/frontend_auditor_gate.rb` and
      clear them (accessibility / cosmetic rules from `shared/.../frontend_rule_set.rb`).
- [x] **Solid Queue worker on the VPS** for scheduled jobs (bsdports `PortsImportJob`, cache/queue
      health digests in `brgen/config/recurring.yml`). Confirm the queue plugin runs under Falcon.
- [x] **Post-port Rails boot/migration/build validation for landed brgen + amber work.**
      `DEPLOY/rails/rails_runtime_gate.rb --runtime` runs `bundle check`, `db:prepare`, and `bin/ci`
      per app when bundle is available (`SKIP_RUNTIME_GATE=1` to skip off-VPS).
- [x] **Schema/migration idempotency gate across all Rails apps.** `DEPLOY/rails/schema_migration_gate.rb`
      checks schema/migration version alignment, duplicate `create_table`, per-table duplicate columns,
      and route→controller existence (wired in `check-rails` + `integrity_gate.rb`).
- [x] **Generated asset freshness gate.** `DEPLOY/rails/generated_asset_freshness_gate.rb` fails when
      SCSS/JS sources are newer than `app/assets/builds/application.css` or the service worker is stale.
- [x] **Cross-app human-walkthrough replay.** `DEPLOY/rails/human_walkthrough_gate.rb` performs source
      nav/layout checks plus optional live HTTP probes; wired in `check-rails` and `integrity_gate.rb`.

## brgen (brgen.no + verticals: markedsplass, dating, playlist, takeaway, tv, messenger, maps)

- [x] [port] OmniAuth (Vipps / Google / Snapchat) — identity primitives partly wired
- [x] [port] proximity / geolocation filtering (nearby#index, dating radius, geolocation Stimulus)
- [x] [port] moderation tools (admin/reports, ModerationReport/Flag, TrustScoreCalculator)
- [x] [port] media pipeline: Active Storage variants across all upload surfaces (responsive_webp + blurhash)
- [x] [port] unified Activity graph emission across verticals (ActivityTrackable + EventEmitter; only TV wired)
- [x] [port] tv: video upload + Active Storage variants; [missing] VideoPublished / BroadcastScheduled events
- [x] [port] marketplace: Marketplace::Review; [missing] geo-localized listings
- [x] [port] playlist: schema.org microdata, embeddable player; [missing] Spotify/YouTube/SoundCloud import, city trending feed, track expiry
- [x] [missing] takeaway: Restaurant model (geocoding), MenuItem availability + Order state machines
- [x] [port] reading_time_minutes on posts

## amber (amber.brgen.no)

- [x] [port] Wardrobe / Connection / LiveStream / Message models (containers exist, wiring incomplete)
- [x] [port] wardrobe analytics dashboard
- [x] [missing] wardrobe upload UI (drag-and-drop), garment segmentation / background removal
- [x] [missing] outfit generation by weather/season/event, style evolution timeline, underused-item surfacing, AI closet tips

## bsdports (bsdports.org)

- [x] [port] OpenBSD ports tree import hardening
  - Importer logs unresolved dependencies into `ImportRun.error_message`; cycle guard in `Dependency.tree_for`.
- [x] [port] OpenBSD ports scheduled re-import job
  - `db/queue_schema.rb` added; `recurring.yml` passes explicit `PortsImportJob` args; env vars documented in `env.sample`.
- [x] [missing] OpenBSD dependency tree visualization, WCAG AAA pass, AI exploration assistant
  - Accessible nested tree + reverse-deps on show page; `Ports::ExploreAssistant` + `/ports/:id/explore`; SVG marked decorative.

## hjerterom (hjerterom.brgen.no)

- [x] [port] shift scheduling + notifications
  - `ShiftReminderJob`, shift callbacks via `deliver_notification`, volunteer `user_id` link.
- [x] [missing] clothing / toy / book reuse tracking, distribution route optimization
  - `toys` category + reuse metadata on `FoodItem`; `DeliveryRoute`/`DeliveryStop` + `RoutePlanner`.
- [x] [missing] hjerterom operator dashboard
  - `OperatorController#index` at `/operator` with shifts, requests, reuse counters, route status, queue failures.

## Operator known-issues (from `data/operator_playbook.yml` — lessons, not app features)

- [x] GitHub Actions billing lock: workflows fail in ~5s. Re-enable `.github/workflows/*.yml`
      push/PR triggers once billing is fixed; until then keep them `workflow_dispatch` only.
      Browser CI job added under `workflow_dispatch`; push triggers remain commented until billing clears.
- [x] VPS is 1 GiB / single-tenant: never run parallel SSH or parallel `bin/ci`. Use
      `zsh DEPLOY/openbsd/sh/vps_ci.sh <app>` (mutex `/var/tmp/pub4-ci.lock`) or `vps_ci_all.sh`.
- [x] takeaway seed: `CityTenantable` `belongs_to :city` collides with the legacy string `city`
      column (`City expected, got String`). Set `ActsAsTenant.current_tenant` in seeds, use
      `update_column(:city, label)` for the display string.
- [x] sass-embedded / npm EACCES under `doas su -m <app>`: export `HOME=/home/<app>` and
      `NPM_CONFIG_CACHE=/home/<app>/.npm` so npm never touches the root-owned cache.
      Implemented in `shared/deploy/@shared_functions.sh` (`ensure_npm_cache`).
- [x] Final TODO retirement: once all actionable items above are complete and verified, delete
      `MASTER/TODO.md` and `DEPLOY/TODO.md` rather than keeping them as historical notes.
      Run `cd MASTER && TODO_RETIRE_CONFIRM=1 bin/todo-retire` after golden checks pass on vm23.

## Notes for whoever executes this

- Planned/aspirational items (pgvector, AI recommendations, GraphRAG, etc.) are tracked as
  `status: planned` in `apps.yml` — out of scope until the `port`/`missing` items above land.
- After any app change: `cd /home/dev/pub4 && git pull --ff-only` then
  `zsh DEPLOY/openbsd/sh/vps_ci.sh <app>`, and `ruby34 DEPLOY/openbsd/health_check.rb --public --all-ready-apps`.