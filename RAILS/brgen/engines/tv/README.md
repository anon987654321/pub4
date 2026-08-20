# brgen tv

Video and live-streaming vertical for brgen, served at `tv.<city>`
(`tv.brgen.no`, `tv.lsangeles.com`). A mountable Rails engine — see
[`../../ENGINES.md`](../../ENGINES.md). Topology: [`../../AGENTS.md`](../../AGENTS.md).

## What it is

Channels publish videos, live streams, and multi-episode shows; viewers comment,
take timestamped video notes, and chat in real time during live streams. View
events and subscriptions drive trending and per-channel feeds.

## Models (`tv_*` tables)

`Channel`, `Video`, `Broadcast`, `LiveStream`, `Show`, `Episode`, `StreamChat`,
`VideoNote`, `Comment`, `Subscription`, `ViewEvent`.

## Routes

Drawn on `Tv::Engine` (`config/routes.rb`), mounted by the host under
`constraints(subdomain: TV_SUBDOMAINS)`. Root is the trending home; channels nest
videos, live streams, and shows/episodes; live streams carry `go_live`/`end_live`
and stream chats. Live stream chat and video notes broadcast over Turbo Streams
(`tv:live_stream:*`, `tv:video:*`) with explicit partials.

## Boundaries

Depends on `pub4-shared` for `User`, auth, tenancy, and the design system.
`isolate_namespace Tv` gives the `tv_` table prefix and unprefixed in-engine route
helpers; the host reaches them as `tv.channel_url(…, subdomain: "tv")`.
