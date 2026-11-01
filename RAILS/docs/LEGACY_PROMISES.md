# Legacy Rails promise recovery

This file connects the archived Rails product briefs in `anon987654321/pub` to the active
`pub4/RAILS` implementation. It is an implementation ledger, not a second feature authority:
`RAILS/apps.yml`, source code, routes and tests determine what is shipped. A historical
promise is not complete merely because it appears in an old README.

## Recovery principles

1. Preserve the product intent; do not resurrect obsolete architecture by copying old setup
   scripts or dependency lists.
2. Reuse the current Rails engines, shared identity, city tenancy and existing domain models.
3. A capability is **shipped** only when the active code and a meaningful test prove it.
4. A capability is **partial** when its data/model foundation exists but the user-facing workflow
   or operational dependency does not.
5. A capability is **blocked** when it needs an external service, legal/rights decision or
   deployment infrastructure that is not present.
6. Keep every promise visible until it is delivered, explicitly retired, or consciously declined.

## Brgen umbrella

The original Brgen concept was a city-first social network joining local conversation, buying and
selling, dating, food, maps, music and video.

- **Recovered and implemented:** city-scoped feed, communities, events, stories, posts, comments,
  reactions, follows, moderation, proximity discovery, direct/group messaging, map and places
  surfaces, marketplace listings and shops, dating, Radio, TV uploads, Takeaway, activity graph,
  local search, affiliate inventory and partner attribution.
- **Partly delivered:** a record-label/artist-services business, a complete local creator
  monetisation system, a fully live global city network and deeper AI ranking.
- **Next work:** prioritise a creator ownership/rights model and creator analytics shared by
  Radio and TV; only then add paid support or sponsorship so revenue is attributable and
  auditable. Do not sell boosts or placement before moderation, disclosure and refund rules exist.

## Dating

The legacy promise was location-aware discovery, preference matching, mutual likes, messaging,
verification, privacy and local events.

- **Recovered and implemented:** profile photos/prompts, city and radius filtering, like/dislike,
  rewind, mutual matches, message hand-off, held daily picks, human-reviewed verification request
  and a Vipps identity gate that fails closed when configured.
- **Still missing:** premium membership, paid boosts, super-likes and a dedicated dating-event
  workflow. The shared Brgen events surface is not the same thing as a dating event planner.
- **Next work:** build safety and consent controls first (block/report parity, age/identity policy,
  visibility controls and abuse-rate limits); then, if wanted, implement paid entitlements with
  explicit Vipps/payment, cancellation, refund and non-paying fairness tests. Never use a hidden
  ML compatibility score or exact location as a substitute for member choice.

## Marketplace and Takeaway

The old Marketplace promise included person-to-person classifieds, shops, search, seller
reputation, direct contact, nearby inventory, payments and multi-vendor operations. Takeaway
promised restaurant menus, orders, tracking and delivery coordination.

- **Recovered and implemented:** native listing/store/order domain, categories, full-text search,
  facets, saved searches, wishlist, reviews, public Q&A, variants, returns, buyer/seller
  conversations, location filtering, goods/jobs/housing/gigs, verified businesses and provider
  webhook foundations. Takeaway has restaurants, menus, opening hours, availability, scheduled
  orders, group orders, order transitions, delivery-driver records and reviews.
- **Partly delivered:** a full casual-classifieds user journey, production multi-seller settlement,
  shipping/courier integrations, driver acceptance and live delivery progress. Solidus is
  optional and staging-only; it is not the active storefront.
- **Next work:** finish the individual-seller listing journey and prove its buyer/seller lifecycle;
  then implement driver acceptance and customer-visible delivery progress. Only enable Dintero
  split checkout after its full staging contract (authorisation, capture, refund, replay and
  payout destination) passes.

## Radio / Playlist

The old Whyp.it-inspired brief promised simple local audio uploads, high-quality playback,
embeds, creator analytics, privacy, expiry, donations, premium tiers and sponsored content.

- **Recovered and implemented:** hosted audio, URL imports, playlists/sets, collaboration roles,
  embeddable players, timestamped comments, listening parties, likes/listens, per-track expiry
  and the Dilla render-to-track bridge. An owner-only aggregate analytics page now reports total
  listens, seven-day listens and per-track counts without exposing listener identities; its
  integration test has been added but still needs execution in the repository runtime.
