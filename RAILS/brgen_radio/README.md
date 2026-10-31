# Brgen Radio and TV

Brgen's local media surfaces let a city publish and discover sound and moving images without
splitting the community into unrelated networks. Both are mountable engines inside the Brgen
Rails process.

- **Radio** is the public name of the Playlist engine at `radio.<city>`. Its code and models
  retain the `Playlist` namespace.
- **TV** is the video and channel engine at `tv.<city>`.

The city/host topology is defined by `RAILS/brgen/README.md` and
`RAILS/brgen/AGENTS.md`. These engines share Brgen identity, tenancy, media processing and
activity infrastructure.

## Product briefs

- [Radio / Playlist](playlist/README.md) — local audio publishing, playlists, collaboration,
  hosted tracks, embeddable players, listening parties, timestamped comments and expiry.
- [TV](tv/README.md) — channels, uploaded video, shows, episodes, subscriptions, watch-time
  discovery, video notes and the live-stream model boundary.

The historical plans also mentioned a record label, creator donations, premium audio tiers,
global music discovery and full live video. Those remain product opportunities, not claims that
the corresponding workflows are already operating. Radio's curated Radio Bergen import has
separate tenant and rights preconditions documented in the Playlist README.

## Architecture rule

Do not create separate Rails applications for Radio or TV. Their engine code is mounted by Brgen
and their records live in the Brgen database. The active implementation and remaining work are
listed in `RAILS/apps.yml`.
