# brgen :: dating

Local-first dating. Discover people in your city.

- Namespace: `Dating::`
- Subdomain: `dating.brgen.no`
- Route prefix: `/dating`

## Models

| Model | Notes |
|---|---|
| `Dating::Profile` | Display name, bio, photos, age range, distance preference; one per `User` |
| `Dating::Like` | One-way interest signal between profiles |
| `Dating::Dislike` | Hide a profile from future swipes |
| `Dating::Match` | Reciprocal `Like` pair; opens chat via existing `Conversation` model |

## Discovery

Profiles are filtered by city (subdomain) and distance radius. Matching unlocks the shared messaging stack (`messages_controller`, Action Cable `MessagesChannel`).
