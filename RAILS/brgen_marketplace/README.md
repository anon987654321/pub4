# brgen marketplace

**Every listing in brgen lives here, the shop's product and the chair someone is
selling alike.** marketplace is a mountable Rails engine served at the
marketplace subdomain, localised per country — `markedsplass.brgen.no`,
`marketplace.lsangeles.com`, resolved through
`Brgen::DomainRegistry::SUBAPP_ALIASES`. `../../README.md` is the recipe;
`../../AGENTS.md` is the topology.

Store owners post product listings across categories, buyers add them to a cart
and check out through Dintero, Vipps or Stripe when configured, and both sides
leave reviews. Food ordering is part of the same commerce surface at `/food`:
restaurants, menus, delivery and group orders are backed by the nested `Takeaway::`
engine without creating a second product boundary. Deals and saved searches aid
discovery, and `favorite` bookmarks a listing.

The two tiers are one model rather than two places. `Listing belongs_to :store,
optional: true`: with a store it is a shop's product, without one it is a person
selling a chair. Only the first is built out. The seeds always attach a store,
there is no separate casual surface, and the storefront chrome wraps both.

Nothing casual lives in the host app either, so do not go looking for it there:
the host has no listing model at all. What is Craigslist-shaped about brgen is the access
model rather than the catalogue: `ListingPolicy` lets anyone list without signing
up, and `Shared::Authentication` gives an anonymous visitor a soft `Current.user`
to do it with. The taxonomy is consumer goods — electronics, clothing, furniture,
vehicles, services — with no housing, jobs or gigs.

The `marketplace_` tables, prefixed by `isolate_namespace Marketplace`, are
`Store`, `Listing`, `Category`, `Order`, `Review`, `Deal`, `ListingFavorite` and
`SavedSearch`.

`webhooks/dintero` is engine-local; `/webhooks/stripe` and `/webhooks/vipps` are host-owned payment callbacks shared with the marketplace domain. Dintero uses signed raw-body webhooks and a separate signed session callback. Solidus remains optional and mounts only when its integration is explicitly enabled.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the
design system. The host reaches its helpers as `marketplace.listing_url(…,
subdomain: "markedsplass")`.

## Optional Solidus commerce kernel

BRGEN keeps Marketplace::* as the public seller and order domain. Solidus is an
optional commerce kernel for catalog, cart, checkout, fulfillment and merchant
operations. It is staged behind SOLIDUS_MARKETPLACE=1 rather than replacing the
marketplace domain in place.

Solidus can cover mixed carts, split shipments, merchant storefronts, merchant
dashboards, permissions, flexible fulfillment and managed payouts. BRGEN does
not install the legacy solidus_marketplace extension.

Marketplace::Listing, Marketplace::Store, Marketplace::Order, seller policy,
buyer–seller messaging, local geography, offers, questions and returns remain
BRGEN-owned. Solidus provides the commerce kernel around product, variant, taxon,
cart, checkout, shipment and merchant operations once the database and cutover
are staged.

### Dintero

Dintero owns marketplace money movement. A seller payout destination must be
approved and ACTIVE before the seller slice is sent in an inline split. BRGEN
persists the exact split contract on each local order and reuses it for capture
and refund, so later configuration changes cannot silently rewrite a historical
transaction. Capture is a separate transition from authorization, and BRGEN does
not mark an order paid merely because a browser returned from checkout.

Dintero's Shopping API creates payment sessions for a Shopping order. The
integration keeps local dintero_order_id, dintero_session_id and
dintero_transaction_id rather than treating a local order id as a Dintero resource.
Dintero hook delivery has its own event-delivery identity. BRGEN verifies the raw
request body before JSON parsing, stores event-delivery for replay handling, and
keeps the signed session callback separate from the webhook route.

The checkout adapter is explicitly gated by DINTERO_CHECKOUT_ENABLED=1. A
credentialed but unverified integration therefore cannot present a payment button
before the Shopping API payload has been exercised in Dintero test mode. Capture
and refund confirmation remain webhook-authoritative.

### Staging

Use a non-production host and a database supported by the Solidus deployment.
Set SOLIDUS_MARKETPLACE=1 and run the Solidus installer only on that staging host.
Verify the Dintero Shopping draft-order and session payload against the current
test account before setting DINTERO_CHECKOUT_ENABLED=1. Register the Dintero hook
subscription against the HTTPS route configured in DINTERO_HOOK_URL. Exercise
authorization, capture, refund, duplicate delivery, seller approval and settlement
events before any production cutover.

The 1 GB OpenBSD host remains the wrong place for the Solidus install. Native
BRGEN continues to serve the public marketplace until a staged cutover is deliberate.


## Food

The canonical food surface is `/food` on the localized Marketplace host: `markedsplass.<city>/food` or `marketplace.<city>/food`. The former `takeaway.<city>` host remains a compatibility mount of the same engine; new links should point to Marketplace.
