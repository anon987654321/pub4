# TODO — DEPLOY contract backlog

Active contract only. Full historical backlog archived at `docs/archive/TODO-full-2026-06-15.md`.
Design ideation (AO–BE, BA–BB, etc.) archived — not execution contract.

Work left to right. Mark done with `[x]` only after wired logic + tests on OpenBSD/ruby34.


## M. OpenBSD / deploy alignment

- [ ] M01 Deploy: copy DEPLOY/openbsd/etc/rc.d/master to /etc/rc.d/master on VPS and verify
- [ ] M02 Deploy: verify /etc/master.env on VPS has all keys from master.env.sample
- [ ] M03 Deploy: `doas rcctl enable master` — verify master service enabled at boot
- [x] M04 openbsd.yml audit: check if MASTER's shell-out commands use doas where rules.yml says `privilege: doas`
- [x] M05 Backup: verify DEPLOY/openbsd/backup_priv.sh uses openrsync (not rsync) per openbsd.amsterdam docs
- [ ] M06 PTR record: verify brgen.no PTR record set via ptr4.openbsd.amsterdam (run from VM, not locally)
- [ ] M07 sshd_config on VPS: verify PermitRootLogin no, PasswordAuthentication no, MaxAuthTries 3


### AN2: Rails 8 Authentication and Authorization

- [ ] AN201 Rails 8 auth scaffold: run `rails generate authentication` — generates User, Session, Password models with bcrypt; replace any custom auth in all 6 apps with scaffold baseline
- [x] AN202 Session fixation protection: `config.action_dispatch.session_fixation: :delete` in all apps; rotate session ID on login
- [x] AN203 Passwordless magic link: add `rails generate authentication --passwordless` for baibl and blognet where frictionless onboarding matters more than security
- [x] AN204 OAuth via OmniAuth: add google_oauth2 + github strategies to brgen and blognet; store in `authentications` polymorphic table (Rails 8 scaffold supports this)
- [x] AN205 Rate limiting on auth: use `Rails.cache` with Solid Cache to track failed login attempts per IP; lock after 10 failures for 15 minutes
- [x] AN206 Remember me: `signed_in_as` persistent cookie (30 days) using encrypted cookie with `cookies.signed`; invalidate on password change
- [x] AN207 Two-factor TOTP: add `rotp` gem; generate QR code with `rqrcode`; require 2FA for marketplace sellers and dating profile activation
- [x] AN208 Pundit authorization: add `pundit` gem to all apps; generate policy per model; `policy_scope` in every index action; `authorize` in every show/create/update/destroy
- [x] AN209 Current attributes: `Current.user` via `ActiveSupport::CurrentAttributes` in all apps; thread-safe request context for audit logging and scoping
- [x] AN210 Device fingerprinting: log `user_agent`, `accept_language`, `timezone` at login; surface new device alerts via notification/email
- [x] AN211 Suspicious login detection: if login from new country (IP geolocation via free ipapi.co), send email alert; do not block but log for review
- [x] AN212 Account deletion: GDPR-compliant `/account/delete` — soft delete with 30-day grace period, hard delete via Solid Queue job, export-before-delete CSV


## BS: Missing Live Search (LIVE_SEARCH_STANDARD.md)

- [x] BS01 brgen marketplace listings: replace `LIKE` with FTS5, add Turbo Frame live update
- [x] BS02 brgen playlist sets and tracks: add FTS5 search with faceted filters (genre, artist)
- [x] BS03 brgen TV videos and channels: add full-text search over title + description
- [x] BS04 brgen takeaway restaurants: replace `LIKE` with FTS5 + distance ranking
- [x] BS05 brgen maps places: add search-as-you-type via Stimulus debounce
- [x] BS06 brgen global search: single endpoint returning union of all vertical results
- [x] BS07 amber wardrobe: add FTS5 fallback for AI search (low-cost offline mode)
- [x] BS08 amber outfits: add search by name, occasion, season, item names
- [x] BS09 blognet posts: add FTS5 over title + body, replace `LIKE`
- [x] BS10 blognet tags: add tag search page with autocomplete
- [x] BS11 hjerterom resources: add FTS5 over title, description, resource_type
- [x] BS12 hjerterom food listings: add geo-aware FTS5 search (distance + keyword)
- [x] BS13 All apps: add search analytics logging (query, result_count, latency_ms)
- [x] BS14 All apps: implement zero-result suggestions via LLM (fallback to related terms)


