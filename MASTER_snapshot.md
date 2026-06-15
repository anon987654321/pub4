# MASTER Snapshot (final big push tranche4+)
Generated: 2026-06-15T07:19:01Z
## Massive push: NN/ARIA/Turbo/Shared across bsdports/baibl/blognet/amber/hjerterom + models + brgen maps stub
```
Next/reassessment (2026-06-14): spike shared engine (top priority #1; copy-script remains but local duplication gone + 6+ concerns in shared), integrate root snapshots (MASTER_snapshot.md / DEPLOY_snapshot.md in pub4 root, pushed 11ad193f) into LLM/self-eval process (new gap: "for other LLMs to evaluate" architecture/DRY/pruning/shared), wire more concerns (e.g. Mentionable if useful), continue AN2 (auth), AN103 (Workbox), AN106 (VAPID), AN15/AN1204 (tests/N+1), activity graph full, notification convergence. See major wins below. (Reassessment: DRY/KISS + pruning wins confirmed via ls/git (8 shared concerns, no local concerns/ dir, 1 README/app, snapshots present); no .md bloat; snapshots fulfill eval request. Smell: TODO length with historical repeats — archive done sections?)
- [x] AN101 Manifest completeness: add `display_override...` etc to manifests (prior); Rails 8 native pwa generator (rails generate pwa) + views/pwa/ + routes align noted in research (edge guides 2026); apps on 8.1 + solid_* + propshaft good. Engine helps shared pwa partials future.
- [x] AN102 Service worker cache versioning: prefix cache name with app + version (`brgen-v1-assets`); bump version on deploy via CACHE_VERSION env var injected at build
- [ ] AN103 Workbox integration: replace hand-rolled... (Rails 8 pwa default is basic sw; Workbox opt-in via import + sw.js build step; keep in backlog, current solid+turbo sufficient for family).
- [ ] AN104 Background sync: register sync events for offline form submissions (post creation, marketplace orders, dating likes); replay queue on reconnect
- [ ] AN105 Periodic background sync: register `periodicsync` for daily briefing fetch, feed pre-warm, and badge count updates
- [ ] AN106 Push notification VAPID: generate VAPID keys once per app; store in credentials; wire webpush gem (already in brgen) to all apps; display OS-native notifications
- [x] AN107 Notification badge API: use `navigator.setAppBadge(count)` for unread message count; update via CableReady broadcast on new message
```