- **Partly delivered:** the first analytics surface exists, but unique listeners, retention
  cohorts, exports and creator revenue reporting do not. Donations, paid creator tiers and
  sponsored-content workflows remain unimplemented.
- **Next work:** run the Brgen integration suite and fix any failures; then add privacy-safe unique
  listener and time-series aggregation before exports or creator payouts. Voluntary support
  requires a real payment/refund and payout contract. Confirm recording rights before importing
  the Radio Bergen archive.

## TV

The old promise included user-generated video, local channels, live streaming, recommendations and
social viewing.

- **Recovered and implemented:** channels, uploads, Active Storage media variants, shows,
  episodes, subscriptions, comments, video notes, stream chat records, watch-time events, a
  watch-time-ranked vertical feed, reusable sounds and a Replicate/ffmpeg starter-pack pipeline.
- **Blocked:** production live streaming. The model state machine exists, but ingest, transcoding,
  packaging and delivery need a media server and an external delivery tier.
- **Next work:** decide whether live TV is worth its operating cost. If yes, design a MediaMTX/SRS
  or equivalent ingest/transcode/delivery architecture with access control, moderation, retention,
  bandwidth budgets and OpenBSD operations before exposing a live button.

## Maps and Messenger

- **Maps recovered:** MapLibre/OpenFreeMap city map, place index/show, live search and check-ins.
  Do not reintroduce Mapbox tokens or claim turn-by-turn navigation.
- **Messenger recovered:** direct/group rooms, live Turbo updates, replies, edit/unsend/forward,
  link previews, voice notes, pins, inbox search, history pagination, read receipts, disappearing
  messages, story replies and invited MASTER. The current app does not claim end-to-end encryption
  or voice/video calling.

## Amber

The historical Amber brief promised wardrobe photography, style assistance, mix-and-match,
fashion discovery, social interaction, analytics, care, virtual fitting, mood matching, runway and
designer discovery, repair/recycling and travel packing.

- **Recovered and implemented:** wardrobe and outfit records, photo upload and one-pass polish,
  daily weather-aware look, taste-ranked dressing room, wardrobe analytics, cost-per-wear,
  underused-item surfacing, care/storage/organisation rules, decluttering, style evolution,
  packing lists, social feed, creator wardrobe publishing under visibility/consent rules and
  owner-managed affiliate links.
- **Partly delivered:** community feedback and mood/occasion discovery. The fashion feed is
  member-created content, not a global runway/trend intelligence feed.
- **Not yet delivered:** semantic garment search, real garment segmentation/background removal,
  virtual try-on, a dedicated mood coach, calendar-linked event planner, global trend/local
  designer intelligence, repair/recycling workflows, creator analytics and live video.
- **Next work:** improve garment import and metadata quality before adding embeddings or try-on.
  Keep private wardrobe data private by default; any AI analysis or creator remix must continue
  to pass through explicit visibility and consent policy.

## Retired architecture — do not restore

The old READMEs and shell installers mention Rails 8.0, Ruby 3.3, PostgreSQL, Redis, Devise,
ActsAsTenant, Mapbox, StimulusReflex, ActionCable as the general real-time layer, Nginx and
standalone app-per-vertical deployments. Those instructions do not describe the current
repository. The active stack is pinned in `RAILS/apps.yml`: Rails 8.2.0.alpha, Ruby 4.0.5,
SQLite, Falcon, Hotwire, Solid Queue/Cache, relayd and the shared `pub4-shared` engine.

Do not restore legacy `rails/*.sh` installers into production. Recover product requirements from
them, not their obsolete infrastructure assumptions.

## Sources

- Legacy Brgen umbrella: `pub/rails/brgen_README.md` and
  `pub/__OLD_BACKUPS/MEGA_ALL_BPLANS.md`.
- Legacy Amber: `pub/rails/other/amber_README.md` and
  `pub/__OLD_BACKUPS/rails/amber/README.md`.
- Legacy Dating: `pub/rails/brgen_dating_README.md`.
- Legacy Radio: `pub/rails/brgen/playlist_README.md`.
- Active status: `pub4/RAILS/apps.yml`, each vertical README, current routes, models and tests.
