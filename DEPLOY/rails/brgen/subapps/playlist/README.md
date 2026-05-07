# brgen :: playlist

Local music discovery. Share playlists, find what your city listens to.

- Namespace: `Playlist::`
- Subdomain: `playlist.brgen.no`
- Route prefix: `/playlist`

## Models

| Model | Notes |
|---|---|
| `Playlist::Playlist` | Owner, title, public/private, cover art (Active Storage) |
| `Playlist::Track` | Title, artist, duration, source URL (Spotify/SoundCloud/local) |
| `Playlist::PlaylistTrack` | Join with `position` for ordering |
| `Playlist::Listen` | Per-user play event; powers trending and personal history |

## Trending

City-scoped trending feed: aggregates `Listen` rows over a rolling window, filtered by user-city.
