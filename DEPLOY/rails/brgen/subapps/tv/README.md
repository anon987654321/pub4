# brgen :: tv

Local-channel television. User-run channels broadcast to a city.

- Namespace: `Tv::`
- Subdomain: `tv.brgen.no`
- Route prefix: `/tv`

## Models

| Model | Notes |
|---|---|
| `Tv::Channel` | Owner, name, description, logo |
| `Tv::Video` | Uploaded MP4 (Active Storage), title, runtime, channel |
| `Tv::Broadcast` | Live or scheduled airing of a `Video` on a `Channel` |
| `Tv::Subscription` | User → Channel follow; drives notifications |
| `Tv::ViewEvent` | Per-user playback event; powers analytics + recommendations |

## Streaming

Recorded video served via Active Storage + Cloudflare CDN. Live broadcast via Action Cable signaling + WebRTC peer relay (planned).
