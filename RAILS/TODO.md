# RAILS TODO

Active backlog for the 3-app shared-engine tree. Feature inventory and status of
truth: `apps.yml`. Horizon/aspirational: `apps.horizon.yml` (`agent: ignore`).
Operator/deploy debt: `OPENBSD/data/debt.yml`, `MASTER/DEBT.md`.

Status legend: `[ ]` open · `[~]` partial/in-progress · `[horizon]` deliberately
deferred (`agent: ignore` in `apps.yml`) · `[hygiene]` low-risk cleanup.

_Last analyzed: 2026-07-18._

---

## 0. Constitutional command-chain coverage (priority)

Both MASTER **and** RAILS must be run through MASTER's chain of commands —
the `/scan → /fix → /scan → /critique → /review` loop driven by `bin/cli`.

- [x] Made the RAILS pass a first-class, discoverable step — documented
  `cd MASTER && ruby bin/gate` in `RAILS/README.md` ("Constitutional command
  chain"), alongside `gates/runner.rb`. The `:deploy` command set already scans
  `../RAILS` (+`../OPENBSD`); `:master` scans `.`; each ends with
  `git diff --exit-code`.
- [ ] Actually run the full chain and confirm clean. **Not run in this pass:**
  the `/fix` step makes autonomous edits across MASTER/RAILS/OPENBSD in a
  shared worktree, so this needs an explicit go-ahead (offered to the user).
- [ ] Decide cadence: wire `bin/gate` (or at least the `/scan`+`/critique`
  RAILS pass) into CI or the deploy preflight so RAILS is re-scanned on change,
  not only when an agent remembers to. Today only `gates/runner.rb` +
  per-app `bin/ci` run automatically; the constitutional chain is manual.

## 0b. MVC integrity audit (2026-07-18)

Ran a static integrity sweep across all three apps + shared engine (not a
full file-by-file read — a scripted check of the resolvable axes). Result:
**no missing views/styles/models/controllers found.**

| Axis checked | Result |
|---|---|
| `render "partial"` / `render partial:` → file exists | 0 misses (after FP removal) |
| RESTful `index/show/new/edit` actions → template or explicit render | 0 misses |
| SCSS `@import`/`@use` → file exists (app + shared load path) | 0 misses |
| `class_name:` association targets → model class exists (147 indexed) | 0 misses |
| `image_tag`/`asset_path` static refs → file exists | 0 misses |

Corroborates `apps.yml` ("Active apps: 0 port/missing gaps"). The genuine gaps
are the *known* ones below (stubs, planned features, infra) — not absent MVC
scaffolding.

Extended 2026-07-18 with a static **route-target + i18n** pass (can't boot
locally — laptop Ruby 4.0.5 vs. Gemfile `~> 3.4`, the known `macos_ruby_mismatch`).
Every explicit `to:`/`root`/`=>` target, every `resources`/`resource`, and every
static/lazy `t()` key was checked against real controllers/actions/locales. ~20
heuristic flags were each verified by hand and dismissed as false positives
(singular `resource :x`→pluralized/namespaced controller; `rails/health` is a
framework controller; `sitemaps#index`, `fingerprints#create` come from included
concerns; `home#next` sits in `scope module: "dating"`). i18n: **0 missing keys.**

**bsdports — vestigial social surface (low priority; app is otherwise complete):**

- [ ] bsdports eval's the shared `social.rb` + `auth.rb`, so it has live routes
  for `notifications`, `reports`, and `fingerprint`, but it has **none of the
  social substrate**: no `notifications`/`reactions`/`reports`/`review_cases`/
  `fingerprints` tables, no notifications/reports views, and its lone
  `ReactionsController < Shared::ReactionsController` has no table behind it
  either. bsdports is a ports-search app that was never wired for social; these
  routes are dead-but-unhit (no view links them; layout doesn't fire the
  fingerprint POST). **Not a feature gap — leave it.** If the dead routes ever
  matter, gate the social/notification eval so it's opt-in per app rather than
  building a social stack into the ports app. (Confirmed with owner: bsdports is
  fairly complete; focus is brgen + amber.)

- [ ] **Still boot-only:** exhaustive route enumeration (member/collection
  blocks, constraints, `DomainRegistry`) and orphan-route detection. Run
  `bin/rails routes` per app once a Ruby 3.4 env is available (or on vm23).

## 0c. brgen completeness verdict (2026-07-18)

Structural completeness scan of brgen + all subapps (tv, dating, marketplace,
playlist, takeaway, maps, messenger/conversations). **brgen is functionally
complete.** Across every view, exactly **one** dead/disabled interactive control
exists; every other control, form, and subapp route is wired. messenger/maps
scanned "thin" only because they resolve to top-level `Conversation`/`Place`
(not namespaced) — both fully implemented. Subapp depth: tv 10c/21v/11m,
dating 6/10/4, marketplace 10/21/8, playlist 12/24/13, takeaway 7/12/7.

Genuine remaining items (not missing files — brgen has none):

- [ ] **Marketplace cart "Send all offers"** (`marketplace/carts/show.html.erb:31`)
  is a `disabled: true` button → `"#"` ("one-click checkout coming soon"). But
  the cart *is* the user's pending `Marketplace::Order`s, and
  `Marketplace::OrdersController#create` **already notifies the seller per offer
  at add-time**. So "send all" is semantically undefined — it needs a decided
  offer lifecycle (draft-on-add + batch-send, vs. send-on-add as today). Design
  decision first; implementing blind would change the working single-offer path.
- [ ] **Stale `apps.yml` claim:** playlist `playlists#index` is documented as a
  "city-scoped trending feed", but the action is a *deliberate* minimal immersive
  view (`radio_tunnel`, per its own comment) — trending lives elsewhere. Update
  the `apps.yml` note so it stops overclaiming.
- Everything else labeled "incomplete" is either a legit conditional empty-state
  (tv "Video coming soon" when `@video` is nil) or a `planned`/`agent: ignore`
  horizon feature (AI feed ranking, creator monetization). Not chased.

**So "completing brgen" is a UX/polish question, not a missing-code question** —
see `UI_REFINEMENTS.md`. Direction pending (asked owner).

## 1. Gate architecture debt

From `README.md` "Still open" + the in-process migration in `gates/lib/`.

- [~] `gates/runner.rb --all` still **subprocesses** each gate. Finish moving
  every registered gate to the in-process `gates/lib/` classes returning
  `Deploy::GateResult`, so `--all` runs one process.
- [~] `release_gate.rb` still shells out to several gates. Point it at the
  in-process gate library once the migration above lands.
- [ ] Migrate the remaining standalone gate scripts to `Deploy::GateResult`
  (per README, `domain_alignment_gate.rb` already uses it; others "migrating
  incrementally"). Enumerate the stragglers and convert or delete the thin CLI
  wrappers (`check_production_gate.rb`, `master_web_assets_gate.rb`,
  `master_tts_gate.rb`) once nothing else depends on the subprocess form.

## 2. Test coverage

- [ ] **Broader controller coverage** (README "Still open"). Model coverage
  landed for the key brgen/amber/bsdports models; controllers remain thin.
  Prioritize request/integration specs for the verticals that mutate state:
  marketplace orders, takeaway orders, dating swipe/match handoff, playlist
  imports, TV broadcast lifecycle.
- [ ] Wire the shared `spec/` suite (if any) into CI/rake, or delete it — it is
  currently not run by `gates/runner.rb` or per-app `bin/ci`. (Mirror of the
  MASTER `spec/`-unwired debt.)
- [ ] Add coverage for the amber background-analysis jobs once they do real work
  (see §3) — currently only their deploy-script placeholder is asserted.

## 3. Amber — unimplemented intelligence jobs

Amber's role is "wardrobe / outfit intelligence", but two core jobs are
log-only stubs:

- [ ] `amber/app/jobs/remove_background_job.rb` — logs a placeholder and sets
  `analysis_status: "background_removal_pending"`; no actual background removal.
- [ ] `amber/app/jobs/segment_garment_image_job.rb` — same shape; no actual
  garment segmentation.
- [ ] Route both through the shared media service boundary
  (`Pub4::DeployPaths` → MASTER postpro/repligen) rather than adding provider
  calls inline, so jobs stay observable/retryable (per README "Media
  integration"). Then advance `analysis_status` to a terminal state.

## 4. Self-contained frontend / vendor external CDNs

The PWA/offline story and a strict production CSP both want zero third-party
runtime hosts. Several views still load assets from `cdn.jsdelivr.net` /
`fonts.googleapis.com`:

- [x] **amber** `swiper-bundle.min.css` — vendored to `amber/public/swiper-bundle.min.css`
  (18 KB) and repointed to `/swiper-bundle.min.css`; `crossorigin` dropped. No
  CSP allowlist entry needed removing (amber has no CSP initializer).
- [ ] **brgen** `maps/home/index.html.erb` — `maplibre-gl` JS + CSS from jsdelivr.
  (~1 MB JS; vendoring into git is a real tradeoff — decide vendor vs. documented
  exception before committing the blob.)
- [ ] **brgen** `dating/home/index.html.erb` — `css-doodle` from jsdelivr.
- [ ] **brgen** `layouts/application.html.erb` — Google Fonts (Libre Baskerville,
  Inter). **amber** `layouts/application.html.erb` — Google Fonts (Caprasimo).
  Self-hosting fonts means fetching woff2 + `@font-face` + `font-display`; do as
  one deliberate pass, not piecemeal.
- [ ] Confirm the service worker (`shared/pwa/service_worker.js`) caches whatever
  stays remote so the offline story holds.

## 5. Hygiene

- [x] `RAILS/brgen/log/test.log.0` — removed the stray rotated log and added
  `*.log.*` to the root `.gitignore` (the existing `*.log` didn't match rotated
  suffixes), so it can't reappear tracked.
- [x] Annotated both `line-height: 0` logo rules in `amber/_brand.scss` as the
  intentional inline-SVG descender-collapse idiom (human-facing comment). NB: a
  comment doesn't silence the auditor — if the audit still counts them, add a
  proper rule exception in the FrontendAuditor (follow-up).

## 6. Cross-cutting / operator (tracked elsewhere, surfaced here)

- [ ] **Off-host DR** (`OPENBSD/data/debt.yml` → `off_host_dr`,
  operator-priority): Litestream replicas are same-disk only; an off-host
  replica is still needed before the SQLite apps can claim durable backup.
- [ ] Domain/config drift guard (README "Blockers"): `master.json`, `apps.yml`,
  `OPERATOR.sh`, and `relayd.conf` must agree — `domain_alignment_gate.rb`
  checks this; keep it in the chain whenever ports/domains change.

## 7. Horizon features (`agent: ignore` — do not chase)

Listed for completeness; deferred by design in `apps.yml` (`status: planned`).
Move to active only on an explicit operator decision.

- [horizon] brgen: AI feed ranking, creator monetization.
- [horizon] brgen TV: live stream infrastructure.
- [horizon] brgen dating: premium memberships / boost purchases.
- [horizon] brgen marketplace: AI recommendations.
- [horizon] brgen playlist: creator donations / ad-free tier.
- [horizon] amber: pgvector / multimodal retrieval, richer PWA/offline
  (`stack_later`).
