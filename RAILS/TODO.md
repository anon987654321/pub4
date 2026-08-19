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
2026-08-19 — mostly because `apps.yml` records a feature as `done` when the
model exists, and several of these models exist with nothing reading or writing
them.

Several entries were themselves stale by 2026-08-18: price-drop alerts, takeaway
push, and the courier, event and story map layers were all built while this file
still listed them as open. A finding is a hypothesis; re-measure before working
from one.

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

**Quote-post is built.** A `reposts.comment` column (max 280) turns the same
row into a quote; empty comment stays a boost; a second boost press still
destroys. The write surface is a form in the more-actions dropdown (no extra
Stimulus — FrontPageWeightTest still holds) and on the post page, which lists
quotes. It is not a `Post`, for the same Sluggable reason as a boost.

**Check:** `brgen/test/models/repost_test.rb` (quote is not a Post, length,
notification body) and `brgen/test/controllers/reposts_controller_test.rb`
(comment creates, updates a boost, second POST without comment destroys).

**Closed 2026-08-18.** The dead-partial note was stale: `shared/_feed_card`
renders `shared/action_bar` when it is given a `record:` and no `actions:`, so
the partial is reached by every app that draws a feed card.

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

**Closed.** Price drops are `SavedSearch#price_drop_matches`, preferred over
plain new listings so a reduction on an existing match is not hidden behind "N
new listings", and `alert` is in `PUSHABLE_KINDS`, so the alert reaches a lock
screen.

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

**Closed.** `Maps::HomeController#courier_layer` draws the courier — the
viewer's own, and only while that order is out for delivery. A live position is
the courier's, not the city's: publishing every rider's would be tracking people
who never agreed to it, and the person waiting for the food is the only one who
needs it.

---

## Tier 2 — structurally absent

### 2.1 No federation (Mastodon) — **done, outbound half**

A brgen account can now be followed from anywhere in the fediverse and its
public posts deliver outward. WebFinger, NodeInfo, actor documents, outbox,
followers, a verified inbox, HTTP signatures, per-inbox delivery with retry.

The city partitioning does the work: `@kari@brgen.no` and `@kari@oshlo.no` are
different accounts because the cities are already different origins with
different populations, which is the same shape as two Mastodon instances. Every
lookup resolves against the *requested host* — answering for the wrong city
would hand a stranger's posts to whoever asked.

Security decisions, since the inbox is where an unverified string becomes an
action:

- **The signer and the claimed author must match.** Without that check a valid
  signature from any actor authorises an activity attributed to any other, and
  every account is forgeable by anyone with an account anywhere.
- **Partial coverage fails closed.** A signature over nothing but `Date` is a
  valid signature that proves nothing about the request, so
  `(request-target)`, `host`, `date` and `digest` are all required.
- **The Digest header is checked**, or a signed request can carry any body.
- **Signatures expire** (5 minutes), so a captured request cannot be replayed.
- **Delete only removes what its sender owns.** A verified signature proves who
  is asking, not what they may ask for.
- Bodies are capped before parsing; keys are cached, because re-fetching an
  actor per inbox POST makes our inbox an amplifier pointed at whoever is being
  impersonated.
- The followers collection reports a count and lists nobody. Who follows a
  small-city account is worth more to a scraper than to anyone else, and the
  protocol does not require publishing it.

Keys are RSA-2048 generated on first use, not at signup — brgen mints a real
`User` row for every cookieless visitor and almost none of them federate.

**Check:** `brgen/test/lib/fediverse_signature_test.rb` (10, every way
verification can be got wrong), `brgen/test/controllers/fediverse_test.rb` (10,
discovery and the city boundary), `brgen/test/controllers/fediverse_inbox_test.rb`
(12, including impersonation, body-swap, replay and duplicate delivery).

**Still open — the inbound half.** Remote `Create`, `Announce` and `Like` are
verified, recorded as seen and then dropped: brgen does not store remote posts.
That is deliberate rather than unfinished — ingesting them means remote media
proxying, remote content moderation (`ModerationReport` has no model for
content whose author is not local) and a blocklist story, each of which is
larger than everything above. The handler says so instead of pretending.

