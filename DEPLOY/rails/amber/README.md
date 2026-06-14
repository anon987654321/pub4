# amber — wardrobe intelligence

Fashion meets graph reasoning. amber tracks what you own, generates outfits, and builds a durable style identity across time.

Most fashion platforms understand purchases. amber understands ownership, aesthetics, context, and identity — before you buy more.

## Features

- Wardrobe upload, segmentation, background removal
- Outfit generation (weather, season, event, aesthetics)
- Style evolution tracking (aesthetic phases, color trends, underused items)
- Fashion embeddings — garments, creators, brands in one vector space
- Visual similarity search, social feeds, affiliate commerce

## Stack

Rails 8 · SQLite/pgvector · Falcon · Hotwire · Active Storage · OpenBSD

## Deploy

```zsh
doas zsh DEPLOY/rails/amber/amber.sh
```

## Current Integration Status (2026)

- **Visual system**: Should inherit Brgen's cinema palette + X.com layout tokens (see `DEPLOY/rails/shared/WIRING_NOTES.md` → Visual System).
- **Activity Graph**: Should emit to the shared city activity stream (see `brgen/brgen_CORE.md` and `shared/WIRING_NOTES.md`).
- **Photo / Multimodal**: Photo creation is allowed for visitors on the public surface. Amber can use the shared photo upload patterns for wardrobe uploads.
- **Shared concerns**: Reactable, Followable, LiveSearchable, etc. available via `shared/`.

## Architecture Layers (condensed from ARCHITECTURE.md)
1. Identity and privacy: User, Profile, PrivacySetting, etc.
2. Wardrobe graph: Item, Outfit, OutfitItem, WearLog, etc.
3. Intelligence and media: GarmentEmbedding, Recommendation, jobs for segment/remove background.
4. Sustainability/commerce: SustainabilityMetric, AffiliateLink, etc.

Vector direction: Currently JSON-backed for SQLite; future pgvector.

## Stimulus / Rails 8 Rollout (condensed)
Prioritize: Lightbox for photos, Sortable for outfits, Notification, Timeago, Clipboard, Dropdown/AutoSubmit for filters, Content Loader.

Rails 8: Solid Queue for processing, Active Storage variants, Solid Cache.
- **Deploy**: Uses thin script + tracked tree model (prefers this over heavy @*.sh generators).

See `DEPLOY/rails/ARCHITECTURE_NOTES.md` and `WIRING_NOTES.md` for family-wide guidance.

## Roadmap

Creator wardrobes · sustainability (cost-per-wear, resale) · travel packing · virtual try-on · style agents
