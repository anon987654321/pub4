# Rails Restore Opportunities from `anon987654321/pub`

This note maps useful logic from the old `pub` Rails shell generators into the current `pub4/DEPLOY/rails` deployment layout.

## Source material inspected

Old repo paths:

- `rails/__shared.sh`
- `rails/brgen/brgen.sh`
- `rails/brgen/marketplace.sh`
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

The old `pub/rails` scripts are noisier but contain feature modules worth restoring as **app templates**, not as direct script replacements.

## Restore candidates

### 1. Brgen marketplace app

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

Create a new tracked app:

```text
DEPLOY/rails/marketplace/
  marketplace.sh
  app/
```

Do **not** blindly restore the full old script. Solidus plus generated controllers and models should be ported into the app tree and validated against Rails 8 first.

Priority: high.

### 2. Brgen takeaway app

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

Create a new tracked app:

```text
DEPLOY/rails/takeaway/
  takeaway.sh
  app/
```

Treat old generator output as a scaffold reference. Fix model/controller naming drift before restore: the old script mixes `user`, `customer`, `total`, and `total_amount` names.

Priority: high.

### 3. Shared Rails feature modules

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

Recommendation:

Add these as separate helpers in `@shared_functions.sh`, behind explicit function names. Avoid running them by default.

Priority: medium.

### 4. AI3 assistant installer logic

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

## Best restore sequence

1. Add `DEPLOY/rails/marketplace/` as a tracked app shell.
2. Add `DEPLOY/rails/takeaway/` as a tracked app shell.
3. Port only domain models, routes, locale keys, and views that pass Rails 8 syntax checks.
4. Add PWA/offline helper to `@shared_functions.sh`.
5. Add JSON-LD/meta helper conventions to `@shared_functions.sh`.
6. Add smoke checks for each Rails app deploy script.
7. Add a docs table listing each app, port, domain, service user, and restore status.

## Restore policy

Preserve the current `DEPLOY/rails` deploy pattern. Restore old app logic as tracked app source, not as one-shot generators.

Correct direction:

```text
old generator idea
  -> reviewed Rails 8 app source
  -> tracked app tree
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
DEPLOY/rails/takeaway/takeaway.sh
DEPLOY/rails/takeaway/app/
DEPLOY/rails/marketplace/marketplace.sh
DEPLOY/rails/marketplace/app/
```

Then port only validated files from the old scripts into the app trees.
