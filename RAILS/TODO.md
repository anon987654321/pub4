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

### 1.1 Repost was a decorative button — **done, built**

The call was build rather than drop, because brgen is aiming at x.com and
Mastodon parity and `Announce` is repost (2.1 depends on it).

A repost is a `Repost` row, not a `Post`: `Post` includes `Shared::Sluggable`,
whose slug is derived from the title and unique per city, so a repost-as-post
would have collided with the thing it reposted. It carries no content, boosts
into followers' timelines via `User#timeline_posts`, notifies the author (but
not for reposting yourself), and toggles off on a second press.

The button is a `button_to`, not the `action` Stimulus controller the vote
button uses. Two reasons: that controller's optimistic toggle is exactly what
made the broken version look like it worked, and a third Stimulus instance per
card breaks `FrontPageWeightTest`'s five-per-post budget.

Three things the repo's own gates caught, all of them real:

- `reposted_by?` as an `exists?` per card is a 25-query N+1 on the feed;
  `QueryBudgetTest` failed on it. It is now one pluck per request memoised on
  `Current`.
- the card is fragment-cached and `reposted_by?` is per-viewer output, so the
  flag had to go into the cache key or one viewer's repost state renders for
  everyone.
- `FrontPageWeightTest` had a test asserting *no repost backend exists* and the
  button stays inert. It is inverted now: the button must reach the endpoint.

**Found while wiring it, and fixed:** `post_vote_path(post)` carries the slug
(`Sluggable#to_param`), and `VotesController#find_votable` called `Post.find` on
it — a 404 that the `action` controller rolls back silently, so **every vote
cast from a feed card was discarded**. Fixing that exposed a second layer:
`Vote#update_author_karma` lazily read `votable.user` on a strict-loading record
and raised after the vote had been written. Both pinned by tests.

**Check:** `brgen/test/models/repost_test.rb` (counter cache, uniqueness, undo,
timeline inclusion, author notification, cascade) and
`brgen/test/controllers/reposts_controller_test.rb` (POST toggle, guest
behaviour, removed posts, cache-key leakage, and voting by slug).

**Still open:** quote-post — a repost carrying a comment — which x.com and
Mastodon both lean on. Also `shared/app/views/shared/_action_bar.html.erb` is
wired the same way but **no view in any of the three apps renders that
partial**; it is contract-pinned by `RAILS/test/design_contract_test.rb` and
otherwise dead. Deleting it is a call for whoever added it.

### 1.2 `Tv::ViewEvent` recorded that a page opened, not that anything was watched — **done**

The first version of this entry said no row was ever created. That was wrong,
and wrong for an instructive reason: the grep behind it searched for the class
name, and the only writer reaches the table through the association
(`@video.view_events.create!` in `videos#show`). Searching for the noun missed
the verb.

What was true: the row was created with `watch_time_seconds` and `completed`
both nil and nothing ever filled them in, and `Tv::Video.trending` sorted
`views_count` — incremented on that same page load. So a viewer who bounced
after four seconds moved a video up the trending page exactly as far as one who
watched it through, and the two columns that could tell them apart were never
written by anything.

Now: `videos#show` keeps the row in an ivar and hands the player its URL; the
player reports the furthest point reached on pause, on `ended`, on tab hide and
on disconnect. `record_progress!` takes the max (beacons arrive out of order),
clamps to the video's own `duration_seconds` (the number comes from the client,
and unclamped the ranking is forgeable), and marks `completed` at 90% because
the last `timeupdate` rarely reaches duration. `trending` now ranks by summed
watch time with `views_count` as the tiebreak, via a correlated subquery rather
than `left_joins + group` — the home page passes the scope to pagy, and pagy
counts a grouped relation with `.count(:all)`, which returns a hash.

Two things fell out of doing it:

- `data-tv-player-target="video"` was declared on no page in the tree, so the
  player's whole `#bindVideoEvents` body — including the wake lock on play —
  had never run. Watch-time reporting needs that target, so it runs now.
