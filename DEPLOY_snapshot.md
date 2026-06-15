# DEPLOY Snapshot (Critical Gaps reassess 2026-06-15)
Generated: 2026-06-15T14:05:00Z
## Evidence
- Engine-ize: 6/6 Gemfiles with pub4-shared; terse engine.rb; tranche9/10: +8+ models (takeaway::*, tv::*, playlist::*, dating match, reaction, store etc.), ARIA in takeaway/bsdports/amber/baibl/blognet/hjerterom, controller flesh (orders record_activity), sh/deploy_all + openbsd + WIRING annotated DEPRECATED.
- NN/ARIA: 20+ tranche9 + 10+ tranche10 (roles on headers/navs/forms/uls/articles/sections/empty/status/region/list/listitem).
- Pruning: brgen/concerns/ removed, 1 README/app, stray dirs gone.
- PWA: most AN1 [x] (manifests, sync, offline, shortcuts, etc.); AN103 Workbox + AN106 VAPID still [ ].
- Web pass (MASTER side) cross-applied.
## Critical Gaps (2026-06-15)
1. AN201: no `rails generate authentication` + custom auth replacement across 6 apps.
2. Engine full deprecate: annotations done; actual removal of copy logic + bundle-verify in all sh/rc.d/openbsd not done.
3. Activity graph mandatory: wired in TV/shows + recent orders; not universal for posts/matches/listings/follows/reactions.
4. AN106 VAPID + webpush across apps.
5. AN103 Workbox.
6. Snapshot substance vs original full-export request for LLM eval of DRY/engine/shared.
7. VPS items (M06/M07) + real deploy (M01-M03) — local-only constraint.
8. Tests/N+1/AN15/1204 evidence.
See DEPLOY/TODO top critical section + engine note + AN1/AN2. 6 apps, ~1418 lines TODO, 9-line snapshot.
Push after.
```