Also open: outbound *following* (a brgen user following a remote account),
instance-level blocklists, and `Update` on edit.

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

### 2.3 No Story / ephemeral media (Snapchat) — **done**

Ephemerality existed only inside DMs. `Story` + `StoryView` put it on a public
surface.

- **The lifetime is a column, not a computation.** `expires_at` is stored, so
  the `alive` scope, the countdown label and the sweep all read one value rather
  than each re-deriving 24 hours and eventually disagreeing.
- **`alive` hides an expired story before the sweep runs**, so a link stops
  working the moment it should rather than whenever the job catches up. The
  sweep is about the bytes: `destroy`, not `delete_all`, so the Active Storage
  blobs go with the rows on a 1 GB VPS.
- **Seen is a set, not a log.** Opening twice is one view and the author's
  viewer list never repeats a name. `create_or_find_by!` was wrong here — it
  rescues the *database's* uniqueness error, and the model validation fires
  first, so a second open raised instead of reading as "already seen".
- **Camera-first**: the file field carries `capture="environment"`, which opens
  the rear camera on a phone and degrades to a file picker on a desktop.
- **The area comes from the position the app already has.** `locations#update`
  stores it coarsened to ~1 km; the compose form opts in rather than taking a
  fresh GPS read. The existing `geolocation` Stimulus controller POSTs to that
  endpoint and has no form-field targets, so hidden inputs wired to it would
  have been controls that do nothing.
- A ring is a person, not a photo: grouped by author, followed authors first.

**Check:** `brgen/test/models/story_test.rb` (10) and
`brgen/test/controllers/stories_controller_test.rb` (7).

**Closed 2026-08-19.** The Snap-Map is `Maps::HomeController#stories_layer`,
which is only acceptable because the coordinates are coarsened to ~1 km on write
— a pin says "around here", not "at this address".

A reply is a direct message carrying the story it answers, so it stays readable
after the 24 hours are up; only `alive` stories take one, because a reply box
that still works after the sweep is a promise broken quietly.

`StoryStreak` counts days running that two people have answered *each other* —
mutual, because a streak one person can hold up alone is a posting counter
rather than a pair still talking. Whether it is over is computed on read: a
sweep that has not run yet would leave a dead streak on the page, and the answer
is one date comparison.

**Found while wiring the reply box, and fixed:** `Conversation.direct_between`
read `for_user(a).for_user(b)`, which looks like an intersection and is not —
both scopes join the same association, Rails collapses them, and the predicates
AND on one participant row. It always answered nil, so `find_or_create_direct`
always created, and **every pair of people got a new DM thread each time they
opened one from a different button**.

### 2.4 `Community` was eight columns (Reddit) — **done**

Roles on `community_memberships` (member / moderator / owner), plus rules,
flair, privacy, icon, banner, `members_count` and an archive flag on
`communities`. A community can now be run by its own members.

- **Owner is a membership row, not just `communities.user_id`.** The creator
  gets one on create, and the migration backfills every existing community —
  otherwise each one predating today has an empty moderator list and nobody who
  can appoint anyone.
- **The last owner cannot be demoted.** Nothing else in the app creates an
  owner, so that is not a state to recover from later.
- **Only an owner appoints.** If a moderator could change roles, one could
  demote the person who made the community, and there is nothing above them to
  appeal to. Moderators may edit rules and flair; only an owner may delete.
- **Reading and posting are separate questions.** Restricted is the interesting
  case: the whole city reads it, only members post. Enforced in the controller,
  because a hidden compose link is not a permission check.
- **The queue is derived, not denormalised.** `ModerationReport` is polymorphic
  and carries no `community_id`; `Community#moderation_queue` reaches it through
  the community's posts and their comments, so there is no column to backfill
  and keep true.
- Flair is the label itself on `posts.flair`, not an id — flairs are edited as a
  text list, so an id would dangle the moment a community renamed one.

**Found while wiring it, and fixed:** `ModerationWorkflow#transition!` read the
polymorphic `report.reportable` on a report loaded by `find`, raising under
strict loading *after* the status had been written — **`Admin::Reports#update`
has been on that path the whole time**, so resolving any report from the admin
queue 500'd. And `communities#show` compared `Current.user != @community.user`,
a lazy read that raised for every signed-in visitor while rendering fine for
guests — the same shape as the tv video page.

