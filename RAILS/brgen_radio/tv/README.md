# brgen tv

**A television channel anyone in the city can start.** Tv gives every neighbourhood a screen of
its own, for what the town makes, what it streams live and what it wants to watch next.

Tv is a mountable Rails engine served at `tv.<city>`, for instance `tv.brgen.no` and
`tv.lsangeles.com`. It is not a separate app: it runs in brgen's process, with brgen's users,
and the city comes from the apex. The recipe for a vertical is in `RAILS/brgen/README.md`, and
the topology is in `RAILS/brgen/AGENTS.md`.

Channels publish uploaded videos and shows with numbered episodes. Viewers comment, take
notes pinned to a moment in a video, and follow channels by subscribing. The data model also
represents broadcasts and live-stream states, but production live-video ingest and delivery are
not available yet: that requires a media server and an external delivery/transcoding tier. The home page is a grid of trending, live and recent videos, ranked by watch
time. The feed at `/feed` is the other shape, one video to a screen, ranked by how much of each
people actually watched, ten at a time. Both depend on `ViewEvent`, which records watch time
because a view counted at page load ranks a bounce like a full watch. Each clip may be built on
a `Sound`, and a sound has a page that gathers every clip made on the same audio.

The models are `Channel`, `Video`, `Broadcast`, `LiveStream`, `Show`, `Episode`, `StreamChat`,
`VideoNote`, `Comment`, `Subscription`, `ViewEvent` and `Sound`. `isolate_namespace Tv` gives
their tables the `tv_` prefix, and the migrations are in `RAILS/brgen/db/migrate`.

Routes live in the engine's own `config/routes.rb`, and brgen mounts the engine at the root
under `constraints(subdomain: TV_SUBDOMAINS)`. Channels are addressed by slug and nest their
videos, live streams and shows. A live stream carries `go_live` and `end_live` and its stream
chats. Stream chat and video notes broadcast over Turbo Streams, on `tv:live_stream:<id>:entries`
and `tv:video:<id>:notes`, with explicit partials rather than inferred ones. Inside the engine
the helpers carry no prefix, so a link reads `channel_url`. From the host, reach them as
`tv.channel_url(…, subdomain: "tv")`.

A new city starts with no television, so the engine ships a content pipeline. The rake task
`tv:starter_pack` writes clips, posters and a manifest. It generates with Replicate when
`REPLICATE_API_TOKEN` is set. Without the token it refuses in plain words, and with
`TV_TEST_CARDS=1` it draws honest test cards with ffmpeg instead. The task `tv:ingest` reads a
manifest into a channel with published videos. It matches channels by slug, so it can run again.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the design system.
Its models include the shared concerns for media processing, notifications, reactions and
slugs.
