# brgen — hyperlocal city network

brgen is the aggregate Rails app for city-scoped social publishing, marketplace, dating, playlist, TV, takeaway, maps, notifications, and local identity.

It keeps the `railsy` product intent, but follows the current pub4 production contract: Rails 8, SQLite, Solid Queue, Solid Cache, Solid Cable, built-in authentication, Falcon, importmap, Hotwire, and OpenBSD rc.d services. The old generator-era assumptions around Devise, Redis, and mandatory PostgreSQL are lineage, not the active deployment shape.

## Surfaces

- Main social network: communities, posts, comments, votes, reactions, follows, messaging, notifications, moderation reports.
- Marketplace: listings, categories, stores, deals, favorites, saved searches, and listing orders.
- Dating: profiles, likes, dislikes, matches, and city-local discovery.
- Playlist: playlists, sets, tracks, listens, audio versions, collaboration, likes, and timestamped comments.
- TV: channels, videos, live streams, stream chats, subscriptions, comments, notes, and view events.
- Takeaway: restaurants, menus, orders, favorite restaurants, delivery drivers.
- Locality: cities, neighborhoods, places, nearby alerts, geolocation, and push subscriptions.
- Trust: external identities, assurance checks, reputation scores, trust signals, account merges.

## Domains

Primary domain: `brgen.no`.

City/domain aliases and subdomains route through OpenBSD `relayd`; app behavior is selected by host and subdomain context inside Rails.

Subdomain apps:

- `tv`
- `dating`
- `playlist`
- `takeaway`
- `marketplace`, plus localized marketplace aliases

## Deploy

```zsh
doas zsh DEPLOY/rails/brgen/brgen.sh
```

The deploy script must copy the tracked app tree, run Bundler, migrate, seed when present, update rc.d, register relayd, restart the service, and verify `/up`.

## Missing logic backlog

- Marketplace buyer-seller chat should reuse conversations instead of creating a parallel message system.
- Playlist sets need routed views for index, show, new, and edit.
- TV and takeaway operational dashboards need explicit views for driver updates, stream chats, and moderation queues.
- Dating needs event integration and premium visibility controls.
- City routing needs a visible locality switcher and domain-to-city audit task.
