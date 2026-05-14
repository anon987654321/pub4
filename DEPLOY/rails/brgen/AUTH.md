# brgen auth

## Decision

Use Rails 8 custom authentication as the primary auth stack.

Do not use Devise as the core session system.

Use external identity providers through a small adapter layer:

- Vipps / BankID for Norwegian high-trust login
- generic OpenID Connect where provider support exists
- guest identity for anonymous posting and chat

## Why not Devise core

Devise solves standard account auth.

brgen needs a locality-aware identity graph:

- guest users
- anonymous posting
- chat presence
- trust scores
- city-scoped reputation
- verified locals
- verified merchants
- BankID assurance
- cross-subapp sessions
- moderation state
- account upgrades

That is not a simple Devise-shaped problem.

A custom Rails 8 auth layer keeps the domain model explicit.

## Devise-guests

Do not depend on `devise-guests` as a hard platform dependency.

Implement guest identity directly.

Guest identity must support:

- anonymous posts
- chat presence
- rate limits
- abuse history
- later account upgrade
- merge into verified account
- safe deletion

A guest is not fake authentication. It is a real low-assurance identity.

## Assurance levels

Use explicit identity assurance.

| Level | Meaning | Examples |
|---|---|---|
| `guest` | browser/session identity | anonymous posting, chat read/write with limits |
| `account` | email/password account | normal posting, follows, saved profile |
| `phone` | phone verified | marketplace contact, stronger anti-spam |
| `bankid` | Norwegian high-assurance identity | payments, merchant verification, high-trust actions |
| `merchant` | verified business | restaurant, shop, paid listing, takeaway |
| `moderator` | trusted local moderator | local moderation actions |

Trust should depend on assurance plus behavior. Assurance alone is not reputation.

## Vipps / BankID

For Norwegian sites, login should support Vipps / BankID when available.

Implementation rule:

- hide provider details behind `IdentityProvider`
- store provider subject identifiers, not assumptions about national ID payloads
- request the minimum claims needed
- keep BankID login separate from payment authorization
- require explicit user consent before linking identities

## Core models

Suggested models:

- `User`
- `Session`
- `GuestIdentity`
- `IdentityProvider`
- `ExternalIdentity`
- `IdentityAssurance`
- `TrustSignal`
- `ReputationScore`
- `AccountMerge`
- `ModerationFlag`

## Guest upgrade flow

A guest can become a full user without losing history.

Flow:

1. guest acts
2. guest hits action requiring account
3. user creates account or uses provider login
4. system links guest identity to user
5. system preserves allowed posts, chats, and trust signals
6. system keeps abuse history attached

Never erase negative trust signals during account upgrade.

## Anonymous posting

Anonymous posting must mean public anonymity, not system anonymity.

The system should retain:

- author identity
- city
- trust state
- moderation state
- abuse signals

The public should see an anonymous label.

Moderation should still know the actor.

## Chat

Guest chat is allowed only with limits.

Require stronger assurance for:

- private DMs
- marketplace seller contact
- dating messages
- repeated links
- media uploads
- high-volume posting

## Rails implementation

Use Rails 8 generated authentication as the base shape:

- `User`
- `Session`
- signed session cookie
- password reset
- rate limits

Extend it with:

- guest session creation
- external identity linking
- assurance levels
- trust signals
- account merge flow

## Controller contract

Application controllers should expose:

- `authenticated?`
- `current_user`
- `guest?`
- `verified?`
- `requires_account!`
- `requires_bankid!`
- `requires_merchant!`

## Security rules

- Host determines locale before auth views render.
- Unknown hosts return 404.
- Guest sessions must rotate on upgrade.
- Provider callback state must be signed and single-use.
- External identity linking must require a logged-in session or explicit callback flow.
- Do not trust email alone from external providers.
- Do not log identity tokens.

## Product rule

Do not make login the first user action.

Let users read, explore, chat lightly, and post anonymously with limits.

Require stronger identity only when risk increases.
