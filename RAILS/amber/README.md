# amber

**A wardrobe that knows what is in it, what you actually wear, and what it is only guessing
at.** amber is Ragnhild's wardrobe app. It holds garments and outfits, runs the KonMari
declutter loop, keeps a style timeline of how your taste has moved, and makes recommendations
that can say where they came from. It is a Rails 8.2.0.alpha app on SQLite behind Falcon, with
Hotwire, Active Storage, Solid Queue and relayd, and it listens on port 61352.

## Character

Amber is a personal wardrobe intelligence, not a fashion shop. Its territory is warmth, intimacy
and taste with evidence: the wardrobe is the source of truth, a recommendation explains itself,
and the product helps its owner wear and understand what already hangs in the closet before it
encourages another purchase. The design values come from MASTER/data/tokens.yml through
Master.tokens, and the feature matrix is RAILS/apps.yml under amber.

The app defaults to Norwegian. The default locale is nb, with en available, and a request picks
its language from a ?locale= parameter, then the session, then Accept-Language, then nb. A
switcher in the footer sets it. Chrome, empty states and flash messages all go through I18n, and
the sentences the shared engine owns, such as not_authorized and rate_limited, come from
shared.flash. Tests assert through keys and never through English literals.

## The original fashion-network promise, restored honestly

The first Amber brief was broader than a wardrobe tracker: a fashion companion where people could
photograph what they own, understand their taste, compose new looks, care for garments, discover
ideas and share style with others. That ambition still guides the product. The old list is not,
however, a declaration that every proposed surface shipped.

The promise resolves against the current application as follows:

- **Wardrobe photography and visualisation — shipped, with a narrower image pipeline.** Members
  upload garment photographs, see their wardrobe and use the dressing room. Processing makes
  Active Storage variants, applies one portrait polish pass and extracts a dominant colour.
  Automated garment cut-out, background removal, relighting, AI-model try-on and true image
  segmentation are not present.
- **Daily styling and mix-and-match — shipped.** The daily Style Assistant builds a weather-aware
  look from the member's own garments. The dressing room has four taste-ranked, counter-rotating
  zone carousels; explanations draw on stated preferences, joy, wear, recency and life phase.
- **Fashion feed and community — partly shipped.** Amber has posts, comments, reactions, follows,
  mutual connections and direct messages. It can display supported media-link players. This is
  a member-created social feed, not a continuously curated runway or global-trend feed, and it is
  not a public live-chat room.
- **Shop smarter — shipped as a restraint-first assistant.** It surfaces wardrobe gaps, duplicate
  candidates and affiliate links the member has chosen to save. It does not import a global
  fashion catalogue or push purchases as the default answer.
- **Wardrobe analytics and closet care — shipped.** Usage, cost per wear, idle garments, category
  mix, wear distribution, care, storage, zoning and restraint advice are available. These scores
  and tips are heuristics, not independent sustainability or lifecycle certifications.
- **Travel packing — shipped in a basic form.** A member can generate and save a packing list from
  wardrobe items for a selected trip duration and climate. It is not a full itinerary planner.
- **Community feedback and challenges — partly shipped.** Members can discuss and react to posts;
  declutter challenges help decide whether to keep or release a garment. They are not public
  fashion competitions with rankings or prizes.
- **Mood, occasion and style discovery — partly shipped.** Mood-board matching, occasion coverage,
  style preferences and occasion-aware outfit suggestions exist. A dedicated emotional mood
  coach and a calendar-linked event outfit planner remain distinct product work.
- **Weather suggestions — shipped with a defined boundary.** The daily look can use cached
  Bergen weather. Do not imply global weather coverage or a live weather agent.
- **Care, repair and sustainability — partly shipped.** Care and storage guidance and a
  heuristic sustainability score exist. Repair estimates, recycling workflows, resale and
  lifecycle assessment are not yet a complete product.
- **Inclusive styling — a design constraint, not a finished fit engine.** Amber must remain useful
  without judging bodies or assuming one ideal shape. Body-aware fit advice and virtual fitting
  are not shipped.
