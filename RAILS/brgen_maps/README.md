# brgen maps

**Places and a live map, for whichever city you arrived through.** Maps puts the shops, cafes
and corners of your town on one screen and lets you say that you were there.

Maps is a mountable Rails engine served at `maps.<city>`, for instance `maps.brgen.no` and
`maps.lsangeles.com`. It is not a separate app: it runs in brgen's process, with brgen's users,
and the city comes from the apex. The recipe for a vertical is in `RAILS/brgen/README.md`, and
the topology is in `RAILS/brgen/AGENTS.md`.

The home page draws the map on a MapLibre canvas, with tiles from OpenFreeMap, and places the
city's points on it. The places page lists them, with a live search and a filter by kind, and
answers JSON to the same query for the map. A place page shows the recent check-ins and the
places nearby. A signed-in visitor, a soft guest included, can check in with a short note.

The engine owns routes, controllers and views only. `Place` and `PlaceCheckIn` stay in brgen's
models, because restaurants and stores point at a place too, so it has more than one consumer
and is shared the way `User` is. Check-ins therefore live in brgen's database, in
`place_check_ins`, with no `maps_` tables. Routes are drawn on `Maps::Engine`, and brgen mounts
the engine at the root under `constraints(subdomain: MAPS_SUBDOMAINS)`. The map is built in the
browser, and no stream or toggle ever refreshes the maps home page, so it carries no guard
against Turbo's page morph yet. Add one before anything starts to refresh that page.
