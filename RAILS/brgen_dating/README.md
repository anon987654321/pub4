# brgen dating

**Matchmaking for a city you already live in.** Dating shows you the people of your own town,
asks them to prove they are who they look like, and leaves the rest to the two of you.

Dating is a mountable Rails engine served at `dating.<city>`, for instance `dating.brgen.no`
and `dating.lsangeles.com`. It is not a separate app: it runs in brgen's process, with brgen's
users, and the city comes from the apex the visitor arrived through. The recipe for building
a vertical is in `RAILS/brgen/README.md`, and the topology is in `RAILS/brgen/AGENTS.md`.

Each person builds a profile of photos, a short bio and up to three prompt answers. The deck
shows one candidate at a time, and the next one comes from `home#next`. A like or a dislike
moves the deck along, and a rewind undoes the last dislike. When two people like each other the
engine creates a match, and the matches page lists them. A separate page shows who has liked
you, since that is a different decision from swiping through the deck. A short list of picks,
five a day, gives a break from a deck with no bottom. The list is stored, so it stays the same
all day, and it skips anyone who was picked earlier in the week.

Two things stand between a stranger and a face in the deck. Making or editing a profile asks
for Vipps Login first, because a verified phone number puts a real person behind a profile.
Beyond that, a person can ask for a verification: a selfie in a pose the app draws at random,
reviewed by a human. Face matching is not automatic, since it fails on the people it should
serve, and a wrong rejection on a dating profile is worse than a slow approval. Only a
reviewer, the same admin who works the moderation queue, may approve or reject one.

The Vipps check fails closed. With `VIPPS_CLIENT_ID` and its secret in `/etc/brgen.env`, only a
Vipps-verified account can put a profile in the deck. Without the keys the writing surfaces lock:
the old behaviour treated a missing variable as an open door, which is the wrong default for a
dating product. A server that deliberately runs without Vipps keys (a demo, a fixture city) opens
the gate only when the operator sets `DATING_IDENTITY_BYPASS=demo` in the same env file — a named
decision, visible next to the variables it stands in for.

The models are `Profile`, `Prompt`, `Like`, `Dislike`, `Match`, `DailyPick` and `Verification`.
`isolate_namespace Dating` gives their tables the `dating_` prefix. The engine lives in
brgen's database and carries no migrations of its own; they are in `RAILS/brgen/db/migrate`.
Routes are drawn on `Dating::Engine`, and brgen mounts the engine at the root under
`constraints(subdomain: DATING_SUBDOMAINS)`. From the host, reach its helpers namespaced, as
in `dating.matches_url(…, subdomain: "dating")`.

## Original product promise and present boundary

The archived brief described a safe, local way to meet people: profiles, preference-aware
discovery, geographic controls, mutual matches, conversation and member-controlled privacy.
The current engine delivers city/radius discovery, profile photos and prompts, like/dislike and
rewind flows, mutual matches, a held daily pick, a message hand-off, and a human-reviewed
verification request. Vipps identity gating fails closed when configured; an unconfigured
production server does not silently admit unverified profile publishing.

Brgen's shared events surface remains the place for city events. A dedicated dating-event planner,
paid boosts, premium membership and super-likes are not presented as live Dating features. The
old brief's claims of ML-powered compatibility, anonymous browsing modes, online-presence
indicators and automatic facial verification are not current implementation facts. Matching must
remain two-sided and respectful: location is a discovery filter, not a public exact-location
disclosure, and a verification badge means a human-reviewed request was approved.

The engine depends on `pub4-shared` for `User`, authentication, tenancy and the design system,
and its boot shape comes from `Shared::VerticalEngine`. Its strings live in the engine's own
Norwegian and English locale files, and Norwegian is the default.