**Check:** `brgen/test/models/community_governance_test.rb` (9) and
`brgen/test/controllers/community_moderation_test.rb` (9).

**Bans are built.** A mod queue that can resolve a report but not stop the
person who caused it is half a tool: resolving takes the content down and the
same account posts the same thing a minute later.

`CommunityBan` is its own table, not a flag on `community_memberships`, because
a public community takes posts from anyone — the person to ban usually has no
membership row, and inventing one to hold the ban would make them a member and
bump `members_count` in the act of banning them. Checked before privacy in
`postable_by?`, since a public community is exactly where a ban has to bite.

Scoped to the community and nowhere else: one community's moderator silencing
someone across the whole city is not a lever that should exist. Temporary bans
lapse on their own; a moderator cannot be banned without being demoted first (a
fight the app should not settle); any moderator can lift any ban, because a mod
team that cannot undo each other's mistakes escalates everything to the owner;
and the banned person is told with the reason, because a ban nobody is informed
of reads as the site being broken.

**Check:** `brgen/test/models/community_ban_test.rb` (10) and
`brgen/test/controllers/community_bans_controller_test.rb` (6).

**Crossposts and the wiki are built (2026-08-18).** A crosspost is a `Post` in a
second community with its own comment thread, not a join row — a repost boosts
into followers' timelines and belongs to no community, which is the other act. A
crosspost of a crosspost points at the original, or "seen in four communities"
cannot be answered without walking a chain. `postable_by?` is the whole
permission check, so a community that banned an account cannot be reached
through a crosspost either.

The wiki is `CommunityWikiPage` plus `CommunityWikiRevision`: moderators write,
whoever can read the community reads. Writing goes through `revise!` rather than
`update!`, so no caller can save a page and forget the revision, and a revert is
a new revision rather than a deletion of the ones after it — a wiki whose
history can be edited is a wiki nobody can audit.

**Check:** `brgen/test/controllers/crossposts_controller_test.rb` (5),
`test/models/community_wiki_page_test.rb` (5),
`test/models/community_wiki_revision_test.rb` (4),
`test/controllers/communities/wiki_controller_test.rb` (5).

**Still open:** nothing in this entry.

### 2.5 No vertical video surface (TikTok) — **done**

`tv.­*/feed`: one video per screen, ranked by watch time. `home#index` stays as
it was — the grid is the YouTube answer to "what is there", and this is the
other question.

Only possible because 1.2 records watch time. Ranking a feed on `views_count`
would have served whatever got the most accidental clicks, since that counter
is incremented on page load.

- **Snapping is CSS, not JS.** The browser already does momentum,
  rubber-banding and keyboard paging correctly; a hand-rolled scroller gets at
  least one of those wrong on some device. Stimulus only decides what plays and
  what gets recorded.
- **`100dvh`, not `vh`** — mobile browser chrome collapses on scroll, and `vh`
  leaves a strip of the next video showing under the address bar all the way
  down.
- **No `autoplay`, `preload="none"`.** Ten videos preloading at once is a few
  hundred megabytes on a phone; the controller plays the visible one and pauses
  the rest. `muted` + `playsinline` because iOS refuses to autoplay anything
  else, and sound is opt-in.
- **Watch time is the furthest point reached, sampled while it plays** — a
  looping video's `currentTime` returns to zero, so the max is the only honest
  number. Reported with `sendBeacon` on scroll-away and unload.
- A video with no file is not in the feed at all: a blank screen you cannot
  scroll past is worse than a shorter feed.
- **Logged-out viewers count.** brgen mints a real `User` per visitor, so their
  watch time ranks too — for video that is the point, since most viewers are
  never signed in. `PruneGuestUsersJob` `destroy_all`s those users and the view
  events are `dependent: :destroy`, so the rows go with them.

**Found while wiring it:** the nested view-events path carries the video's slug
(`Sluggable#to_param`) and the create action looked up by `id` — the third time
that trap has appeared today, after `post_vote_path` and `post_repost_path`.

**Check:** `brgen/test/controllers/tv_feed_test.rb` (6), including that one
viewer who watched a clip through outranks 500 page opens.

