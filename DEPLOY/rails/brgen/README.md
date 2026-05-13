# brgen

## Hyperlocal social network

brgen gives each city its own social graph on one shared Rails platform.

It combines local communities, marketplace, dating, playlists, TV, takeaway, events, and neighborhood identity into one local discovery system.

## Value proposition

For residents: see what is happening nearby.

For creators: build a local audience without platform lock-in.

For merchants: reach nearby people directly.

For cities: preserve local memory, trust, and activity.

## Domains

brgen serves city domains through one Rails 8 codebase and SNI-aware deployment.

Current domain set includes brgen.no, oshlo.no, trndheim.no, stvanger.no, trmso.no, longyearbyn.no, reykjavk.is, kbenhvn.dk, stholm.se, gtebrg.se, mlmoe.se, hlsinki.fi, lndon.uk, cardff.uk, mnchester.uk, brmingham.uk, lverpool.uk, edinbrgh.uk, glasgw.uk, amstrdam.nl, rottrdam.nl, utrcht.nl, brssels.be, zrich.ch, lchtenstein.li, frankfrt.de, wrsawa.pl, gdnsk.pl, brdeaux.fr, mrseille.fr, mlan.it, lsbon.pt, lsangeles.com, newyrk.us, chcago.us, houstn.us, dllas.us, austn.us, prtland.com, and mnneapolis.com.

## Sub-applications

| Namespace | Subdomain | Concept | Models |
|---|---|---|---|
| `Marketplace::` | `markedsplass.*` and locale aliases | local commerce | Category, Listing, Order |
| `Dating::` | `dating.*` | local matching | Profile, Like, Dislike, Match |
| `Playlist::` | `playlist.*` | social music | Playlist, Track, PlaylistTrack, Listen |
| `Tv::` | `tv.*` | local creator video | Channel, Video, Broadcast, Subscription, ViewEvent |
| `Takeaway::` | `takeaway.*` | local food | Restaurant, MenuItem, Order, OrderItem |

## Core systems to build next

### Local graph

Model districts, neighborhoods, venues, campuses, streets, scenes, and local groups. Feed ranking should use place, trust, time, social proximity, and semantic similarity.

### City memory

Archive local stories, venues, photos, events, creators, and neighborhood changes. This gives each city a durable public memory.

### Trust layer

Add verified locals, merchant history, social vouching, transaction reputation, and local moderation councils.

### Map-native interface

The map should show live activity, events, crowded places, creators, food, markets, and local alerts.

### Local agents

Build agents for tonight's events, cheap food, apartments, nightlife, local deals, music scenes, and people nearby.

### Local economy

Add gigs, services, rentals, rides, tutoring, repairs, barter, local jobs, and creator storefronts.

## AI direction

Use embeddings, semantic search, GraphRAG, trust-weighted ranking, geo-aware retrieval, and moderation pipelines.

## Stack

Rails 8, SQLite3, Solid Queue, Solid Cache, Hotwire, Falcon, Active Storage, ImageProcessing, I18n, OpenBSD, relayd.

## Deploy

```zsh
doas zsh DEPLOY/rails/brgen/brgen.sh
```

The deploy installs gems, migrates, seeds, registers `rc.d/brgen`, and adds the relayd backend.

DNS, TLS, SNI routing, and city domain setup live under `DEPLOY/openbsd`.

## Long-term goal

Make brgen the local operating layer for cities: social life, commerce, media, dating, music, food, memory, and trust.