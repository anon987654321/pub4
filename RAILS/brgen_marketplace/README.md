# brgen marketplace

**Every listing in brgen lives here, the shop's product and the chair someone is selling alike.**
Marketplace is one place for a city to buy, sell, rent, hire and order dinner, without asking
anyone to learn a second site for each.

Marketplace is a mountable Rails engine served at the marketplace subdomain, spelled in each
country's own word: `markedsplass.brgen.no`, `marketplace.lsangeles.com`, `marktplatz` in
Germany, `mercato` in Italy. `Brgen::DomainRegistry::SUBAPP_ALIASES` resolves every spelling
to this engine. It is not a separate app: it runs in brgen's process, with brgen's users. The
recipe for a vertical is in `RAILS/brgen/README.md`, and the topology is in
`RAILS/brgen/AGENTS.md`.

## Restored marketplace intent

The original brief aimed at both local person-to-person exchange and professional shops:
discoverable listings, trustworthy sellers, useful search, direct buyer/seller contact and
location-aware inventory. The current data model deliberately supports both: a listing may have
a store or belong to an individual seller. The current storefront and seeded catalogue are
shop-first, so the presence of an individual-listing model must not be mistaken for a finished
classifieds experience.

Category and full-text search, locality filters, facets, saved searches, wishlist, reviews,
public listing questions, variants, order state, returns and the native seller surface are
implemented. AI recommendations, coupon/referral-credit campaigns, anonymous contact relay,
full shipping-label/rate integrations, catalogue-scale multi-currency operations and the
Solidus storefront remain separate work. Solidus is optional and staging-only; it is not the
public production storefront.

Store owners open a shop and post product listings across categories. Buyers add listings to a
cart, give an address, and check out through Dintero, Vipps or Stripe, whichever is configured.
Sellers take payouts, answer public questions on a listing, offer sizes and colours as variants,
and accept returns. Both sides leave reviews. Deals and saved searches aid discovery, a star
bookmarks a listing for the wishlist page, and a merchant feed in XML goes out for shopping
search engines.

The two tiers are one model rather than two places. `Listing belongs_to :store, optional:
true`: with a store it is a shop's product, and without one it is a person selling a chair. The
seeds always attach a store, there is no separate casual surface, and the storefront chrome
wraps both. A listing also has a kind. Goods is the default, and job, housing and gig listings
carry their own facts in a detail table each, so that no column sits empty for every bicycle.
The kind is a parameter of the index page. Seeded categories are consumer goods only:
electronics, clothing, furniture, vehicles and services, each with children.

Nothing casual lives in the host app, so do not look for it there; the host has no listing
model at all. What is Craigslist-shaped about brgen is the access model. `ListingPolicy` asks
only for a user, and `Shared::Authentication` gives an anonymous visitor a soft `Current.user`
to list with, so no one has to sign up first.

The models are `Store`, `Listing`, `Category`, `Order`, `Checkout`, `Review`, `Deal`,
`ListingFavorite`, `SavedSearch`, `Address`, `Payout`, `Question`, `Return`, `Variant`,
`VariantOption`, `ListingEvent`, `WebhookDelivery` and the three detail tables `JobDetail`,
`HousingDetail` and `GigDetail`. `isolate_namespace Marketplace` gives their tables the
`marketplace_` prefix, and the migrations are in `RAILS/brgen/db/migrate`. Payment services
and the Dintero client are in brgen's `app/services/marketplace/payments`, not in the engine.

Routes are drawn on `Marketplace::Engine`, and brgen mounts the engine at the root under
`constraints(subdomain: MARKETPLACE_SUBDOMAINS)`. From the host, reach the helpers as
`marketplace.listing_url(…, subdomain: "markedsplass")`. The saved list is at `/wishlist`,
because the host declares `/saved` for bookmarks before it mounts this engine, and a `/saved`
here would never run.

Payment callbacks split between engine and host. `webhooks/dintero` and its signed session
callback are engine-local. The `webhooks/stripe` route in the engine hands off to the host's
Stripe controller, so that a dashboard pointed at either URL still pays the order, and the
host also owns `/webhooks/vipps`. Dintero webhooks are verified on the raw body before any
JSON parsing, and each delivery is stored for replay handling.

## Food

The canonical food surface is `/food` on the localised Marketplace host, as in
`markedsplass.<city>/food` or `marketplace.<city>/food`. Restaurants, menus, delivery drivers,
group orders and reviews are backed by the nested `Takeaway` engine, kept at
`engines/takeaway`. Marketplace and takeaway share one campaign-art system, described in the
shared engine's README. The former `takeaway.<city>` host remains a compatibility mount of the
same engine, and new links should point to Marketplace.

## Dintero

Dintero owns marketplace money movement. A seller's payout destination must be approved and
ACTIVE before the seller's slice goes out in an inline split. BRGEN stores the exact split
contract on each local order and reuses it for capture and refund, so a later change of
configuration cannot rewrite a historical transaction. Capture is a separate step from
authorisation, and BRGEN does not mark an order paid because a browser came back from checkout.
Paid status follows the webhook.

Dintero's Shopping API creates the payment sessions. The integration keeps its own
`dintero_order_id`, `dintero_session_id` and `dintero_transaction_id` and never treats a local
order id as a Dintero resource. The checkout adapter is gated by `DINTERO_CHECKOUT_ENABLED=1`,
so a credentialed but unverified integration cannot show a payment button before the Shopping
API payload has been exercised in Dintero's test mode. The hook subscription registers against
the HTTPS address in `DINTERO_HOOK_URL`, which must not point at localhost or at Dintero.

## Solidus

Solidus is an optional commerce kernel for catalogue, cart, checkout, fulfilment and merchant
operations. It stays behind `SOLIDUS_MARKETPLACE=1` and mounts at `/solidus` only when its gems
are also loaded. The native `Marketplace::*` models remain the public seller and order domain
until a deliberate cutover. Listings, stores, orders, seller policy, buyer and seller
messaging, local geography, offers, questions and returns stay BRGEN's own. BRGEN does not
install the legacy solidus_marketplace extension.

The 1 GB OpenBSD host is the wrong place to install Solidus. Install it only on a staging host
with a database the Solidus deployment supports. Before any production cutover, verify the
Dintero Shopping payload against the current test account, and exercise authorisation, capture,
refund, duplicate delivery, seller approval and settlement events.
