# Rails App Architecture Notes

The Rails deploy folder should prefer tracked Rails source trees over one-shot generators.

Each production app folder should mirror Rails structure:

- app
- config
- db
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

blognet should be a blog network product with Foodielicious as the food vertical.

Marketplace should use Solidus Starter Frontend as its baseline and then adapt to local style, deploy, and moderation standards.

## Shared frontend direction

Use Stimulus Components where possible.

Use stimulus-lightbox backed by lightGallery.js for gallery needs.

Keep the license key in credentials or environment, never in committed source.
