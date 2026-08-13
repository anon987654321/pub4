# RAILS TODO — parity gaps

What brgen would need to read as a peer of TikTok, Snapchat, Mastodon, x.com,
Reddit, Craigslist and Facebook, and its verticals as peers of Amazon/Temu,
Tinder/Hinge, DoorDash/Foodora and Messenger.

Scope is brgen and its engines. amber and bsdports are not measured against
consumer apps, and their planned work stays in `apps.horizon.yml`. Paths below
are relative to `RAILS/`.

This file is **not** a second feature inventory. `apps.yml` is feature truth and
`apps.horizon.yml` holds aspirational items marked `agent: ignore`. Everything
below is a gap that neither file records, verified against the tree on
2026-08-13 — mostly because `apps.yml` records a feature as `done` when the
model exists, and several of these models exist with nothing reading or writing
them.

An item leaves this file when a check proves it, not when it stops being
mentioned.

---

## Tier 1 — built and inert

The schema and the model exist. Nothing reads or writes them. These are the
cheapest items here and they gate most of Tier 2, because ranking and
notification both need a signal that is currently never recorded.

### 1.1 Repost is a decorative button

`brgen/app/views/posts/_post.html.erb:23-39` renders the repost control with no
`data-controller` and a comment saying there is no repost feature.
`shared/app/views/shared/_action_bar.html.erb` renders its own repost button
with no behaviour either. A user pressing it saw optimistic UI that reverted on
the next render, so the optimism was removed and the button kept.

Decide first: build it or drop it. Both are correct; rendering an inert control
is not. Building it means a `Repost` model (or `Post#reposted_from_id`), feed
inclusion, and the quote-post variant that x.com and Mastodon both depend on.

**Check:** none today. A view test asserting every `feed-action` button resolves
to a controller or a form would catch the whole class.

### 1.2 `Tv::ViewEvent` is never created

`tv_view_events` carries `watch_time_seconds` and `completed`. The model exists.
`Tv::Video has_many :view_events`. **Nothing anywhere creates a row.**
`Tv::Video.trending` sorts on the `views_count` counter column instead.

So there is no watch-time signal in the database, and no TikTok-style ranking is
possible until the player writes one. This is the single highest-leverage item
in the file: it is a Stimulus controller posting progress plus a create action.

**Check:** none today.

### 1.3 `Marketplace::SavedSearch` never runs itself

The model persists `query`, `category` and `name`, and the saved-searches index
(`brgen/engines/marketplace/app/views/marketplace/saved_searches/`) renders each
one as a *manual* `listings_path` link. So a saved search is a bookmark: nothing
ever runs it on your behalf — no job, no mailer, no digest, no match on new
inventory.

Craigslist and Amazon both run substantially on that notification. Needs a
recurring job matching new `Marketplace::Listing` rows against saved searches
and delivering through the existing `Notification` + `PushSubscription` path.
Price-drop alerts fall out of the same job once `Deal` is joined in.

**Check:** none today. `brgen/config/recurring.yml` would name the job.

### 1.4 `takeaway_orders.delivery_driver_id` had no writer — **done**

The column had shipped with the table, carrying two indexes including a
composite `["delivery_driver_id", "status"]`, and
`Takeaway::DeliveryDriver has_many :orders` had always resolved through it.
There was no `belongs_to` on `Takeaway::Order` and nothing ever wrote the
column, so every order reached `out_for_delivery` with no courier attached.

Now: `belongs_to :delivery_driver`, and `transition_to!` dispatches the nearest
free courier on the same write as the status change, so an order is never
observable as out for delivery with nobody on it.
`DeliveryDriver.nearest_free` post-sorts the `nearby` bounding box by real
haversine distance — the box alone would take a courier in the corner over one
on the doorstep — and excludes anyone already mid-delivery. No free courier in
range is left as a real state rather than a failed transition: the order still
leaves the kitchen and the page says nobody is assigned yet.

**Check:** `engines/takeaway/test/models/takeaway/order_test.rb` — four tests
covering nearest-not-merely-in-box, no double-booking, dispatch with no courier
available, and dispatch on an order loaded without preloads.

**Still open:** the courier's live position on the maps engine. The order page
names the courier and their distance from the kitchen; it does not move.

---

## Tier 2 — structurally absent

### 2.1 No federation (Mastodon)

No ActivityPub, WebFinger or nodeinfo anywhere in the tree.

This is the only item on the list that is not parity work. brgen is already
partitioned by city subdomain through `Brgen::DomainRegistry`, so a city is
already shaped like an instance. Federating cities to each other, and then
outward to the fediverse, is a differentiator rather than a clone. It also has
the largest surface: actor documents, inbox/outbox, HTTP signatures, delivery
retry, and a moderation story for remote content that `ModerationReport` does
not currently model.

Depends on 1.1 — `Announce` is repost.

### 2.2 No `Event` model (Facebook)