## BU: Missing Production Readiness (PRODUCTION_READINESS.md)

- [ ] BU01 All apps: rotate `config/master.key` and credentials (no committed master keys)
- [ ] BU02 All apps: add CI workflow with Brakeman, bundler-audit, RuboCop
- [ ] BU03 All apps: add `bin/ci` script (already in some — copy to all)
- [ ] BU04 All apps: configure `config.hosts` explicitly for all domains (including wildcard subdomains)
- [ ] BU05 All apps: add `config.action_mailer.smtp_settings` (currently missing in production.rb)
- [ ] BU06 All apps: ensure `GET /up` checks Solid Queue and Solid Cache connectivity
- [ ] BU07 All apps: set `config.active_job.queue_adapter = :solid_queue` (some still missing)
- [ ] BU08 brgen: add `config.hosts` to include all city subdomains (currently only `*.brgen.no`)
- [ ] BU09 amber: add `config.hosts` for `www.amber.brgen.no`
- [ ] BU10 bsdports: add `config/recurring.yml` for daily ports import and advisory refresh
- [ ] BU11 baibl: replace `cable.yml` redis adapter with `solid_cable` (Redis not on VPS)
- [ ] BU12 baibl: add `config/recurring.yml` for reading plan notifications
- [ ] BU13 blognet: add `config/recurring.yml` for newsletter sends and subscriber sync
- [ ] BU14 hjerterom: add Geocoder configuration for address parsing
- [ ] BU15 hjerterom: implement `SolidQueue` recurring job for expiry alerting (expiry within 48h)


## BQ: Cross-App Infrastructure & Deployment (DEPLOY snapshot)

- [ ] BQ01 rails/check_production_gate.rb: add check that each app's Gemfile.lock is present and matches Gemfile (no drift)
- [ ] BQ02 rails/check_production_gate.rb: verify `config.host_authorization` excludes `/up` for all apps
- [ ] BQ03 All apps: ensure `config.active_storage.service = :local` is used in production; S3/mirror only via explicit override
- [ ] BQ04 All apps: add `config.assume_ssl = true` — verify no `config.force_ssl = true` anywhere
- [ ] BQ05 All apps: verify `config.consider_all_requests_local = false` in production
- [ ] BQ06 All apps: add `config.logger = ActiveSupport::TaggedLogging.logger($stdout)` for JSON-friendly logging
- [ ] BQ07 All apps: add `config.active_record.query_log_tags_enabled = true` to trace N+1 in production logs
- [ ] BQ08 All apps: add `config.action_dispatch.show_exceptions = :none` (exceptions → 500) — document if overridden
- [ ] BQ09 brgen: ensure `Tv::Channel`, `Tv::Video`, `Tv::Broadcast` models are fully migrated and have Active Storage attachments
- [ ] BQ10 bsdports: verify `PortsImportJob` can run without OOM on OpenBSD (use `find_each` + streaming)
- [ ] BQ11 bsdports: add `SecurityAdvisory` model and a job that scrapes OpenBSD errata
- [ ] BQ12 baibl: add `ReadingPlan` & `ReadingPlanDay` — models exist in migration but not in current app tree
- [ ] BQ13 hjerterom: add `Box` → `Beneficiary` foreign key constraint (migration exists but might be missing in schema.rb)
- [ ] BQ14 hjerterom: add `Donor` model (table already created in migration) and wire to `Donation`
- [ ] BQ15 All apps: verify every `db/migrate/` file is idempotent (no `remove_column` without `if_exists`)
- [ ] BQ16 All apps: add `database.yml` connection pool (`pool:`) equal to Falcon/Puma worker count
- [ ] BQ17 All apps: set `timeout` in `database.yml` to 5000 — ensure it is not overridden per environment
- [ ] BQ18 DEPLOY/openbsd/openbsd.sh: add `rcctl enable` and `rcctl start` for `litestream` (backup service)
- [ ] BQ19 DEPLOY/openbsd/openbsd.sh: add cron job for `cert-renewal.sh` to run weekly — verify on VPS
- [ ] BQ20 DEPLOY/openbsd/openbsd.sh: after Stage 2, run `verify_deploy_identity.rb` and fail if any error
- [ ] BQ21 All apps: add `GET /up` endpoint that returns 200 only if DB, cache, and queue are reachable
- [ ] BQ22 All apps: add `GET /health` returning JSON with component statuses for load balancer
- [ ] BQ23 All apps: set `config.active_job.queue_adapter = :solid_queue` in production.rb — verify no Redis dependency
- [ ] BQ24 All apps: add `config/recurring.yml` with `clear_solid_queue_finished_jobs` (copy to apps that are missing it)
- [ ] BQ25 brgen: add `config.after_initialize` to load `sqlite-vec` extension if present (needed for distance queries)


