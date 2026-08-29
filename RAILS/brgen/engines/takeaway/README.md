# brgen takeaway

**Dinner, from the restaurant three streets over.** takeaway is a mountable Rails
engine served at `takeaway.<city>` — `takeaway.brgen.no`,
`takeaway.lsangeles.com`. `../../ENGINES.md` is the recipe; `../../AGENTS.md` is
the topology.

Local restaurants list menus, diners build orders and favourite the places they
come back to and leave reviews, and delivery drivers pick up and fulfil. The
`takeaway_` tables, prefixed by `isolate_namespace Takeaway`, are `Restaurant`,
`MenuItem`, `Order`, `OrderItem`, `DeliveryDriver`, `FavoriteRestaurant` and
`Review`.

Routes are drawn on `Takeaway::Engine` and mounted under `constraints(subdomain:
TAKEAWAY_SUBDOMAINS)`. Root is the restaurant index; restaurants nest menu items,
orders, reviews and a favourite toggle; `delivery_drivers` and top-level `orders`
carry the fulfilment and order-status side.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the
design system. The host reaches its helpers as `takeaway.restaurant_url(…,
subdomain: "takeaway")`.