Live streaming stays blocked — see "Blocked" below.

**Still open:** sounds/remix as a first-class object (a video has no audio
identity, so there is nothing to browse "more of"), and duets.

---

## Tier 3 — per-surface parity

### Marketplace (Amazon / Temu) — **basket done**

`Marketplace::Order` is a per-listing *offer* with its own payment, which is the
right shape for classifieds: a bike from a stranger is negotiated, not added to
a cart. It was the wrong shape for a shop — four things meant four payments,
four PSP round trips and four card charges, with nowhere to put an address.

So `Marketplace::Checkout` sits **above** the orders rather than replacing them,
and both shapes keep working. One basket, one payment, one address, many orders,
split by seller for fulfilment.

- **`Marketplace::Address` is its own record**, so a second purchase does not
  mean typing it again and a later edit does not rewrite the address printed on
  last month's label.
- **Fulfilment is a separate axis from payment.** A paid order that has not
  shipped and a shipped order awaiting payment are both real states; collapsing
  them into one column is why "where is my parcel" goes unanswered. `ship!`
  carries a tracking code and tells the buyer.
- **`stock` is nil for one-of-a-kind**, a number for a shop. Defaulting to 1
  would have made every private sale read as a shop with one left.
- **Paying is all-or-nothing** — a half-paid basket, one card charged, is the
  state nobody can resolve.
- The payment services stopped reading `order.listing.currency`/`.title` and now
  ask the payable for them, so a basket goes through the *same* guarded path
  (including the sk_test_-key-in-production guard) rather than a second one.
- Check order in `checkouts#create` is the order a buyer should meet it in:
  nothing to pay for → provider unconfigured → no address → then a basket.
  Getting this wrong produced a `DoubleRenderError`, i.e. a 500 for a buyer who
  had simply not saved an address.

**Check:** `brgen/test/models/marketplace_checkout_test.rb` (8) and
`brgen/test/controllers/marketplace_basket_test.rb` (5).

**Listing Q&A is built (2026-08-19).** Asking went through the offer thread, so
the seller answered "is it still available" once per buyer and the answer left
with them. `Marketplace::Question` is public on the listing, answered by the
seller, notifying both ways as kind `alert` (which is pushable). Answered
questions sort first; an unanswered one still shows, because it is the question
the next buyer has too.

**Check:** `brgen/test/controllers/marketplace_questions_test.rb` (3).

**Still open:** product variants (size/colour — a real schema, not a column),
returns, seller payouts, wishlist, and search facets. Temu-flavoured
work is still cheap on top of `Marketplace::Deal`: countdown flash deals,
coupons, referral credit, bundle pricing.

Solidus remains blocked — see below — so all of this is native-path work.

### Dating (Tinder / Hinge) — **ranking and prompts done**

The deck was `ORDER BY RANDOM()`: orientation, neighbourhood and a 20 km radius
filtered the pool and nothing ranked it, so someone last seen in March sat
beside someone online now — and every reload reshuffled, so a profile you had
just passed could not be found again.

`Dating::Profile.ranked_for` orders by three things, in this order:

1. **recency** — who is actually around; a deck full of dormant accounts is a
   dating app nobody matches on;
2. **effort** — profiles with prompts answered, because that is what gives the
   viewer something to reply to;
3. **a per-viewer, per-day shuffle** — stable while someone browses, different
   tomorrow, and different between two people.

Deliberately *not* attractiveness, engagement, or any like-count feedback loop:
ranking people by the attention they already receive is how these products end
up with a handful of accounts getting everything.

The shuffle is a per-viewer **multiplier** over a prime modulus, not an offset.
The first version added a per-viewer salt, which shifts every id equally and
leaves the order identical — the test that two viewers see different decks is
what caught it.

`Dating::Prompt` is the Hinge half: a fixed question list (free text becomes a
second bio), three per profile, and a like that points at one answer and says
something about it. Plain likes still work — a product that refuses one is a
product people stop using at 1am. Prompt ids are scoped to the liked person's
own profile, or a like could point at a stranger's answer.

Who-liked-you is its own page, not folded into the deck: people who have already
said yes are a different decision from people who have not seen you.