## BW: Missing OpenBSD Deployment Hardening

- [x] BW01 All apps: add `newsyslog.conf` entry for log rotation (weekly, compress, signal)
- [x] BW02 All apps: ensure `rcctl enable` and `rcctl start` are idempotent in deploy scripts
- [x] BW03 All apps: add `check_ports.sh` to CI to prevent port collisions
- [x] BW04 All apps: add `verify_deploy_identity.rb` to deploy pipeline
- [x] BW05 DEPLOY/openbsd: install and configure Litestream for all SQLite databases
- [x] BW06 DEPLOY/openbsd: add cron job for `backup_priv.sh` (daily)
- [x] BW07 DEPLOY/openbsd: ensure `relayd.conf` health checks exist for every app (`check http "/up" code 200`)
- [x] BW08 DEPLOY/openbsd: configure `doas` for postpro and repligen commands
- [x] BW09 DEPLOY/openbsd: set `PermitRootLogin no`, `PasswordAuthentication no`, `MaxAuthTries 3` in `sshd_config`


## CG: Authentication & Access Security

- [ ] CG01 All apps: implement rate limiting on login (5 attempts per 10 min per IP via `Rack::Attack`)
- [ ] CG02 All apps: add TOTP two-factor authentication option (via `rotp` gem)
- [ ] CG03 All apps: enforce `Secure; HttpOnly; SameSite=Lax` on all session cookies
- [ ] CG04 All apps: add `Content-Security-Policy` header (nonce-based; no `unsafe-inline`)
- [ ] CG05 All apps: add `Permissions-Policy` header (deny camera, mic except where needed)
- [ ] CG06 brgen: hash browser fingerprint server-side before storing anonymous post gate count
- [ ] CG07 MASTER: add API token auth to web UI (`/token` query param or `Authorization: Bearer`)
- [ ] CG08 MASTER: add `pledge(2)` and `unveil(2)` to MASTER rc.d script on OpenBSD
- [ ] CG09 VM: flush bruteforce pf table on demand: `doas pfctl -t bruteforce -T flush`
- [ ] CG10 VM: add fail2ban-style log monitoring for relayd access.log → feed `<bruteforce>` table


## CI: Testing Strategy

- [ ] CI01 MASTER: add integration test that boots full pipeline and runs one real turn (no mocks)
- [ ] CI02 MASTER: add `test/fixtures/` with canonical good/bad Ruby, JS, CSS, YAML samples
- [ ] CI03 MASTER: add regression test per scan rule — one file that triggers, one that doesn't
- [ ] CI04 MASTER: test that chrome/Chromium processes are cleaned up after `reach/web.rb` tool use
- [ ] CI05 All apps: add `test/system/` Capybara tests with `pkill -9 chrome` cleanup in `teardown`
- [ ] CI06 All apps: add `test/performance/` benchmarks — feed load, search, post create under 50ms
- [ ] CI07 brgen: add anonymous post gate test — 3rd post must redirect to signup
- [ ] CI08 brgen: add city isolation test — data from city A must not appear in city B queries
- [ ] CI09 MASTER: run full test suite on VPS before each `git push` (pre-push hook)
- [ ] CI10 MASTER: add `test/council/` with deliberation fixtures — check council output for known inputs