- `videos#show` preloaded `:channel` but not `channel: :user`, and the subscribe
  control reads `Current.user != @video.channel.user` only when authenticated.
  The page rendered for guests and raised for every signed-in viewer, which is
  why a guest-only smoke test never caught it.

**Check:** `engines/tv/test/models/tv/view_event_test.rb` (monotonicity, clamp,
90% threshold, no-duration case, strict loading, and that trending puts one
watched-through view above 500 page opens) and
`test/controllers/tv_watch_time_test.rb` (a viewer can only write their own
event; the page carries the progress URL).

**Still open:** the vertical feed that would consume this ranking — see 2.5.

### 1.3 `Marketplace::SavedSearch` never ran itself — **done**

Worse than a bookmark, as it turned out. The table carries a `notify` boolean,
the create form permits it, and the saved-searches page renders an "alerts on"
chip from it — while nothing in the tree ever ran a saved search on anyone's
behalf. Ticking "notify me" changed a label. The only other reader was a manual
"run search" link.

Now `SavedSearchAlertJob` runs every 30 minutes over searches with `notify` on,
matching new listings through `Shared::LiveSearch` on the same columns the
listings page searches, so an alert cannot disagree with what that row's own
"run search" link would show. Three things it deliberately does:

- a new `last_notified_at` column, anchored to `created_at` on first run, so
  switching alerts on does not mail you the entire back catalogue;
- a 6-hour floor per search, independent of the schedule, so the cadence of the
  job is not the cadence of the interruption;
- a quiet run leaves `last_notified_at` alone, so the next run still measures
  from the last thing the user was actually told about rather than silently
  stepping over listings posted in between.

**Check:** `brgen/test/jobs/saved_search_alert_job_test.rb` — eight tests
covering first alert, back-catalogue suppression, alerts-off, the interval floor
and its expiry, category scoping, the untouched watermark, and one broken search
not stopping everyone else's.

**Still open:** price-drop alerts, which fall out of the same job once `Deal` is
joined in, and web push — the alert lands in `Notification`, and
`PushSubscription` only fires for `PUSHABLE_KINDS`.

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

### 2.2 No `Event` model (Facebook) — **done**

The largest missing noun on the list, and the one with the most already sitting
underneath it: `Place`, `PlaceCheckIn`, `Neighborhood`, the maps engine, and a
city-strip on the home page that now carries `EventCreated`.

`Event` + `EventRsvp`, with the decisions worth keeping:

- **Location is two-sided.** An event either points at a `Place` (which fills in
  coordinates, venue name and neighbourhood at validation) or carries free text.
  Requiring a Place means nobody can post a party in their own flat; requiring
  coordinates means nobody can post before the venue is settled.
- **`upcoming` means "has not finished", not "has not started"** — a three-day
  festival is still on during day two, and dropping it at the opening minute is
  how a what's-on page lies.
- **RSVP is three-way.** "Interested" is the majority answer on every event
  platform; collapsing it into going/not-going both overstates attendance and
  loses the reminder signal. Pressing the answer you hold withdraws it.
- **The counts are recounted, not counter-cached.** Rails increments on create
  and decrements on destroy, and a status moving from going to interested is
  neither. `update_columns` writes `updated_at` by hand, because the card is
  fragment-cached on `[event]`.
- **Cancelling is not deleting.** People have it in their calendar; `cancel!`
  notifies everyone who said they were coming and the event stays readable.
- `capacity` nil means unlimited, and `places_left` returns nil rather than 0 so
  it cannot render as "0 places left". A full event still takes "interested".

**Check:** `brgen/test/models/event_test.rb` (12) and
`brgen/test/controllers/events_controller_test.rb` (9).

**Still open:** recurring events, ticketing beyond an external link, and an
event's own map pin on the maps engine (it has coordinates; nothing draws them).

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