- **Not yet delivered:** virtual fitting, live webcam/video streaming, a dedicated inspiration
  library, DIY/fabric-design tools, celebrity-look matching, runway reviews, fashion-history
  publishing, global trend intelligence and local-designer discovery.

The old phrase “AI-enhanced” also needs precision. OpenRouter can power selected analyses when
configured; otherwise explicit deterministic rules and heuristics are used. A photo fingerprint
is an exact local checksum, not semantic visual search. A scheduled style session is a calendar
record, not a webcam broadcast. These boundaries are part of Amber's trust contract, not caveats
to hide.

## The wardrobe

An Item is a garment, with its colour, size, material, brand, price, category and photographs,
and it computes its own cost per wear. An Outfit joins items in order. Wear logs, planned
outfits and style preferences record how the wardrobe is used and what the owner says she likes.
A WardrobeItem is not a duplicate of Item: it belongs to one garment and one user and carries
only the condition of that garment in that wardrobe. Analytics counts in SQL, so a large
wardrobe is never loaded whole, and four figures draw the picture without a chart library:
category mix, wear distribution, cost per wear and what sits idle.

Photographs go through WardrobeMediaJob, which makes the variants, gives a portrait one polish
pass and extracts the dominant colour. It does not cut the garment out of its background, and no
segmentation or matting exists in the tree. Upload takes a drag and drop onto the item form.

## The declutter loop

The KonMari loop is complete. A garment gets a joy score, and DeclutterScore folds joy, utility
and fit into one recommendation. A challenge binds a user, an item and a due date, and it ends
completed, skipped or expired. A release candidate gets a last-chance outfit, a final way to
wear it before it goes. The decision routes to a destination and a donation bucket.
DeclutterHygieneJob runs every morning at six, expires overdue challenges and nudges anything
that has sat in the declutter box for thirty days.

## What the intelligence is

The intelligence is heuristic and says so. When OPENROUTER_API_KEY is set, the joy analysis, the
outfit suggestions and the capsule path call google/gemini-2.0-flash-001 through OpenRouter.
When it is not set, which is the usual case on the production box, deterministic rules answer
and the interface states which one did.

TasteRanker blends declared style preferences with joy, wear count, recency and life phase at
fixed weights, so it is a formula and not a learned model. StyleAssistant picks one look a day,
deterministic for each user and date, aware of the weather, and it stores nothing until the
owner saves the look. The weather is open-meteo for Bergen alone, cached for fifteen minutes,
with a failed answer cached too and the connection bounded at two seconds to open and three to
read, because it sits in front of the dashboard.

The scores are targets and not judgements. WardrobeGap compares the closet with a fixed list of
essentials per category. The sustainability score scales and caps wear count and adds a bonus
for joy, and it is not a lifecycle assessment. ClosetOrganization offers care, storage, zoning
and restraint tips, each naming the principle behind it, and WardrobeAnalytics adds its own
nudges. These are rules and the interface labels them as rules.

Two things that sound like AI are not. A garment fingerprint is a local CRC checksum over the
image bytes, which finds a repeated upload and never a lookalike, and EmbedGarmentJob survives
only as an alias of FingerprintGarmentJob so that queued rows still find a class. There are no
embeddings anywhere, and the vector column is JSON because pgvector would require Postgres.
DuplicateDetector follows from that: it groups items on an exact key made from category, colour,
material and brand, so two similar shirts that differ in any of those are not duplicates to it.
Style sessions carry a calendar date and a status and are not video. Shop the Look ranks the
affiliate links the owner added herself, and its remote half needs TRADEDOUBLER_TOKEN, which
lives on brgen, and says so when that half is dark. amber imports no product feed.

## The social side

