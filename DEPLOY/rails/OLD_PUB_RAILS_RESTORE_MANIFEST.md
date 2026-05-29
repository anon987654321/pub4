# Old `pub/rails` restore manifest

Source repo: `anon987654321/pub`
Source tree: `rails/`  (REMOVED 2026-05 as ONE_SOURCE cleanup — all active code lives in DEPLOY/rails/)
Target repo: `anon987654321/pub4`
Target tree: `DEPLOY/rails/`

## Critical restoration rule

Do not copy old generator scripts verbatim when they contain embedded application files.

Old `pub/rails/*.sh` and `pub/rails/*/*.sh` scripts often contain inline `cat <<EOF` blocks that generate Ruby, ERB, JavaScript, YAML, service worker files, controllers, models, views, reflexes, channels, and initializers.

In `pub4`, shell scripts should be orchestration only:

- package checks
- `bundle add`
- `bin/rails generate ...`
- `bin/rails db:*`
- copy/sync/deploy commands
- rc.d/rely/OpenBSD service wiring
- safe idempotent CLI operations

Embedded app files must be extracted into tracked source files:

- Ruby models -> `app/models/...`
- Ruby controllers -> `app/controllers/...`
- jobs -> `app/jobs/...`
- services -> `app/services/...`
- channels -> `app/channels/...`
- reflexes, if kept -> `app/reflexes/...`
- Stimulus controllers -> `app/javascript/controllers/...`
- ERB views/partials -> `app/views/...`
- initializers -> `config/initializers/...`
- routes -> `config/routes.rb`
- migrations -> `db/migrate/...`
- locale data -> `config/locales/...`
- PWA/service worker assets -> tracked app/public/assets paths

## Verified old source inventory

### Shared generator/orchestration

- `rails/__shared.sh`
  - Old global helper script.
  - Contains Rails app generation, PostgreSQL/Redis setup, Hotwire/StimulusReflex setup, Devise/Vipps setup, anonymous posting, anonymous chat, PWA, I18n, storage, Stripe, Mapbox, live search, infinite scroll, and embedded app file templates.
  - Restore by extracting app files and rewriting shell helpers into pub4-style deploy/control functions.

### BRGEN modules in `rails/brgen/`

- `rails/brgen/brgen.sh`
  - Core multi-tenant social/local marketplace platform.
  - Contains ActsAsTenant setup, listings/city scaffolds, Mapbox controller, insights reflex, tenant middleware, app/home/listings controllers.
  - Extract embedded Ruby/JS/initializer code into `DEPLOY/rails/brgen/app`.

- `rails/brgen/dating.sh`
  - Dating module.
  - Contains profile/match/like/dislike generation and embedded matchmaking service.
  - Restore under Brgen subapp namespace, not as separate top-level app unless operational separation is chosen.

- `rails/brgen/marketplace.sh`
  - Marketplace module.
  - Old version installs Solidus and creates Vendor/VendorProduct/Listing/product controllers/reflexes.
  - `pub4/apps.yml` currently says pub4 should prefer native Rails 8 models instead of Solidus for Brgen marketplace; preserve Solidus script as source/reference only.

- `rails/brgen/playlist.sh`
  - Playlist module.
  - Contains playlist sets/tracks/collaboration/likes/comments and external music service integrations.
  - Extract models/services/controllers into `DEPLOY/rails/brgen/app/models/playlist` etc.

- `rails/brgen/takeaway.sh`
  - Takeaway module.
  - Restore restaurant/menu/order models, order status updates, and restaurant/menu UI as tracked Rails files.

- `rails/brgen/tv.sh`
  - TV/video module.
  - Restore video/channel/broadcast/show/episode concepts as tracked Rails files.

### Other apps in `rails/other/`

- `rails/other/amber.sh`
  - Restore wardrobe/item/outfit/social/media functionality into `DEPLOY/rails/amber/app`.

- `rails/other/baibl.sh`
  - Restore scripture/translation/search/analysis functionality into `DEPLOY/rails/baibl/app`.

- `rails/other/blognet.sh`
  - Restore blog/article/category/comment/like/editorial/Foodielicious features into `DEPLOY/rails/blognet/app`.

- `rails/other/bsdports.sh`
  - Restore ports/categories/platforms/import/search/advisory concepts into `DEPLOY/rails/bsdports/app`.

- `rails/other/hjerterom.sh`
  - Restore food/donation/volunteer/beneficiary/box/route/reporting concepts into `DEPLOY/rails/hjerterom/app`.

- `rails/other/privcam.sh`
  - Not currently represented in `pub4/DEPLOY/rails/apps.yml`.
  - Treat as candidate/new app only after product decision and safety/privacy review.

## Restoration workflow

1. Fetch old script from `anon987654321/pub`.
2. Identify generator commands versus embedded file bodies.
3. Keep CLI/generator commands in a pub4 control script only if still relevant.
4. Extract every embedded file into the target Rails tree.
5. Replace StimulusReflex-era flows with Turbo/Stimulus where possible unless the app already uses Reflex.
6. Prefer SQLite/Solid Queue/Solid Cache/Falcon/OpenBSD defaults from pub4 `apps.yml` unless the product explicitly requires PostgreSQL/Redis.
7. Add migrations/tests alongside models.
8. Update `DEPLOY/rails/apps.yml` statuses only after files and tests exist.
9. Run app-local `bin/ci` or at least `bin/rails zeitwerk:check` when app skeleton is complete.
10. Keep all restore PRs small enough to merge cleanly.

## First extraction targets

1. Extract `rails/brgen/dating.sh` matchmaking service and models into Brgen namespace.
2. Extract `rails/brgen/playlist.sh` models/services into Brgen playlist namespace.
3. Extract `rails/brgen/tv.sh` remaining show/episode/video concepts.
4. Extract `rails/brgen/takeaway.sh` restaurant/menu/order concepts.
5. Extract useful non-Solidus marketplace concepts while avoiding blind Solidus dependency restoration.
6. Extract `rails/__shared.sh` reusable concerns into `DEPLOY/rails/shared` only after de-embedding.

## Do not do

- Do not paste old `cat <<EOF` generated file bodies into new shell scripts.
- Do not mix `#!/bin/bash` and `#!/usr/bin/env zsh` in the same script.
- Do not run `rails new` inside deploy scripts for apps that now have tracked source trees.
- Do not append to `Gemfile`, `application.rb`, or `database.yml` blindly from shell scripts.
- Do not restore PostgreSQL/Redis assumptions where pub4 app metadata says SQLite/Solid Queue/Solid Cache.
- Do not mark old features as `done` until code exists in pub4 and passes app-local checks.
