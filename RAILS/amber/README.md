# amber

**A wardrobe that knows what is in it, what you actually wear, and what it is
guessing at.** amber holds garments and outfits, runs the KonMari declutter loop,
keeps a style timeline, and makes recommendations that can say where they came
from. Rails 8.1 on SQLite behind Falcon, with Hotwire, Active Storage and relayd,
on port 61352.

Deploy it with `doas zsh RAILS/amber/amber.sh` and prove it on
`http://127.0.0.1:61352/up`. Check the port and not the site: every deploy of any
app sheds amber, and relayd keeps answering TLS while it is down, so the failure
arrives as `curl 000` rather than a 5xx. `ALLOW_AMBER_DOWN=1` waives that check
in `deploy-smoke.sh` where being down is the policy.

`default_locale` is `:nb`, with `:en` available and a switcher in the footer.
Chrome, empty states and every controller flash go through I18n. The app's own
copy is in `config/locales/nb.yml` and `en.yml` under `flash:`; the sentences the
shared engine owns, `not_authorized` and `rate_limited`, come from
`shared.flash.*`. `raise_on_missing_translations` is on in test, so a key that
does not resolve fails a run instead of rendering a span nobody reads.

### What each claim actually rests on

The declutter loop is complete: a joy score, challenges, last-chance outfits, and
a thirty-day box in `DeclutterHygieneJob`. The photo pipeline is
`WardrobeMediaJob` — variants, portrait polish, colour — and not an ML cut-out.
`RemoveBackgroundJob` and `SegmentGarmentImageJob` are deprecated shells that
remove nothing and segment nothing; they mark an honest status, no-op, and exist
only for queues still in flight. `EmbedGarmentJob` is an alias of
`FingerprintGarmentJob`, and there are no embeddings anywhere: a fingerprint is a
local `zlib` CRC over the image bytes, which finds a re-upload and never a
lookalike. `DuplicateDetector` follows from that — it groups on an exact
`duplicate_key`, so two similar shirts are not duplicates to it.

The intelligence is honest about being heuristic. Real AI runs through OpenRouter
on `google/gemini-2.0-flash-001` when `OPENROUTER_API_KEY` is set, and
deterministic heuristics run otherwise, with the UI saying which one answered.
`TasteRanker` combines declared `StylePreference` rows with joy, wear count,
recency and life phase at fixed weights — a model, not a learned one.
`StyleAssistant` produces the daily look deterministically per user and date,
weather-aware, and persists nothing until you save it. The weather itself is
open-meteo for Bergen alone, its latitude and longitude constants, cached fifteen
minutes with negative caching and bounded at two seconds to connect and three to
read, because it sits in front of the dashboard.

The scores are targets rather than judgements. `WardrobeGap` compares your closet
against fixed essentials counts per category. The sustainability score scales and
caps wear count and adds a bonus for sparking joy; it is not a lifecycle
assessment. Tips come from `WardrobeAnalytics` nudges and from
`ClosetOrganization`'s care, storage, zoning and restraint registers, each naming
the principle it is applying. Style sessions carry a calendar and a status and
nothing more. There are no store feeds at all: amber imports no product feed, and
`ShopTheLook` ranks the affiliate links you added yourself — its remote half
needs `TRADEDOUBLER_TOKEN`, which lives on brgen, and it says so when that half
is dark.

### Guests, and the gate that is not one

`User` carries a `guest` column, so an anonymous visitor gets a soft
`Current.user` and can use the product without signing up.
`allow_unauthenticated_access` is therefore a no-op here, and logs that it is in
development and test; `require_real_user` is the identity gate that means
anything. `Shared::PruneGuestUsersJob` prunes the guest rows nightly.

Two things are fragile. amber shares one 1 GB box with brgen, bsdports and
MASTER, and needs roughly twenty seconds to signal ready — under load Falcon
kills the worker before that window closes, which reads as a broken app and is
not one. And the Litestream replicas are on the same disk, so there is no
off-host copy of the database. That one is tracked, not solved.

