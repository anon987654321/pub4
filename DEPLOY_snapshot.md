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
- Fictive + web-augmented seeds: ruby-faker base for brgen (all subapps) + amber; optional Ferrum/LLM scrape seeds via rake scrape:reddit_seed, x_seed (brgen verticals), fashion_seed (amber) when SEED_FROM_WEB + key. Creates realistic fictive data routed to models (posts, listings, profiles, restaurants, shows, places, items, outfits etc.). Scrape service in shared. See updated seeds.rb and lib/tasks.
## Evidence
Sh deprecate (all 6 apps e.g. baibl.sh): # Engine-ize: legacy... commented cp -R blocks.
Activity: e.g. takeaway/orders_controller, marketplace/*, now + posts/follows/dating/maps/messages/playlist.
Auth: DEPLOY/rails/brgen/app/controllers/concerns/authentication.rb (AN201 comment).
VAPID stub example in WIRING + env notes.
6 apps (brgen+amber+baibl+blognet+bsdports+hjerterom), shared engine, NN ARIA tranche9/10.
Fictive seeds: comprehensive Faker + optional web scrape for brgen subapps/amber. See db/seeds.rb, lib/tasks/*_seed.rake, shared/scrape.rb.
Critical remaining (see TODO): full AN201 migration, complete activity for every action, VAPID keys gen per app, Workbox build step, full snapshot exports, tests.
See critical section in DEPLOY/TODO + engine note.
Git archaeology (2026-06-15): no critical info/logic omitted (ee3a56e33 MD prune condensed+verified in canonicals; unban removal + pf rate drop ee29827b0/e6d5d5712 intentional+fully documented in openbsd/README + "For LLMs"; WIRING stale refs cleaned; all seeds/Ferrum/rules gates/VPS preserved). See DEPLOY/TODO critical.
Push after.