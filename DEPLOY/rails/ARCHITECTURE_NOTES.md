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

Use Stimulus Components where possible.

Use stimulus-lightbox backed by lightGallery.js for gallery needs.

Keep the license key in credentials or environment, never in committed source.

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