amber shares the social stack with brgen. It has a feed of posts with comments, reactions,
follows and mutual connections, messages, and scheduled style sessions. Posts that carry a
YouTube, SoundCloud, Vimeo or Spotify link show a player facade, and the lookup waits for the
hourly queue drain, so the plain link shows until then. A creator profile can publish a garment
for others to remix, under the consent rules in the owner's privacy settings, and
WardrobeVisibilityPolicy answers every question of who may view, remix or analyse what. MASTER
can be invited into a message thread. A sign-in from brgen never reaches amber, because the
session cookie is scoped to the registrable domain, and the one door between them is the
MASTER-signed token at /sso/from_master.

## Guests

User carries a guest column, so an anonymous visitor gets a soft Current.user and can use the
product without signing up. For that reason allow_unauthenticated_access is a no-op in amber,
and require_real_user is the identity check that means anything. A demo wardrobe at /demo is
seeded for guests, and Shared::PruneGuestUsersJob prunes the guest rows every night. Guests can
post and message without first creating an account.

## Identity and account continuity

Amber and Brgen use the same registration fields, email-verification policy and shared OAuth
callback. Email/password, Google, Facebook, Vipps and BankID are available when the matching
provider credentials and configuration are present. Email confirmation is separate from explicit
newsletter marketing consent. A high-assurance BankID subject can authenticate without inventing
mailbox proof from a synthetic email address.

When a visitor registers or signs in while a persisted guest owns activity, the shared merger
moves the guest's post/comment ownership and applicable conversation or message history inside
one transaction, records an account-merge audit row, destroys guest sessions, and anonymises the
source guest row as a non-authenticating audit referent before the registered session is created.
An old guest cookie is never promoted into a full account session.
If the merge cannot be committed and audited, the visitor is told that the transfer is blocked
and the guest session remains available for retry; authentication must not silently strand the
activity. The federated-identity and account-merge tables are app-owned migrations in
`db/migrate`, so run Amber's migrations and dump the schema before enabling this path.

## Account deletion

Account deletion sets a 30-day grace period and revokes the active login immediately. Amber's
`UserPurgeJob` is scheduled daily at 03:50. It removes private wardrobe, profile, connection,
identity, session, inbox and account-linked outbound-attribution data; deletes click records tied to private wardrobe objects, purges attachments through model callbacks, and anonymises the
user row. Public posts and comments remain attached to the anonymised row to preserve discussion,
but references to removed wardrobe items/outfits and deleted inbox messages are removed from posts, recommendations,
declutter history, reactions, notifications, votes, outbound-click attribution and moderation
cases so another user's row cannot retain a pointer to erased private data. If a required erasure table is missing or an account cannot be purged, the
transaction rolls back for that account, its deletion marker remains due for retry, and the job
reports the failure rather than marking erasure complete.

## Architecture

Amber is a wardrobe intelligence graph. Layers 1–4 are restored verbatim from
`DEPLOY/rails/amber/ARCHITECTURE.md`, deleted at `ee3a56e33` and never replaced;
all 23 components it named are still present and still accurate. Layer 5 and the
service catalog cover what grew after the deletion and had no written record.

### Additional component catalog

The layer headings below keep the original identity and wardrobe structure. The following components belong to those same boundaries and are named explicitly so the catalog remains searchable as the code grows.

**Models**

- `AffiliateLink`: an owner-managed product link used by Shop the Look.
- `Comment`: a comment within the social content graph.
- `Connection`: a mutual connection between user accounts.
- `ConsentEvent`: an auditable consent-change record.
- `CreatorProfile`: the public creator identity for publishing and remixing garments.
- `CreatorWardrobeItem`: the creator-owned garment record used by creator publishing.
- `DeclutterChallenge`: a time-bound prompt to consider releasing a garment.
- `DeclutterOutcome`: the recorded result of a declutter action.
- `DeclutterReview`: the stored review associated with a declutter decision.
- `Follow`: a directional social-follow relationship.
- `GarmentEmbedding`: a legacy JSON-backed vector record; this does not imply an active embedding-generation or vector-search pipeline.
- `IdentityVerification`: account verification evidence, handled as private identity data.
- `LiveStream`: the record for a user's live-stream activity.
- `Reaction`: one like per person and target, so a like counts once per user.

