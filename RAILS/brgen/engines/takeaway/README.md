# brgen takeaway

Food-ordering and delivery vertical for brgen, served at `takeaway.<city>`
(`takeaway.brgen.no`, `takeaway.lsangeles.com`). A mountable Rails engine — see
[`../../ENGINES.md`](../../ENGINES.md). Topology: [`../../AGENTS.md`](../../AGENTS.md).

## What it is

Local restaurants list menus; diners build orders, favorite restaurants, and
leave reviews; delivery drivers pick up and fulfill orders. Ordering is the
original takeaway subapp's "items and orders" flow, now its own engine.

## Models (`takeaway_*` tables)

`Restaurant`, `MenuItem`, `Order`, `OrderItem`, `DeliveryDriver`,
`FavoriteRestaurant`, `Review`.

## Routes

Drawn on `Takeaway::Engine`, mounted under `constraints(subdomain: TAKEAWAY_SUBDOMAINS)`.
Root is the restaurant index; restaurants nest menu items, orders, reviews, and a
favorite toggle; `delivery_drivers` and top-level `orders` cover the fulfillment
and order-status side.

## Boundaries

Depends on `pub4-shared` for `User`, auth, tenancy, and the design system.
`isolate_namespace Takeaway` gives the `takeaway_` table prefix; the host reaches
its helpers as `takeaway.restaurant_url(…, subdomain: "takeaway")`.
