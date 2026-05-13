# brgen

## What matters nearby right now

brgen gives each city its own local discovery system on one Rails 8 codebase.

The core loop is simple:

1. See what matters nearby.
2. Act on it.
3. Leave a trust signal.
4. Improve the next local recommendation.

Everything else serves that loop.

## Value proposition

For residents: find people, events, food, posts, listings, music, and video near you.

For creators: build a local audience and earn from local attention.

For merchants: reach nearby buyers without renting attention from global platforms.

For cities: preserve local activity, memory, and trust.

## Product rule

Do not build five separate apps.

Build one local graph with five surfaces:

- commerce
- dating
- music
- video
- food

A user, place, post, listing, channel, restaurant, playlist, and event should all belong to the same city graph.

## Domains

brgen serves city domains through one Rails 8 codebase and SNI-aware deployment.

Current domain set includes brgen.no, oshlo.no, trndheim.no, stvanger.no, trmso.no, longyearbyn.no, reykjavk.is, kbenhvn.dk, stholm.se, gtebrg.se, mlmoe.se, hlsinki.fi, lndon.uk, cardff.uk, mnchester.uk, brmingham.uk, lverpool.uk, edinbrgh.uk, glasgw.uk, amstrdam.nl, rottrdam.nl, utrcht.nl, brssels.be, zrich.ch, lchtenstein.li, frankfrt.de, wrsawa.pl, gdnsk.pl, brdeaux.fr, mrseille.fr, mlan.it, lsbon.pt, lsangeles.com, newyrk.us, chcago.us, houstn.us, dllas.us, austn.us, prtland.com, and mnneapolis.com.

## Sub-applications

| Namespace | Subdomain | Job | Models |
|---|---|---|---|
| `Marketplace::` | `markedsplass.*` and locale aliases | local commerce | Category, Listing, Order |
| `Dating::` | `dating.*` | local matching | Profile, Like, Dislike, Match |
| `Playlist::` | `playlist.*` | social music | Playlist, Track, PlaylistTrack, Listen |
| `Tv::` | `tv.*` | local creator video | Channel, Video, Broadcast, Subscription, ViewEvent |
| `Takeaway::` | `takeaway.*` | local food | Restaurant, MenuItem, Order, OrderItem |

## Shared primitives

Build these once and use them everywhere:

- `City`
- `Neighborhood`
- `Place`
- `User`
- `TrustSignal`
- `ReputationScore`
- `Event`
- `Post`
- `Conversation`
- `Notification`
- `MediaAsset`
- `SearchIndexEntry`
- `Embedding`

## Feed ranking

Rank by:

- distance
- freshness
- trust
- social proximity
- semantic match
- city relevance
- user intent

Do not rank by engagement alone.

## Map-native interface

The map should show:

- live posts
- listings
- restaurants
- creators
- events
- venues
- crowded places
- neighborhood activity

The feed explains the map. The map should not be an afterthought.

## Trust layer

Add:

- verified locals
- verified merchants
- profile age
- transaction history
- social vouching
- moderation history
- block and report signals

Trust should affect reach, search, matching, and commerce.

## Rails direction

Use Rails 8 patterns for the operational core:

- Hotwire for live feeds, maps, chat, order state, and packing screens
- Solid Queue for ranking jobs, notifications, imports, media jobs, and digest jobs
- Solid Cache for local feed fragments and city landing pages
- Active Storage for photos, videos, thumbnails, menus, and documents
- Action Text for posts, listings, articles, venue pages, and profiles
- Action Mailbox later for inbound support, claims, abuse reports, and merchant workflows

## AI direction

Use AI where it improves local discovery:

- semantic search
- listing deduplication
- moderation
- city summaries
- event extraction
- recommendation embeddings
- map clustering
- trust anomaly detection

Do not lead with AI in the product. Lead with local usefulness.

## Stack

Rails 8, SQLite3 now, PostgreSQL later where needed, Solid Queue, Solid Cache, Hotwire, Falcon, Active Storage, ImageProcessing, I18n, OpenBSD, relayd.

## Deploy

```zsh
doas zsh DEPLOY/rails/brgen/brgen.sh
```

The deploy installs gems, migrates, seeds, registers `rc.d/brgen`, and adds the relayd backend.

DNS, TLS, SNI routing, and city domain setup live under `DEPLOY/openbsd`.

## Long-term goal

Make brgen the fastest way to understand and act on what matters nearby.