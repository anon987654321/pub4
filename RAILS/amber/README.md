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
and require_real_user is the identity gate that means anything. A demo wardrobe at /demo is
seeded for guests, and Shared::PruneGuestUsersJob prunes the guest rows every night.

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
