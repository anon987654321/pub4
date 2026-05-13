# Rails Restore Opportunities from `anon987654321/pub`

This note maps useful logic from the old `pub` Rails shell generators into the current `pub4/DEPLOY/rails` deployment layout.

## Source material inspected

Old repo paths:

- `rails/__shared.sh`
- `rails/brgen/brgen.sh`
- `rails/brgen/marketplace.sh`
- `rails/brgen/playlist.sh`
- `rails/brgen/dating.sh`
- `rails/brgen/tv.sh`
- `rails/brgen/takeaway.sh`
- `__OLD_BACKUPS/ai33/install.sh`
- `__OLD_BACKUPS/ai33/install_ass.sh`
- `__OLD_BACKUPS/ai33/ai3_old/assistants/install_assistants.sh`
- `__OLD_BACKUPS/ai33/ai3_old/assistants/final_install_assistants.sh`
- `ai3/RESTORATION_SUMMARY.md`

Current repo paths checked:

- `DEPLOY/rails/@shared_functions.sh`
- `DEPLOY/rails/brgen/brgen.sh`
- `DEPLOY/rails/amber/amber.sh`

## Main finding

The current `DEPLOY/rails` stack is cleaner and more deployable. It already has the right substrate:

- tracked app trees under each app directory
- OpenBSD user creation
- copied app deployment into `/home/<app>/app`
- bundle bootstrap from `/home/amber/.bundle`
- rc.d service installation
- relayd registration
- Solid Cache / Queue / Cable helpers
- Rails 8 auth helpers
- base SCSS/layout helpers
- social features: votes, threaded comments, hashtags, messaging

The old `pub/rails` scripts are noisier but contain feature modules worth restoring as **Brgen namespaced subapp templates**, not as direct script replacements.

## Brgen topology correction

`marketplace`, `playlist`, `dating`, `tv`, and `takeaway` are not unrelated Rails products. They are namespaced Brgen subapps.

Canonical namespace pattern:

```text
brgen
brgen_marketplace
brgen_playlist
brgen_dating
brgen_tv
brgen_takeaway
```

Canonical deploy layout should be:

```text
DEPLOY/rails/brgen/
  brgen.sh
  app/
  subapps/
    marketplace/
    playlist/
    dating/
    tv/
    takeaway/
```

or, if separate service users remain preferable:

```text
DEPLOY/rails/brgen_marketplace/
DEPLOY/rails/brgen_playlist/
DEPLOY/rails/brgen_dating/
DEPLOY/rails/brgen_tv/
DEPLOY/rails/brgen_takeaway/
```

but the documentation, locales, route namespaces, domains, and service descriptions should still treat them as Brgen subapps.

## Brgen city/domain coverage

The old Brgen core script generated a `City` model with:

```text
name
subdomain
country
city
language
favicon
analytics
tld
```

That is the important domain model to preserve. Brgen is a city/community network where each city can carry its own subdomain, language, favicon, analytics ID, and TLD.

Domain pattern from the old app:

```text
<city-subdomain>.brgen.<city-tld>
```

Examples implied by the old scripts:

```text
bergen.brgen.no
oslo.brgen.no
trondheim.brgen.no
stavanger.brgen.no
```

Subapp domain pattern should extend that rather than replace it:

```text
marketplace.<city>.brgen.<tld>
playlist.<city>.brgen.<tld>
dating.<city>.brgen.<tld>
tv.<city>.brgen.<tld>
takeaway.<city>.brgen.<tld>
```

Alternative flat pattern if relayd/cert handling is simpler:

```text
<city>.marketplace.brgen.<tld>
<city>.playlist.brgen.<tld>
<city>.dating.brgen.<tld>
<city>.tv.brgen.<tld>
<city>.takeaway.brgen.<tld>
```

Restore requirement:

- keep `City` as the canonical tenant/community object
- keep `subdomain`, `language`, `favicon`, `analytics`, and `tld`
- make every Brgen subapp tenant-aware through `City`
- document each deployed city/domain pair in a generated registry

Suggested registry:

```text
DEPLOY/rails/brgen/domains.yml
```

Shape:

```yaml
cities:
  - name: Bergen
    city: Bergen
    country: Norway
    language: nb
    subdomain: bergen
    tld: no
    domains:
      core: bergen.brgen.no
      marketplace: marketplace.bergen.brgen.no
      playlist: playlist.bergen.brgen.no
      dating: dating.bergen.brgen.no
      tv: tv.bergen.brgen.no
      takeaway: takeaway.bergen.brgen.no
```

## Restore candidates

### 1. Brgen marketplace subapp

Old source: `rails/brgen/marketplace.sh`

Valuable logic:

- multi-vendor marketplace concept
- vendor/product/order models
- Solidus integration idea
- product cards
- product JSON-LD
- marketplace-specific locale file
- product/order infinite-scroll concepts

Recommendation:

Create a Brgen namespaced tracked subapp:

```text
DEPLOY/rails/brgen/subapps/marketplace/
  app/
  README.md
```

or a service wrapper:

```text
DEPLOY/rails/brgen_marketplace/brgen_marketplace.sh
DEPLOY/rails/brgen_marketplace/app/
```

Do **not** blindly restore the full old script. Solidus plus generated controllers and models should be ported into the app tree and validated against Rails 8 first.

Priority: high.

### 2. Brgen playlist subapp

Old source: `rails/brgen/playlist.sh`

Valuable logic:

