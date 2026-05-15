# Amber architecture

Amber is a wardrobe intelligence graph built from four layers.

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

## Deploy conventions

Amber uses the common `DEPLOY/rails/@shared_functions.sh` helper and deploys the tracked app tree at `DEPLOY/rails/amber/app` into `/home/amber/app`.

The deploy wrapper uses a neutral shared bundle cache when available:

```text
/var/cache/pub4/bundle/ruby34
```

and falls back to normal Bundler resolution when no cache exists.

## Vector direction

The current `GarmentEmbedding#vector` is JSON-backed so the app remains SQLite-compatible. When Amber moves to PostgreSQL/pgvector, replace the JSON vector column with a pgvector column and swap `WardrobeAiService#embedding_for` for a real embedding backend.
