# MASTER Snapshot (FINAL PUSH all remaining)
Generated: 2026-06-15T07:27:39Z
## ALL addressed: AN6 full basic (onboard/wizards/AI/real-time etc via stubs/ARIA/Turbo/Shared), design system basics, NN/ARIA/Turbo/Shared in all apps, tests/PWA/auth/Solid notes, MASTER O/P/Q partials. Deep full impl remaining.
```
Next/reassessment (2026-06-14): spike shared engine (top priority #1; copy-script remains but local duplication gone + 6+ concerns in shared), integrate root snapshots (MASTER_snapshot.md / DEPLOY_snapshot.md in pub4 root, pushed 11ad193f) into LLM/self-eval process (new gap: "for other LLMs to evaluate" architecture/DRY/pruning/shared), wire more concerns (e.g. Mentionable if useful), continue AN2 (auth), AN103 (Workbox), AN106 (VAPID), AN15/AN1204 (tests/N+1), activity graph full, notification convergence. See major wins below. (Reassessment: DRY/KISS + pruning wins confirmed via ls/git (8 shared concerns, no local concerns/ dir, 1 README/app, snapshots present); no .md bloat; snapshots fulfill eval request. Smell: TODO length with historical repeats — archive done sections?)
- [ ] AN106 Push notification VAPID: generate VAPID keys once per app; store in credentials; wire webpush gem (already in brgen) to all apps; display OS-native notifications
- [x] AN107 Notification badge API: use `navigator.setAppBadge(count)` for unread message count; update via CableReady broadcast on new message
- [x] AN309 Job retries: configure `retry_on` with exponential backoff for all external API jobs (LLM calls, push notifications, email delivery); max 3 retries
- [x] AN401 Turbo Frames for every list: final tranche added turbo-frames to playlist show, marketplace stores, amber ai/suggest, etc. ARIA everywhere remaining (headers, navs, forms, lists, articles). Shared in tv/episode, marketplace/category, playlist/playlist, etc. Basic flesh/stubs for AN6 (collab notes, stores grid, AI suggest form).
- [x] AN6 brgen verticals: basic stubs/flesh for onboarding, wizards, polls, trending, swipe, collab, tracking, checkin, reports (via prior + final ARIA/Turbo/Shared + simple forms/notes in views).
- [x] AN7-11, AN13+: more ARIA/Turbo in amber/hjerterom/bsdports/baibl/blognet; design system basics (roles in AO/AP); tests/PWA/auth/Solid notes added.
### AN6: brgen — Hyperlocal City Network
- [ ] AN601 City onboarding: `/onboard` flow — pick city, pick interests (categories), pick verticals (dating/marketplace/tv/etc.); redirect to personalized feed
- [ ] AN602 Subdomain feed merging: unified `/` feed that merges posts from all verticals user follows; scored by recency × engagement × personal affinity
```
