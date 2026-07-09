# DEPLOY_RAILS_NEW_PROPOSAL.md

Implementation plan for an external agent (Grok/GPT). Written 2026-07-09 after a full
read of `DEPLOY/rails/` at commit `ab91c21b7` (all four active apps — brgen, amber,
bsdports, hjerterom — the pub4-shared engine, the three archived apps, and every gate).

## Ground rules (the omakase you may not season)

- Rails 8.1, Ruby 3.4 (`ruby34`/`bundle34` on the VPS), SQLite + Solid trifecta
  (cache/queue/cable), Falcon only (no Puma), Propshaft + importmap + dartsass,
  Hotwire + StimulusReflex. `config.assume_ssl = true`, **never** `force_ssl`
  (TLS terminates at relayd) — `check_production_gate.rb` enforces all of this; keep it green.
- `apps.yml` is the canonical inventory. Deploys are copy-tree via
  `shared/deploy/@shared_functions.sh deploy_tracked_app`; routine entry is now
  `cd ~/pub4/DEPLOY/rails && doas zsh DEPLOY.sh [app|all]` (commit `ab91c21b7`).
- Acceptance for every item: the app's `bin/ci` green, plus
  `ruby check_production_gate.rb`, `domain_alignment_gate.rb`, `schema_migration_gate.rb`,
  `port_inventory_gate.rb`, and the frontend gates.
- Tooling: pure Ruby or zsh for any sweep/rewrite. No `find`/`sed`/`awk`.

## Principle → defect mapping

The codebase's one systemic disease is **silent degradation**: shared behavior included
via `include Shared.concern(:X) rescue nil`. If the engine fails to load, models quietly
lose notifications, reactions, geo, activity tracking — no error, no test failure. That
violates POLA, the fail-fast half of KISS, and MASTER's own veto on silent rescues.
Most items below are that disease and its side effects (duplication kept alive because
nobody trusted the engine to be there).

## Work items

### R1 — Kill `Shared.concern(...) rescue nil` (the big sweep)
Replace every `include Shared.concern(:X) rescue nil` and every
`include Shared.concern(:X) rescue include Shared::X` with a plain `include Shared::X`
across brgen, bsdports, hjerterom (roughly 100 occurrences, concentrated in
`brgen/app/models/**`). The engine is a path gem in every Gemfile; if it cannot load,
boot should fail loudly. Then delete the `Shared::Engine.concern` class method
(`shared/lib/shared/engine.rb`) once zero callers remain.
Do this one app per commit; run that app's full test suite between commits.

### R2 — Delete app-local copies of engine code
Verified duplicates (brgen copy vs engine original):
- `brgen/app/services/scrape.rb` == `shared/app/services/scrape.rb` — delete the brgen copy.
- `brgen/app/services/reaction_toggle.rb` vs `Shared::ReactionToggle` — port callers, delete.
- `brgen/app/services/activity_event_recorder.rb` vs `Shared::ActivityEventRecorder` —
  port callers, delete.
- `ApplicationHelper#nok/#norwegian_date/#api_date` duplicated identically in bsdports,
  hjerterom, and the three archived apps — move into the engine's `ApplicationHelper`
  (which apps already include transitively) and delete the copies in the two active apps.
- `brgen/app/models/notification.rb` vs `Shared::Notification` — **investigate first**:
  they may back different tables (`notifications` vs `shared_notifications`). If the
  schemas match, consolidate; if not, record the reason in `shared/WIRING_NOTES.md`
  (AHA: duplication beats the wrong abstraction) and stop.

### R3 — Remove redundant double-includes
`ApplicationRecord` (engine) already includes `Shared::ActivityTrackable`; many brgen
models include it again. Separately, `Dating::Profile` and `Marketplace::Listing` include
`GeoLocatable` twice (once via the rescue-nil line, once unconditionally a few lines
later). After R1, one include per concern per class. Pure mechanical cleanup; the
existing tests are the safety net.

### R4 — Split the brgen `User` god object
`brgen/app/models/user.rb` carries ~45 associations across every vertical. Extract
per-vertical concerns under `brgen/app/models/user/` (`User::DatingAssociations`,
`User::MarketplaceAssociations`, `User::TvAssociations`, …) and include them from a
short `User`. No behavior change — associations move verbatim. SRP for readability;
each file lands under the style guide's size comfort zone.

### R5 — Routes hygiene (brgen)
- Move `TV_SUBDOMAINS`/`DATING_SUBDOMAINS`/… constant definitions out of
  `config/routes.rb` (constants defined inside `routes.draw` are redefined on every
  routes reload) into `Brgen::DomainRegistry`, which already owns the
  `SUBAPP_ALIASES`-derived marketplace list.
- The messenger constraint block re-declares the same `conversations` resources that
  exist at the top level; keep only the `messenger_root` root route inside the
  constraint and let the shared resources serve both hosts.
`domain_alignment_gate.rb` parses these constants — update its extractor in the same
commit and keep it green.

### R6 — `Time.current`, not `Time.now`
`TypingIndicator.active` scope compares `expires_at` with `Time.now`. Everything else in
the codebase uses `Time.current`. One-line fix; add a test with a non-UTC zone.

### R7 — Move brgen SQLite files to `storage/` (pair with OpenBSD proposal O11)
brgen alone keeps production databases in `db/` (`db/production*.sqlite3`); amber,
bsdports, hjerterom use `storage/` (the Rails 8 convention). Unify brgen to `storage/`:
update `config/database.yml`, move the files on the VPS during a deploy window, and
update `DEPLOY/openbsd/etc/litestream.yml`'s brgen path **in the same commit**. This
removes the one asymmetry that backup tooling and future agents keep tripping over.

### R8 — Archived apps stay frozen
mytoonz, privcam, pub_attorney are archived in `apps.yml`. Do not include them in the
R1/R2 sweeps; do not delete them. `archive_restore_gate.rb` is the contract that they
remain restorable. (Their HTTParty use and helper duplication are quarantined debt.)

### R9 — What NOT to DRY (AHA guardrail)
Keep the per-app one-line reflex subclasses (`VoteReflex < Shared::VoteReflex`, etc.) and
the per-app `Authentication` concern shims: StimulusReflex and Zeitwerk resolve these
constants per application, and the explicit stub is the cheapest correct wiring. Keep
per-app `Rails::PwaController` for the same reason. Deleting them "for DRY" breaks
constant lookup at runtime, which no gate currently catches.

## Sequencing

R6 first (trivial), then R1 app-by-app, then R3 (depends on R1), then R2, R5, R4 in any
order, R7 last (needs a VPS window and the OpenBSD-side litestream edit). After each
landed item: `bin/ci` in the touched app, then from `DEPLOY/rails/`:
`ruby check_production_gate.rb && ruby domain_alignment_gate.rb && ruby schema_migration_gate.rb`.
Deploy with `doas zsh DEPLOY.sh <app>` and verify `/up` returns 200 through relayd before
moving to the next item.