**Services**

- `BrgenCommerce`: the shared commerce integration used by Amber's commerce-facing flows.
- `CapsuleBuilder`: assembles a capsule from garments in the wardrobe.
- `CommerceFit`: the fit-related service used by commerce recommendations.
- `DeclutterActionRouter`: routes a declutter choice to its selected destination.
- `DeclutterDashboard`: prepares the declutter progress and challenge view.
- `GarmentTaxonomy`: the canonical garment-category vocabulary.
- `LastChanceOutfit`: proposes a final outfit before an item is released.

**Jobs**

- `CalculateSustainabilityJob`: refreshes Amber's heuristic sustainability score; it is not a lifecycle assessment.
- `MasterMessageReplyJob`: runs the queued work for a MASTER reply in a message thread.

## 1. Identity and privacy

- `User`
- `Profile`
- `PrivacySetting`
- `IdentityVerification`
- `ConsentEvent`
- `CreatorProfile`

This layer owns user identity, public creator mode, wardrobe visibility,
AI-analysis consent, and creator remix consent.

## 2. Wardrobe graph

- `Item`
- `Outfit`
- `OutfitItem`
- `PlannedOutfit`
- `WearLog`
- `StylePreference`

This layer owns garments, combinations, usage history, preferences, planning,
and style evolution.

## 3. Intelligence and media

- `GarmentEmbedding`
- `Recommendation`
- `EmbedGarmentJob`
- `RecommendOutfitsJob`
- `SegmentGarmentImageJob`
- `RemoveBackgroundJob`

This layer owns embeddings, semantic matching, recommendation records,
segmentation hooks, background-removal hooks, and safe AI fallbacks.

## 4. Sustainability, travel, and commerce

- `SustainabilityMetric`
- `PackingList`
- `PackingListItem`
- `AffiliateLink`
- `CalculateSustainabilityJob`

This layer owns cost-per-wear, resale estimates, repair estimates, packing,
travel wardrobes, and affiliate commerce.

## 5. Social graph and declutter

Added after the original specification was deleted, so nothing described it
until now. Migration `20260802180000_create_amber_social_tables.rb` created the
social tables; the controllers and routes predated them.

**Social graph** — `Post`, `Comment`, `Follow`, `Connection`, `Message`,
`LiveStream`, `CreatorWardrobeItem`. `Follow` is one-directional; `Connection`
is the mutual request with `pending/accepted/blocked` and no self-connection.
`LiveStream` carries `scheduled/live/ended/cancelled` and its own start/end
transitions. `CreatorWardrobeItem` joins a `CreatorProfile` to an `Item`, which
is how a creator publishes a garment for remix under layer 1's consent rules.
Controllers: `posts`, `comments`, `follows`, `connections`, `messages`,
`live_streams`, `reactions`, `reports`, `notifications`.

**Declutter loop** — `DeclutterChallenge`, `DeclutterOutcome`,
`DeclutterReview`, `DeclutterHygieneJob`, with `DeclutterScore`,
`DeclutterActionRouter`, `DeclutterDashboard`, and `LastChanceOutfit` in the
service layer. A challenge binds a user, an item, an optional outfit and a due
date through `pending/completed/skipped/expired`; the score decomposes into joy,
utility and fit; the router turns a decision into a destination and donation
bucket; `LastChanceOutfit` proposes a final way to wear a release candidate
before it leaves the wardrobe.

**Media and session** — `FingerprintGarmentJob`, `WardrobeMediaJob`,
`WardrobeItem`, `Session`, `Current`.

`Item` and `WardrobeItem` are not a duplicate pair. `Item` is the garment —
attributes, price, embedding, sustainability metric, declutter review.
`WardrobeItem` `belongs_to :item` and `belongs_to :user` with a uniqueness scope
on the pair, and carries condition only
(`new/excellent/good/worn/repair/retire`, `needs_attention`). It is the
per-owner care record layered on a garment, not a rival model.

## Service layer

Where Amber's product intelligence lives, and the layer no document has covered.
All under `app/services/`.

