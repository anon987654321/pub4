# brgen takeaway

**Good food from kitchens in your city, ordered without leaving the local network.** Takeaway
connects restaurants, their menus, neighbours and delivery drivers. It is the food-ordering
surface inside Brgen Marketplace, not a separate Rails application.

The canonical route is `/food` on the city's localised Marketplace host, for example
`markedsplass.brgen.no/food` or `marketplace.lsangeles.com/food`. The historical
`takeaway.<city>` host remains a compatibility mount. New links should use Marketplace.
The topology is described in `RAILS/brgen/README.md` and `RAILS/brgen/AGENTS.md`.

## Recovered product promise

The original Brgen plan described local restaurant discovery, menus, ordering, order tracking
and delivery coordination. The current Takeaway engine has grown beyond a static restaurant
directory:

- Public restaurant discovery with cuisine filtering, live search, city context and nearby
  restaurants when coordinates are known.
- Restaurant-owned menus, item availability, photos, opening hours, minimum order values,
  delivery fees and stated delivery radii.
- Guest-friendly browsing and ordering without forcing a full account registration first.
- Server-calculated order totals, delivery address and optional tip; client-submitted totals are
  never trusted.
- A guarded order lifecycle: pending, confirmed, preparing, out for delivery, delivered or
  cancelled. Invalid transitions are refused.
- Scheduled orders, immediate-cart expiry, reorder from a previous order and customer-visible
  status notifications.
- Shared group orders: one host opens a token-addressed order, invites others to add their own
  lines, and places the combined ticket.
- Delivery-driver profiles, availability and dispatch relationships; a driver is attached to an
  order only when the dispatch rules have a suitable candidate.
- Restaurant reviews tied to a delivered order, favourites, local discovery and verified
  business status through Brgen's shared verification workflow.
- Activity graph events and shared media processing.

The implementation is backed by the nested engine at
`RAILS/brgen_marketplace/engines/takeaway`, with host-owned migrations and shared Brgen
identity/tenant records. The precise status and implementation notes live in `RAILS/apps.yml`.

## Ordering and delivery boundaries

A restaurant with recorded opening hours is treated as open only when those hours say so.
Scheduled orders may be placed for a future time. When a restaurant has not supplied hours,
the application does not invent a closing schedule.

Delivery-radius checks run only when the restaurant has supplied a radius and both sides have
usable coordinates. A free-text address is not silently geocoded, and missing coordinates are
not replaced with a guessed city-centre pin. Driver dispatch can leave an order unassigned when
there is no verified candidate; the product must not pretend a courier accepted a delivery when
none did.

The current order lifecycle and driver assignment are not a third-party courier network. Live
GPS tracking, route optimisation, external courier APIs, guaranteed delivery ETAs and a
market-wide logistics exchange are separate work until implemented and tested.

## Architecture

Takeaway is nested inside `brgen_marketplace` and mounted by the Brgen host. Its models use the
`Takeaway::` namespace and `takeaway_` table prefix. Migrations are maintained in
`RAILS/brgen/db/migrate`, not in a second independent database.

The engine class includes `Shared::VerticalEngine`. Routes are drawn on
`Takeaway::Engine`; from the Marketplace host the route helpers are namespaced under
`takeaway`. Keep restaurant, menu, order and driver records in the shared city/tenant context.

Marketplace and Takeaway intentionally share the commerce and campaign foundations while
keeping distinct navigation and user journeys. Their nav bars remain separate partials because
their section lists, cart behaviour and route helpers differ.

## Safety and trust

- Restaurant owners may change their own menus and restaurant details.
- Orders remain receipts and are not deleted when a restaurant is archived.
- Buyers can see only their own orders; restaurant owners can see orders for their own kitchen.
- Reviews require a delivered order.
- Order totals are calculated on the server from available menu items.
- Webhook and payment state must come from verified provider events, never a browser return URL.

## Still to build

The archived promise of end-to-end delivery coordination is only partly fulfilled. The next
substantial steps are a tested driver dispatch/acceptance flow, customer-facing delivery status
and ETA semantics, courier location updates with explicit consent, and a provider adapter only
when a real courier partner is selected. Restaurant payout and payment flows must remain
consistent with Marketplace's provider contracts.

Do not revive the old PostgreSQL, Redis, Mapbox, Nginx or Rails 8.0 setup instructions. The
current stack is pinned in `RAILS/apps.yml` and the Brgen host's Gemfile/lockfile.