`HEIR.md` covers what runs alone, the health checks, the env keys and the honesty
map. `ARCHITECTURE.md` has the components and layers, the comments on the models
the shapes that look like bugs and are not, and `RAILS/shared/WIRING_NOTES.md` the shared
tokens and concerns. The feature matrix is `RAILS/apps.yml` under `amber`.

## Architecture

Amber is a wardrobe intelligence graph. Layers 1–4 are restored verbatim from
`DEPLOY/rails/amber/ARCHITECTURE.md`, deleted at `ee3a56e33` and never replaced;
all 23 components it named are still present and still accurate. Layer 5 and the
service catalog cover what grew after the deletion and had no written record.

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

## Deploy conventions

`amber.sh` sources the shared `_deploy.sh` contract and copies the tracked tree
at `RAILS/amber` into `/home/amber/app`, with the `pub4-shared` engine copied
alongside at `/home/amber/shared` — a sibling of `app/`, not inside it. Port
61352, `amber.fashion`, Falcon behind relayd. Deploy matrix: `RAILS/apps.yml`.

The original document described `DEPLOY/rails/@shared_functions.sh` and a
`/var/cache/pub4/bundle/ruby34` bundle cache. The `DEPLOY/` tree no longer
exists and the `@`-prefixed shims were retired in favour of `RAILS/_*.sh`; that
paragraph is the one part of the recovered text that did not survive
restoration.

## Vector direction

`GarmentEmbedding#vector` is a JSON column rather than pgvector, and the comment
on `app/models/garment_embedding.rb` says why.

## Stewardship

Amber is a **social fashion** app (`amber.fashion`) — feed, follows, outfits
and a wardrobe, sharing the same social stack as brgen. Day-to-day it should run
without engineering. This page is for the person who inherits stewardship.

## What you do

1. Open https://amber.fashion and watch wardrobes grow.
2. Help the occasional user (password, “what is declutter?”, content concern).
3. Keep bills paid: VPS + domain.
4. If the site is down, tell a technical contact (see below).

You do **not** need to process photos, score declutter decisions, or restart
servers on a normal week.

## What runs itself

| Piece | Behaviour |
|--------|-----------|
| OpenBSD service | `rc.d/amber` starts Falcon + Solid Queue on port 61352 |
| TLS | relayd + cert renew scripts for `amber.fashion` |
| Photo upload | Variants, colour extract, one portrait polish, local fingerprint, sustainability score |
| Declutter hygiene | Daily job: expire overdue wear challenges; nudge 30-day box items |
| Queue cleanup | Hourly clear of finished Solid Queue jobs |
| Demo wardrobe | Seeded for guests without an admin filling the catalog |

## Health checks (tech or laptop)

```sh
curl -fsS https://amber.fashion/up
# or full stack:
sh OPENBSD/bin/uptime-check.sh
```

Red `/up` → technical contact restarts in order: **master → brgen → amber →
relayd**.

## Secrets that keep AI smart

| Env | Required for |
|-----|----------------|
| `SECRET_KEY_BASE` | App boot |
| `OPENROUTER_API_KEY` | LLM joy analysis, vision outfits, capsule LLM path |
| `AMBER_ENABLE_MASTER_PHOTO=1` | Optional MASTER look photography (off by default) |

Without OpenRouter, Amber still works: **heuristics and rules** (joy from wear,
rule-based outfits, local capsule). Buttons say so in the UI.

## Honesty map (so you are not sold vapor)

- **Photo polish** — yes. ML cut-out / segment — no (planned).
- **Fingerprint** — local CRC for change detection. Real embeddings / lookalike
  search — planned.
- **Analytics tips** — rule coach, not AI.
- **Style sessions** — schedule/status, not live video.
- **KonMari loop** — real: joy, challenges, last-chance outfits, box, release
  paths.

## When to call tech

- Site down more than a few minutes
- “AI analyse” broken after key rotation
- Disk full / queue stuck (rare; there is `OPENBSD/bin/amber_queue_sweep.sh`)
- Security update or code deploy needed

## Deploy (technical)

```sh
doas zsh RAILS/amber/amber.sh
# or fleet:
doas zsh RAILS/deploy.sh amber
```

Feature matrix: `RAILS/apps.yml` → `amber`.
