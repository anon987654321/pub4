# Mr. Damascy

**Fra Damaskus med kjærlighet** — from Damascus with love, grilled in Bergen.

Mr. Damascy is a mobile-first ordering PWA for the real restaurant at
**Solheimsgaten 60, 5054 Bergen (Danmarksplass)**. The kitchen serves one local
customer base; this is not a multi-tenant delivery marketplace. Customers order
directly from the kitchen and pay through Vipps Express or Stripe Checkout.
The product's shorter checkout, brand, routes, schema, service contracts,
views, menu, seed catalogue and tests are specified in
[APP_SPEC.md](APP_SPEC.md). That document is the implementation source of truth;
this README is the product and operator entrypoint.

## The product

The app brings Damascus/Syrian food culture into Bergen street-kebab life:
toum and tarator, generous portions, a free salad bar and the "kvartover-ærlig"
weight promise. Its ordering flow is designed to remove the steps and form
fields customers encounter on marketplace delivery apps. The menu carries
twelve food-origin stories and credits; the app does not claim those restaurants
or recipes as its own.

One Bergen kitchen owns the order and customer relationship. It operates the
menu, kitchen board, courier run list, customer tracking and loyalty card.
The PWA can be installed from the browser; it is not a separate app-store
application. The exact screen, offline and service-worker behavior is in
APP_SPEC.md sections 7 and 10–12.

## Foodora and Wolt

Foodora's Restaurant Integration API sends orders that were placed on
Foodora's marketplace to a merchant POS. Integrating it would restore the
marketplace channel and commission this product is designed to avoid. Foodora
orders are not accepted by this app.

Wolt Drive is different: it can dispatch a courier for an order placed through
Mr. Damascy's own checkout. The app uses it only as an overflow delivery lane
when the kitchen's own couriers are unavailable. Staff request a delivery from
the ready-order board; the integration obtains the availability/fee/ETA quote,
books the courier and stores the external delivery reference and tracking URL.
The mock lane is the default and assigns a local demo courier without making
network calls.

To use the real Wolt Drive lane, set `WOLT_DRIVE_MOCK=0` and provide
`WOLT_DRIVE_API_TOKEN` and `WOLT_DRIVE_CLIENT_ID` in the app's private
environment. Wolt Drive Web at [drive.wolt.com](https://drive.wolt.com) is the
manual alternative. Foodora marketplace credentials and order ingestion are
not part of the integration.

## Payments and operation

Mock payment lanes are the default in development and test. They do not move
real money. Production Vipps requires `VIPPS_MOCK=0` and the merchant
subscription key, MSN, client ID, client secret and webhook secret. Stripe
requires `STRIPE_MOCK=0`, `STRIPE_SECRET_KEY` and
`STRIPE_WEBHOOK_SECRET`. Keep credentials in the private environment file;
never put them in this repository. APP_SPEC describes the exact payment
protocols, callback verification, idempotency and failure behavior.

Local setup:

```zsh
bundle install
bin/rails db:prepare
bin/rails db:seed
bin/rails server
```

Run the app's tests with:

```zsh
bin/rails test
```

Deployment is owned by `RAILS/mrdamascy/mrdamascy.sh` and the repository's
OpenBSD deployment contract (`RAILS/apps.yml` holds the port and domain). The
app runs as a demo at `https://mrd.brgen.no`: one Puma process on
`127.0.0.1:47314` behind relayd, payments in mock mode. On vm23, as dev,
`VPS_DEPLOY_SHA=<sha> zsh OPENBSD/bin/vps-deploy mrdamascy` deploys it and
`curl -fsS http://127.0.0.1:47314/up` answers once it is up. No deploy seeds:
the menu was loaded once, and `db/seeds.rb` destroys every row before it
recreates the menu. Stopping the demo, and removing its route, is
`OPENBSD/RUNBOOK.md`, "Mr. Damascy demo". Do not infer production payment
readiness from a successful mock checkout.

## Allergens: the kitchen must fill these in

Food sold at a distance must name the 14 EU allergens before purchase
(matinformasjonsforskriften). The app has the mechanism, not the data: every
dish's `menu_items.allergens` is empty until the kitchen records it, and until
then the item sheet tells the customer the allergens are not recorded and to
call the kitchen before ordering. Only the kitchen knows its recipes and
suppliers, so nothing here guesses.

For each dish, set a comma list of the keys in `MenuItem::ALLERGENS`
(`gluten crustaceans eggs fish peanuts soybeans milk nuts celery mustard sesame
sulphites lupin molluscs`), or `none` when it holds none of them, for example
`bin/rails runner 'MenuItem.find(ID).update!(allergens: "gluten,milk")'`. An
unknown key is refused. Change a dish's recipe, and its list with it.

## Product assets and future boundary

The restaurant's original logo assets are operator-owned originals. Keep them
byte-for-byte; do not redraw or replace them. Generated dish photographs have
provenance sidecars in `app/assets/images/food/provenance.json`. Reference
captures of the former Webflow site and the current app are retained under
`docs/webflow-reference/` and `screenshots/`.

The orange Vipps wordmark in `app/assets/images/vipps/vipps-wordmark.svg` is
an unmodified copy of the asset published in the Vipps WooCommerce merchant
plugin:
https://github.com/vippsas/vipps-woocommerce/blob/052b7fd57365ec9c68e91a7b60df7af210bb61d2/payment/img/vipps-rgb-orange-pos.svg
Use it without recolouring or stretching. Replace it with the asset supplied
under the restaurant's merchant agreement when that brand kit is available.

Mr. Damascy is the first restaurant intended for the future Brgen Takeaway
surface. That does not make this standalone app a multi-restaurant marketplace
today. Any future integration must preserve its own order/payment ownership
boundary and is not permission to add marketplace coupling pre-emptively.

For implementation detail, read [APP_SPEC.md](APP_SPEC.md). For contribution
constraints, read [AGENTS.md](AGENTS.md). The dated
[`/fix` ledger](docs/fix-ledger.md) is historical evidence, not a competing
specification.
