# MASTER Snapshot (autocontinue more)
Generated: 2026-06-15T07:24:59Z
## Fixed model Shared for marketplace/deal, hjerterom/donation; TODO updated.
```
  - geo_locatable.rb: nearby + haversine (replaced inconsistent math in 7+ places: listing, dating, delivery, user, hjerterom resources, restaurant).
- Major pruning (file sprawl reduction): removed entire brgen/app/models/concerns/ dir (after promotion), 6x bogus app/controllers/rails/ nested dirs (across amber/baibl/blognet/brgen/bsdports/hjerterom, each with duplicate pwa_controller), root marketplace/ stub, reduced .md files to exactly 1 README.md per app (amber/baibl/blognet/brgen/bsdports/hjerterom) + root README + shared/WIRING_NOTES (no other per-app ARCHITECTURE/STIMULUS etc. left).
7. **Monolith boundaries for brgen verticals + LLM eval snapshots**. Namespaces work today for the "one city" model. As marketplace/takeaway/orders grow, introduce clearer bounded contexts (or internal engines) without breaking the shared activity/search/moderation layers. (New: root MASTER_snapshot.md + DEPLOY_snapshot.md added/pushed in pub4 root for external LLM evaluation of architecture/DRY/pruning/shared layer; integrate into self-snapshot process.)
- Full pruning: removed 6 nested controllers/rails/ dirs (duplicate pwa broken under wrong module), root marketplace/ stub, reduced .md bloat to 1 README/app + essentials.
```
