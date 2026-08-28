# Amber architecture

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

This layer owns user identity, public creator mode, wardrobe visibility, AI-analysis consent, and creator remix consent.

## 2. Wardrobe graph

- `Item`
- `Outfit`
- `OutfitItem`
- `PlannedOutfit`
- `WearLog`
- `StylePreference`

This layer owns garments, combinations, usage history, preferences, planning, and style evolution.

## 3. Intelligence and media

- `GarmentEmbedding`
- `Recommendation`
- `EmbedGarmentJob`
- `RecommendOutfitsJob`
- `SegmentGarmentImageJob`
- `RemoveBackgroundJob`

This layer owns embeddings, semantic matching, recommendation records, segmentation hooks, background-removal hooks, and safe AI fallbacks.

## 4. Sustainability, travel, and commerce

- `SustainabilityMetric`
- `PackingList`
- `PackingListItem`
- `AffiliateLink`
- `CalculateSustainabilityJob`

This layer owns cost-per-wear, resale estimates, repair estimates, packing, travel wardrobes, and affiliate commerce.

## 5. Social graph and declutter

Added after the original specification was deleted, so nothing described it until
now. Migration `20260802180000_create_amber_social_tables.rb` created the social
tables; the controllers and routes predated them.

**Social graph** — `Post`, `Comment`, `Follow`, `Connection`, `Message`,
`LiveStream`, `CreatorWardrobeItem`. `Follow` is one-directional; `Connection` is
the mutual request with `pending/accepted/blocked` and no self-connection.
`LiveStream` carries `scheduled/live/ended/cancelled` and its own start/end
transitions. `CreatorWardrobeItem` joins a `CreatorProfile` to an `Item`, which is
how a creator publishes a garment for remix under layer 1's consent rules.
Controllers: `posts`, `comments`, `follows`, `connections`, `messages`,
`live_streams`, `reactions`, `reports`, `notifications`.

**Declutter loop** — `DeclutterChallenge`, `DeclutterOutcome`, `DeclutterReview`,
`DeclutterHygieneJob`, with `DeclutterScore`, `DeclutterActionRouter`,
`DeclutterDashboard`, and `LastChanceOutfit` in the service layer. A challenge
binds a user, an item, an optional outfit and a due date through
`pending/completed/skipped/expired`; the score decomposes into joy, utility and
fit; the router turns a decision into a destination and donation bucket;
`LastChanceOutfit` proposes a final way to wear a release candidate before it
leaves the wardrobe.

**Media and session** — `FingerprintGarmentJob`, `WardrobeMediaJob`,
`WardrobeItem`, `Session`, `Current`.

`Item` and `WardrobeItem` are not a duplicate pair. `Item` is the garment —
attributes, price, embedding, sustainability metric, declutter review. `WardrobeItem`
`belongs_to :item` and `belongs_to :user` with a uniqueness scope on the pair, and
carries condition only (`new/excellent/good/worn/repair/retire`, `needs_attention`).
It is the per-owner care record layered on a garment, not a rival model.

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

Controllers are discoverable from `config/routes.rb`; service intent is not, which
is why services are enumerated here and controllers are not.

## Deploy conventions

`amber.sh` sources the shared `_deploy.sh` contract and copies the tracked tree at
`RAILS/amber` into `/home/amber/app`, with the `pub4-shared` engine copied
alongside at `/home/amber/shared` — a sibling of `app/`, not inside it. Port
61352, `amber.brgen.no`, Falcon behind relayd. Deploy matrix: `RAILS/apps.yml`.

The original document described `DEPLOY/rails/@shared_functions.sh` and a
`/var/cache/pub4/bundle/ruby34` bundle cache. The `DEPLOY/` tree no longer exists
and the `@`-prefixed shims were retired in favour of `RAILS/_*.sh`; that paragraph
is the one part of the recovered text that did not survive restoration.

## Vector direction

Moved to `DECISIONS.md`, where a deliberate shape that looks like a bug belongs.
