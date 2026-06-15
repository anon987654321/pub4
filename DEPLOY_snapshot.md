# DEPLOY Snapshot (auto-iter tranche2 + LLM eval)
Generated: 2026-06-15T06:18:54Z
## Progress
```
- [x] AN111 App shortcuts: manifest `shortcuts` array — brgen: new post, new listing, dating swipe; amber: add item, create outfit; bsdports: search; blognet: new post
- [x] AN112 Share target: manifest `share_target` so native Share sheet can send URLs/text/files directly into each app (brgen post composer, amber item photo, blognet draft)
- [x partial] AN401 Turbo Frames for every list: tranche2 added turbo-frames + ARIA nav/header/role on playlist/sets + tv/channels + amber items/new (now 6+ verticals); empties enhanced with role=status aria-live. Shared.concern on Playlist::Playlist/Track. Evidence in views.
- [x] AN503 Swipe gesture: HammerJS-free swipe via `touchstart`/`touchend` delta; for dating card stack, marketplace image carousel, and playlist track swipe-to-queue
- [x] AN518 Sortable: `data-controller="sortable"` wrapping SortableJS; for outfit item reordering, playlist track ordering; saves order via PATCH on dragend
- [ ] AN601 City onboarding: `/onboard` flow — pick city, pick interests (categories), pick verticals (dating/marketplace/tv/etc.); redirect to personalized feed
