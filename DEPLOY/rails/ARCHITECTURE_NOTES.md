# Rails App Architecture Notes

The Rails deploy folder should prefer tracked Rails source trees over one-shot generators.

Each production app folder should mirror Rails structure:

- app
- app/controllers
- app/models
- app/views
- app/javascript/controllers
- app/assets/stylesheets
- config
- config/routes.rb
- config/locales
- db
- db/migrate
- db/seeds.rb
- lib
- public
- storage
- test

Deploy wrappers should only sync, configure, migrate, seed, install service files, and wire relayd.

## Core rule

A product folder is a Rails application folder first and a deployment folder second.

## App groups

Brgen is the Bergen local platform.

Amber is a reusable baseline Rails application and bundle source.

bsdports is close to production-ready and should be treated as a hardened reference app.

Hjerterom is its own product and should mirror Rails structure.

blognet is the publishing network product.

Foodielicious is the blognet food vertical and should clone the editorial/recipe affordances of Matprat-style sites while staying original in branding, copy, and implementation.

Marketplace should use Solidus Starter Frontend as its baseline and then adapt to local style, deploy, and moderation standards.

## Shared frontend direction

Brgen's `application.css` (X.com 3-col + MASTER cinema palette + NNG tokens) is the visual base. All apps should inherit its `:root` variables and align components to it over time. See `shared/WIRING_NOTES.md` → "Visual System & Component Inheritance".

Photo/multimodal upload is deliberately open to visitors on the public surface (see `shared/WIRING_NOTES.md` → "Photo / Multimodal Upload Inheritance"). This is a conscious KISS carve-out: anyone can attach images to chat, while the agent’s deeper filesystem tools stay locked behind the auth token.

Use Stimulus Components where possible.

Use stimulus-lightbox backed by lightGallery.js for gallery needs.

Keep the license key in credentials or environment, never in committed source.

All Rails apps should include live search.

Baseline pattern: live search with Rails and StimulusReflex, following the Colby.so pattern from `https://www.colby.so/posts/live-search-with-rails-and-stimulusreflex`.

Implementation rule:

- Use StimulusReflex where already present.
- Use Turbo/Stimulus-compatible live search where Reflex is not installed.
- Search must be progressive enhancement, not a hard dependency for basic navigation.
- Every search surface should support empty state, loading state, no-results state, and keyboard-friendly interaction.
- Search should emit analytics/search events for shared discovery and ranking.

Required live-search surfaces:

- Brgen root feed
- markedsplass listings
- spilleliste playlists
- tv videos and shows
- takeaway restaurants and menu items
- blognet posts and authors
- Foodielicious recipes and ingredients
- bsdports ports/packages
- Hjerterom content/resources
- Amber baseline examples

## Legacy scripts note

The `@*.sh` feature modules at the root of `DEPLOY/rails/` are reference patterns from earlier work (see `github_repos/rails-style-guide/`). The active model uses tracked app trees + thin deploy scripts. See `README.md` → "Legacy feature scripts" for details.

## Completion checklist

- Brgen folder mirrors Rails structure.
- Brgen verticals live inside the Brgen Rails app unless operational separation is required.
- Amber remains the bundle/bootstrap baseline.
- bsdports becomes the production-readiness reference.
- Hjerterom receives a Rails mirror layout and product architecture note.
- blognet receives a Rails mirror layout and Foodielicious vertical note.
- Marketplace restoration starts from Solidus Starter Frontend concepts and adapts them to local standards.
- Shared frontend standards document Stimulus Components and lightGallery integration.
- Every deployable app has README, domains/service notes, and restore status.
- Every Rails app has live search on its primary index and discovery surfaces.