**Check:** `brgen/test/models/dating_ranking_test.rb` (8) and
`brgen/test/controllers/dating_likes_test.rb` (5).

**Unmatch is built.** `Dating::Match#unmatch!` writes `unmatched`, drops the
mutual likes so the pair can like again, and rematch flips the same row back
to `matched` rather than inserting a second pair. The matches list is still
`active` (matched only); destroy is scoped to a participant.

**Check:** `engines/dating/test/models/dating/match_test.rb` (likes cleared,
rematch, strict loading) and `brgen/test/controllers/dating_unmatch_test.rb`
(participant can, stranger 404s).

**Rewind is built.** Last pass only: `Dating::Dislike.rewind!` destroys the
most recent dislike and the deck query already excludes dislikes, so that
profile comes back. A like is a different decision (it may have created a
match) and is left alone. Empty rewind is a flash, not a 404.

**Check:** `brgen/test/controllers/dating_rewind_test.rb` (last pass undone,
a like is not).

**Still open:** super-like and boost (both purchases — `apps.horizon.yml` has
them as `agent: ignore`), photo verification, daily picks.

### Takeaway (DoorDash / Foodora) — **hours, tips, scheduling done**

`Takeaway::OpeningHour` is a row per weekday, not a JSON blob: "is this open
now" is a query, and a blob turns the restaurant list into a Ruby loop over
every row on the page. Minutes past midnight rather than a `Time` (which
carries a date and a zone that mean nothing here), and `closes_minute` may
exceed 1440 — because closing after midnight is normal for a kitchen, and
reading only today's row says a place open until 02:00 is shut at 00:30.

- **No hours recorded = open.** Most restaurants have none yet and defaulting
  to closed would empty the listing; `active` stays the "not trading" switch.
- **A closed kitchen still takes a scheduled order** — that is most of what
  scheduling is for. Enforced in the controller, because a hidden button is not
  a closing time.
- The tip is in the total from `calculate_totals!`, not added somewhere later.
- A scheduled order estimates from **when it was asked for**, or it is
  permanently late for having been placed that morning.

**Check:** `brgen/test/models/takeaway_hours_test.rb` (8).

**Order-again is built.** `orders#again` copies available items at current
prices onto a new pending ticket with the same address. Items that left the
menu are skipped; if none remain, the diner is sent to the restaurant rather
than placing an empty order. Tip and scheduled_for stay off — those are
per-ticket. The show-page "reorder" control is a POST, not a link at the
menu.

**Check:** `engines/takeaway/test/models/takeaway/order_test.rb` (`build_reorder`)
and `brgen/test/controllers/takeaway_order_again_test.rb` (copy, skip-empty).

**The live courier map is built** — see 1.4; the maps engine draws the viewer's
own courier while the order is out for delivery.

**Still open:** group orders, and web push on each `transition_to!` is now on
the path: `order` is in `PUSHABLE_KINDS`, so a transition reaches a lock screen
rather than only the in-app list.

### Messenger — **reply, edit and unsend done**

Typing indicators, read receipts, reactions, presence, disappearing messages and
attachments were already there.

- **Reply-to**: in a channel with several conversations at once, a message with
  no referent is one nobody can follow.
- **Editing is bounded to 15 minutes.** A message that can be rewritten hours
  later is one a reader cannot trust, and the receipt saying they read it is
  already gone.
- **Unsending has no window at all** — a message sent to the wrong room, on a
  chat where people post real addresses, is a safety problem rather than a typo.
- **The unsend is soft.** The row stays and the body goes, because a hard delete
  leaves a hole in a thread and orphans whatever replied to it. That required
  exempting deleted messages from the content presence validation, or the record
  is permanently invalid and every later save on it — a receipt, a reaction —
  fails.

**Check:** `brgen/test/models/message_edit_test.rb` (7).

**Closed 2026-08-18, except the calls.** Voice messages, forwarding, link
previews, message search, group naming with admin roles, and pinned
conversations are built.

The recorder writes into the composer's own file field, so a voice note goes
through the same create path as a photo — `duration_seconds` and `Message#voice?`
had shipped and nothing in the tree could produce an audio message. An
attachment is now a message on its own: a voice note has no words in it by
definition.

