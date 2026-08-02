# brgen marketplace

Amazon-style multi-seller storefront for brgen, served at the marketplace
subdomain (localized per country, e.g. `markedsplass.brgen.no` — see
`Brgen::DomainRegistry::SUBAPP_ALIASES`). A mountable Rails engine — see
[`../../ENGINES.md`](../../ENGINES.md).

## What it is

Where brgen main's classifieds are casual, person-to-person listings (craigslist/
airbnb-style, in the host app), **marketplace is the transactional storefront**:
shop owners (`Store`) post product `Listing`s across `Categories`, buyers add them
to a cart and `Checkout` (Stripe/Vipps via `webhooks`), and both sides leave
`Review`s. `Deal`s and `SavedSearch`es aid discovery; `favorite` bookmarks a listing.

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
