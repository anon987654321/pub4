# brgen :: tv

Public domain: tv.brgen.no

Local video, shows, and channels integrated into Brgen Core.

- Namespace: `Tv::`
- Subdomain: `tv.brgen.no`
- Route prefix: `/tv`

## Core dependencies

- Brgen identity
- Brgen feed
- Brgen media pipeline
- Brgen notifications
- Brgen moderation
- Brgen search

## Models

| Model | Notes |
|---|---|
| `Tv::Channel` | Owner, name, description, logo |
| `Tv::Video` | Uploaded video, title, runtime, channel |
| `Tv::Broadcast` | Live or scheduled airing of a video on a channel |
| `Tv::Subscription` | User to channel follow relationship |
| `Tv::ViewEvent` | Playback event powering analytics and recommendations |
| `Tv::Show` | Optional longform show grouping |
| `Tv::Episode` | Optional episodic content model |

## Streaming

Recorded media should use the shared Brgen media pipeline and Active Storage integration.

Realtime/live functionality should integrate with the shared realtime infrastructure.

## Events

- VideoPublished
- BroadcastScheduled
- ChannelCreated
- EpisodePublished
- ViewingProgressed

## Discovery

Videos and channels should participate in the shared Brgen discovery graph and feed ranking.
