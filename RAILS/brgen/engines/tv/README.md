# brgen tv

**A television channel anyone in the city can start.** tv is a mountable Rails
engine served at `tv.<city>` — `tv.brgen.no`, `tv.lsangeles.com`.
`../../ENGINES.md` is the recipe; `../../AGENTS.md` is the topology.

Channels publish videos, live streams and multi-episode shows. Viewers comment,
take timestamped notes against a video, and chat in real time while a stream
runs. View events and subscriptions feed trending and the per-channel feeds.

The `tv_` tables, prefixed by `isolate_namespace Tv`, are `Channel`, `Video`,
`Broadcast`, `LiveStream`, `Show`, `Episode`, `StreamChat`, `VideoNote`,
`Comment`, `Subscription` and `ViewEvent`.

Routes live in the engine's own `config/routes.rb` and the host mounts them under
`constraints(subdomain: TV_SUBDOMAINS)`. Root is the trending home; channels nest
videos, live streams and shows with their episodes; a live stream carries
`go_live` and `end_live` and its stream chats. Stream chat and video notes
broadcast over Turbo Streams on `tv:live_stream:*` and `tv:video:*`, with
explicit partials rather than inferred ones.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the
design system. `isolate_namespace Tv` also gives unprefixed route helpers inside
the engine; the host reaches them as `tv.channel_url(…, subdomain: "tv")`.
