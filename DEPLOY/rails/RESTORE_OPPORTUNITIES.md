# Rails Restore Opportunities from `anon987654321/pub`

This note maps useful logic from the old `pub` Rails shell generators into the current `pub4/DEPLOY/rails` deployment layout.

**Note (2026-05):** The old top-level `rails/` directory (source of the paths below) has been removed repo-wide as stale/dupe (ONE_SOURCE cleanup). All active code lives in DEPLOY/rails/.

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

## Brgen product correction

Brgen is Bergen, Norway first.

`brgen.no` is the main Bergen local superapp: Reddit + Craigslist/Finn-style marketplace + X.com-style posting + TikTok-style short media feed.

The vertical apps are not separate city networks. They are Bergen/Brgen subdomains under `brgen.no`, with Norwegian names where appropriate.

Canonical public pattern:

```text
brgen.no                         # main Bergen social/local superapp
markedsplass.brgen.no            # marketplace / Craigslist / Finn-style vertical
spilleliste.brgen.no             # playlist / music vertical
dating.brgen.no                  # dating vertical
tv.brgen.no                      # video / TV / live vertical
takeaway.brgen.no                # food ordering / delivery vertical
```

English internal service names may stay useful in code:

```text
brgen
brgen_marketplace
brgen_playlist
brgen_dating
brgen_tv
brgen_takeaway
```

but the public-facing domains and UX should prefer the Bergen/Norwegian naming pattern:

```text
markedsplass
spilleliste
dating
tv
takeaway
```

## Brgen topology

Canonical deploy layout should be Bergen-first:

```text
DEPLOY/rails/brgen/
  brgen.sh
  domains.yml
  app/
  subapps/
    markedsplass/
    spilleliste/
    dating/
    tv/
    takeaway/
```

or, if separate service users remain preferable:

```text
DEPLOY/rails/brgen_markedsplass/
DEPLOY/rails/brgen_spilleliste/
DEPLOY/rails/brgen_dating/
DEPLOY/rails/brgen_tv/
DEPLOY/rails/brgen_takeaway/
```

but the documentation, locales, route namespaces, domains, and service descriptions should still treat them as Brgen subapps.

## Domain coverage

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

Keep the useful metadata, but the product meaning is now clearer: `City` should represent Bergen-local configuration first, not a generic global city network.

Canonical Brgen registry:

```yaml
primary:
  name: Brgen
  city: Bergen
  country: Norway
  language: nb
  tld: no
  domains:
    core: brgen.no
    marketplace: markedsplass.brgen.no
    playlist: spilleliste.brgen.no
    dating: dating.brgen.no
    tv: tv.brgen.no
    takeaway: takeaway.brgen.no
```

Possible future city expansion should be explicit and secondary, not assumed by default.

If expansion happens later, use separate brands or controlled local subdomains rather than making Bergen disappear inside a generic tenant model.

Restore requirement:

- make Bergen/Brgen the primary tenant
- keep Norwegian public naming for local verticals
- keep `City` metadata only where it helps domain, locale, analytics, and branding
- document every deployed Brgen domain in `DEPLOY/rails/brgen/domains.yml`
- generate relayd/cert config from that registry

## Restore candidates

### 1. Brgen markedsplass subapp

Old source: `rails/brgen/marketplace.sh`

Public domain:

```text
markedsplass.brgen.no
```

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
DEPLOY/rails/brgen/subapps/markedsplass/
  app/
  README.md
```

or a service wrapper:

```text
DEPLOY/rails/brgen_markedsplass/brgen_markedsplass.sh
DEPLOY/rails/brgen_markedsplass/app/
```

Do **not** blindly restore the full old script. Solidus plus generated controllers and models should be ported into the app tree and validated against Rails 8 first.

Priority: high.

### 2. Brgen spilleliste subapp

Old source: `rails/brgen/playlist.sh`

Public domain:

```text
spilleliste.brgen.no
```

Valuable logic:

- `Playlist::Set`, `Playlist::Track`, `Playlist::Collaboration`, and `Playlist::Like`
- collaborative playlist editing
- public/private/unlisted privacy model
- playlist duration helpers
- music service integration ideas: Spotify, YouTube, SoundCloud
- `MusicPlaylist` JSON-LD
- playlist-specific locale namespace

Recommendation:

Restore as a Brgen subapp with `Playlist::*` namespacing preserved internally, but Norwegian UX/domain naming externally.

Priority: high.

### 3. Brgen dating subapp

Old source: `rails/brgen/dating.sh`

Public domain:

```text
dating.brgen.no
```

Valuable logic:

- profiles with location, gender, age, interests, photos
- match, like, dislike models
- `Dating::MatchmakingService`
- Bergen-aware matching
- Mapbox profile map
- profile/person JSON-LD
- dating-specific locale namespace

Recommendation:

Restore only after normalizing safety/privacy boundaries and model names. Dating should be Bergen-local by default and must not expose profile/location data outside intended scopes.

Priority: high, but privacy-sensitive.

### 4. Brgen TV subapp

Old source: `rails/brgen/tv.sh`

Public domain:

```text
tv.brgen.no
```

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

Public domain:

```text
takeaway.brgen.no
```

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
- Brgen domain registry generation
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
- subapps that ignore the Brgen/Bergen primary product model

## Best restore sequence

1. Add `DEPLOY/rails/brgen/domains.yml` with `brgen.no` and Brgen subdomains.
2. Add Brgen subapp shell directories for markedsplass, spilleliste, dating, tv, and takeaway.
3. Port only domain models, routes, locale keys, and views that pass Rails 8 syntax checks.
4. Add PWA/offline helper to `@shared_functions.sh`.
5. Add JSON-LD/meta helper conventions to `@shared_functions.sh`.
6. Add relayd/cert generation from `brgen/domains.yml`.
7. Add smoke checks for each Rails app deploy script.
8. Add a docs table listing each app, port, domain, service user, public Norwegian name, and restore status.

## Restore policy

Preserve the current `DEPLOY/rails` deploy pattern. Restore old app logic as tracked app source, not as one-shot generators.

Correct direction:

```text
old generator idea
  -> reviewed Rails 8 app source
  -> Brgen namespaced app/source tree
  -> brgen.no domain-aware routing
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
DEPLOY/rails/brgen/subapps/markedsplass/README.md
DEPLOY/rails/brgen/subapps/spilleliste/README.md
DEPLOY/rails/brgen/subapps/dating/README.md
DEPLOY/rails/brgen/subapps/tv/README.md
DEPLOY/rails/brgen/subapps/takeaway/README.md
```

Then port only validated files from the old scripts into the subapp trees.
