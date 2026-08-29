# brgen marketplace

**Every listing in brgen lives here, the shop's product and the chair someone is
selling alike.** marketplace is a mountable Rails engine served at the
marketplace subdomain, localised per country — `markedsplass.brgen.no`,
`marketplace.lsangeles.com`, resolved through
`Brgen::DomainRegistry::SUBAPP_ALIASES`. `../../ENGINES.md` is the recipe;
`../../AGENTS.md` is the topology.

Store owners post product listings across categories, buyers add them to a cart
and check out through Stripe or Vipps, and both sides leave reviews. Deals and
saved searches aid discovery, and `favorite` bookmarks a listing.

The two tiers are one model rather than two places. `Listing belongs_to :store,
optional: true`: with a store it is a shop's product, without one it is a person
selling a chair. Only the first is built out. The seeds always attach a store,
there is no separate casual surface, and the storefront chrome wraps both.

Nothing casual lives in the host app either, so do not go looking for it there.
`brgen/app/models/marketplace.rb` is a table-name-prefix module and the host has
no listing model at all. What is Craigslist-shaped about brgen is the access
model rather than the catalogue: `ListingPolicy` lets anyone list without signing
up, and `Shared::Authentication` gives an anonymous visitor a soft `Current.user`
to do it with. The taxonomy is consumer goods — electronics, clothing, furniture,
vehicles, services — with no housing, jobs or gigs.

The `marketplace_` tables, prefixed by `isolate_namespace Marketplace`, are
`Store`, `Listing`, `Category`, `Order`, `Review`, `Deal`, `ListingFavorite` and
`SavedSearch`.

Routes are drawn on `Marketplace::Engine` and mounted under
`constraints(subdomain: MARKETPLACE_SUBDOMAINS)`. Listings nest orders, reviews
and a favourite toggle; `cart` and `checkout` drive the purchase flow; and
`webhooks/stripe` and `webhooks/vipps` receive the payment callbacks. The Solidus
commerce engine mounts at `/solidus` only when `SOLIDUS_MARKETPLACE=1` and the
gem is installed — native `Marketplace::*` stays the public storefront until an
explicit cutover.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the
design system. The host reaches its helpers as `marketplace.listing_url(…,
subdomain: "markedsplass")`.
