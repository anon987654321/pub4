# brgen messenger

**The city's conversations, without losing the thread.** Messenger is the private and group
conversation surface shared by people using Brgen. It should feel immediate, but its deeper
promise is continuity: a conversation remains readable, searchable, safe to leave, and useful
across devices and time.

Messenger is a mountable vertical surface at `messenger.<city>`, for example
`messenger.brgen.no` and `messenger.lsangeles.com`. Its routes are drawn by the Brgen host;
the `brgen_messenger` engine supplies the vertical's autoloading and JavaScript assets. It is
not a separate Rails application, database, identity system or deployment. The host topology
and engine rules are documented in `RAILS/brgen/README.md` and `RAILS/brgen/AGENTS.md`.

## Recovered product intent

The original Brgen brief promised real-time messaging as part of one integrated city network.
The later architecture adds the features that make messaging dependable rather than merely
instant: durable history, identity and privacy boundaries, moderation, and a clear distinction
between direct messages, group conversations and public rooms.

The current implementation includes:

- Direct conversations reused for the same pair of people, rather than creating a new thread
  every time a different entry point is used.
- Group conversations with membership, an owner/operator role, member invitations and safe
  handover when the last operator leaves.
- Live message delivery through Turbo Streams, with typing indicators and read receipts.
- Message replies, editing within a bounded window, unsending, forwarding and link previews.
- Image attachments and audio voice notes, validated on the server as well as in the composer.
- Search across conversation titles and message bodies, pinned conversations, archive/resurface
  behaviour and cursor-based load-earlier history.
- Per-conversation disappearing-message modes, including view-once semantics, with expiry
  removing content from search, forwarding and previews.
- Story replies that continue in the DM thread after the original story expires.
- Channel rooms, role/mode handling and bot participation; MASTER can be invited to a direct
  or group conversation.
- A responsive desktop layout with a room rail, inbox, thread and contextual artifact pane.

These are code-backed capabilities recorded in the Brgen feature inventory. The authoritative
implementation is in the host models/controllers plus the engine's Stimulus controllers; see
`RAILS/apps.yml` for the precise inventory.

## Privacy and safety

A private message is not a public city post. Conversation membership scopes access to the thread;
blocks are checked in both directions for direct conversations. Attachments are restricted to
supported image and audio media types. Message history is not silently discarded when a sender
deletes an account: the erasure path unsends that person's content and purges attachments while
preserving the thread structure needed by other participants.

Disappearing messages are a user-selected retention mode, not a guarantee against screenshots,
copies or a recipient recording content elsewhere. Voice notes are attachments, not a promise of
end-to-end encrypted calls. The current product does not claim end-to-end encryption.

## What the original brief did not specify

Messenger should eventually make safety controls, notification preferences and account/device
session management easy to understand. Any future encryption, federation, calling or file-sharing
work must begin with a threat model and explicit compatibility decisions; it must not be added as
a cosmetic badge or implied by the word private.

## Architecture

The engine lives at `RAILS/brgen_messenger`. The host owns the shared conversation and message
models because the Brgen feed, dating matches, marketplace listings, stories, channels and
messenger surface all use the same conversation graph. Do not duplicate those models inside the
engine.

`BrgenMessenger::Engine` includes `Shared::VerticalEngine`, which puts the engine's JavaScript
controllers on the asset path. The actual routes are host-drawn under the Messenger subdomain
constraint. Use the host's route helpers and preserve the existing city/tenant scope.

The engine depends on `pub4-shared` for identity, authentication, tenancy, media processing and
shared UI. Read the host's agent notes before changing routes, models or shared concerns.

## Development

Run the Brgen host's test suite for messenger changes; the engine's shared test inventory is
listed in `RAILS/test/engine_roots.rb`. Add regression tests for access control, duplicate direct
threads, group ownership, expiry, unread/read receipts, pagination cursors, attachment types and
Turbo broadcasts whenever those contracts change.

Do not revive the historical PostgreSQL/Redis/ActionCable/StimulusReflex instructions. The active
stack is the one pinned in `RAILS/apps.yml` and the host Gemfile/lockfile.
