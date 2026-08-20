# brgen playlist

Music-sharing and listening vertical for brgen, served at `playlist.<city>`
(`playlist.brgen.no`, `playlist.lsangeles.com`). A mountable Rails engine — see
[`../../ENGINES.md`](../../ENGINES.md). Topology: [`../../AGENTS.md`](../../AGENTS.md).

## What it is

Users build playlists and sets, import hosted tracks, and collaborate on them;
synchronized **listening parties** let people listen together with party chat and
timestamped comments. `DillaSketch` ties tracks to the studio/dilla engine for
generated audio (`render_audio`). Likes and listens drive discovery.

## Models (`playlist_*` tables)

`Playlist`, `Track`, `PlaylistTrack`, `Set`, `SetTrack`, `Collaboration`,
`ListeningParty`, `PartyMessage`, `Listen`, `Like`, `TimestampedComment`,
`DillaSketch`, `AudioVersion`.

## Routes

Drawn on `Playlist::Engine`, mounted under `constraints(subdomain: PLAYLIST_SUBDOMAINS)`.
Playlists and sets nest tracks, collaborations, and dilla sketches; sets add
likes and a `listening_party` with party messages; `hosted_tracks` and `listens`
round out import and playback.

## Boundaries

Depends on `pub4-shared` for `User`, auth, tenancy, and the design system.
`isolate_namespace Playlist` gives the `playlist_` table prefix; the host reaches
its helpers as `playlist.playlist_url(…, subdomain: "playlist")`.