- `Playlist::Set`, `Playlist::Track`, `Playlist::Collaboration`, and `Playlist::Like`
- collaborative playlist editing
- public/private/unlisted privacy model
- playlist duration helpers
- music service integration ideas: Spotify, YouTube, SoundCloud
- `MusicPlaylist` JSON-LD
- playlist-specific locale namespace

Recommendation:

Restore as a Brgen subapp with `Playlist::*` namespacing preserved.

Priority: high.

### 3. Brgen dating subapp

Old source: `rails/brgen/dating.sh`

Valuable logic:

- profiles with location, gender, age, interests, photos
- match, like, dislike models
- `Dating::MatchmakingService`
- location-aware matching
- Mapbox profile map
- profile/person JSON-LD
- dating-specific locale namespace

Recommendation:

Restore only after normalizing safety/privacy boundaries and model names. Dating should be tenant-aware through `City` and should not leak profiles across city tenants unless explicitly configured.

Priority: high, but privacy-sensitive.

### 4. Brgen TV subapp

Old source: `rails/brgen/tv.sh`

Valuable logic:

- video/show/channel/live-stream direction
- show/episode/viewing lifecycle
- video player view
- watch-progress tracking
- TVSeries JSON-LD
- genre filters
- video-oriented SCSS

Recommendation:

Restore as `brgen_tv`, but decide whether the canonical domain model is `Video/LiveStream/Channel` or `Show/Episode/Viewing`. The old script contains both ideas and should be normalized before porting.

Priority: medium-high.

### 5. Brgen takeaway subapp

Old source: `rails/brgen/takeaway.sh`

Valuable logic:

- restaurant/menu/order/delivery-driver domain model
- restaurant cards
- menu category grouping
- order status lifecycle
- takeaway locale namespace
- delivery-oriented SCSS
- Stripe/geocoder integration idea

Recommendation:

Create a Brgen namespaced tracked subapp:

```text
DEPLOY/rails/brgen/subapps/takeaway/
  app/
  README.md
```

or a service wrapper:

```text
DEPLOY/rails/brgen_takeaway/brgen_takeaway.sh
DEPLOY/rails/brgen_takeaway/app/
```

Treat old generator output as a scaffold reference. Fix model/controller naming drift before restore: the old script mixes `user`, `customer`, `total`, and `total_amount` names.

Priority: high.

### 6. Shared Rails feature modules

Old source: `rails/__shared.sh`

Already partially restored in current `@shared_functions.sh`:

- rc.d install
- relayd helper
- base SCSS/layout
- Solid stack
- authentication
- Active Storage
- Action Text
- Pagy
- votes/comments
- hashtags
- messaging

Still worth restoring:

- PWA/offline helper
- live search helper, but rewritten for Turbo/Stimulus rather than StimulusReflex if the app no longer uses Reflex
- app-specific JSON-LD helpers
- SEO meta helper conventions
- structured i18n seed templates
- city/domain registry generation
- relayd/cert generation from `brgen/domains.yml`

Recommendation:

Add these as separate helpers in `@shared_functions.sh`, behind explicit function names. Avoid running them by default.

Priority: medium.

### 7. AI3 assistant installer logic

Old source: `__OLD_BACKUPS/ai33/*install*.sh`

Valuable logic:

- assistant component installation pattern
- restored assistant catalog
- tool/library restoration checklist
- syntax verification pass
- dependency pruning notes

Recommendation:

Do not blend this into Rails deploy scripts directly. Instead, create a separate restoration/audit helper for app-local AI assistants:

```text
DEPLOY/rails/@ai_restore_functions.sh
```

Useful for future Rails apps that embed AI assistants, but not core to every app.

Priority: low-medium.

## Do not restore directly

Avoid direct restoration of:

- duplicate shebangs
- `setup_full_app` calls unless that function is ported and tested
- PostgreSQL/Redis mandatory assumptions where current apps use SQLite/Solid stack
- StimulusReflex-only code unless the target app includes Reflex
- handwritten generated Rails controllers that reference missing columns
- hard-coded `BRGEN_IP`
- scripts that mutate existing apps without sentinels
- subapps that ignore the `City` tenant/domain model

## Best restore sequence

1. Add `DEPLOY/rails/brgen/domains.yml` with all known Brgen cities, TLDs, and subapp domains.
2. Add Brgen subapp shell directories for marketplace, playlist, dating, tv, and takeaway.
3. Port only domain models, routes, locale keys, and views that pass Rails 8 syntax checks.
4. Add PWA/offline helper to `@shared_functions.sh`.
5. Add JSON-LD/meta helper conventions to `@shared_functions.sh`.
6. Add relayd/cert generation from `brgen/domains.yml`.
7. Add smoke checks for each Rails app deploy script.
8. Add a docs table listing each app, port, domain, service user, tenant mode, and restore status.

## Restore policy

Preserve the current `DEPLOY/rails` deploy pattern. Restore old app logic as tracked app source, not as one-shot generators.

Correct direction:

```text
old generator idea
  -> reviewed Rails 8 app source
  -> Brgen namespaced app/source tree
  -> City/domain-aware routing
  -> current deploy wrapper
```

Wrong direction:

```text
old generator script
  -> run directly on production app
```

## Highest-value next patch

Create:

```text
DEPLOY/rails/brgen/domains.yml
DEPLOY/rails/brgen/subapps/marketplace/README.md
DEPLOY/rails/brgen/subapps/playlist/README.md
DEPLOY/rails/brgen/subapps/dating/README.md
DEPLOY/rails/brgen/subapps/tv/README.md
DEPLOY/rails/brgen/subapps/takeaway/README.md
```

Then port only validated files from the old scripts into the subapp trees.
