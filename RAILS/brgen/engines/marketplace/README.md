# brgen marketplace

Amazon-style multi-seller storefront for brgen, served at the marketplace
subdomain (localized per country: `markedsplass.brgen.no`,
`marketplace.lsangeles.com` — see `Brgen::DomainRegistry::SUBAPP_ALIASES`).
A mountable Rails engine — see [`../../ENGINES.md`](../../ENGINES.md).
Topology: [`../../AGENTS.md`](../../AGENTS.md).

## What it is

**Every listing in brgen lives here**, casual and transactional alike. Shop owners
(`Store`) post product `Listing`s across `Categories`, buyers add them to a cart
and `Checkout` (Stripe/Vipps via `webhooks`), and both sides leave `Review`s.
`Deal`s and `SavedSearch`es aid discovery; `favorite` bookmarks a listing.

The two tiers are one model, not two places. `Listing belongs_to :store,
optional: true` — with a store it is a shop's product, without one it is a person
selling a chair. Only the first is built out: the seeds always attach a store,
there is no separate casual surface, and the storefront chrome wraps both.

This paragraph used to say the casual tier was "in the host app". It is not.
`brgen/app/models/marketplace.rb` is a table-name-prefix module and the host has
no listing model at all, so a reader following that sentence goes looking for
something that was never written. What *is* Craigslist-shaped about brgen is the
access model rather than the catalogue: `ListingPolicy` lets anyone list without
signing up, and `Shared::Authentication` gives anonymous visitors a soft
`Current.user` to do it with. The taxonomy is consumer goods — electronics,
clothing, furniture, vehicles, services — with no housing, jobs or gigs.

## Models (`marketplace_*` tables)

`Store`, `Listing`, `Category`, `Order`, `Review`, `Deal`, `ListingFavorite`,
`SavedSearch`.

## Routes

Drawn on `Marketplace::Engine`, mounted under `constraints(subdomain: MARKETPLACE_SUBDOMAINS)`.
Listings nest orders, reviews, and a favorite toggle; `cart`/`checkout` drive the
Amazon-like purchase flow; `webhooks/{stripe,vipps}` receive PSP callbacks. The
Solidus commerce engine mounts at `/solidus` only when `SOLIDUS_MARKETPLACE=1` and
the gem is installed — native `Marketplace::*` stays the public storefront until an
explicit cutover.

## Boundaries

Depends on `pub4-shared` for `User`, auth, tenancy, and the design system.
`isolate_namespace Marketplace` gives the `marketplace_` table prefix; the host
reaches its helpers as `marketplace.listing_url(…, subdomain: "markedsplass")`.
