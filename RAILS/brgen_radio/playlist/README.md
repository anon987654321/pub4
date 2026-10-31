# brgen playlist

**Music is better when someone is listening with you.** Playlist lets a city build its soundtrack
together, hear the same song at the same moment, and talk over it as it plays.

Playlist is a mountable Rails engine, and the public name of its host is radio: the engine is
served at `radio.<city>`, for instance `radio.brgen.no` and `radio.lsangeles.com`. The engine
keeps the name Playlist in its directory, module and tables, and the host constraint is called
`RADIO_SUBDOMAINS`. The old `playlist.<city>` host no longer resolves, and no alias was kept. The
engine is not a separate app: it runs in brgen's process, with brgen's users. The recipe for a
vertical is in `RAILS/brgen/README.md`, and the topology is in `RAILS/brgen/AGENTS.md`.

Users build playlists and sets, add tracks, and invite collaborators as owner, editor or viewer.
Pasting URLs, one to a line, imports tracks into a playlist from YouTube, Spotify, SoundCloud,
Whyp or a direct link, and any member with a real account can upload an audio file as a hosted
track. A set can open a listening party, where people hear the same thing at the same time and
chat beside it. Listeners leave comments pinned to a moment in a track. Likes and listens drive
discovery.

A `DillaSketch` ties a playlist or a set to the studio's dilla engine. Its `render_audio` action
queues `DillaRenderJob` on the bulk queue, which renders through `Shared::DillaProcessor` and the
STUDIO contract, attaches the render to the sketch, and by default publishes it as a track. When
the dilla script is missing on the machine, the sketch records the failure in its `render_error`
instead of failing quietly.

The models are `Playlist`, `Track`, `PlaylistTrack`, `Set`, `SetTrack`, `Collaboration`,
`ListeningParty`, `PartyMessage`, `Listen`, `Like`, `TimestampedComment`, `DillaSketch` and
`AudioVersion`. `isolate_namespace Playlist` gives their tables the `playlist_` prefix, and the
migrations are in `RAILS/brgen/db/migrate`. Inside the engine, write `::Playlist::Playlist` with
the leading colons, because the plain name resolves to the module's own model first.

Routes are drawn on `Playlist::Engine`, and brgen mounts the engine at the root under
`constraints(subdomain: RADIO_SUBDOMAINS)`. Playlists and sets nest their tracks, collaborations
and dilla sketches. A playlist also has an embeddable page. A set adds a like and a
`listening_party` with its party messages, and `hosted_tracks` and `listens` round out upload
and playback. From the host, reach the helpers as `playlist.playlist_url(…, subdomain: "radio")`.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the design system.
On screen it uses an immersive stage with a transport bar, and it publishes the bar's height so
floating widgets clear it. Its stylesheet rules live in brgen's single `application.scss`,
scoped under `body.vertical-playlist`.


## Original creator-platform promise

The archived Whyp.it-inspired brief called for easy local audio publishing, high-quality playback,
embeds, listening insight, privacy/expiry controls and support for independent creators. The
current engine has hosted tracks, external URL imports, playlists and sets, owner/editor/viewer
collaboration, embeddable players, timestamped comments, listening parties, likes/listen records
and per-track expiry. The Radio Bergen archive is a separate curated import and remains gated by
its tenant and recording-rights preconditions.

Listen and Like records provide the foundation for engagement counts; do not describe a complete
creator analytics dashboard, donations, paid creator tier or sponsored-content marketplace as
shipped without a matching surface and tests. The public host is `radio.<city>`; `playlist.<city>`
is not a supported host.

## Radio Bergen tunnel and curated archive

The Playlist home now renders the existing Radio Bergen tunnel through the Rails
engine view and Stimulus controller rather than a standalone HTML page. Playback
starts after a user gesture. Once the selected crate is imported, the tunnel
plays same-origin Active Storage audio and analyses the actual audio signal.

The exact 35-track selection and ordering live in
`RAILS/brgen/config/radio_bergen/tracks.yml`; filenames map to the archive-root
files in `pub2`, not the stale `mp3/akmd-…` URLs. Audio is deliberately not
committed into Git. The command below is for reference only. Do not execute it
until the tenant-scope blocker is closed and tested locally. Distribution rights
for every recording must also be confirmed.

```sh
RADIO_BERGEN_ARCHIVE_ROOT=/absolute/path/to/pub2 \
RADIO_BERGEN_OWNER_EMAIL=your-existing-account@example.invalid \
RADIO_BERGEN_RIGHTS_CONFIRMED=1 \
bin/rails radio_bergen:import_curated
```

**Blocker:** the request-less rake path does not yet explicitly establish and enforce the `brgen.no` tenant context before creating the public playlist. Running it now could create a nil-city/global playlist. This is a hard blocker, not a test result.

The task is intended to preflight all source files, attach them through Active Storage, and
create the playlist in the original order. It is idempotent for matching audio
and refuses to silently overwrite a changed attachment. The confirmation flag
is an operator attestation, not a legal determination.