Nothing in `brgen/db/schema.rb`. For a city-scoped social network this is the largest
missing noun on the list — larger than Stories or Reels. `Place`,
`PlaceCheckIn`, `Neighborhood` and the maps engine already sit underneath it,
and `ActivityEvent.for_city_home` already has a slot on the home page for it.

### 2.3 No Story / ephemeral media (Snapchat)

Ephemeral exists, but only in DMs: `Conversation#disappearing_messages?` and
`Message#expires_at` with `schedule_expiration`. There is no 24-hour media
story, no camera-first capture surface, and no streak.

The Snap-Map equivalent is closest to shipping — `Place`, `PlaceCheckIn` and the
geo rooms (`Conversation.find_or_create_geo_room`) are already built.

### 2.4 `Community` is eight columns (Reddit)

`communities` carries `city_id, name, slug, subdomain, description, user_id` and
timestamps. No moderators, rules, icon, banner, privacy level, or flair.
`ModerationReport`/`ModerationFlag`/`TrustScore` are global, so there is no mod
team per community, no per-community queue, and no crossposts.

A community that cannot be moderated by its own members is a category page, not
a subreddit.

### 2.5 No vertical video surface (TikTok)

`Tv::HomeController#index` is a trending/live/recent grid — the YouTube shape,
not the TikTok one. A full-screen vertical swipe feed over existing
`Tv::Video` is unblocked *once 1.2 records watch time*; the playlist engine's
swipe tracking (`Playlist::ListensController`) is the closest existing pattern.

Live streaming stays blocked — see "Blocked" below.

---

## Tier 3 — per-surface parity

### Marketplace (Amazon / Temu)

The cart is not a cart. `Marketplace::CartsController#load_cart` lists pending
per-listing `Marketplace::Order` rows and `CheckoutsController#create` pays
exactly one of them. Stripe and Vipps are wired; the basket is not.

Missing: multi-item single payment, shipping addresses, fulfilment and tracking,
product variants (size/colour), inventory counts, returns, seller payouts,
listing Q&A, wishlist, and search facets (FTS only, no faceting).

Temu-flavoured work is cheap on top of the existing `Marketplace::Deal`:
countdown flash deals, coupons, referral credit, bundle pricing.

Solidus remains blocked — see below — so all of this is native-path work.

### Dating (Tinder / Hinge)

`Dating::HomeController#candidate_scope` ends in `ORDER BY RANDOM()`. Orientation,
neighbourhood and a 20 km radius filter the pool; nothing ranks it. No
compatibility, recency or activity weighting.

Missing: who-liked-you, super-like, rewind, unmatch, photo verification, daily
picks.

Worth naming: the current shape of the category is **Hinge**, not Tinder —
liking a specific photo or prompt with a comment, rather than a swipe deck. That
is a `Dating::Prompt` model plus a like-carrying-a-comment, and it lands on the
existing `Dating::Match#announce_match → Conversation` handoff unchanged.

### Takeaway (DoorDash / Foodora)

Beyond 1.4: `Takeaway::Restaurant` has no opening hours, so nothing models
closed. `estimated_ready_at` is the only estimate — no delivery ETA. Missing:
live courier map, tipping, scheduled orders, group orders, order-again, and a
push notification on each `transition_to!` (the transition already sends an
in-app notification; `PushSubscription` is not on that path).

### Messenger

Done already: typing indicators, read receipts, reactions, presence,
disappearing messages, attachments with variants.

Missing: voice messages, reply-to-a-message, edit/unsend, forwarding, link
previews, message search, group naming and admin roles, pinned conversations.
No WebRTC anywhere, so no voice or video calls.

### Craigslist

Nearly complete — geo listings, categories, city subdomains, casual (no-store)
listings, buyer–seller chat and FTS all exist. Missing: an anonymised contact
relay, post expiry-and-renew, and the non-goods verticals (jobs, housing, gigs).

---

## Blocked — do not chase

These are recorded in `RAILS/apps.yml` with verified blockers. Repeated here
only so nothing above reads as available.

- **Live streaming (tv).** Needs a media server (nginx-rtmp / MediaMTX / SRS)
  plus transcoding. ffmpeg is not installed on vm23. Infrastructure, not app
  code — `Tv::Broadcast` already models `stream_key`/`go_live!`/`end_live!`.
- **Solidus marketplace.** `brgen/config/database.yml` is sqlite3 in all four environments
  and Solidus supports Postgres/MySQL in production. This is a database
  migration first, not a gem install.
- **pgvector-backed recommendations.** Same Postgres dependency.

---

## Sequencing

Tier 1 first. It is mechanical, it is four small changes, and it produces the
ranking and notification signals that Tier 2 and most of Tier 3 read. Then
`Event` (2.2) and community moderation depth (2.4), which are the largest
missing nouns. Then ActivityPub (2.1), which is the item that makes brgen
something other than a clone.
