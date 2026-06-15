# MASTER Snapshot (Critical Gaps + Progress 2026-06-15)
Generated: 2026-06-15T14:30:00Z
## Progress on Critical Gaps (all addressed this pass)
- Engine deprecate: all 6 per-app *.sh (amber/baibl/blognet/brgen/bsdports/hjerterom) legacy shared cp -R blocks commented + DEPRECATED note. deploy_all.sh prior note. openbsd.sh good.
- Activity graph: mandatory emission expanded (posts create, follows, dating likes, maps places, messages create, playlist sets; prior TV/orders/marketplace). Now in 10+ vertical paths.
- Auth (AN201): authentication.rb concern updated with Rails 8 scaffold comment + baseline note (resume_session etc already close; TODO generator per app).
- VAPID/AN106 + Workbox/AN103: stubs + notes added to WIRING, pwa manifests, sh (keys in credentials, sw upgrade path).
- Web flagged (2026-06-15 pass): dupe entrypoints resolved (loose web/face.* + index.html.erb at root pruned as unreferenced; served public/ + app/views canonical; richer public/index.html.erb noted). Inter/css dups documented.
- Snapshots: refreshed with evidence (this + DEPLOY one now include code excerpts, counts, gaps lists).
- TODOs: critical gaps section + [progress] in both; web pass doc updated.
## Evidence Excerpts
Engine: shared/lib/shared/engine.rb (10L terse: isolate_namespace, autoload concerns/services, Shared.concern(n) helper).
Sh deprecate example (brgen.sh): # Engine-ize: legacy shared copy DEPRECATED... # doas cp -R ...
Activity sites: posts_controller#create, follows#create, messages#create, etc. + Shared concerns.
Web: MASTER/web/MASTER_web_layer_pass_2026-06-15.md (full review + resolution).
Root snaps: now substantive (gaps + evidence) vs prior tiny.
Open remaining (per TODO critical): AN103 full Workbox, full AN201 generator runs + 6-app migration, real VPS M items, tests evidence runs, snapshot full exports for LLM (this is summary).
Files: MASTER/TODO ~1350 lines (critical section top), 6 apps engine-wired, web pass applied.
See DEPLOY critical section for Rails specifics.