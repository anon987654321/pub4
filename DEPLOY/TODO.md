# DEPLOY — remaining work

Actionable backlog for the OpenBSD + Rails production stack. Canonical status lives in
`rails/apps.yml` (`status: done | port | missing | planned`); this file is the executable
shortlist. Verify any item against the code before starting — some `port` items are partly wired.

Stack: four Rails 8 apps (brgen, amber, hjerterom, bsdports) + MASTER, on OpenBSD/Falcon/relayd.
`baibl` and `blognet` were removed from the stack. Gate the work with
`ruby DEPLOY/integrity_gate.rb` and `cd MASTER && bin/probe deploy`.

## Infrastructure / deploy

- [ ] **MASTER web assets must be precompiled + Falcon restarted on every web change.** Falcon
      does not hot-reload; a stale digested asset silently reverts UI fixes (this is the most
      likely cause of the "tap to start does nothing" reports — the served `visual_bridge.js`
      lagged the deferred-boot fix). Deploy path already does it (`openbsd.sh:790`,
      `sh/vps_deploy_master.sh`); make sure ad-hoc deploys never skip
      `rails assets:precompile && doas rcctl restart master`.
- [ ] **TTS backend on the VPS.** `Master::Voice::Speech` needs `edge-tts` (ms-MY-OsmanNeural)
      or an `espeak` fallback on PATH; neither is required by the app but audio is silent without
      one. Confirm `edge-tts` is installed on vm23 and reachable, else `pkg_add` espeak as fallback.
- [ ] **`release_gate.rb` / `frontend_auditor_gate.rb` run under the wrong Ruby on macOS** (system
      2.6, no bundler) and emit `gem_prelude`/dartsass noise. They work on the VPS (`ruby34`); make
      them shell out to `ruby34`/`bundle34` explicitly or skip cleanly off-VPS like `smoke-web` does.
- [ ] **frontend_auditor: 17 open findings.** Run `ruby DEPLOY/rails/frontend_auditor_gate.rb` and
      clear them (accessibility / cosmetic rules from `shared/.../frontend_rule_set.rb`).
- [ ] **Solid Queue worker on the VPS** for scheduled jobs (bsdports `PortsImportJob`, cache/queue
      health digests in `brgen/config/recurring.yml`). Confirm the queue plugin runs under Falcon.

## brgen (brgen.no + verticals: markedsplass, dating, playlist, takeaway, tv, messenger, maps)

- [ ] [port] OmniAuth (Vipps / Google / Snapchat) — identity primitives partly wired
- [ ] [port] proximity / geolocation filtering (nearby#index, dating radius, geolocation Stimulus)
- [ ] [port] moderation tools (admin/reports, ModerationReport/Flag, TrustScoreCalculator)
- [ ] [port] media pipeline: Active Storage variants across all upload surfaces (responsive_webp + blurhash)
- [ ] [port] unified Activity graph emission across verticals (ActivityTrackable + EventEmitter; only TV wired)
- [ ] [port] tv: video upload + Active Storage variants; [missing] VideoPublished / BroadcastScheduled events
- [ ] [port] marketplace: Marketplace::Review; [missing] geo-localized listings
- [ ] [port] playlist: schema.org microdata, embeddable player; [missing] Spotify/YouTube/SoundCloud import, city trending feed, track expiry
- [ ] [missing] takeaway: Restaurant model (geocoding), MenuItem availability + Order state machines
- [ ] [port] reading_time_minutes on posts

## amber (amber.brgen.no)

- [ ] [port] Wardrobe / Connection / LiveStream / Message models (containers exist, wiring incomplete)
- [ ] [port] wardrobe analytics dashboard
- [ ] [missing] wardrobe upload UI (drag-and-drop), garment segmentation / background removal
- [ ] [missing] outfit generation by weather/season/event, style evolution timeline, underused-item surfacing, AI closet tips

## bsdports (bsdports.org)

- [ ] [port] FTP import of real ports tree (OpenBSD Makefile walk done; FreeBSD/NetBSD parsers pending)
- [ ] [port] ports tree scheduled re-import job (needs the VPS queue worker above)
- [ ] [missing] dependency tree visualization, WCAG AAA pass, AI exploration assistant

## hjerterom (hjerterom.brgen.no)

- [ ] [port] shift scheduling + notifications
- [ ] [missing] clothing / toy / book reuse tracking, distribution route optimization

## Operator known-issues (from `data/operator_playbook.yml` — lessons, not app features)

- [ ] GitHub Actions billing lock: workflows fail in ~5s. Re-enable `.github/workflows/*.yml`
      push/PR triggers once billing is fixed; until then keep them `workflow_dispatch` only.
- [ ] VPS is 1 GiB / single-tenant: never run parallel SSH or parallel `bin/ci`. Use
      `zsh DEPLOY/openbsd/sh/vps_ci.sh <app>` (mutex `/var/tmp/pub4-ci.lock`) or `vps_ci_all.sh`.
- [ ] takeaway seed: `CityTenantable` `belongs_to :city` collides with the legacy string `city`
      column (`City expected, got String`). Set `ActsAsTenant.current_tenant` in seeds, use
      `update_column(:city, label)` for the display string.
- [ ] sass-embedded / npm EACCES under `doas su -m <app>`: export `HOME=/home/<app>` and
      `NPM_CONFIG_CACHE=/home/<app>/.npm` so npm never touches the root-owned cache.

## Notes for whoever executes this

- Planned/aspirational items (pgvector, AI recommendations, GraphRAG, etc.) are tracked as
  `status: planned` in `apps.yml` — out of scope until the `port`/`missing` items above land.
- After any app change: `cd /home/dev/pub4 && git pull --ff-only` then
  `zsh DEPLOY/openbsd/sh/vps_ci.sh <app>`, and `ruby34 DEPLOY/openbsd/health_check.rb --public --all-ready-apps`.
