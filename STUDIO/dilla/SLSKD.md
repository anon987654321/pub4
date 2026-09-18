# slskd sample digging

`demo.rb` can use a local [slskd](https://github.com/slskd/slskd) instance as
an optional sample source. slskd exposes search and transfer APIs under
`/api/v0`; the adapter uses those APIs rather than embedding Soulseek in Dilla.

Run:

`SLSKD_API_KEY=... SLSKD_DOWNLOAD_DIR=/path/to/slskd/completed ruby demo.rb`

The adapter prefers FLAC/WAV/AIFF over lossy formats and prefers peers with an
available upload slot and shorter queues. It copies the selected file into
Dilla's ignored local cache and registers it in the existing chopped-loop
registry, so the ordinary renderer sees it as a normal sample loop.

Soulseek availability is not a licence. The default rights state is `unknown`,
and an unknown result is blocked unless `SLSKD_ALLOW_UNKNOWN=1` is set. For
material whose rights you have actually established, set
`SLSKD_RIGHTS=owned`, `public_domain`, `cc0`, or `cc_by`.

The registry preserves the Soulseek peer, exact filename and byte size, search
query, SHA-256 of the downloaded audio, duration, sample rate, channel count,
rights state, verification state and download timestamp.

For production/release work, keep `SLSKD_ALLOW_UNKNOWN` off. The explicit
unknown mode exists for private experimentation and research; it is not a
copyright bypass.

The slskd API contract is isolated in `lib/slskd_crate.rb`. If slskd changes,
the renderer and the existing Dilla sample registry do not need to know.
