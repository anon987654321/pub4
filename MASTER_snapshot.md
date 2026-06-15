# MASTER Snapshot (auto-iter tranche3 update)
Generated: 2026-06-15T07:07:14Z
## Tranche3 + hjerterom fix
```
  - geo_locatable.rb: nearby + haversine (replaced inconsistent math in 7+ places: listing, dating, delivery, user, hjerterom resources, restaurant).
- Major pruning (file sprawl reduction): removed entire brgen/app/models/concerns/ dir (after promotion), 6x bogus app/controllers/rails/ nested dirs (across amber/baibl/blognet/brgen/bsdports/hjerterom, each with duplicate pwa_controller), root marketplace/ stub, reduced .md files to exactly 1 README.md per app (amber/baibl/blognet/brgen/bsdports/hjerterom) + root README + shared/WIRING_NOTES (no other per-app ARCHITECTURE/STIMULUS etc. left).
- [x] AN116 Screen wake lock: acquire wake lock during video playback (brgen TV), recipe view (blognet), and navigation (hjerterom map mode)
- [x partial] AN401 Turbo Frames for every list: tranche3 added to maps/home (interactive ARIA searchbox/popup role=status), places/show (header/nav/article/dl), messages new (form role/aria-label, errors alert), _message (listitem/aria-label), hjerterom food_listings + resources indexes. Models: Message/Conversation Notifiable/Reactable, Place GeoLocatable. ARIA/NN on maps/messages per AN624/625/AN9.
```