| Service | Role |
|---|---|
| `CapsuleBuilder` | Builds a capsule wardrobe and explains why each item earned its place |
| `DuplicateDetector` | Groups near-identical garments, ranks them, names a keeper and release candidates |
| `WardrobeGap` | Finds missing categories and connectors; writes `Recommendation` rows |
| `OutfitCompatibility` | Scores a combination on category balance, color balance, occasion fit |
| `OutfitGeneration` | Generates outfits from scoped items, layer-aware, biased toward least-worn |
| `StyleEvolution` | Wear timeline grouped into life phases |
| `TasteRanker` | Ranks garments on declared preference plus joy, wear, recency and life phase; `explain` names the reasons |
| `StyleAssistant` | One outfit for today — deterministic per user and date, weather-aware, rests recent wears, persists nothing |
| `ClosetOrganization` | Care, storage, zoning and restraint tips, each naming its principle and the wardrobe evidence behind it |
| `WardrobeAnalytics` | Summary, average cost-per-wear, tips. Counts in SQL — it never loads the wardrobe |
| `WardrobeCharts` | The four analytics figures: category mix, wear distribution, cost-per-wear, idle |
| `WardrobeAi` | Joy analysis and outfit suggestion; reports `available?` and degrades when unconfigured |
| `WardrobeVisibilityPolicy` | Answers view / remix / run-AI-analysis against layer 1 consent |
| `GarmentTaxonomy` | Category normalization, weather fit, formality score, semantic tags |
| `ShopTheLook` | Local affiliate links plus remote suggestions for an item |
| `Weather` | Today's conditions, decoded for planning |
| `DeclutterScore` | Joy, utility and fit into one score and a recommendation |
| `DeclutterActionRouter` | Decision to destination, donation bucket, and user-facing copy |
| `DeclutterDashboard` | Summary, top candidates, decision matrix |
| `LastChanceOutfit` | Final outfit suggestions for a garment about to leave |

Controllers are discoverable from `config/routes.rb`; service intent is not,
which is why services are enumerated here and controllers are not.

### Current components added after the archived architecture

- `Vote` stores user-scoped polymorphic up/down votes and applies score deltas to votable records that expose a score column.
- `MasterMessageReplyJob` handles Amber messages addressed to MASTER and delegates reply generation to `Shared::MasterMessenger`.
- `BrgenCommerce` queries the BRGEN marketplace catalog with bounded HTTP timeouts and short-lived caching.
- `CommerceFit` scores marketplace-product relevance from category, brand and description signals, and flags potential duplicates.

## Running it

amber.sh sources the shared deploy contract and copies the tracked tree at RAILS/amber to
/home/amber/app on vm23, with the pub4-shared engine copied beside it at /home/amber/shared. The
service reads one env file, /etc/amber.env, which needs SECRET_KEY_BASE. Solid Queue clears its
finished jobs hourly. Falcon is started with a long health-check timeout, because on one vCPU
beside master and brgen the app does not boot inside Falcon's default thirty seconds, and a
worker killed at that mark reads as a broken app.

Every deploy of any app sheds amber and bsdports, and relayd keeps answering TLS while amber is
down, so the failure shows as curl 000 and never as a 5xx. Check the port and not the site.
ALLOW_AMBER_DOWN=1 waives the check in deploy-smoke.sh where being down is the policy. The
domain is amberapp.art, and its registration was unpaid on 2026-10-09, so confirm that the name
resolves before pointing anyone at it.

The Litestream config is inert by decision, because OpenBSD has no binary for it. The backup is
a nightly pull from the operator's Mac with OPENBSD/bin/dr-pull, which checks each database
before it keeps the copy. When a Solid Queue backlog builds, OPENBSD/bin/amber_queue_sweep.sh
clears it with sqlite3, without booting Rails.

## Bringing it up

```zsh
MASTER/bin/operator triangle up amber
curl -fsS http://127.0.0.1:61352/up
doas zsh RAILS/amber/amber.sh
```
