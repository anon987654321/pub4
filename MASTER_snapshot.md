# MASTER Snapshot (auto-iter tranche4)
Generated: 2026-06-15T07:17:37Z
## Tranche4: bsdports/baibl/blognet NN/Turbo/Shared
```
- Major pruning (file sprawl reduction): removed entire brgen/app/models/concerns/ dir (after promotion), 6x bogus app/controllers/rails/ nested dirs (across amber/baibl/blognet/brgen/bsdports/hjerterom, each with duplicate pwa_controller), root marketplace/ stub, reduced .md files to exactly 1 README.md per app (amber/baibl/blognet/brgen/bsdports/hjerterom) + root README + shared/WIRING_NOTES (no other per-app ARCHITECTURE/STIMULUS etc. left).
- [x] Engine-ize + prune + snapshots + deprecate: complete (see top AN note + root snapshots + WIRING). 6/6 Gemfiles, stray gone, scripts annotated, openbsd updated. NN/ARIA + flesh: takeaway orders (role+aria-label on form+header), amber Item (Shared.concern(:Reactable) via engine), bsdports search already wired; more in shared partials + layouts prior. Ongoing perfect loop.
- [x] AN111 App shortcuts: manifest `shortcuts` array — brgen: new post, new listing, dating swipe; amber: add item, create outfit; bsdports: search; blognet: new post
- [x] AN112 Share target: manifest `share_target` so native Share sheet can send URLs/text/files directly into each app (brgen post composer, amber item photo, blognet draft)
- [x] AN113 File handler: manifest `file_handlers` — amber handles image/* (add to wardrobe), blognet handles text/markdown (import as draft)
```