Forwarding is a copy, not a pointer: the copy has to outlive the original being
unsent, it belongs to the forwarder, and its readers usually cannot open the
thread it came from. Both ends are scoped to the reader's own conversations.

Link previews carry title, site and summary and **no image**: hotlinking one
tells that server the IP of everyone in the thread, and proxying it is remote
media hosting — the problem 2.1 defers. One row per URL, so the same article in
twenty rooms is one fetch rather than twenty pointed at whoever was linked.

Search reads `visible.unexpired` like every render does, or ephemerality would
be a rendering choice rather than a promise.

A group DM is a `Conversation` with a name and no slug (a #channel is one with a
slug), and roles reuse the IRC ladder already on the participant row. Ops rename
and remove; any member may add, because a group where only the founder can bring
someone in is one people work around by starting a second group. The last op
leaving hands the room to the longest-standing member rather than trapping them
in it.

Pinning is per-participant and a timestamp: a pin on the shared row would let
either side reorder the other's inbox, and pinned threads order among
themselves.

**Found while wiring the controls, and fixed:** reply, edit and unsend had a
route, a model method, a test each — and no control on any page. A backend
nobody can reach is not a feature.

**Check:** `brgen/test/controllers/{conversation_pins_controller,conversation_search,message_forward,group_conversations_controller,voice_message}_test.rb`
and `test/models/link_preview_test.rb`.

**Still open:** no WebRTC anywhere, so still no voice or video calls.

### Craigslist — **expiry and renewal done**

Geo listings, categories, city subdomains, casual (no-store) listings,
buyer–seller chat and FTS were already there. Listings now expire after 45 days
and can be renewed.

**Expiry is a scope, not a state change.** `live` (active *and* unexpired) is
what the policy scope resolves for public surfaces; `active` still includes a
lapsed listing, which is what lets its owner see and renew it. A listing that
silently vanished from its own seller's account would read as a bug rather than
a policy. Renewing restarts the window from now, so renewing late does not
immediately expire again, and it clears the notice flag so the next lapse is
announced too.

**Check:** `brgen/test/models/listing_expiry_test.rb` (5).

**Still open:** the anonymised contact relay — it needs mail infrastructure
(inbound routing and per-listing addresses), which is an operator change on
vm23 rather than app code, and `brgen.no` mail is only outbound-verified today.
Also the non-goods verticals (jobs, housing, gigs), which are mostly category
data plus per-vertical fields rather than new machinery.

---

## 4. The gates cannot see a WebGL surface

`gates/support/cdp_session.rb` launches Chrome with `--disable-gpu`, so
`webglSupported` is `false` in every rendered gate. MapLibre and the MASTER face
both need WebGL, so **both measure as an empty canvas** — a gate asserting "the
map draws" would pass or fail for reasons that have nothing to do with the map.

Found on 2026-08-13 while checking a report that `maps.brgen.no` was broken. It
is not: with `--use-angle=swiftshader` the map renders Bergen, its tiles and its
markers, with zero console errors. The blank screenshot came from the
instrument, and any gate built on that instrument would have inherited it.

`--disable-gpu` is right for the layout and CSS gates it was written for —
software GL is slow and its text rasterisation differs — so the fix is probably
a separate opt-in flag for the WebGL surfaces rather than dropping it globally.

**Check:** none. Nothing asserts that a WebGL surface drew anything, which is
the point of the entry.

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

Tier 1 and Tier 2 are closed as of 2026-08-19, apart from the inbound half of
federation, which is deliberate rather than unfinished. What is left is Tier 3
and one instrument problem:

1. **Marketplace depth** — variants, returns, seller payouts, wishlist, search
   facets. The densest surface in the family and the one with money on it.
2. **The verticals' own gaps** — dating photo verification and daily picks, tv
   sounds and duets, takeaway group orders, the Craigslist non-goods verticals.
3. **Outbound federation** (2.1) — following a remote account, `Update` on edit,
   instance blocklists.
4. **Section 4**, the WebGL blind spot in the rendered gates, which is not a
   feature at all: it is the reason no gate can currently assert that a map or a
   face drew anything.
