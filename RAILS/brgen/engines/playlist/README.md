# brgen playlist

**Music is better when someone is listening with you.** playlist is a mountable
Rails engine served at `playlist.<city>` — `playlist.brgen.no`,
`playlist.lsangeles.com`. `../../ENGINES.md` is the recipe; `../../AGENTS.md` is
the topology.

Users build playlists and sets, import hosted tracks, and collaborate on them.
Synchronised listening parties let people hear the same thing at the same time,
with party chat and timestamped comments against the audio. `DillaSketch` ties a
track to the studio's dilla engine so `render_audio` can generate one. Likes and
listens drive discovery.

The `playlist_` tables, prefixed by `isolate_namespace Playlist`, are `Playlist`,
`Track`, `PlaylistTrack`, `Set`, `SetTrack`, `Collaboration`, `ListeningParty`,
`PartyMessage`, `Listen`, `Like`, `TimestampedComment`, `DillaSketch` and
`AudioVersion`.

Routes are drawn on `Playlist::Engine` and mounted under `constraints(subdomain:
PLAYLIST_SUBDOMAINS)`. Playlists and sets nest tracks, collaborations and dilla
sketches; sets add likes and a `listening_party` with its party messages;
`hosted_tracks` and `listens` round out import and playback.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the
design system. The host reaches its helpers as `playlist.playlist_url(…,
subdomain: "playlist")`.
