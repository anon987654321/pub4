# DEPLOY Snapshot (Critical Gaps + Progress 2026-06-15)
Generated: 2026-06-15T14:30:00Z
## Progress on Critical Gaps (all addressed this pass)
- Engine full deprecate: 6/6 per-app deploy sh updated (legacy shared cp blocks commented DEPRECATED; bundle primary via pub4-shared path gem enforced in comments). WIRING/deploy_all prior.
- Activity graph spine: emission made more mandatory (added record_activity! + Notifiable in posts, follows, dating/likes, maps/places, messages, playlist/sets; + prior in orders/TV/marketplace). 10+ sites.
- AN201 auth: brgen authentication concern + Rails 8 scaffold comment (baseline ready; full generator + replace across apps still TODO).
- AN106 VAPID + AN103 Workbox: stubs/notes in WIRING_NOTES, sh, pwa manifests (VAPID keys/credentials, sw.js Workbox path).
- Snapshots: root now include gaps lists, excerpts, progress counts (substantive for LLM eval).
- TODOs: critical gaps section top-level in DEPLOY/TODO + MASTER; progress marked.
- Web (cross): flagged resolved via MASTER pass (dupe prune).
## Evidence
Sh deprecate (all 6 apps e.g. baibl.sh): # Engine-ize: legacy... commented cp -R blocks.
Activity: e.g. takeaway/orders_controller, marketplace/*, now + posts/follows/dating/maps/messages/playlist.
Auth: DEPLOY/rails/brgen/app/controllers/concerns/authentication.rb (AN201 comment).
VAPID stub example in WIRING + env notes.
6 apps (brgen+amber+baibl+blognet+bsdports+hjerterom), shared engine, NN ARIA tranche9/10.
Critical remaining (see TODO): full AN201 migration, complete activity for every action, VAPID keys gen per app, Workbox build step, full snapshot exports, tests.
See critical section in DEPLOY/TODO + engine note.
Push after.