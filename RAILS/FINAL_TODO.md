# RAILS final polish backlog

Measured 2026-08-03 against the working tree, with the four apps booted on
their canonical ports (`RAILS/bin/triangle up`). Every item below is a scanner
finding or a browser measurement, not a proposal — `UI_REFINEMENTS.md` already
records what previous waves closed, and its own 2026-08-01 entry names the
failure this file is built to avoid: "a landed row and an inert one look
identical from the outside."

Authority order for anything here: `MASTER/data/soul.yml` >
`MASTER/data/rules.yml` > `MASTER/data/design_rules.yml` > `CLAUDE.md`.

## The contract this list is written against

**Commands.** `cd MASTER && bin/check` for ordinary code; `--profile=agent` for
law, scanners and the fix loop; `--profile=web` for the face; `--profile=full`
as the release gate. `bin/pub4 status` at repo level. For RAILS specifically:
`OPENBSD/bin/check-rails --profile=contributor`, plus the per-app trio in
`WIRING_NOTES.md` (`dartsass:build`, importmap audit, `bin/rails test`) and the
family gates in `RAILS/gates/`. Run the smallest check that proves the work and
never report done without its output.

**Work rules that bind this file** (`soul.yml` `absolute.code_rules`):
PRESERVE_FIRST — read before writing, never rewrite working code from scratch.
FAIL_VISIBLY — no bare rescue, no swallowed error. SIMPLEST_WORKS — no god
classes. SURFACE_ERRORS_FIRST — failures lead. NO_DEAD_ENDS — every closed door
names an adjacent open one. RTFM_FIRST — read the reference before using a
flag. `anti_simulation.forbidden` bans *will/would/could/might*, so every claim
below is stated as a measurement with the evidence that produced it.

**Design law** (`design_rules.yml`): flat only — no `box-shadow`, `text-shadow`,
`backdrop-filter` or `filter: blur()` outside a documented
`pixel_perfection.exception_policy` exception. 8px rhythm
(0/4/8/12/16/20/24/32/40/48/64/96). Tokens over magic values. 44px touch
targets, 48px for primary actions. Body text at 16px minimum, line-height 1.4+.
Max 7 peer choices per nav group (Hick). Separation is space, not lines
(operator decision 2026-07-28). Empty, loading, error and reduced-motion states
are all designed states, not omissions. Default locale `nb`, available `nb`/`en`.

**Standing local preference, which outranks `design_rules` where they
disagree:** flat, brutalist, minimal, x.com-shaped. The `pixel_field` /
IRIX / 8-bit vocabulary in `design_rules.yml` was dropped 2026-07-18 and is not
a target. Never invent a visual layout fix — restore the intended look or ask.
The hidden swipe-reveal chrome is deliberate.

---

## P0 — confirmed broken on the brgen front page

Four reports, four root causes, all reproduced locally on
`http://127.0.0.1:38182/` at 390x844 via CDP. These are defects, not polish;
they sit above every scanner section below.

### P0.1 The logo is rendered, invisible, and unclickable — a z-index conflict

- [ ] `brgen/app/assets/stylesheets/_root.scss:115` — `.brgen-logo-mark` sets
      `z-index: calc(var(--z-chrome, 10) + 1)`, which computes to **11**.
      `brgen/app/assets/stylesheets/_nav_swiper.scss:8` sets `.nav_swiper`
      `z-index: var(--z-nav)`, which resolves through
      `_dialect_tokens.scss:202` (`--z-nav: var(--z-ui)`) to **90**.
      `.nav_swiper_bar` inside it has `background: var(--bg)`, measured
      `rgb(0, 0, 0)` — fully opaque.

      Measured geometry: the logo is at `x:14 y:14 w:63 h:44`, `position:
      fixed`, `visibility: visible`, `opacity: 1` — it is painting. The nav bar
      occupies `y:0 h:55`. They overlap for the logo's full height, and the bar
      wins the stack at 90 vs 11. `document.elementFromPoint` at the logo's own
      centre returns **`.nav_link.active`** — the "front" nav item. So the
      wordmark is not merely hidden: a tap in the brand corner navigates to
      `front` instead of home.

      The existing fix for this exact bug is already in the tree and was
      applied to the wrong bar. `_root.scss:102` publishes
      `--brand-mark-inline: 4.75rem` with a comment naming the symptom ("the
      first `.feed-tab` had its left ~63px swallowed"), and `_nav.scss:34`
      consumes it in `.feed-tabs`. `.nav_swiper_bar` — which moved to the top
      of the page when the nav became always-visible — never got the same
      padding. Fix: give `.nav_swiper_bar` the same
      `padding-inline-start: var(--brand-mark-inline)` and
      `scroll-padding-inline-start`, or lift the logo above `--z-nav`. Pick one;
      do not add another `!important`.

- [ ] Add a gate for this class of bug. `elementFromPoint` at the centre of
      every fixed chrome element must return that element or a descendant. This
      is the second time fixed chrome has swallowed taps in the same corner
      (`_root.scss:94-101`, `_root.scss:104-107`), and neither the
      `design_contract` nor the `visual_contract` gate catches it, because both
      elements render correctly in isolation.

### P0.2 Two stacked nav scrollers, one of them a duplicate

- [ ] `brgen/app/views/layouts/application.html.erb:196-202` — the front page
      renders **both** nav rows, sticky at `top: 0`, one directly under the
      other:

      | Bar | Source | Measured | Items |
      |---|---|---|---|
      | `.nav_swiper_bar` | `shared/_nav_swiper.html.erb` -> `brgen_nav_groups` | y:0 h:55, scrollW 1019 / clientW 390 | front · live · AI · channels · sign up · **marketplace · dating · playlist · TV · takeaway · maps · messenger** |
      | `.feed-tabs` | layout `.feed-header` -> `subapp_nav_items` | y:0 h:49, scrollW 911 / clientW 390 | **marketplace · dating · playlist · TV · takeaway · maps · messenger** |

      `subapp_nav_items` (`application_helper.rb:118`) is
      `brgen_nav_items.select { VERTICAL_NAV_LABELS.include?(label) }` and
      `brgen_nav_groups` (`:113`) partitions the same list — so
      `.feed-tabs` is a strict subset of what the swiper above it already
      shows. Both overflow and scroll horizontally with an edge mask, so they
      read as two swipers. 104px of stacked chrome on a 997px page; the first
      feed item starts at y:128.

      Fix: delete the `.feed-header` `<nav class="feed-tabs">` block from the
      layout and keep the `visually-hidden` `<h1>`. The nav swiper is the
      canonical primary nav. Do not instead delete the swiper —
      `WIRING_NOTES.md` and the layout comment at `:194` both name the fixed
      wordmark plus swiper as the intended shell.

- [ ] `application_helper.rb:118` — `subapp_nav_items` has exactly one caller,
      the block being deleted. Remove it with the markup rather than leaving a
      helper with no reader.

- [ ] `_nav_swiper.scss:36-40` — with `.feed-tabs` gone, re-check the
      two-group divider. Group one is 5 items and group two is 7; Hick's
      `max_visible_choices` is 7, so the split stays correct, but the visual
      break lands mid-scroll on a 390px viewport where only ~4 items are
      visible at once. Measure before adjusting.

### P0.3 Chat is broken twice over

**(a) The composer turns into an edit form after the first send.**

- [ ] `brgen/app/views/messages/create_widget.turbo_stream.erb:5` passes the
      **persisted** `@message` into the composer partial. Reproduced with a
      real POST to `/conversations/71/messages` (`origin=widget`, HTTP 200) —
      the single returned turbo-stream replaces `#nearby_widget_message` with a
      form that has `<input type="hidden" name="_method" value="patch">` and
      the just-sent text still in the textarea.

      So: send once, and the text does not clear and the form becomes a PATCH
      to `/conversations/:id/messages`. `config/routes.rb:102` is
      `resources :messages, only: [ :create ]` — there is no PATCH route.
      The second send cannot succeed.

      The partial's own comment says the intent is "on validation failure we
      re-render the same form with the invalid message", which is right; the
      template just does it unconditionally. Fix:
      `message: (@message.persisted? ? Message.new : @message)`.

- [ ] Add a test asserting the success-path widget stream contains no
      `_method` field and an empty textarea. `brgen/test/controllers/` has no
      widget-composer test, which is why a one-word template argument shipped.

**(b) Nothing on the page is interactive until four third-party CDNs answer.**

- [ ] `brgen/config/importmap.rb` — 7 of 97 importmap pins resolve to
      external hosts, and they fan out to hundreds of transitive module
      requests at page load:

      | Pin | Host |
      |---|---|
      | `@tiptap/core`, `@tiptap/starter-kit` | esm.sh |
      | `swiper/bundle`, `web-vitals`, `@rails/request.js` | cdn.jsdelivr.net |
      | `date-fns` | unpkg.com |
      | `morphdom` | ga.jspm.io |

      Measured on one front-page load: **537 requests**, including the whole
      `prosemirror-*` tree from esm.sh, `swiper@11.1.15/shared/*` and
      `modules/*` from jsDelivr, and `date-fns@4.4.0/_lib/*` from unpkg.
      Twenty seconds after load, four requests were still unresolved
      (`prosemirror-keymap`, `prosemirror-view`, `prosemirror-state`,
      `rope-sequence`).

      ES modules fail as a graph. When any one of those does not arrive,
      `import "application"` never executes — so `window.Turbo` and
      `window.Stimulus` stay `undefined`, all **169** `data-controller`
      elements on the page stay dead, and the chat's
      `#nearby-chat-widget-frame` sits on its "Laster…" placeholder forever
      with `complete=false` and `busy=false`, because a frame with a `src`
      needs Turbo to fetch it. Observed exactly that state on a run where one
      module load was interrupted: the server rendered the widget correctly
      (verified separately over HTTP — 200, real composer, real handle), and
      the browser still showed nothing.

      **Done 2026-08-03, and `--download` was the wrong prescription for most
      of them.** `importmap_baseline.rb` documents why swiper and date-fns are
      pinned to a CDN: both cross-reference siblings by *relative* path, so one
      vendored file breaks every one of those paths. What was actually wrong was
      `preload`. `pin` defaults to `preload: true`, so each CDN pin emitted a
      `<link rel="modulepreload">` and the browser fetched it eagerly no matter
      what any controller did — which is also why
      `tiptap_editor_controller`'s existing dynamic `import()` bought nothing.

      Landed: `preload: false` on every CDN pin; tiptap mounts on first focus
      instead of on connect (it sat on `.composer-body` inside a *closed*
      dialog, and Stimulus connects there all the same); carousel and timeago
      registered on demand via `registerWhenPresent` in `stimulus_boot.js`;
      `dialog`, `scroll-to`, `sound` and `speech-recognition` removed —
      imported, registered, pinned and vendored in four apps with no
      `data-controller` for any of them anywhere.

      Measured after: **537 → 95 requests**, external hosts **4 → 2**,
      `performance.getEntriesByType("resource")` **250 → 91**. esm.sh and
      unpkg.com are gone from page load entirely. The two that remain,
      `ga.jspm.io` (morphdom) and `cdn.jsdelivr.net` (`@rails/request.js`), are
      eager dependencies of cable_ready/StimulusReflex; `@rails/request.js` is
      `dist/requestjs.js` with no imports of its own, so that one *can* be
      vendored with `--download` and is the remaining GDPR/supply-chain item.

- [x] ~~The front page becomes unresponsive to any JS evaluation about 3 seconds
      after load.~~ **Withdrawn — this was my instrument, not the page.**
      CDP `Runtime.evaluate` on this page times out unless Ferrum's request
      interception happens to be enabled, and the reading flips with that
      setting rather than with anything in the app: with interception on, a
      trivial evaluate returns in 10–80ms at every offset from 1s to 20s. The
      original "reproducible at t=3.2s" reading came from a wedged CDP session
      — once one `send_message` times out, every later command on that session
      fails identically, which is what produced the flat 6.01s rows that looked
      like data. An earlier bisect "isolating" tiptap failed the same way.

      Nothing in this file should be read as evidence of a main-thread stall.
      If one is ever suspected again, measure it with `Performance.getMetrics`
      or a `Tracing` capture, which do not need the page's main thread, and
      never with repeated `evaluate` calls on one session.

- [ ] `brgen/app/controllers/nearby_controller.rb:38` — `widget` renders inside
      the full application layout. Measured 64,640 bytes for what Turbo then
      reduces to one ~2KB frame, and the response contains a nested copy of the
      chat widget that rendered it. Add `layout: false`.

### P0.4 Responsiveness and gesture floor

- [ ] `application.html.erb:2` — `<html class="chrome-hidden">` plus the fixed
      wordmark, two sticky nav bars and the fixed theme toggle means five
      independent fixed/sticky chrome layers compete for the top 55px. Measured
      `main` `padding-top: 0px`, so content starts underneath them.

- [ ] `overscroll-behavior-y` computes to `auto` on `<html>` while `main`
      carries `data-controller="pull-to-refresh"`. A custom pull-to-refresh
      competing with the browser's native overscroll is the standard cause of a
      gesture that fires twice or not at all. `.feed-tabs` got this right
      (`_nav.scss:47`, `overscroll-behavior-x: contain`); the page scroll
      container did not.

- [ ] `touch-action` computes to `auto` on `<body>` and on `main`. The
      bottom sheet binds `pointerdown/pointermove/pointerup` **and**
      `touchstart/touchmove/touchend` on the same element
      (`application.html.erb`, `.mobile-sheet` `data-action`) — double-firing
      on every touch device, since pointer events already cover touch.

- [ ] 169 `data-controller` elements on first paint, from
      `popover` (100), `clipboard` (50) and `dropdown` (25) instances. Each is
      a Stimulus instantiation before the user has done anything. Move them
      behind a lazy/`futurism` boundary or render the menu markup on demand.

- [ ] 232,132 bytes of HTML for the front page, 169,972 of it inside `<main>`.

- [ ] `bsdports/db/schema.rb:1` — a hand-added `# frozen_string_literal: true`
      sits at the top of a generated file. Running any migration removes it
      again (observed: `RAILS/bin/triangle up` did exactly that, and it was
      reverted). Either teach the schema dumper to emit it or drop it; as it
      stands it produces a spurious dirty file for whoever migrates next, on a
      shared git index where a stray modification gets swept into someone
      else's commit.

- [ ] `futurism` is registered in `shared/frontend/stimulus_boot.js` and has
      zero `data-controller="futurism"` references in any ERB — the lazy-render
      mechanism that would fix the item above is already installed and unused.

---

## Scanner findings

1,851 raw findings across 45 rules. Grouped by theme, most-frequent rule
first inside each section, every item with its `file:line`. Confidence is the
scanner's, not a severity: `high` means the pattern is the finding, `low`
means confirm intent before changing anything.

## i18n and copy — 166 items

### hardcoded_copy — 131 · confidence high

Hardcoded English copy in a view. design_rules.ui_polish.chrome_i18n makes untranslated shell copy debt; default_locale is nb, so an English string ships to a Norwegian visitor. Law: `design_rules.ui_polish.chrome_i18n`.

- [ ] `amber/app/views/ai/_analysis.html.erb:3` — Analysis unavailable
- [ ] `amber/app/views/ai/capsule.html.erb:5` — Capsule builder
- [ ] `amber/app/views/ai/capsule.html.erb:38` — Gap items to consider
- [ ] `amber/app/views/ai/color_palette.html.erb:7` — Swatches from your items
- [ ] `amber/app/views/ai/color_palette.html.erb:25` — Clashing items
- [ ] `amber/app/views/ai/packing_list.html.erb:19` — Suggested outfits for
- [ ] `amber/app/views/creator_profiles/edit.html.erb:3` — Edit creator profile
- [ ] `amber/app/views/creator_profiles/edit.html.erb:7` — Showcase items
- [ ] `amber/app/views/creator_profiles/new.html.erb:3` — Create creator profile
- [ ] `amber/app/views/declutter/index.html.erb:26` — Overdue wear challenges
- [ ] `amber/app/views/declutter/index.html.erb:41` — Active wear challenges
- [ ] `amber/app/views/declutter/index.html.erb:65` — Declutter box
- [ ] `amber/app/views/declutter/index.html.erb:77` — Highest release scores
- [ ] `amber/app/views/declutter/index.html.erb:89` — Duplicate groups
- [ ] `amber/app/views/declutter/review.html.erb:3` — Declutter review
- [ ] `amber/app/views/declutter/review.html.erb:25` — Recommended action
- [ ] `amber/app/views/declutter/review.html.erb:55` — Move item
- [ ] `amber/app/views/demo_wardrobe/index.html.erb:5` — Demo wardrobe
- [ ] `amber/app/views/demo_wardrobe/index.html.erb:30` — All pieces
- [ ] `amber/app/views/demo_wardrobe/show.html.erb:12` — Spark joy
- [ ] `amber/app/views/items/_form.html.erb:34` — Choose or drop photos
- [ ] `amber/app/views/items/_live_search_results.html.erb:8` — Filter by category
- [ ] `amber/app/views/items/show.html.erb:21` — Sparks joy
- [ ] `amber/app/views/items/show.html.erb:55` — Wardrobe intelligence
- [ ] `amber/app/views/items/show.html.erb:97` — Shop the look
- [ ] `amber/app/views/items/show.html.erb:116` — Permanent removal
- [ ] `amber/app/views/outfits/_form.html.erb:28` — Add item
- [ ] `amber/app/views/outfits/index.html.erb:6` — Style combinations
- [ ] `amber/app/views/outfits/show.html.erb:37` — Style intelligence
- [ ] `amber/app/views/shared/_widgets.html.erb:14` — Your wardrobe
- [ ] `amber/app/views/shared/_widgets.html.erb:26` — Demo capsule
- [ ] `amber/app/views/shared/_widgets.html.erb:33` — Style notes
- [ ] `amber/app/views/users/show.html.erb:18` — Recent items
- [ ] `amber/app/views/wardrobe_items/timeline.html.erb:5` — Aesthetic phases over time
- [ ] `amber/app/views/wardrobe_items/timeline.html.erb:23` — Life phases
- [ ] `amber/app/views/wardrobe_items/timeline.html.erb:55` — Wear history
- [ ] `brgen/app/views/activity_events/index.html.erb:5` — Local graph
- [ ] `brgen/app/views/admin/reports/index.html.erb:17` — Select all
- [ ] `brgen/app/views/communities/new.html.erb:1` — New community
- [ ] `brgen/app/views/email_subscription_mailer/confirm.html.erb:5` — Confirm your subscription
- [ ] `brgen/app/views/email_subscription_mailer/confirm.html.erb:6` — Permission marketing
- [ ] `brgen/app/views/email_subscription_mailer/confirm.html.erb:18` — Confirm subscription
- [ ] `brgen/app/views/pages/cookies.html.erb:19` — Annonsene vi viser er
- [ ] `brgen/app/views/pages/cookies.html.erb:21` — Slik styrer du dem
- [ ] `brgen/app/views/pages/cookies.html.erb:25` — Cookies on
- [ ] `brgen/app/views/pages/cookies.html.erb:30` — Strictly necessary
- [ ] `brgen/app/views/pages/cookies.html.erb:37` — The ads we show are
- [ ] `brgen/app/views/pages/cookies.html.erb:39` — How to control them
- [ ] `brgen/app/views/pages/privacy.html.erb:7` — Personvern hos
- [ ] `brgen/app/views/pages/privacy.html.erb:14` — Hva vi samler inn
- [ ] `brgen/app/views/pages/privacy.html.erb:17` — Innhold du lager
- [ ] `brgen/app/views/pages/privacy.html.erb:22` — Reklame og partnerlenker
- [ ] `brgen/app/views/pages/privacy.html.erb:23` — Vi selger og viser
- [ ] `brgen/app/views/pages/privacy.html.erb:24` — Enkelte lenker er
- [ ] `brgen/app/views/pages/privacy.html.erb:29` — Dine rettigheter
- [ ] `brgen/app/views/pages/privacy.html.erb:32` — Lagring og deling
- [ ] `brgen/app/views/pages/privacy.html.erb:35` — Privacy policy
- [ ] `brgen/app/views/pages/privacy.html.erb:36` — Privacy at
- [ ] `brgen/app/views/pages/privacy.html.erb:43` — What we collect
- [ ] `brgen/app/views/pages/privacy.html.erb:46` — Content you create
- [ ] `brgen/app/views/pages/privacy.html.erb:51` — Advertising and partner links
- [ ] `brgen/app/views/pages/privacy.html.erb:52` — We sell and serve
- [ ] `brgen/app/views/pages/privacy.html.erb:53` — Some links are
- [ ] `brgen/app/views/pages/privacy.html.erb:55` — Legal basis
- [ ] `brgen/app/views/pages/privacy.html.erb:58` — Your rights
- [ ] `brgen/app/views/pages/privacy.html.erb:61` — Storage and sharing
- [ ] `brgen/app/views/pages/terms.html.erb:12` — Hvem kan bruke tjenesten
- [ ] `brgen/app/views/pages/terms.html.erb:15` — Innholdet ditt
- [ ] `brgen/app/views/pages/terms.html.erb:18` — Akseptabel bruk
- [ ] `brgen/app/views/pages/terms.html.erb:21` — Reklame og partnerlenker
- [ ] `brgen/app/views/pages/terms.html.erb:22` — Nettstedet finansieres av
- [ ] `brgen/app/views/pages/terms.html.erb:27` — Avslutning og lovvalg
- [ ] `brgen/app/views/pages/terms.html.erb:30` — Terms of use
- [ ] `brgen/app/views/pages/terms.html.erb:31` — Terms for
- [ ] `brgen/app/views/pages/terms.html.erb:36` — Who can use it
- [ ] `brgen/app/views/pages/terms.html.erb:39` — Your content
- [ ] `brgen/app/views/pages/terms.html.erb:42` — Acceptable use
- [ ] `brgen/app/views/pages/terms.html.erb:45` — Advertising and partner links
- [ ] `brgen/app/views/pages/terms.html.erb:46` — The site is funded by
- [ ] `brgen/app/views/pages/terms.html.erb:51` — Termination and governing law
- [ ] `brgen/app/views/shared/_nav_swiper.html.erb:24` — Show sections
- [ ] `brgen/app/views/shared/_sidebar_discovery.html.erb:14` — Your feed
- [ ] `brgen/engines/dating/app/views/dating/home/_card.html.erb:35` — Looking for
- [ ] `brgen/engines/dating/app/views/dating/home/index.html.erb:26` — Beskyttet med
- [ ] `brgen/engines/dating/app/views/dating/profiles/edit.html.erb:17` — Current photos
- [ ] `brgen/engines/dating/app/views/dating/profiles/edit.html.erb:47` — More details
- [ ] `brgen/engines/dating/app/views/dating/profiles/show.html.erb:46` — Looking for
- [ ] `brgen/engines/marketplace/app/views/marketplace/_top_offers.html.erb:7` — Top offers
- [ ] `brgen/engines/marketplace/app/views/marketplace/_top_offers.html.erb:8` — Picked for the city
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/show.html.erb:81` — Make an offer
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/show.html.erb:98` — Seller dashboard
- [ ] `brgen/engines/marketplace/app/views/marketplace/orders/show.html.erb:28` — Chat with
- [ ] `brgen/engines/marketplace/app/views/marketplace/saved_searches/index.html.erb:5` — Marketplace alerts
- [ ] `brgen/engines/playlist/app/views/playlist/hosted_tracks/show.html.erb:30` — Timestamped comments
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/show.html.erb:17` — Add a track
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/show.html.erb:31` — Import links
- [ ] `brgen/engines/playlist/app/views/playlist/sets/edit.html.erb:5` — Playlist set
- [ ] `brgen/engines/playlist/app/views/playlist/sets/index.html.erb:5` — Local audio collections
- [ ] `brgen/engines/playlist/app/views/playlist/sets/new.html.erb:5` — Playlist set
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:5` — Playlist set
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:87` — Add a track
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:101` — Listening party
- [ ] `brgen/engines/playlist/app/views/playlist/shared/_dilla_sketches.html.erb:62` — Render now
- [ ] `brgen/engines/playlist/app/views/playlist/shared/_dilla_sketches.html.erb:63` — Publish as playlist track
- [ ] `brgen/engines/takeaway/app/views/takeaway/delivery_drivers/index.html.erb:5` — Takeaway operations
- [ ] `brgen/engines/takeaway/app/views/takeaway/delivery_drivers/show.html.erb:5` — Takeaway operations
- [ ] `brgen/engines/takeaway/app/views/takeaway/orders/new.html.erb:6` — Order from
- [ ] `brgen/engines/takeaway/app/views/takeaway/orders/show.html.erb:12` — Status timeline
- [ ] `brgen/engines/takeaway/app/views/takeaway/orders/show.html.erb:26` — Order cancelled
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:24` — Add menu item
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:56` — Sold out
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:89` — Sold out
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:101` — Reviews from neighbours
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:119` — Leave a review
- [ ] `brgen/engines/tv/app/views/tv/channels/edit.html.erb:3` — Edit channel
- [ ] `brgen/engines/tv/app/views/tv/channels/new.html.erb:3` — New channel
- [ ] `brgen/engines/tv/app/views/tv/home/index.html.erb:16` — Live now
- [ ] `brgen/engines/tv/app/views/tv/shows/index.html.erb:4` — Shows on
- [ ] `brgen/engines/tv/app/views/tv/videos/new.html.erb:3` — Upload video
- [ ] `brgen/engines/tv/app/views/tv/videos/new.html.erb:11` — Uploading to
- [ ] `bsdports/app/views/ports/show.html.erb:11` — Command targets
- [ ] `bsdports/app/views/ports/show.html.erb:17` — Exact identity
- [ ] `bsdports/app/views/ports/show.html.erb:20` — Local install
- [ ] `bsdports/app/views/ports/show.html.erb:51` — Exploration assistant
- [ ] `bsdports/app/views/ports/show.html.erb:70` — Version history
- [ ] `shared/app/views/layouts/mailer.html.erb:18` — Skip to main content
- [ ] `shared/app/views/shared/newsletter/_deal.html.erb:14` — View offer
- [ ] `shared/app/views/shared/newsletter/_edition.html.erb:16` — Today in
- [ ] `shared/app/views/shared/newsletter/_edition.html.erb:24` — Curated offers
- [ ] `shared/frontend/layouts/_flash.html.erb:22` — Dismiss this message
- [ ] `shared/frontend/layouts/_nav.html.erb:2` — Skip to main content

### i18n_key_undefined — 26 · confidence high

t() key with no definition and no :default. Renders as `translation missing:` in production. FAIL_VISIBLY inverted — it fails quietly and looks like copy. Law: `soul.absolute.code_rules.FAIL_VISIBLY`.

- [ ] `amber/app/views/messages/index.html.erb` — messages.unread_count
- [ ] `amber/public/assets/layouts/_footer.html-ba3c30c2.erb` — footer.copyright
- [ ] `amber/public/assets/layouts/_nav.html-0bc00dde.erb` — navigation.sign_out
- [ ] `amber/public/assets/layouts/_nav.html-0bc00dde.erb` — navigation.sign_in
- [ ] `brgen/app/views/partner/programs/index.html.erb` — partner.hold
- [ ] `brgen/app/views/partner/programs/show.html.erb` — partner.days
- [ ] `brgen/app/views/partner/programs/show.html.erb` — partner.hours
- [ ] `brgen/engines/dating/test/models/dating/match_test.rb` — errors.messages.taken
- [ ] `brgen/engines/dating/test/models/dating/match_test.rb` — errors.messages.inclusion
- [ ] `brgen/engines/marketplace/app/views/marketplace/carts/show.html.erb` — marketplace.item
- [ ] `bsdports/public/assets/layouts/_footer.html-ba3c30c2.erb` — footer.copyright
- [ ] `bsdports/public/assets/layouts/_nav.html-0bc00dde.erb` — navigation.sign_out
- [ ] `bsdports/public/assets/layouts/_nav.html-0bc00dde.erb` — navigation.sign_in
- [ ] `shared/app/views/passwords/edit.html.erb` — auth.update_password
- [ ] `shared/app/views/passwords/edit.html.erb` — auth.update_password_lead
- [ ] `shared/app/views/passwords/edit.html.erb` — auth.new_password
- [ ] `shared/app/views/passwords/edit.html.erb` — auth.confirm_password
- [ ] `shared/app/views/passwords/edit.html.erb` — auth.save_password
- [ ] `shared/app/views/passwords/edit.html.erb` — auth.back_to_sign_in
- [ ] `shared/app/views/passwords/new.html.erb` — auth.forgot_title
- [ ] `shared/app/views/passwords/new.html.erb` — auth.forgot_lead
- [ ] `shared/app/views/passwords/new.html.erb` — auth.email
- [ ] `shared/app/views/passwords/new.html.erb` — auth.email_reset
- [ ] `shared/frontend/layouts/_footer.html.erb` — footer.copyright
- [ ] `shared/frontend/layouts/_nav.html.erb` — navigation.sign_out
- [ ] `shared/frontend/layouts/_nav.html.erb` — navigation.sign_in

### placeholder_hardcoded — 5 · confidence high

Hardcoded placeholder text. Same rule — `placeholder:` is chrome copy. Law: `design_rules.ui_polish.chrome_i18n`.

- [ ] `brgen/engines/playlist/app/views/playlist/playlists/_player.html.erb:108`
- [ ] `brgen/engines/playlist/app/views/playlist/shared/_dilla_sketches.html.erb:70` — Paste JSON state from lab
- [ ] `bsdports/app/views/comments/create.turbo_stream.erb:5` — Add a comment…
- [ ] `bsdports/app/views/ports/show.html.erb:125` — Add a comment…
- [ ] `shared/frontend/examples.html.erb:27`

### submit_hardcoded — 3 · confidence high

Hardcoded submit button label. Submit labels are the highest-traffic chrome string on a form. Law: `design_rules.ui_polish.chrome_i18n`.

- [ ] `bsdports/app/views/comments/create.turbo_stream.erb:8` — <p><%= f.submit "Comment" %></p>
- [ ] `bsdports/app/views/ports/show.html.erb:128` — <p><%= f.submit "Comment" %></p>
- [ ] `shared/app/views/two_factor_setups/show.html.erb:15` — <%= f.submit "Enable 2FA", class: "btn btn-primary" %>

### i18n_missing_nb — 1 · confidence high

Key present in en but missing in nb. nb is the default locale; the fallback shows English. Law: `design_rules.ui_polish.default_locale`.

- [ ] `shared/config/locales` — hello

## Design tokens and magic values — 165 items

### magic_hex — 75 · confidence high

Literal hex colour in a view. design_rules.pixel_perfection.magic_color_hex_ban_inline. Colour belongs in a token, not in markup. Law: `pixel_perfection.magic_color_hex_ban_inline`.

- [ ] `amber/app/views/layouts/application.html.erb:7` — #ffffff
- [ ] `amber/app/views/outfits/dressing_room.html.erb:16` — #2a2a2a
- [ ] `amber/app/views/outfits/dressing_room.html.erb:17` — #2a2a2a
- [ ] `amber/app/views/outfits/dressing_room.html.erb:18` — #2a2a2a
- [ ] `amber/app/views/outfits/dressing_room.html.erb:19` — #2a2a2a
- [ ] `amber/app/views/outfits/dressing_room.html.erb:20` — #2a2a2a
- [ ] `amber/app/views/outfits/dressing_room.html.erb:21` — #2a2a2a
- [ ] `amber/app/views/outfits/dressing_room.html.erb:22` — #1a1a1a
- [ ] `amber/app/views/outfits/dressing_room.html.erb:23` — #1a1a1a
- [ ] `amber/app/views/pwa/manifest.json.erb:46` — #FFB999
- [ ] `amber/app/views/pwa/manifest.json.erb:47` — #FFFFFF
- [ ] `amber/app/views/shared/_jox_logo.html.erb:7` — #0000FE
- [ ] `amber/app/views/shared/_jox_logo.html.erb:15` — #01FF01
- [ ] `amber/app/views/shared/_jox_logo.html.erb:23` — #DB0000
- [ ] `amber/app/views/shared/_logo.html.erb:23` — #FFFFFF
- [ ] `amber/app/views/shared/_logo.html.erb:24` — #FFFFFF
- [ ] `amber/app/views/shared/_logo.html.erb:25` — #FFFFFF
- [ ] `amber/app/views/shared/_logo.html.erb:26` — #FFFFFF
- [ ] `amber/app/views/shared/_logo.html.erb:27` — #FFFFFF
- [ ] `amber/app/views/shared/_logo.html.erb:28` — #FFFFFF
- [ ] `amber/app/views/shared/_logo.html.erb:29` — #FFFFFF
- [ ] `amber/app/views/shared/_logo.html.erb:30` — #FFFFFF
- [ ] `amber/app/views/shared/_logo.html.erb:31` — #FFFFFF
- [ ] `brgen/app/views/layouts/application.html.erb:13` — #000000
- [ ] `brgen/app/views/pwa/manifest.json.erb:132` — #000000
- [ ] `brgen/app/views/pwa/manifest.json.erb:133` — #000000
- [ ] `brgen/app/views/shared/_site_legal_footer.html.erb:6` — #e4e2db
- [ ] `brgen/app/views/shared/_site_legal_footer.html.erb:9` — #6b7178
- [ ] `brgen/app/views/shared/_site_legal_footer.html.erb:10` — #16181c
- [ ] `brgen/app/views/shared/_site_legal_footer.html.erb:12` — #6b7178
- [ ] `brgen/app/views/shared/_site_legal_footer.html.erb:16` — #6b7178
- [ ] `brgen/app/views/shared/_site_legal_footer.html.erb:17` — #6b7178
- [ ] `brgen/app/views/shared/_site_legal_footer.html.erb:23` — #e4e2db
- [ ] `brgen/engines/dating/app/views/dating/home/_heart.html.erb:23` — #00f0c8
- [ ] `brgen/engines/dating/app/views/dating/home/_heart.html.erb:24` — #b8fff5
- [ ] `brgen/engines/dating/app/views/dating/home/_heart.html.erb:25` — #ffffff
- [ ] `brgen/engines/dating/app/views/dating/home/_heart.html.erb:26` — #ffb347
- [ ] `brgen/engines/dating/app/views/dating/home/_heart.html.erb:27` — #ff5500
- [ ] `brgen/engines/dating/app/views/dating/home/_heart.html.erb:28` — #ff2d2d
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/_player.html.erb:25` — #00d4ff
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/embed.html.erb:2` — #00d4ff
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/show.html.erb:5` — #00d4ff
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:17` — #00d4ff
- [ ] `bsdports/app/views/layouts/application.html.erb:7` — #000000
- [ ] `bsdports/app/views/pwa/manifest.json.erb:38` — #0ea5e9
- [ ] `bsdports/app/views/pwa/manifest.json.erb:39` — #0ea5e9
- [ ] `bsdports/app/views/shared/_jox_logo.html.erb:6` — #63c363
- [ ] `bsdports/app/views/shared/_jox_logo.html.erb:14` — #4fa34f
- [ ] `bsdports/app/views/shared/_jox_logo.html.erb:22` — #00ba7c
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:2` — #050505
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:3` — #050505
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:4` — #0a0a0a
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:5` — #8a8a8a
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:7` — #6f6f6f
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:9` — #f7f7f7
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:10` — #1f1f1f
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:11` — #7a7a7a
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:13` — #171717
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:15` — #ffffff
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:16` — #7a7a7a
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:17` — #c8c8c8
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:19` — #171717
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:23` — #ffffff
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:24` — #b5b5b5
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:25` — #f0f0f0
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:27` — #ffffff
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:28` — #9a9a9a
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:29` — #6d6d6d
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:30` — #171717
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:31` — #8d8d8d
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:32` — #4f4f4f
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:33` — #121212
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:34` — #fafafa
- [ ] `shared/app/views/layouts/_mailer_styles.html.erb:35` — #7a7a7a
- [ ] `shared/app/views/layouts/master_embed.html.erb:7` — #000000

### css_magic_hex — 56 · confidence medium

Literal hex colour in SCSS outside a custom-property definition. Same rule at the stylesheet layer. Law: `pixel_perfection.magic_color_hex_ban_inline`.

- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:41` — stroke: #fff;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:26` — background-color: #131921;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:27` — color: #fff;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:51` — border-color: #fff;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:97` — color: #ccc;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:115` — color: #ccc;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:155` — background-color: #e6e6e6;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:156` — color: #111;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:162` — background-color: #cdcdcd;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:173` — background: #fff;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:174` — color: #111;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:186` — background-color: #febd69;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:187` — color: #111;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:192` — background-color: #f3a847;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:224` — color: #cd9042;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:230` — border-color: #febd69;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:242` — background-color: #232f3e;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:274` — color: #fff;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:286` — color: #ccc;
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:61` — .monogram--0 { background: #4b2e83; color: #fff; }
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:62` — .monogram--1 { background: #7a3e12; color: #fff; }
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:63` — .monogram--2 { background: #075e54; color: #fff; }
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:64` — .monogram--3 { background: #7b1e3a; color: #fff; }
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:65` — .monogram--4 { background: #184e77; color: #fff; }
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:66` — .monogram--5 { background: #5f4b32; color: #fff; }
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:74` — .video-player { width: 100%; max-height: 420px; background: #000; display: block; }
- [ ] `bsdports/app/assets/stylesheets/_jsfiddle_chrome.scss:48` — background-color: #0f1a0f;
- [ ] `bsdports/app/assets/stylesheets/_jsfiddle_chrome.scss:63` — background-color: #0a140a;
- [ ] `bsdports/app/assets/stylesheets/application.scss:375` — .data-state--stale { border-color: #b7791f; color: #f6c453; }
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:5` — $bg: #17161c,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:6` — $surface: #17161c,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:7` — $surface-elevated: #211f28,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:8` — $search-bg: #232030,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:9` — $text: #d8d6e0,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:10` — $text-secondary: #8a879c,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:11` — $border: #46435a,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:12` — $accent: #7c6fd6,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:13` — $accent-hover: #9686e8,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:14` — $danger: #e46151,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:58` — $bg: #f7f6fa,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:59` — $surface: #ffffff,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:60` — $surface-elevated: #eeedf3,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:61` — $search-bg: #e8e6ef,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:62` — $text: #1a1824,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:63` — $text-secondary: #5c586e,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:64` — $border: #d4d1de,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:65` — $accent: #5b4fc4,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:66` — $accent-hover: #4a3fb0,
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:67` — $danger: #a9483c
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:148` — // app/assets/stylesheets/all.css): `body { color: #222 }` on the browser's
- [ ] `shared/app/assets/stylesheets/_master_embed.scss:49` — background: #000;
- [ ] `shared/app/assets/stylesheets/_master_embed.scss:64` — background: #000;
- [ ] `shared/app/assets/stylesheets/_search_yep.scss:6` — background-color: #ccc;
- [ ] `shared/app/assets/stylesheets/_search_yep.scss:27` — color: #aaa;
- [ ] `shared/frontend/layouts/visualizer.css:15` — background: #000;
- [ ] `shared/frontend/layouts/visualizer.css:16` — color: #dcdcdc;

### css_font_px_hardcoded — 25 · confidence high

Hardcoded px font-size. design_rules.ui_polish.type_tokens — use var(--text-title) / var(--text-display); a px literal cannot participate in the modular scale. Law: `ui_polish.type_tokens`.

- [ ] `amber/app/assets/stylesheets/_brand.scss:26` — font-size: 60px;
- [ ] `amber/app/assets/stylesheets/_brand.scss:30` — font-size: 12px;
- [ ] `amber/app/assets/stylesheets/_brand.scss:35` — font-size: 120px;
- [ ] `amber/app/assets/stylesheets/_brand.scss:39` — font-size: 24px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:86` — font-size: 70px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:91` — font-size: 28px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:103` — font-size: 4px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:112` — font-size: 3px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:28` — font-size: 14px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:96` — font-size: 12px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:114` — font-size: 12px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:119` — font-size: 14px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:157` — font-size: 12px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:175` — font-size: 15px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:225` — font-size: 16px;
- [ ] `brgen/app/assets/stylesheets/_root.scss:14` — --font-size: 18px;
- [ ] `brgen/app/assets/stylesheets/_root.scss:38` — --font-size: 18px;
- [ ] `brgen/app/assets/stylesheets/_tiptap.scss:89` — font-size: 16px;
- [ ] `bsdports/app/assets/stylesheets/_jsfiddle_chrome.scss:41` — font-size: 14px;
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:38` — --font-size: 16px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:58` — font-size: 21px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:396` — font-size: 64px;
- [ ] `shared/app/assets/stylesheets/_search_yep.scss:9` — font-size: 18px;
- [ ] `shared/app/assets/stylesheets/_shell.scss:176` — font-size: 22px;
- [ ] `shared/app/assets/stylesheets/_shell.scss:294` — font-size: 17px;

### inline_style — 9 · confidence high

Inline style attribute. Bypasses the token system entirely; nothing can audit or theme it. Law: `design_rules.ultraminimalism.design_tokens.exact_token_use`.

- [ ] `amber/app/views/ai/color_palette.html.erb:11` — <span class="color-swatch color-swatch--sm" style="--swatch: <%= wardrobe_color_swatch(col
- [ ] `amber/app/views/items/show.html.erb:23` — <span class="color-swatch" style="--swatch: <%= wardrobe_color_swatch(@item.color) %>" tit
- [ ] `brgen/app/views/channels/_roster.html.erb:9` — <li class="roster-nick" data-role="<%= member.role %>" style="<%= nick_style(handle) %>">
- [ ] `brgen/app/views/messages/_message.html.erb:9` — <span class="msg-nick" style="<%= nick_style(who) %>"><%= who %></span>
- [ ] `brgen/app/views/users/new.html.erb:29` — <div class="hp-field" aria-hidden="true" style="position:absolute;left:-9999px;top:-9999px
- [ ] `brgen/engines/takeaway/app/views/takeaway/orders/show.html.erb:20` — <div class="order-progress-fill" style="width: <%= (fraction * 100).round %>%"></div>
- [ ] `shared/app/views/layouts/mailer.html.erb:11` — <div style="display:none;max-height:0;overflow:hidden;mso-hide:all;">
- [ ] `shared/app/views/shared/_ad_slot.html.erb:32` — style="display:block"
- [ ] `shared/app/views/shared/_icon_sprite.html.erb:36` — <svg class="icon-sprite" aria-hidden="true" focusable="false" width="0" height="0" style="

## Flat UI, cascade and stacking — 160 items

### css_important — 128 · confidence medium

!important. Specificity escape hatch; each one makes the next override harder and hides the real cascade bug. The brgen logo bug below is exactly this shape. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `amber/app/assets/stylesheets/_base.scss:47` — animation: none !important;
- [ ] `amber/app/assets/stylesheets/_base.scss:48` — transition: none !important;
- [ ] `amber/app/assets/stylesheets/_brand.scss:436` — * { animation: none !important; transition: none !important; }
- [ ] `amber/app/assets/stylesheets/_dressing_room.scss:151` — animation: none !important;
- [ ] `amber/app/assets/stylesheets/_dressing_room.scss:152` — transition: none !important;
- [ ] `amber/app/assets/stylesheets/_editorial.scss:50` — animation: none !important;
- [ ] `amber/app/assets/stylesheets/_editorial.scss:51` — transition: none !important;
- [ ] `amber/app/assets/stylesheets/_items_luxury.scss:146` — animation: none !important;
- [ ] `amber/app/assets/stylesheets/_items_luxury.scss:147` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_canvas.scss:101` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_canvas.scss:102` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_chrome_surfaces.scss:186` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_communities.scss:27` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_communities.scss:28` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_dating_actions.scss:91` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_dating_actions.scss:92` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_dating_stack.scss:130` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_dating_stack.scss:131` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:179` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:180` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_forms.scss:97` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_forms.scss:98` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_maps.scss:134` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_maps.scss:135` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_marketplace.scss:172` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_marketplace_cards.scss:164` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_marketplace_top_offers.scss:127` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_media.scss:96` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_media.scss:97` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_mobile.scss:132` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_mobile.scss:133` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_nav.scss:213` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_nav.scss:214` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:76` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:77` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:88` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:89` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_posts.scss:186` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_posts.scss:187` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:70` — @media (prefers-reduced-motion: reduce) { *, *::before, *::after { animation: none !important; transition: non
- [ ] `brgen/app/assets/stylesheets/_root.scss:87` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:88` — border-radius: 0 !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:89` — outline: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:91` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:134` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:135` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:136` — border-width: 0 !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:137` — border-style: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:138` — border-color: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:139` — border-radius: 0 !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:140` — outline: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:141` — outline-offset: 0 !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:150` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:151` — outline: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:153` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:169` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:170` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:171` — outline: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:181` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:182` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:186` — outline: var(--focus-ring, 2px solid var(--accent)) !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:192` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:197` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_share.scss:92` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_share.scss:93` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_tiptap.scss:99` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_tiptap.scss:100` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_messenger_list.scss:155` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_messenger_list.scss:156` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:62` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:78` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:83` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:96` — display: inline-flex !important;
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:80` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:81` — transition: none !important;
- [ ] `brgen/engines/dating/app/assets/stylesheets/_vertical_dating_shell.scss:58` — display: none !important;
- [ ] `brgen/engines/dating/app/assets/stylesheets/_vertical_dating_shell.scss:110` — animation: none !important;
- [ ] `brgen/engines/dating/app/assets/stylesheets/_vertical_dating_shell.scss:111` — transition: none !important;
- [ ] `brgen/engines/marketplace/app/assets/stylesheets/_vertical_marketplace.scss:84` — transition: none !important;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:172` — animation: none !important;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss:102` — animation: none !important;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss:103` — transition: none !important;
- [ ] `bsdports/app/assets/stylesheets/application.scss:529` — animation: none !important;
- [ ] `bsdports/app/assets/stylesheets/application.scss:530` — transition: none !important;
- [ ] `shared/app/assets/stylesheets/_animations.scss:62` — animation: none !important;
- [ ] `shared/app/assets/stylesheets/_animations.scss:63` — transition: none !important;
- [ ] `shared/app/assets/stylesheets/_auth_form.scss:22` — display: none !important;
- [ ] `shared/app/assets/stylesheets/_focus_ring.scss:29` — * `outline: none !important`, which a plain :focus-visible rule cannot beat.
- [ ] `shared/app/assets/stylesheets/_focus_ring.scss:60` — outline: var(--focus-ring, 2px solid var(--accent)) !important;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:639` — animation: none !important;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:640` — transition: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:44` — border: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:45` — background: transparent !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:154` — border: 0 !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:155` — border-radius: 0 !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:156` — background: transparent !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:183` — background: transparent !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:188` — background: transparent !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:191` — .edge-grip:hover { opacity: 0.9; background: transparent !important; }
- [ ] `shared/app/assets/stylesheets/_shell.scss:208` — border: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:209` — border-radius: 0 !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:210` — outline: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:212` — background: transparent !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:220` — background: transparent !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:221` — border: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:222` — outline: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:231` — border: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:232` — outline: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:234` — background: transparent !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:312` — display: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:562` — animation: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:563` — transition: none !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:110` — border: none !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:111` — border-radius: 0 !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:112` — background: transparent !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:114` — outline: none !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:123` — background: transparent !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:124` — border: none !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:125` — outline: none !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:338` — border-bottom: 0 !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:339` — padding: 0 !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:537` — animation: none !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:538` — transition: none !important;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:509` — animation-duration: 0.001ms !important;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:510` — animation-iteration-count: 1 !important;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:511` — transition-duration: 0.001ms !important;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:512` — scroll-behavior: auto !important;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:523` — display: none !important;

### css_autofix_scar — 11 · confidence medium

`autofix:` comment left in the sheet. GATE_AUTOFIX stripped a property and left a marker; the declaration around it usually no longer needs to exist. Law: `aesthetic_rules.NO_ASCII_DECORATION`.

- [ ] `brgen/app/assets/stylesheets/_root.scss:90` — /* autofix: removed box-shadow (flat UI) */
- [ ] `brgen/app/assets/stylesheets/_root.scss:142` — /* autofix: removed box-shadow (flat UI) */
- [ ] `brgen/app/assets/stylesheets/_root.scss:152` — /* autofix: removed box-shadow (flat UI) */
- [ ] `brgen/app/assets/stylesheets/_root.scss:172` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_focus_ring.scss:10` — * Several of those suppressors are annotated `autofix: removed box-shadow (flat
- [ ] `shared/app/assets/stylesheets/_shell.scss:157` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell.scss:211` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell.scss:223` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell.scss:233` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:113` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:126` — /* autofix: removed box-shadow (flat UI) */

### css_zindex_magic — 9 · confidence high

Numeric z-index above 10 not from a token. The brgen logo is invisible because two z-index sources disagreed. Every stacking value belongs to the token ladder. Law: `ultraminimalism.design_tokens`.

- [ ] `brgen/app/assets/stylesheets/_maps.scss:85` — z-index: 120;
- [ ] `brgen/app/assets/stylesheets/_share.scss:12` — z-index: 20;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:5` — z-index: 50;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:42` — z-index: 11;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:110` — z-index: 200;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:150` — z-index: 12;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:193` — z-index: 120;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:83` — z-index: 100;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:104` — z-index: 110;

### css_display_none_override — 9 · confidence medium

display: none !important. Hiding an element the layout still renders. Delete the render instead of hiding the output. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `brgen/app/assets/stylesheets/_root.scss:192` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:197` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:62` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:78` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:83` — display: none !important;
- [ ] `brgen/engines/dating/app/assets/stylesheets/_vertical_dating_shell.scss:58` — display: none !important;
- [ ] `shared/app/assets/stylesheets/_auth_form.scss:22` — display: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:312` — display: none !important;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:523` — display: none !important;

### css_blur — 3 · confidence high

filter: blur / drop-shadow / backdrop-filter. Same flat rule. If deliberate it needs a documented exception at point of use. Law: `pixel_perfection.exception_policy`.

- [ ] `brgen/app/assets/stylesheets/_popover_tooltip.scss:4` — a drop-shadow behind the visible one since filter: drop-shadow() wasn't
- [ ] `brgen/app/assets/stylesheets/_popover_tooltip.scss:12` — filter: drop-shadow(), same shadowed-arrow look as the original.
- [ ] `brgen/app/assets/stylesheets/_popover_tooltip.scss:49` — filter: drop-shadow(0 2px 3px rgba(0, 0, 0, 0.35));

## 8px rhythm and geometry — 85 items

### css_off_grid — 83 · confidence medium

Spacing value off the 8px rhythm. pixel_perfection.eight_px_rhythm allows 0/4/8/12/16/20/24/32/40/48/64/96 only. Law: `pixel_perfection.eight_px_rhythm`.

- [ ] `amber/app/assets/stylesheets/_autofix_geometry.scss:13` — 44px in div.sidebar-swiper > button.edge-grip.edge-grip-left { min-h
- [ ] `amber/app/assets/stylesheets/_autofix_geometry.scss:15` — 44px in div.widgets-swiper > button.edge-grip.edge-grip-right { min-
- [ ] `amber/app/assets/stylesheets/_jsfiddle_chrome.scss:35` — 14px in inset-inline-start: 14px;
- [ ] `amber/app/assets/stylesheets/_jsfiddle_chrome.scss:40` — 26px in inset-inline-start: 26px;
- [ ] `amber/app/assets/stylesheets/_jsfiddle_chrome.scss:47` — 18px in top: 18px;
- [ ] `amber/app/assets/stylesheets/_jsfiddle_chrome.scss:48` — 84px in inset-inline-start: 84px;
- [ ] `brgen/app/assets/stylesheets/_canvas.scss:7` — 10px in top: calc(10px + var(--safe-top));
- [ ] `brgen/app/assets/stylesheets/_canvas.scss:21` — 120px in @media (max-width: 1265px) { .city-carousel { inset-inline-s
- [ ] `brgen/app/assets/stylesheets/_card_modifiers.scss:7` — 6px in margin-bottom: 6px;
- [ ] `brgen/app/assets/stylesheets/_card_modifiers.scss:43` — 10px in padding: 10px 12px;
- [ ] `brgen/app/assets/stylesheets/_card_modifiers.scss:53` — 6px in margin-bottom: 6px;
- [ ] `brgen/app/assets/stylesheets/_channels.scss:59` — 88px in padding: max(12px, env(safe-area-inset-top)) 12px max(88px, 
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:57` — 6px in margin: 0 0 6px;
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:70` — 14px in padding: 14px 12px;
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:87` — 14px in padding: 14px 12px;
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:88` — 10px in gap: 10px;
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:98` — 6px in margin-top: 6px;
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:106` — 10px in padding: 8px 10px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:13` — 10px in padding: 10px 0 28px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:13` — 28px in padding: 10px 0 28px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:83` — -34px in top: -34px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:93` — -14px in top: -14px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:37` — 10px in padding-inline: 10px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:63` — 6px in gap: 6px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:64` — 6px in padding: 6px 8px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:107` — 9px in padding: 4px 9px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:132` — 6px in margin-inline: 6px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:170` — 10px in padding: 0 10px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:240` — 10px in padding-inline: 10px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:249` — 6px in gap: 6px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:313` — 6px in padding-block: 6px;
- [ ] `brgen/app/assets/stylesheets/_media.scss:59` — 72px in bottom: calc(72px + var(--safe-bottom) + var(--space-2));
- [ ] `brgen/app/assets/stylesheets/_mobile.scss:76` — 18px in padding: var(--space-2) var(--space-4) calc(18px + var(--saf
- [ ] `brgen/app/assets/stylesheets/_popover_tooltip.scss:28` — 10px in inset-block-end: calc(100% + 10px);
- [ ] `brgen/app/assets/stylesheets/_popover_tooltip.scss:35` — 6px in padding: 4px 6px;
- [ ] `brgen/app/assets/stylesheets/_tiptap.scss:9` — 10px in padding: 10px 0;
- [ ] `brgen/app/assets/stylesheets/_tiptap.scss:24` — 10px in inset-block-start: 10px;
- [ ] `brgen/app/assets/stylesheets/_vertical_messenger_list.scss:29` — 88px in padding: max(12px, env(safe-area-inset-top)) 12px max(88px, 
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:13` — 14px in padding: 14px 16px; /* mobile tighter */
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:72` — 6px in .live-badge { display: inline-block; background: var(--hover
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:115` — 10px in gap: 10px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:117` — 14px in padding: 12px 14px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:158` — 10px in padding: 10px 8px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:188` — 14px in padding: 8px 14px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:252` — 6px in padding: 6px 10px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:252` — 10px in padding: 6px 10px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:333` — 10px in gap: 10px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:44` — 10px in gap: 10px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:51` — 6px in padding: 6px 12px;
- [ ] `brgen/engines/takeaway/app/assets/stylesheets/_vertical_takeaway.scss:147` — 72px in bottom: calc(72px + var(--safe-bottom));
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv_cards.scss:104` — 6px in inset-block-end: 6px;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv_cards.scss:105` — 6px in inset-inline-end: 6px;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv_cards.scss:106` — 5px in padding: 1px 5px;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv_cards.scss:114` — 6px in .tv-card-meta { padding-block-start: 6px; }
- [ ] `bsdports/app/assets/stylesheets/_jsfiddle_chrome.scss:24` — 14px in left: 14px;
- [ ] `bsdports/app/assets/stylesheets/_jsfiddle_chrome.scss:29` — 26px in left: 26px;
- [ ] `bsdports/app/assets/stylesheets/_jsfiddle_chrome.scss:36` — 18px in top: 18px;
- [ ] `bsdports/app/assets/stylesheets/_jsfiddle_chrome.scss:37` — 84px in left: 84px;
- [ ] `bsdports/app/assets/stylesheets/application.scss:54` — 58px in padding-block-start: 58px;
- [ ] `bsdports/app/assets/stylesheets/application.scss:420` — 104px in padding-block-start: 104px;
- [ ] `bsdports/app/assets/stylesheets/application.scss:510` — 52px in top: 52px;
- [ ] `shared/app/assets/stylesheets/_chat_reactions.scss:21` — 3px in gap: 3px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:177` — 72px in padding-bottom: 72px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:473` — 10px in padding: 10px 12px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:474` — 10px in gap: 10px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:527` — 6px in margin: 0 0 6px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:540` — 6px in margin-bottom: 6px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:561` — 6px in margin-top: 6px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:568` — 10px in padding: 8px 10px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:595` — 10px in padding: 10px 12px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:604` — 6px in margin-bottom: 6px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:614` — 6px in padding: 6px 8px;
- [ ] `shared/app/assets/stylesheets/_modal.scss:38` — 18px in padding: var(--space-2) var(--space-4) calc(18px + var(--saf
- [ ] `shared/app/assets/stylesheets/_responsive.scss:15` — 54px in padding-bottom: calc(var(--tab-bar-h, 54px) + var(--safe-bot
- [ ] `shared/app/assets/stylesheets/_shell.scss:285` — 10px in gap: 10px;
- [ ] `shared/app/assets/stylesheets/_shell.scss:315` — 70px in bottom: calc(70px + var(--safe-bottom, 0px));
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:168` — 72px in bottom: calc(72px + var(--safe-bottom, 0px));
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:174` — 6px in gap: 6px;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:280` — 6px in gap: 6px;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:451` — 88px in bottom: calc(88px + var(--safe-bottom, 0px));
- [ ] `shared/frontend/layouts/visualizer.css:57` — 10px in top: calc(10px + var(--safe-top));
- [ ] `shared/frontend/layouts/visualizer.css:58` — 10px in inset-inline-start: calc(10px + var(--safe-left));
- [ ] `shared/frontend/layouts/visualizer.css:75` — 10px in padding: 10px;

### css_radius_large — 2 · confidence high

border-radius above 16px. forbid_arbitrary_radius_px_above: 16. Law: `pixel_perfection.forbid_arbitrary_radius_px_above`.

- [ ] `amber/app/assets/stylesheets/_items.scss:89` — border-radius: 999px;
- [ ] `shared/app/assets/stylesheets/_search_yep.scss:8` — border-radius: 30px;

## Motion and easing — 135 items

### css_transition_no_easing — 83 · confidence medium

transition without an easing function. aesthetic_rules.CINEMA_PALETTE requires cubic-bezier easing on every transition. Law: `aesthetic_rules.CINEMA_PALETTE`.

- [ ] `amber/app/assets/stylesheets/_base.scss:48` — transition: none !important;
- [ ] `amber/app/assets/stylesheets/_brand.scss:436` — * { animation: none !important; transition: none !important; }
- [ ] `amber/app/assets/stylesheets/_dressing_room.scss:152` — transition: none !important;
- [ ] `amber/app/assets/stylesheets/_editorial.scss:5` — transition: background var(--transition-fast);
- [ ] `amber/app/assets/stylesheets/_editorial.scss:51` — transition: none !important;
- [ ] `amber/app/assets/stylesheets/_items.scss:135` — transition: none;
- [ ] `amber/app/assets/stylesheets/_items_luxury.scss:147` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_canvas.scss:85` — transition: color var(--transition-fast), border-color var(--transition-fast), background var(--transition-fas
- [ ] `brgen/app/assets/stylesheets/_canvas.scss:102` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_communities.scss:13` — transition: background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_communities.scss:28` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_composer.scss:26` — transition: background var(--transition-fast, 180ms), border-color var(--transition-fast, 180ms);
- [ ] `brgen/app/assets/stylesheets/_dating_actions.scss:92` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_dating_stack.scss:131` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:11` — transition: background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:108` — transition: color var(--transition-fast), background var(--transition-fast),
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:180` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_forms.scss:14` — transition: opacity var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_forms.scss:98` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_maps.scss:135` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_marketplace.scss:76` — transition: background var(--transition-fast), border-color var(--transition-fast), color var(--transition-fas
- [ ] `brgen/app/assets/stylesheets/_marketplace.scss:172` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_marketplace_cards.scss:35` — transition: background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_marketplace_cards.scss:164` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_marketplace_top_offers.scss:75` — transition: background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_marketplace_top_offers.scss:127` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_media.scss:37` — transition: background var(--transition-fast), border-color var(--transition-fast), color var(--transition-fas
- [ ] `brgen/app/assets/stylesheets/_media.scss:97` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_mobile.scss:22` — transition: background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_mobile.scss:60` — transition: opacity var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_mobile.scss:88` — transition:
- [ ] `brgen/app/assets/stylesheets/_mobile.scss:98` — transition:
- [ ] `brgen/app/assets/stylesheets/_mobile.scss:133` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_nav.scss:76` — transition: color var(--transition-fast), background var(--transition-fast), border-color var(--transition-fas
- [ ] `brgen/app/assets/stylesheets/_nav.scss:106` — transition: background var(--transition-fast, 180ms), border-color var(--transition-fast, 180ms);
- [ ] `brgen/app/assets/stylesheets/_nav.scss:201` — transition: color var(--transition-fast, 180ms);
- [ ] `brgen/app/assets/stylesheets/_nav.scss:214` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:54` — transition: color var(--transition-fast), background var(--transition-fast), border-color var(--transition-fas
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:77` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:71` — transition: color var(--transition-fast), border-color var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:89` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_posts.scss:7` — transition: background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_posts.scss:34` — transition: color var(--transition-fast), background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_posts.scss:64` — transition: color var(--transition-fast), background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_posts.scss:159` — transition: background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_posts.scss:187` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:70` — @media (prefers-reduced-motion: reduce) { *, *::before, *::after { animation: none !important; transition: non
- [ ] `brgen/app/assets/stylesheets/_share.scss:38` — transition: background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_share.scss:93` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_tiptap.scss:67` — transition: opacity var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_tiptap.scss:90` — transition: color var(--transition-fast), background var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_tiptap.scss:100` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_messenger_list.scss:156` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:18` — transition: background var(--transition-fast), color var(--transition-fast);
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:81` — transition: none !important;
- [ ] `brgen/engines/dating/app/assets/stylesheets/_vertical_dating_shell.scss:111` — transition: none !important;
- [ ] `brgen/engines/marketplace/app/assets/stylesheets/_vertical_marketplace.scss:84` — transition: none !important;
- [ ] `brgen/engines/takeaway/app/assets/stylesheets/_vertical_takeaway.scss:110` — transition: width var(--transition-normal);
- [ ] `brgen/engines/takeaway/app/assets/stylesheets/_vertical_takeaway.scss:115` — transition: none;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss:91` — transition: background var(--transition-fast);
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss:103` — transition: none !important;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv_cards.scss:29` — transition: background var(--transition-fast);
- [ ] `bsdports/app/assets/stylesheets/application.scss:530` — transition: none !important;
- [ ] `shared/app/assets/stylesheets/_animations.scss:63` — transition: none !important;
- [ ] `shared/app/assets/stylesheets/_chat_reactions.scss:62` — transition: opacity var(--transition-fast, 140ms);
- [ ] `shared/app/assets/stylesheets/_chat_reactions.scss:77` — .msg_reaction_picker { transition: none; }
- [ ] `shared/app/assets/stylesheets/_minimal.scss:272` — transition: background var(--transition-fast, 180ms);
- [ ] `shared/app/assets/stylesheets/_minimal.scss:466` — transition: background var(--transition-fast);
- [ ] `shared/app/assets/stylesheets/_minimal.scss:570` — transition: color var(--transition-fast), background var(--transition-fast);
- [ ] `shared/app/assets/stylesheets/_minimal.scss:640` — transition: none !important;
- [ ] `shared/app/assets/stylesheets/_modal.scss:22` — transition: opacity var(--transition-fast);
- [ ] `shared/app/assets/stylesheets/_modal.scss:51` — transition:
- [ ] `shared/app/assets/stylesheets/_modal.scss:61` — transition:
- [ ] `shared/app/assets/stylesheets/_shell.scss:163` — transition: opacity var(--transition-fast, 180ms);
- [ ] `shared/app/assets/stylesheets/_shell.scss:179` — transition: color var(--transition-fast, 180ms), opacity var(--transition-fast, 180ms);
- [ ] `shared/app/assets/stylesheets/_shell.scss:215` — transition: opacity var(--transition-fast, 180ms);
- [ ] `shared/app/assets/stylesheets/_shell.scss:258` — transition: background var(--transition-fast, 180ms), color var(--transition-fast, 180ms);
- [ ] `shared/app/assets/stylesheets/_shell.scss:298` — transition: opacity var(--transition-fast, 180ms);
- [ ] `shared/app/assets/stylesheets/_shell.scss:473` — transition: background var(--transition-fast, 180ms);
- [ ] `shared/app/assets/stylesheets/_shell.scss:563` — transition: none !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:32` — transition: background var(--transition-fast, 180ms);
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:118` — transition: opacity var(--transition-fast, 180ms), color var(--transition-fast, 180ms);
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:538` — transition: none !important;

### css_animation_present — 52 · confidence low

animation declaration — verify it is reduced-motion guarded and frame-budgeted. design_rules.pixel_field.performance requires graceful degradation before motion. Law: `pixel_field.performance`.

- [ ] `amber/app/assets/stylesheets/_base.scss:47` — animation: none !important;
- [ ] `amber/app/assets/stylesheets/_brand.scss:54` — animation: moveGradient 20s infinite var(--ease-out, cubic-bezier(0.25, 0.1, 0.25, 1));
- [ ] `amber/app/assets/stylesheets/_brand.scss:68` — animation: none;
- [ ] `amber/app/assets/stylesheets/_brand.scss:353` — animation: amber-skeleton 1.2s ease-in-out infinite;
- [ ] `amber/app/assets/stylesheets/_dressing_room.scss:151` — animation: none !important;
- [ ] `amber/app/assets/stylesheets/_editorial.scss:50` — animation: none !important;
- [ ] `amber/app/assets/stylesheets/_items_luxury.scss:146` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_canvas.scss:101` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_chrome_surfaces.scss:155` — animation: skeleton-shimmer 1.2s ease-in-out infinite;
- [ ] `brgen/app/assets/stylesheets/_chrome_surfaces.scss:186` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_communities.scss:27` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_composer_responsive.scss:11` — animation: composer-drop-in 220ms cubic-bezier(0.2, 0.8, 0.3, 1);
- [ ] `brgen/app/assets/stylesheets/_composer_responsive.scss:15` — animation: composer-backdrop-in 180ms ease-out;
- [ ] `brgen/app/assets/stylesheets/_composer_responsive.scss:31` — animation: none;
- [ ] `brgen/app/assets/stylesheets/_dating_actions.scss:91` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_dating_stack.scss:130` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:179` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_forms.scss:97` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_maps.scss:86` — animation: matchFadeIn .18s ease-out both;
- [ ] `brgen/app/assets/stylesheets/_maps.scss:134` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_media.scss:71` — animation: nearby-in 300ms cubic-bezier(.34, 1.56, .64, 1) both;
- [ ] `brgen/app/assets/stylesheets/_media.scss:96` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_mobile.scss:132` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_nav.scss:213` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:76` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:24` — animation: nearby-in 280ms cubic-bezier(.34, 1.56, .64, 1) both;
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:40` — animation: pulse-dot 1.8s ease-in-out infinite;
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:88` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_posts.scss:186` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_share.scss:92` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_tiptap.scss:99` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_messenger_list.scss:155` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_messenger_thread.scss:188` — animation: msg-type-bar 1s ease-in-out infinite;
- [ ] `brgen/app/assets/stylesheets/_vertical_messenger_thread.scss:198` — animation: none;
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:80` — animation: none !important;
- [ ] `brgen/engines/dating/app/assets/stylesheets/_vertical_dating_shell.scss:110` — animation: none !important;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:135` — animation: radio-pulse 2s ease-in-out infinite;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:172` — animation: none !important;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss:39` — animation: tv-live-pulse 2s ease-in-out infinite;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss:102` — animation: none !important;
- [ ] `bsdports/app/assets/stylesheets/application.scss:529` — animation: none !important;
- [ ] `shared/app/assets/stylesheets/_animations.scss:49` — animation: shimmer 1.4s linear infinite;
- [ ] `shared/app/assets/stylesheets/_animations.scss:62` — animation: none !important;
- [ ] `shared/app/assets/stylesheets/_empty_state.scss:151` — animation: shared-skeleton-shimmer 1.2s ease-in-out infinite;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:639` — animation: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:562` — animation: none !important;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:206` — animation: nearby-widget-in 180ms cubic-bezier(.34, 1.56, .64, 1) both;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:537` — animation: none !important;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:188` — animation: shimmer 1.4s ease-in-out infinite;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:203` — animation: slideInRight 240ms cubic-bezier(0.22, 1, 0.36, 1);
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:473` — animation: expandLayout 240ms cubic-bezier(0.22, 1, 0.36, 1) both;
- [ ] `shared/frontend/layouts/visualizer.css:51` — animation: start-ack 240ms ease-out;

## Accessibility — 40 items

### form_no_label — 18 · confidence high

Form with inputs and no label element.  Law: `rams_checklist.understandable`.

- [ ] `amber/app/views/outfits/index.html.erb:1` — fields without label
- [ ] `amber/app/views/planned_outfits/index.html.erb:1` — fields without label
- [ ] `amber/app/views/shared/_feed_compose.html.erb:1` — fields without label
- [ ] `brgen/app/views/channels/show.html.erb:1` — fields without label
- [ ] `brgen/app/views/maps/places/show.html.erb:1` — fields without label
- [ ] `brgen/app/views/messages/create.turbo_stream.erb:1` — fields without label
- [ ] `brgen/app/views/messages/new.html.erb:1` — fields without label
- [ ] `brgen/app/views/nearby/_widget_composer.html.erb:1` — fields without label
- [ ] `brgen/engines/marketplace/app/views/marketplace/_nav_bar.html.erb:1` — fields without label
- [ ] `brgen/engines/marketplace/app/views/marketplace/orders/show.html.erb:1` — fields without label
- [ ] `brgen/engines/playlist/app/views/playlist/listening_parties/show.html.erb:1` — fields without label
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/show.html.erb:1` — fields without label
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:1` — fields without label
- [ ] `brgen/engines/playlist/app/views/playlist/shared/_collaborators.html.erb:1` — fields without label
- [ ] `brgen/engines/takeaway/app/views/takeaway/_nav_bar.html.erb:1` — fields without label
- [ ] `brgen/engines/tv/app/views/tv/live_streams/show.html.erb:1` — fields without label
- [ ] `bsdports/app/views/comments/create.turbo_stream.erb:1` — fields without label
- [ ] `bsdports/app/views/ports/show.html.erb:1` — fields without label

### css_font_px_small — 10 · confidence high

Font-size below 16px. typography.accessibility.body_min_px is 16; below that iOS zooms the viewport on focus. Law: `typography.accessibility.body_min_px`.

- [ ] `amber/app/assets/stylesheets/_brand.scss:30` — font-size: 12px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:103` — font-size: 4px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:112` — font-size: 3px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:28` — font-size: 14px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:96` — font-size: 12px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:114` — font-size: 12px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:119` — font-size: 14px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:157` — font-size: 12px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:175` — font-size: 15px;
- [ ] `bsdports/app/assets/stylesheets/_jsfiddle_chrome.scss:41` — font-size: 14px;

### heading_skip — 5 · confidence high

Heading level skipped. Breaks the document outline screen-reader users navigate by. Law: `rams_checklist.understandable`.

- [ ] `amber/app/views/ai/occasion_map.html.erb:6` — h1 -> h3
- [ ] `brgen/app/views/communities/show.html.erb:50` — h1 -> h3
- [ ] `brgen/app/views/posts/index.html.erb:18` — h1 -> h3
- [ ] `brgen/app/views/posts/show.html.erb:90` — h1 -> h3
- [ ] `brgen/engines/marketplace/app/views/marketplace/orders/show.html.erb:28` — h1 -> h3

### button_div — 3 · confidence high

div/span carrying a click action. Not focusable, not keyboard-activatable, not announced as a control. Law: `ux_laws.fitts`.

- [ ] `brgen/app/views/layouts/application.html.erb:173` — <div class="sidebar-dropdown" data-controller="dropdown" data-action="click@window->dropdo
- [ ] `brgen/app/views/layouts/application.html.erb:281` — <div class="mobile-sheet-backdrop" data-bottom-sheet-target="backdrop" data-action="click-
- [ ] `brgen/app/views/posts/_post.html.erb:41` — <div class="feed-action-menu" data-controller="dropdown" data-action="click@window->dropdo

### form_no_autocomplete — 2 · confidence high

password/email field with no autocomplete. Blocks password managers. Law: `rams_checklist.useful`.

- [ ] `brgen/app/views/shared/_email_subscribe.html.erb:6` — <%= f.email_field :email, name: "email_subscription[email]",
- [ ] `shared/app/views/shared/_newsletter_cta.html.erb:7` — <%= form.email_field :email, name: "email_subscription[email]",

### css_line_height_tight — 2 · confidence high

line-height below 1.4. typography.line_height.body_min 1.4, accessibility_min 1.5. Law: `typography.line_height`.

- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:29` — line-height: 1.2;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv_cards.scss:115` — .tv-card-title { display: block; font-weight: 600; color: var(--text); line-height: 1.3; text-decoration: none

## Icons — 26 items

### emoji_in_view — 26 · confidence high

Emoji glyph in a view. WIRING_NOTES: feed actions use shared/_x_feed_icon SVG icons, not emoji. Emoji render differently per platform and are read aloud verbatim. Law: `WIRING_NOTES Feed actions`.

- [ ] `amber/app/views/ai/color_palette.html.erb:35` — ←
- [ ] `amber/app/views/ai/occasion_map.html.erb:17` — ←
- [ ] `amber/app/views/declutter/review.html.erb:95` — ←
- [ ] `amber/app/views/demo_wardrobe/show.html.erb:4` — ←
- [ ] `amber/app/views/home/index.html.erb:113` — →
- [ ] `amber/app/views/shared/_feed_compose.html.erb:8` — ✦
- [ ] `amber/app/views/shared/_widgets.html.erb:28` — →
- [ ] `brgen/app/views/nearby/_alert.html.erb:7` — ✕
- [ ] `brgen/app/views/nearby/widget.html.erb:16` — ↻
- [ ] `brgen/engines/dating/app/views/dating/home/_card.html.erb:52` — ✕
- [ ] `brgen/engines/dating/app/views/dating/home/_card.html.erb:53` — ♥
- [ ] `brgen/engines/marketplace/app/views/marketplace/deals/_card.html.erb:29` — ★
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/_card.html.erb:45` — ★
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/index.html.erb:21` — ↑
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/index.html.erb:22` — ↓
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/show.html.erb:28` — ★
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/show.html.erb:54` — ★
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/show.html.erb:66` — ★
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/_radio_tunnel.html.erb:54` — ♪
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/show.html.erb:4` — ←
- [ ] `brgen/engines/takeaway/app/views/takeaway/orders/show.html.erb:15` — ✓
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/_card.html.erb:3` — ★
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:105` — ★
- [ ] `bsdports/app/views/ports/show.html.erb:28` — →
- [ ] `bsdports/app/views/ports/show.html.erb:39` — →
- [ ] `bsdports/app/views/ports/show.html.erb:42` — ←

## Responsive and mobile — 72 items

### css_px_width — 72 · confidence medium

Fixed px width of 3+ digits. Fixed widths are the usual cause of horizontal overflow on a 390px viewport. Prefer min()/clamp()/ch. Law: `ultraminimalism.negative_space.content_width`.

- [ ] `amber/app/assets/stylesheets/_base.scss:20` — @media (min-width: 1280px) {
- [ ] `amber/app/assets/stylesheets/_brand.scss:33` — @media (min-width: 768px) {
- [ ] `amber/app/assets/stylesheets/_brand.scss:90` — max-width: 1000px;
- [ ] `amber/app/assets/stylesheets/_brand.scss:109` — @media (min-width: 768px) {
- [ ] `amber/app/assets/stylesheets/_brand.scss:169` — @media (min-width: 768px) {
- [ ] `amber/app/assets/stylesheets/_brand.scss:230` — max-width: 640px;
- [ ] `amber/app/assets/stylesheets/_dashboard.scss:27` — @media (max-width: 640px) {
- [ ] `amber/app/assets/stylesheets/_dashboard.scss:116` — min-width: 280px;
- [ ] `amber/app/assets/stylesheets/_dressing_room.scss:14` — width: 200px;
- [ ] `amber/app/assets/stylesheets/_dressing_room.scss:19` — width: 200px;
- [ ] `amber/app/assets/stylesheets/_dressing_room.scss:86` — max-width: 420px;
- [ ] `amber/app/assets/stylesheets/_item_forms.scss:2` — max-width: 480px;
- [ ] `amber/app/assets/stylesheets/_items.scss:81` — max-width: 700px;
- [ ] `amber/app/assets/stylesheets/_items.scss:114` — width: 200px;
- [ ] `amber/app/assets/stylesheets/_items_luxury.scss:81` — @media (min-width: 768px) {
- [ ] `amber/app/assets/stylesheets/_jsfiddle_chrome.scss:45` — width: 116px;
- [ ] `amber/app/assets/stylesheets/_layout.scss:46` — @media (max-width: 640px) {
- [ ] `brgen/app/assets/stylesheets/_affiliate.scss:77` — .map-hud { position: fixed; top: var(--space-4); left: var(--brand-mark-inline); z-index: var(--z-app); displa
- [ ] `brgen/app/assets/stylesheets/_canvas.scss:21` — @media (max-width: 1265px) { .city-carousel { inset-inline-start: calc(120px + 16px); } }
- [ ] `brgen/app/assets/stylesheets/_canvas.scss:22` — @media (max-width: 768px) {
- [ ] `brgen/app/assets/stylesheets/_card_modifiers.scss:57` — @media (min-width: 768px) {
- [ ] `brgen/app/assets/stylesheets/_composer_responsive.scss:36` — @media (max-width: 767px) {
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:78` — @media (min-width: 768px) {
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:84` — @media (max-width: 480px) {
- [ ] `brgen/app/assets/stylesheets/_forms.scss:77` — @media (max-width: 767px) {
- [ ] `brgen/app/assets/stylesheets/_marketplace.scss:132` — @media (min-width: 768px) {
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:26` — width: 300px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_animated_logo.scss:35` — width: 100px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_cards.scss:10` — @media (min-width: 768px) {
- [ ] `brgen/app/assets/stylesheets/_marketplace_cards.scss:17` — @media (min-width: 1265px) {
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:81` — width: 100px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:149` — max-width: 140px;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:310` — @media (max-width: 700px) {
- [ ] `brgen/app/assets/stylesheets/_marketplace_top_offers.scss:55` — @media (min-width: 768px) {
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:10` — max-width: 320px;
- [ ] `brgen/app/assets/stylesheets/_posts.scss:142` — .form-wrap { padding: var(--space-6) var(--space-4); max-width: 480px; }
- [ ] `brgen/app/assets/stylesheets/_root.scss:233` — @media (min-width: 1265px) {
- [ ] `brgen/app/assets/stylesheets/_root.scss:238` — @media (min-width: 769px) and (max-width: 1264px) {
- [ ] `brgen/app/assets/stylesheets/_root.scss:243` — @media (max-width: 768px) {
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:22` — @media (min-width: 768px) {
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:33` — @media (min-width: 768px) {
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:47` — @media (min-width: 768px) {
- [ ] `brgen/engines/marketplace/app/assets/stylesheets/_vertical_marketplace.scss:14` — max-width: 1280px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:51` — max-width: 720px;
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:71` — @media (min-width: 768px) {
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:72` — .radio-track-display { max-width: 350px; }
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:75` — @media (max-width: 767px) {
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:92` — max-width: 720px;
- [ ] `brgen/engines/takeaway/app/assets/stylesheets/_vertical_takeaway.scss:21` — max-width: 1280px;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss:8` — max-width: 1100px;
- [ ] `bsdports/app/assets/stylesheets/_jsfiddle_chrome.scss:34` — width: 116px;
- [ ] `bsdports/app/assets/stylesheets/application.scss:202` — width: 182px;
- [ ] `bsdports/app/assets/stylesheets/application.scss:251` — max-width: 660px;
- [ ] `bsdports/app/assets/stylesheets/application.scss:316` — max-width: 584px;
- [ ] `bsdports/app/assets/stylesheets/application.scss:418` — @media (max-width: 640px) {
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:50` — --sidebar-width: 275px;
- [ ] `shared/app/assets/stylesheets/_dialect_tokens.scss:52` — --widgets-width: 350px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:55` — @media (min-width: 1280px) {
- [ ] `shared/app/assets/stylesheets/_minimal.scss:195` — max-width: 660px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:247` — max-width: 584px;
- [ ] `shared/app/assets/stylesheets/_minimal.scss:449` — @media (max-width: 480px) {
- [ ] `shared/app/assets/stylesheets/_minimal.scss:471` — @media (max-width: 480px) {
- [ ] `shared/app/assets/stylesheets/_minimal.scss:608` — @media (min-width: 768px) {
- [ ] `shared/app/assets/stylesheets/_responsive.scss:3` — // This used to be wrapped in @media (max-width: 768px), with the note "desktop
- [ ] `shared/app/assets/stylesheets/_search_yep.scss:4` — width: 480px;
- [ ] `shared/app/assets/stylesheets/_shell.scss:286` — width: 230px;
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:444` — @media (max-width: 480px) {
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:201` — max-width: 360px;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:369` — @media (max-width: 480px) {
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:465` — @container grid (min-width: 400px) {
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:471` — @container grid (min-width: 600px) {
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:578` — .brand-wordmark .logo-carousel { max-width: 140px; overflow: hidden; }

## Performance — 44 items

### count_in_view — 18 · confidence medium

.count in a view. Fires a COUNT query per render; use size on a loaded relation or a counter cache. Law: `pixel_field.performance`.

- [ ] `amber/app/views/creator_profiles/_form.html.erb:4` — <%= tag.h2 t("shared.errors", count: profile.errors.count, default: "Please revi
- [ ] `amber/app/views/items/_live_search_results.html.erb:3` — <span class="tag"><%= @items.count(&:spark_joy?) %> joy keepers</span>
- [ ] `amber/app/views/items/index.html.erb:8` — <h1><%= t("pages.wardrobe") %> (<%= @pagy.count %>)</h1>
- [ ] `amber/app/views/outfits/_live_search_results.html.erb:2` — <span class="tag"><%= pluralize(@outfits.sum { |outfit| outfit.items.count }, "l
- [ ] `amber/app/views/outfits/_outfit.html.erb:20` — <span class="dim"><%= outfit.items.count %> items · <%= pluralize(outfit.total_w
- [ ] `amber/app/views/outfits/show.html.erb:11` — <span class="tag"><%= pluralize(@outfit.items.count, "item") %></span>
- [ ] `amber/app/views/users/show.html.erb:4` — <p><%= @user.items.count %> items · <%= @user.followers.count %> followers · <%=
- [ ] `amber/app/views/wardrobe_items/_form.html.erb:4` — <%= tag.h2 t("shared.errors", count: wardrobe_item.errors.count, default: "Pleas
- [ ] `brgen/app/views/messages/_reactions.html.erb:11` — <% counts = message.reactions.group(:kind).count %>
- [ ] `brgen/engines/playlist/app/views/playlist/hosted_tracks/show.html.erb:24` — <p class="dim"><%= @track.listens.count %> plays · <%= @comments.size %> timesta
- [ ] `brgen/engines/playlist/app/views/playlist/sets/_card.html.erb:5` — meta: "#{set.tracks.count} tracks · #{set.formatted_duration}",
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:23` — <p class="dim"><%= @set.privacy.presence&.humanize || "Public" %> · <%= @tracks.
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:34` — <span class="dim"><%= @set.likes.count %> likes</span>
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:37` — <p class="dim"><%= @set.likes.count %> likes</p>
- [ ] `brgen/engines/tv/app/views/tv/channels/show.html.erb:26` — <span class="chip"><%= pluralize(@videos.count, "video") %> shown</span>
- [ ] `brgen/engines/tv/app/views/tv/shows/_card.html.erb:5` — meta: "#{show.episodes.count} episodes",
- [ ] `shared/app/views/notifications/index.html.erb:8` — <% unread = @notifications.count { |n| !n.read? } %>
- [ ] `shared/app/views/shared/_errors.html.erb:3` — <h2 id="form-errors-title" class="errors-title"><%= pluralize(object.errors.coun

### ctrl_index_no_pagination — 11 · confidence high

index action with no pagination or limit. Renders the whole table; vm23 has 1GB and 1 vCPU. Law: `vm23 capacity ceiling`.

- [ ] `amber/app/controllers/connections_controller.rb:1` — connections_controller.rb
- [ ] `amber/app/controllers/live_streams_controller.rb:1` — live_streams_controller.rb
- [ ] `amber/app/controllers/messages_controller.rb:1` — messages_controller.rb
- [ ] `amber/app/controllers/planned_outfits_controller.rb:1` — planned_outfits_controller.rb
- [ ] `brgen/app/controllers/admin/reports_controller.rb:1` — reports_controller.rb
- [ ] `brgen/app/controllers/bookmarks_controller.rb:1` — bookmarks_controller.rb
- [ ] `brgen/app/controllers/channels_controller.rb:1` — channels_controller.rb
- [ ] `brgen/app/controllers/nearby_controller.rb:1` — nearby_controller.rb
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/orders_controller.rb:1` — orders_controller.rb
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/saved_searches_controller.rb:1` — saved_searches_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/playlists_controller.rb:1` — playlists_controller.rb

### rb_unscoped_all — 7 · confidence high

Unbounded .all in a controller. No LIMIT; grows with the table. Law: `pixel_field.performance`.

- [ ] `brgen/app/controllers/search_controller.rb:24` — @results[:channels] = apply_live_search(Tv::Channel.all, columns: %w[name description], vertical: "tv")
- [ ] `brgen/app/controllers/search_controller.rb:28` — @results[:places] = apply_live_search(Place.all, columns: %w[name kind], vertical: "maps")
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/listings_controller.rb:56` — @categories = Marketplace::Category.all
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/listings_controller.rb:77` — @categories = Marketplace::Category.all
- [ ] `brgen/engines/tv/app/controllers/tv/shows_controller.rb:7` — scope = (@channel ? @channel.shows : Tv::Show.all).published
- [ ] `shared/app/controllers/fleet_health_controller.rb:12` — critical_ok = critical.all? { |key| checks[key] }
- [ ] `shared/app/controllers/fleet_health_controller.rb:13` — status = critical_ok ? (checks.values.all? ? "ok" : "degraded") : "unavailable"

### img_no_dims — 6 · confidence high

image_tag with no width/height. Missing intrinsic size causes layout shift (CLS). Law: `pixel_field.performance`.

- [ ] `brgen/app/views/maps/places/_card.html.erb:4` — <%= responsive_image_tag(place.photo, alt: place.name, loading: "lazy", class: "place-card
- [ ] `brgen/app/views/maps/places/show.html.erb:13` — <%= responsive_image_tag(@place.photo, alt: @place.name, class: "place-hero__image") %>
- [ ] `brgen/app/views/posts/_post.html.erb:72` — media: (post.image.attached? ? link_to(responsive_image_tag(post.image, alt: post.title, l
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:52` — <%= responsive_image_tag(item.photo, alt: item.name, loading: "lazy", class: "menu-row__ph
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:85` — <%= responsive_image_tag(item.photo, alt: item.name, loading: "lazy", class: "menu-row__ph
- [ ] `brgen/engines/tv/app/views/tv/videos/_tv_video.html.erb:5` — <%= responsive_image_tag(tv_video.thumbnail, alt: tv_video.title, loading: "lazy", class: 

### img_no_lazy — 2 · confidence medium

image_tag with no loading:.  Law: `pixel_field.performance`.

- [ ] `brgen/app/views/maps/places/show.html.erb:13` — <%= responsive_image_tag(@place.photo, alt: @place.name, class: "place-hero__image") %>
- [ ] `shared/app/views/shared/_avatar.html.erb:5` — <%= image_tag(main_app.url_for(local_assigns[:user].avatar), class: "avatar #{size_class}"

## Security — 75 items

### ctrl_no_rate_limit — 64 · confidence medium

create action with no rate_limit. Anonymous posting is a product feature here, which makes every unrated create endpoint an abuse surface. Law: `soul.absolute.protection_tiers`.

- [ ] `amber/app/controllers/affiliate_links_controller.rb:1` — affiliate_links_controller.rb
- [ ] `amber/app/controllers/comments_controller.rb:1` — comments_controller.rb
- [ ] `amber/app/controllers/connections_controller.rb:1` — connections_controller.rb
- [ ] `amber/app/controllers/creator_profiles_controller.rb:1` — creator_profiles_controller.rb
- [ ] `amber/app/controllers/creator_wardrobe_items_controller.rb:1` — creator_wardrobe_items_controller.rb
- [ ] `amber/app/controllers/follows_controller.rb:1` — follows_controller.rb
- [ ] `amber/app/controllers/items_controller.rb:1` — items_controller.rb
- [ ] `amber/app/controllers/live_streams_controller.rb:1` — live_streams_controller.rb
- [ ] `amber/app/controllers/messages_controller.rb:1` — messages_controller.rb
- [ ] `amber/app/controllers/outfits_controller.rb:1` — outfits_controller.rb
- [ ] `amber/app/controllers/planned_outfits_controller.rb:1` — planned_outfits_controller.rb
- [ ] `amber/app/controllers/posts_controller.rb:1` — posts_controller.rb
- [ ] `amber/app/controllers/registrations_controller.rb:1` — registrations_controller.rb
- [ ] `amber/app/controllers/wardrobe_items_controller.rb:1` — wardrobe_items_controller.rb
- [ ] `brgen/app/controllers/blocks_controller.rb:1` — blocks_controller.rb
- [ ] `brgen/app/controllers/bookmarks_controller.rb:1` — bookmarks_controller.rb
- [ ] `brgen/app/controllers/communities_controller.rb:1` — communities_controller.rb
- [ ] `brgen/app/controllers/community_memberships_controller.rb:1` — community_memberships_controller.rb
- [ ] `brgen/app/controllers/conversations_controller.rb:1` — conversations_controller.rb
- [ ] `brgen/app/controllers/email_subscriptions_controller.rb:1` — email_subscriptions_controller.rb
- [ ] `brgen/app/controllers/follows_controller.rb:1` — follows_controller.rb
- [ ] `brgen/app/controllers/partner/memberships_controller.rb:1` — memberships_controller.rb
- [ ] `brgen/app/controllers/partner/programs_controller.rb:1` — programs_controller.rb
- [ ] `brgen/app/controllers/presences_controller.rb:1` — presences_controller.rb
- [ ] `brgen/app/controllers/push_subscriptions_controller.rb:1` — push_subscriptions_controller.rb
- [ ] `brgen/app/controllers/typing_indicators_controller.rb:1` — typing_indicators_controller.rb
- [ ] `brgen/app/controllers/webhooks/tradedoubler_controller.rb:1` — tradedoubler_controller.rb
- [ ] `brgen/engines/dating/app/controllers/dating/dislikes_controller.rb:1` — dislikes_controller.rb
- [ ] `brgen/engines/dating/app/controllers/dating/likes_controller.rb:1` — likes_controller.rb
- [ ] `brgen/engines/dating/app/controllers/dating/profiles_controller.rb:1` — profiles_controller.rb
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/checkouts_controller.rb:1` — checkouts_controller.rb
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/favorites_controller.rb:1` — favorites_controller.rb
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/orders_controller.rb:1` — orders_controller.rb
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/reviews_controller.rb:1` — reviews_controller.rb
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/saved_searches_controller.rb:1` — saved_searches_controller.rb
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/stores_controller.rb:1` — stores_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/collaborations_controller.rb:1` — collaborations_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/dilla_sketches_controller.rb:1` — dilla_sketches_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/hosted_tracks_controller.rb:1` — hosted_tracks_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/imports_controller.rb:1` — imports_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/likes_controller.rb:1` — likes_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/listening_parties_controller.rb:1` — listening_parties_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/listens_controller.rb:1` — listens_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/party_messages_controller.rb:1` — party_messages_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/playlists_controller.rb:1` — playlists_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/sets_controller.rb:1` — sets_controller.rb
- [ ] `brgen/engines/playlist/app/controllers/playlist/tracks_controller.rb:1` — tracks_controller.rb
- [ ] `brgen/engines/takeaway/app/controllers/takeaway/favorite_restaurants_controller.rb:1` — favorite_restaurants_controller.rb
- [ ] `brgen/engines/takeaway/app/controllers/takeaway/menu_items_controller.rb:1` — menu_items_controller.rb
- [ ] `brgen/engines/takeaway/app/controllers/takeaway/orders_controller.rb:1` — orders_controller.rb
- [ ] `brgen/engines/takeaway/app/controllers/takeaway/restaurants_controller.rb:1` — restaurants_controller.rb
- [ ] `brgen/engines/takeaway/app/controllers/takeaway/reviews_controller.rb:1` — reviews_controller.rb
- [ ] `brgen/engines/tv/app/controllers/tv/channels_controller.rb:1` — channels_controller.rb
- [ ] `brgen/engines/tv/app/controllers/tv/comments_controller.rb:1` — comments_controller.rb
- [ ] `brgen/engines/tv/app/controllers/tv/live_streams_controller.rb:1` — live_streams_controller.rb
- [ ] `brgen/engines/tv/app/controllers/tv/stream_chats_controller.rb:1` — stream_chats_controller.rb
- [ ] `brgen/engines/tv/app/controllers/tv/video_notes_controller.rb:1` — video_notes_controller.rb
- [ ] `brgen/engines/tv/app/controllers/tv/videos_controller.rb:1` — videos_controller.rb
- [ ] `bsdports/app/controllers/comments_controller.rb:1` — comments_controller.rb
- [ ] `shared/app/controllers/omniauth_callbacks_controller.rb:1` — omniauth_callbacks_controller.rb
- [ ] `shared/app/controllers/shared/reactions_controller.rb:1` — reactions_controller.rb
- [ ] `shared/app/controllers/shared/review_cases_controller.rb:1` — review_cases_controller.rb
- [ ] `shared/app/controllers/two_factor_setups_controller.rb:1` — two_factor_setups_controller.rb
- [ ] `shared/app/controllers/web_vitals_controller.rb:1` — web_vitals_controller.rb

### rb_skip_forgery — 5 · confidence high

skip_before_action :verify_authenticity_token. Confirm each is a webhook with its own signature check. Law: `soul.absolute.protection_tiers`.

- [ ] `amber/app/controllers/fingerprints_controller.rb:7` — skip_before_action :verify_authenticity_token, only: :create
- [ ] `amber/app/controllers/items_controller.rb:14` — skip_before_action :verify_authenticity_token, only: [ :share ]
- [ ] `brgen/app/controllers/fingerprints_controller.rb:7` — skip_before_action :verify_authenticity_token, only: :create
- [ ] `brgen/app/controllers/posts_controller.rb:19` — skip_before_action :verify_authenticity_token, only: [ :share ]
- [ ] `shared/app/controllers/concerns/shared/internal_token_auth.rb:11` — skip_before_action :verify_authenticity_token, raise: false

### raw_html_safe — 4 · confidence high

raw() or .html_safe in a view. Each one is an XSS surface; confirm the source cannot be user input. Law: `soul.absolute.protection_tiers`.

- [ ] `brgen/app/views/shared/_link_converter.html.erb:6` — var epi = <%= raw(
- [ ] `brgen/engines/dating/app/views/dating/matches/_match.html.erb:9` — content: capture { %(<p class="feed-card-meta">Matched on #{match.created_at.to_date}</p>)
- [ ] `brgen/engines/tv/app/views/tv/home/index.html.erb:21` — content: capture { %(<span class="live-badge">Live</span>).html_safe },
- [ ] `shared/app/views/two_factor_setups/show.html.erb:6` — <div class="auth-form-qr"><%= @qr.html_safe %></div>

### target_blank_no_rel — 2 · confidence high

target=_blank without rel=noopener. Reverse tabnabbing. Law: `soul.absolute.protection_tiers`.

- [ ] `bsdports/app/views/ports/show.html.erb:92` — <%= link_to adv.identifier, adv.nvd_url, target: "_blank" %>
- [ ] `shared/app/views/shared/_master_embed.html.erb:28` — target: "_blank",

## Correctness — 282 items

### rb_env_fetch_no_default — 93 · confidence medium

ENV["..."] instead of ENV.fetch. ENV[] returns nil silently; on the VPS a missing /etc/*.env key becomes a nil deep in a request. FAIL_VISIBLY. Law: `soul.absolute.code_rules.FAIL_VISIBLY`.

- [ ] `amber/app/services/shop_the_look.rb:32` — return [] unless ENV["TRADEDOUBLER_TOKEN"].present? || ENV["TRADEDOUBLER_PRODUCTS_TOKEN"].present?
- [ ] `amber/app/services/wardrobe_ai.rb:11` — ENV["OPENROUTER_API_KEY"].to_s.strip.present?
- [ ] `amber/app/services/wardrobe_ai.rb:15` — return false if ENV["CI"] == "1" || Rails.env.test?
- [ ] `amber/app/services/wardrobe_ai.rb:16` — return false unless ENV["AMBER_ENABLE_MASTER_PHOTO"].to_s == "1"
- [ ] `amber/app/services/wardrobe_ai.rb:221` — token = ENV["OPENROUTER_API_KEY"].to_s.strip
- [ ] `amber/config/boot.rb:3` — ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
- [ ] `amber/db/seeds.rb:20` — scale = (ENV['SEED_SCALE'] || (Rails.env.production? ? 1 : 5)).to_i.clamp(1, 50)
- [ ] `amber/db/seeds.rb:94` — if ENV["SEED_FROM_WEB"] && ENV["OPENROUTER_API_KEY"]
- [ ] `brgen/app/controllers/webhooks/tradedoubler_controller.rb:32` — secret = ENV["TRADEDOUBLER_WEBHOOK_SECRET"].presence ||
- [ ] `brgen/app/controllers/webhooks/tradedoubler_controller.rb:33` — ENV["TRADEDOUBLER_CONVERSIONS_TOKEN"].presence
- [ ] `brgen/app/services/amazon_associates.rb:43` — def access_key = ENV["AMAZON_ACCESS_KEY"].presence
- [ ] `brgen/app/services/amazon_associates.rb:44` — def secret_key = ENV["AMAZON_SECRET_KEY"].presence
- [ ] `brgen/app/services/amazon_associates.rb:45` — def partner_tag = ENV["AMAZON_PARTNER_TAG"].presence
- [ ] `brgen/app/services/marketplace/payments/stripe_checkout.rb:15` — ENV["STRIPE_SECRET_KEY"].to_s.strip.present?
- [ ] `brgen/app/services/marketplace/payments/vipps_checkout.rb:15` — ENV["VIPPS_EPAYMENT_CLIENT_ID"].to_s.strip.present? &&
- [ ] `brgen/app/services/marketplace/payments/vipps_checkout.rb:16` — ENV["VIPPS_EPAYMENT_CLIENT_SECRET"].to_s.strip.present? &&
- [ ] `brgen/app/services/marketplace/payments/vipps_checkout.rb:17` — ENV["VIPPS_MSN"].to_s.strip.present? &&
- [ ] `brgen/app/services/marketplace/payments/vipps_checkout.rb:18` — ENV["VIPPS_SUBSCRIPTION_KEY"].to_s.strip.present?
- [ ] `brgen/app/services/tradedoubler.rb:38` — ENV["TRADEDOUBLER_PRODUCTS_TOKEN"].presence || ENV["TRADEDOUBLER_TOKEN"].presence
- [ ] `brgen/app/services/tradedoubler.rb:42` — ENV["TRADEDOUBLER_VOUCHERS_TOKEN"].presence || products_token
- [ ] `brgen/app/services/tradedoubler.rb:46` — ENV["TRADEDOUBLER_CONVERSIONS_TOKEN"].presence
- [ ] `brgen/app/services/tradedoubler.rb:50` — ENV["TRADEDOUBLER_WEBSITE_ID"].presence
- [ ] `brgen/app/services/tradedoubler.rb:61` — raw = ENV["TRADEDOUBLER_FEED_IDS"].to_s
- [ ] `brgen/app/services/tradedoubler.rb:426` — ENV["TRADEDOUBLER_LANGUAGE"].presence # e.g. nb, no, en
- [ ] `brgen/config/boot.rb:3` — ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
- [ ] `brgen/config/initializers/solidus_marketplace.rb:13` — ENV["SOLIDUS_MARKETPLACE"].to_s == "1"
- [ ] `brgen/db/seeds.rb:15` — SEED_SCALE = [1, (ENV['SEED_SCALE'] || (Rails.env.production? ? 1 : 10)).to_i].max
- [ ] `brgen/db/seeds.rb:511` — if (bergen = City.find_by(domain: 'brgen.no')) && !ENV['SKIP_BERGEN_DEMO']
- [ ] `brgen/db/seeds.rb:524` — if ENV['SEED_FROM_WEB'] && ENV['OPENROUTER_API_KEY']
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/webhooks_controller.rb:68` — secret = ENV["STRIPE_WEBHOOK_SECRET"].to_s
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/webhooks_controller.rb:86` — secret = ENV["VIPPS_WEBHOOK_SECRET"].to_s
- [ ] `bsdports/app/controllers/ports_controller.rb:45` — @pkg_info = if ENV["CI"] == "1" || Rails.env.test?
- [ ] `bsdports/app/services/nvd_cve.rb:27` — if (key = ENV["NVD_API_KEY"]).present?
- [ ] `bsdports/app/services/ports/tree_locator.rb:10` — candidate = override.presence || platform.tree_path.presence || ENV["BSDPORTS_TREE_PATH"]
- [ ] `bsdports/config/boot.rb:3` — ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
- [ ] `bsdports/config/routes.rb:17` — if ENV["BSDPORTS_SOCIAL"] == "1"
- [ ] `bsdports/db/seeds.rb:33` — scale = (ENV["SEED_SCALE"] || 3).to_i.clamp(1, 20)
- [ ] `gates/lib/calibration.rb:68` — %w[1 true yes on].include?(ENV["GATE_CALIBRATION_APPLY"].to_s.strip.downcase)
- [ ] `gates/lib/constitutional_scan.rb:124` — def changed_only? = ENV["GATE_SCAN_CHANGED"].to_s == "1"
- [ ] `gates/lib/constitutional_scan.rb:178` — return unless ENV["GATE_SCAN_RATCHET"].to_s == "1"
- [ ] `gates/lib/design_metrics.rb:323` — return unless %w[1 true yes on].include?(ENV["DESIGN_METRICS_BROWSER"].to_s.strip.downcase)
- [ ] `gates/lib/layout_snapshot.rb:42` — def self.update? = %w[1 true yes on].include?(ENV["GATE_SNAPSHOT_UPDATE"].to_s.strip.downcase)
- [ ] `gates/lib/master_tts.rb:57` — if ENV["MASTER_TTS_REQUIRE_HOST_BACKEND"] == "1"
- [ ] `gates/release.rb:36` — return ENV["RUBY_CMD"].split if ENV["RUBY_CMD"].to_s != ""
- [ ] `gates/release.rb:45` — return ENV["BUNDLE_CMD"].split if ENV["BUNDLE_CMD"].to_s != ""
- [ ] `gates/release.rb:161` — if UNCHECKED.any? && %w[1 true yes on].include?(ENV["GATE_STRICT_INCONCLUSIVE"].to_s.strip.downcase)
- [ ] `gates/runner.rb:77` — return [] unless ENV["VISUAL_CAPTURE"] == "1"
- [ ] `gates/runner.rb:111` — autofix_off = ENV["GATE_AUTOFIX"].to_s.strip.downcase.match?(/\A(0|false|no|off)\z/)
- [ ] `gates/support/cdp_session.rb:44` — ENV["CHROME_PATH"],
- [ ] `gates/support/geometry_probe.rb:79` — raw = ENV["GATE_SURFACES"].to_s.strip
- [ ] `gates/visual_contract.rb:198` — strict: %w[1 true yes on].include?(ENV["VISUAL_STRICT"].to_s.strip.downcase),
- [ ] `gates/visual_contract.rb:199` — drift_max: ENV["VISUAL_DRIFT_MAX_RATIO"]&.then { |value| Float(value) }
- [ ] `shared/app/controllers/concerns/shared/internal_token_auth.rb:17` — expected = ENV["MASTER_INTERNAL_TOKEN"].to_s
- [ ] `shared/app/controllers/omniauth_callbacks_controller.rb:67` — record.client_id = ENV["#{auth.provider.to_s.upcase}_CLIENT_ID"]
- [ ] `shared/app/jobs/shared/database_snapshot_job.rb:36` — ENV["PUB4_BACKUP_DIR"].presence || Rails.root.join("..", "backups").to_s
- [ ] `shared/app/services/shared/amazon_marketplace.rb:116` — ENV["AMAZON_ASSOCIATE_TAG_#{country_for(market)}"].to_s.strip.presence
- [ ] `shared/app/services/shared/amazon_marketplace.rb:126` — STOREFRONTS.keys.select { |code| ENV["AMAZON_ASSOCIATE_TAG_#{code}"].to_s.strip.present? }
- [ ] `shared/app/services/shared/amazon_marketplace.rb:151` — tag = ENV["AMAZON_ASSOCIATE_TAG_#{country}"].to_s.strip
- [ ] `shared/app/services/shared/demo_media/catalog.rb:23` — env = ENV["DEMO_MEDIA_CATALOG"].to_s
- [ ] `shared/app/services/shared/demo_media/catalog.rb:28` — slug = ENV["DEMO_MEDIA_CITY"].presence
- [ ] `shared/app/services/shared/dilla_processor.rb:27` — ENV["SKIP_DILLA_RENDER"].to_s != "" || !available?
- [ ] `shared/app/services/shared/master_client.rb:19` — ENV["MASTER_BRIDGE_TOKEN"].to_s.strip.presence ||
- [ ] `shared/app/services/shared/master_client.rb:20` — ENV["MASTER_INTERNAL_TOKEN"].to_s.strip.presence
- [ ] `shared/app/services/shared/newsletter_composer.rb:123` — def llm_available? = defined?(RubyLLM) && ENV["OPENROUTER_API_KEY"].present?
- [ ] `shared/app/services/shared/newsletter_visuals.rb:68` — token = ENV["REPLICATE_API_TOKEN"].presence || ENV["REPLIGEN_API_TOKEN"].presence
- [ ] `shared/app/services/shared/sso_token.rb:33` — ENV["MASTER_SSO_SECRET"].to_s.strip.presence ||
- [ ] `shared/app/services/shared/sso_token.rb:34` — ENV["MASTER_INTERNAL_TOKEN"].to_s.strip.presence ||
- [ ] `shared/app/services/shared/sso_token.rb:35` — ENV["MASTER_BRIDGE_TOKEN"].to_s.strip.presence
- [ ] `shared/config/boot.rb:3` — ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
- [ ] `shared/config/ci.rb:7` — ENV["GIT_CEILING_DIRECTORIES"] ||= "/"
- [ ] `shared/config/ci.rb:8` — ENV["BUNDLER_AUDIT_UPDATE"] ||= "0"
- [ ] `shared/config/ci.rb:9` — ENV["NPM_CONFIG_CACHE"] ||= File.expand_path("~/.npm")
- [ ] `shared/config/ci.rb:11` — ENV["PUB4_RAILS_ROOT"] ||= monorepo_rails if File.directory?(File.join(monorepo_rails, "shared"))
- [ ] `shared/config/ci.rb:13` — vps_host = ENV["PUB4_CI_GUARD"] == "1" || File.exist?("/var/db/pub4_vps") || File.exist?("/etc/relayd.conf")
- [ ] `shared/config/ci.rb:20` — ENV["PUB4_RAILS_ROOT"] && File.join(ENV["PUB4_RAILS_ROOT"], "tools", "build_all_css.rb"),
- [ ] `shared/config/ci.rb:23` — File.expand_path("pub4-rails/RAILS/tools/build_all_css.rb", ENV["HOME"].to_s)
- [ ] `shared/config/ci.rb:30` — pub4_lib = ENV["PUB4_RAILS_ROOT"] && File.join(ENV["PUB4_RAILS_ROOT"], "shared/lib/pub4")
- [ ] `shared/config/ci.rb:52` — audit = ENV["BUNDLER_AUDIT_UPDATE"] == "1" ? "bundle exec bundler-audit check --update" : "bundle exec bundler
- [ ] `shared/config/environments/production_baseline.rb:7` — config.secret_key_base = ENV.fetch("SECRET_KEY_BASE") if secret_key_base && ENV["SECRET_KEY_BASE"].present?
- [ ] `shared/config/environments/production_baseline.rb:22` — cdn_asset_host = ENV["CDN_ASSET_HOST"].to_s.strip
- [ ] `shared/config/environments/test.rb:18` — config.eager_load = ENV["CI"].present?
- [ ] `shared/config/initializers/content_security_policy.rb:24` — enforce = ENV["PUB4_CSP_ENFORCE"] == "1"
- [ ] `shared/config/initializers/ruby_llm.rb:6` — config.openai_api_key = ENV["OPENAI_API_KEY"] || ENV["RUBY_LLM_OPENAI_API_KEY"]
- [ ] `shared/config/initializers/ruby_llm.rb:7` — config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"] || ENV["RUBY_LLM_ANTHROPIC_API_KEY"]
- [ ] `shared/lib/pub4/ci_guard.rb:18` — return true if ENV["PUB4_CI_GUARD"] == "1"
- [ ] `shared/lib/pub4/ci_guard.rb:19` — return false if ENV["PUB4_CI_GUARD"] == "0"
- [ ] `shared/lib/pub4/ci_guard.rb:117` — user = ENV["USER"] || ENV["LOGNAME"] || "unknown"
- [ ] `shared/lib/pub4/deploy_paths.rb:145` — return true unless ENV["PUB4_RAILS_ROOT"] || ENV["RAILS_ENV"] == "production" || RUBY_PLATFORM.include?("openb
- [ ] `shared/lib/pub4/dialect_token_drift_check.rb:8` — pub4_rails_root = ENV["PUB4_RAILS_ROOT"] || File.expand_path("../../..", __dir__)
- [ ] `shared/lib/pub4/rhythm_lint.rb:52` — ENV["PUB4_RAILS_ROOT"] && File.join(File.dirname(ENV["PUB4_RAILS_ROOT"]), "MASTER/data/design_rules.yml"),
- [ ] `tools/build_all_css.rb:21` — home = ENV["HOME"].to_s
- [ ] `tools/build_all_css.rb:250` — next if File.file?(out) && !build_stale?(app_dir, out) && ENV["PUB4_CSS_FORCE"] != "1"
- [ ] `tools/crawl_browser.rb:68` — options = { public: false, skip_closed: true, force: ENV["PROBE_FORCE_BROWSER"] == "1" }

### rb_puts — 69 · confidence medium

puts in application code. Goes nowhere under a daemonised rc.d service. Use Rails.logger. Law: `soul.absolute.code_rules.SURFACE_ERRORS_FIRST`.

Known false positives in this rule: the scanner excluded `lib/tasks/`,
`tools/` and `gates/` but not `db/seeds.rb` or `*/script/`, where writing to
stdout is the correct behaviour. Roughly a third of the 69 are those. The ones
that matter are in `app/`.

- [ ] `amber/db/seeds.rb:6` — puts "ok demo items=#{Amber::DemoWardrobe.items.count} outfits=#{Amber::DemoWardrobe.outfits.count}"
- [ ] `amber/db/seeds.rb:12` — puts "Seeding Amber with female fashion fictive data..."
- [ ] `amber/db/seeds.rb:41` — puts "Created #{users.size} users"
- [ ] `amber/db/seeds.rb:50` — puts "Created #{items.size} wardrobe items"
- [ ] `amber/db/seeds.rb:67` — puts "Created #{outfits.size} outfits"
- [ ] `amber/db/seeds.rb:81` — puts "Created #{posts.size} posts"
- [ ] `amber/db/seeds.rb:88` — puts "Seeded Amber fictive data successfully."
- [ ] `amber/db/seeds.rb:89` — puts "Users: #{User.count}, Items: #{Item.count}, Outfits: #{Outfit.count}, Posts: #{Post.count}"
- [ ] `amber/db/seeds.rb:95` — puts "\nAugmenting Amber with web-scraped fashion data via Ferrum..."
- [ ] `amber/db/seeds.rb:99` — puts " fashion_seed skipped: #{e.message}"
- [ ] `amber/db/seeds.rb:101` — puts " (Creates Items, Outfits, Posts from Reddit fashion subs like femalefashionadvice.)"
- [ ] `brgen/db/seeds.rb:18` — puts "Production seed: Bergen demo only (skipping Faker flood)."
- [ ] `brgen/db/seeds.rb:25` — puts "Bergen demo: #{Post.where(city: bergen).count} posts"
- [ ] `brgen/db/seeds.rb:31` — puts 'Seeding flagship per-city content (brgen.no, lsangeles.com, amstrdam.nl, oshlo.no)...'
- [ ] `brgen/db/seeds.rb:37` — puts 'Seeding Brgen (core + subapps) with rich fictive data...'
- [ ] `brgen/db/seeds.rb:86` — puts "Created #{users.size + 1} users (incl admin)"
- [ ] `brgen/db/seeds.rb:119` — puts "Created #{posts.size} posts + reactions"
- [ ] `brgen/db/seeds.rb:215` — puts "Live: #{Post.live.count} geo-stamped notes"
- [ ] `brgen/db/seeds.rb:230` — puts "Marketplace: #{stores.size} stores, #{listings.size} listings, some orders"
- [ ] `brgen/db/seeds.rb:254` — puts "Dating: #{dating_profiles.size} profiles, #{Dating::Like.count} likes, #{Dating::Match.count} matches"
- [ ] `brgen/db/seeds.rb:292` — puts "Playlist: #{playlists.size} playlists, tracks, sets"
- [ ] `brgen/db/seeds.rb:373` — puts "Takeaway: #{restaurants.size} restaurants, menu items, orders, reviews, drivers"
- [ ] `brgen/db/seeds.rb:412` — puts "TV: #{channels.size} channels, #{videos.size} videos, broadcasts"
- [ ] `brgen/db/seeds.rb:434` — puts "Maps: #{places.size} places"
- [ ] `brgen/db/seeds.rb:436` — puts 'Maps: skipped (places table not migrated)'
- [ ] `brgen/db/seeds.rb:464` — puts 'Messages: conversations and messages seeded'
- [ ] `brgen/db/seeds.rb:475` — puts "Affiliate: imported #{imported} real TradeDoubler product(s)"
- [ ] `brgen/db/seeds.rb:478` — puts "Affiliate: #{placed} placeholder product(s) (TRADEDOUBLER_TOKEN unset — flagged placeholder: true)"
- [ ] `brgen/db/seeds.rb:500` — puts "\nBrgen + subapps fully seeded with fictive Faker data (scale=#{SEED_SCALE})."
- [ ] `brgen/db/seeds.rb:505` — puts "Users: #{total_users}, Posts: #{Post.count} (Live: #{Post.live.count}), Marketplace listings: #{Marketpl
- [ ] `brgen/db/seeds.rb:506` — puts "Dating profiles: #{Dating::Profile.count}, Takeaway restaurants: #{Takeaway::Restaurant.count}"
- [ ] `brgen/db/seeds.rb:508` — puts "TV channels: #{Tv::Channel.count}, Places: #{place_count}"
- [ ] `brgen/db/seeds.rb:509` — puts 'Ready for demo / development. Use SEED_SCALE=20 for more "millions" impression via volume + counters.'
- [ ] `brgen/db/seeds.rb:512` — puts "\nSeeding Bergen demo content (Norwegian posts, users, media)..."
- [ ] `brgen/db/seeds.rb:516` — puts "Bergen demo: #{Post.where(city: bergen).count} posts, #{Dating::Profile.joins(:user).where(users: { city
- [ ] `brgen/db/seeds.rb:525` — puts "\nAugmenting with web-scraped fictive data via Ferrum (reddit + x)..."
- [ ] `brgen/db/seeds.rb:529` — puts " reddit_seed skipped: #{e.message}"
- [ ] `brgen/db/seeds.rb:534` — puts " x_seed skipped: #{e.message}"
- [ ] `brgen/db/seeds.rb:537` — puts ' (Maps and messages can be augmented via local posts or additional rakes.)'
- [ ] `brgen/db/seeds.rb:538` — puts 'Web-augmented seeding complete.'
- [ ] `brgen/script/profile_cookieless.rb:16` — puts "cache cleared; caching=#{ActionController::Base.perform_caching}"
- [ ] `brgen/script/profile_cookieless.rb:30` — puts format("%-22s p50=%6.0fms min=%5.0fms max=%6.0fms", path, times.sort[runs / 2], times.min, times.max)
- [ ] `brgen/script/profile_cookieless.rb:31` — puts format("cache: %d writes, %d hits across %d cookieless requests", writes, hits, runs)
- [ ] `brgen/script/profile_cookieless.rb:32` — puts format("per request: %.1f writes, %.1f hits", writes.to_f / runs, hits.to_f / runs)
- [ ] `brgen/script/profile_request.rb:27` — puts "seeded community #{community.id} (#{community.slug}) with #{seed} posts"
- [ ] `brgen/script/profile_request.rb:53` — puts
- [ ] `brgen/script/profile_request.rb:54` — puts "#{path} -> #{session.response.status} #{(session.response.body.bytesize / 1024.0).round}KB"
- [ ] `brgen/script/profile_request.rb:55` — puts format("wall: min=%.0fms p50=%.0fms max=%.0fms queries/request=%d",
- [ ] `brgen/script/profile_request.rb:57` — puts
- [ ] `brgen/script/profile_request.rb:58` — puts "top query shapes (per request):"
- [ ] `brgen/script/profile_request.rb:60` — puts format(" %4d %s", n / runs, sql[0, 96])
- [ ] `brgen/script/profile_request.rb:62` — puts
- [ ] `brgen/script/profile_request.rb:63` — puts "slowest partials (ms per request):"
- [ ] `brgen/script/profile_request.rb:65` — puts format(" %7.1f %s", ms / runs, file)
- [ ] `bsdports/db/seeds.rb:37` — puts "Production bsdports seed: platforms + light users only."
- [ ] `bsdports/db/seeds.rb:58` — puts "Seeding BSDports demo activity (scale=#{scale})..."
- [ ] `bsdports/db/seeds.rb:70` — puts "Seeded #{users.size} users."
- [ ] `bsdports/db/seeds.rb:94` — puts "Using #{ports.size} ports for activity seeding."
- [ ] `bsdports/db/seeds.rb:116` — puts "Bsdports demo seed complete: #{users.size} users, #{ports.size} ports, #{total_watches} watches, #{Comme
- [ ] `bsdports/db/seeds.rb:117` — puts "For more: SEED_SCALE=10 bin/rails db:seed (then optionally run ports import rake)."
- [ ] `bsdports/db/seeds.rb:127` — puts "Bsdports base platforms ready."
- [ ] `shared/lib/pub4/adhoc_empty_lint.rb:23` — puts "adhoc_empty_lint: #{findings.size} free-form empty line#{'s' unless findings.size == 1} " \
- [ ] `shared/lib/pub4/adhoc_empty_lint.rb:26` — puts " …" if findings.size > 20
- [ ] `shared/lib/pub4/chrome_i18n_lint.rb:83` — puts "chrome_i18n_lint: #{kind} #{count} (baseline #{baseline})#{note}"
- [ ] `shared/lib/pub4/chrome_i18n_lint.rb:89` — puts " …" if offenders.size > 30
- [ ] `shared/lib/pub4/dialect_token_drift_check.rb:13` — puts "dialect_token_drift_check: ok (shared_chrome/luxury values match design_tokens.yml everywhere)"
- [ ] `shared/lib/pub4/empty_state_lint.rb:31` — puts "empty_state_lint: #{findings.size} render#{'s' unless findings.size == 1} without action:/actions: " \
- [ ] `shared/lib/pub4/fallback_drift_lint.rb:49` — puts "fallback_drift_lint: ok (no stale var() fallbacks found)"
- [ ] `shared/lib/pub4/rhythm_lint.rb:40` — puts "rhythm_lint: ok (#{allowed.size}-value rhythm, all spacing tokens compliant)"

### rb_hardcoded_domain — 66 · confidence medium

Hardcoded external URL. brgen is multi-domain; a literal host defeats DomainRegistry and the 30 configured city TLDs. Law: `brgen/lib/brgen/domain_registry.rb`.

- [ ] `amber/app/services/wardrobe_ai.rb:7` — OPENROUTER_BASE = "https://openrouter.ai/api/v1"
- [ ] `amber/app/services/weather.rb:6` — API_URL = "https://api.open-meteo.com/v1/forecast"
- [ ] `brgen/app/models/affiliate_voucher.rb:63` — track_url: voucher.track_url.presence || voucher.landing_url.presence || "https://brgen.no",
- [ ] `brgen/app/services/amazon_associates.rb:128` — uri = URI("https://#{host}/paapi5/#{operation.downcase}")
- [ ] `brgen/app/services/marketplace/payments/stripe_checkout.rb:12` — API = "https://api.stripe.com/v1/checkout/sessions"
- [ ] `brgen/app/services/marketplace/payments/vipps_checkout.rb:22` — ENV.fetch("VIPPS_API_BASE", "https://apitest.vipps.no")
- [ ] `brgen/app/services/newsletter_edition_builder.rb:143` — "https://brgen.no"
- [ ] `brgen/app/services/reddit_seed.rb:25` — "https://www.reddit.com/r/#{sub}/hot/",
- [ ] `brgen/app/services/tradedoubler.rb:21` — BASE = "https://api.tradedoubler.com/1.0"
- [ ] `brgen/app/services/tradedoubler.rb:22` — LINK_CONVERTER_URL = "https://link.tradedoubler.com/lc"
- [ ] `brgen/config/importmap.rb:12` — pin "@tiptap/core", to: "https://esm.sh/@tiptap/core@2.11.5"
- [ ] `brgen/config/importmap.rb:13` — pin "@tiptap/starter-kit", to: "https://esm.sh/@tiptap/starter-kit@2.11.5"
- [ ] `brgen/config/initializers/omniauth.rb:24` — register_provider.call(self, :snapchat, "SNAPCHAT_CLIENT_ID", "SNAPCHAT_CLIENT_SECRET", scope: "https://auth.s
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:77` — "https://w.soundcloud.com/player/?url=#{CGI.escape(source_url)}"
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:99` — "https://www.youtube.com/embed/#{id}"
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:109` — "https://open.spotify.com/embed/#{parts[-2]}/#{parts[-1]}"
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:119` — "https://whyp.it/tracks/#{$1}/embed"
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:23` — category: "electronics", url: "https://www.elkjop.no/",
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:27` — category: "electronics", url: "https://www.elkjop.no/",
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:31` — category: "electronics", url: "https://www.power.no/",
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:35` — category: "clothing", url: "https://www.xxl.no/",
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:39` — category: "clothing", url: "https://www.xxl.no/",
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:43` — category: "home", url: "https://www.jernia.no/",
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:47` — category: "electronics", url: "https://www.komplett.no/",
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:51` — category: "books", url: "https://www.adlibris.com/no",
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:55` — category: "home", url: "https://www.clasohlson.com/no",
- [ ] `brgen/lib/brgen/affiliate_placeholders.rb:59` — category: "vehicles", url: "https://www.sport1.no/",
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:10` — LOCAL_AUDIO_BASE = ENV.fetch("RADIO_BERGEN_AUDIO_BASE", "https://ai.brgen.no")
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:784` — source_url: "https://www.youtube.com/watch?v=#{row['id']}"
- [ ] `bsdports/app/models/security_advisory.rb:27` — source_url.presence || (identifier.present? ? "https://nvd.nist.gov/vuln/detail/#{identifier}" : nil)
- [ ] `bsdports/app/services/nvd_cve.rb:8` — BASE = "https://services.nvd.nist.gov/rest/json/cves/2.0"
- [ ] `bsdports/app/services/nvd_cve.rb:55` — adv.source_url ||= "https://nvd.nist.gov/vuln/detail/#{id}"
- [ ] `gates/lib/flow_journey.rb:196` — url = "http://#{@host}:#{@port}#{path}"
- [ ] `gates/lib/flow_journey.rb:232` — "http://#{header_host}#{uri.request_uri}"
- [ ] `gates/support/geometry_probe.rb:32` — def url = "http://#{authority}#{path}"
- [ ] `gates/support/guest_flow_persona.rb:131` — uri = URI("http://#{@base_host}:#{@port}#{path}")
- [ ] `shared/app/helpers/schema_helper.rb:29` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/schema_helper.rb:88` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/schema_helper.rb:103` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/schema_helper.rb:113` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/schema_helper.rb:126` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/schema_helper.rb:144` — "availability" => listing.try(:sold?) ? "https://schema.org/OutOfStock" : "https://schema.org/InStock",
- [ ] `shared/app/helpers/schema_helper.rb:158` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/schema_helper.rb:170` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/schema_helper.rb:191` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/schema_helper.rb:200` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/shared/seo_kit.rb:36` — "https://www.amazon.com/dp/#{target}?tag=#{AMAZON_TAG}"
- [ ] `shared/app/helpers/shared/seo_kit.rb:44` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/shared/seo_kit.rb:54` — "@context" => "https://schema.org",
- [ ] `shared/app/helpers/shared/seo_kit.rb:69` — "@context" => "https://schema.org",
- [ ] `shared/app/services/scrape.rb:17` — ENDPOINT = URI("https://openrouter.ai/api/v1/chat/completions")
- [ ] `shared/app/services/shared/amazon_marketplace.rb:135` — url = "https://www.#{host_for(market)}/dp/#{id}"
- [ ] `shared/app/services/shared/demo_media.rb:18` — url = "https://picsum.photos/seed/#{seed}/#{width}/#{height}"
- [ ] `shared/app/services/shared/demo_media.rb:72` — ENV.fetch("DEMO_MEDIA_USER_AGENT", "BrgenDemoSeed/1.0 (+https://brgen.no; demo content)")
- [ ] `shared/app/services/shared/newsletter_visuals.rb:83` — uri = URI("https://api.replicate.com/v1/models/#{REPLIGEN_MODEL}/predictions")
- [ ] `shared/app/services/shared/sitemap_builder.rb:27` — xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
- [ ] `shared/config/importmap_baseline.rb:19` — pin "@rails/request.js", to: "https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/dist/requestjs.js"
- [ ] `shared/config/importmap_baseline.rb:37` — pin "date-fns", to: "https://unpkg.com/date-fns@4.4.0/index.js"
- [ ] `shared/config/importmap_baseline.rb:61` — pin "web-vitals", to: "https://cdn.jsdelivr.net/npm/web-vitals@4.2.4/dist/web-vitals.js"
- [ ] `shared/config/importmap_baseline.rb:70` — pin "swiper/bundle", to: "https://cdn.jsdelivr.net/npm/swiper@11.1.15/swiper-bundle.min.mjs"
- [ ] `shared/config/initializers/content_security_policy.rb:12` — policy.font_src :self, :https, :data, "https://fonts.gstatic.com"
- [ ] `shared/config/initializers/master_web.rb:3` — Rails.application.config.x.master_web_url = ENV.fetch("MASTER_WEB_URL", "https://ai.brgen.no")
- [ ] `shared/config/initializers/omniauth.rb:27` — scope: "https://auth.snapchat.com/oauth2/api/user.display_name")
- [ ] `shared/lib/omniauth/strategies/vipps.rb:10` — site: "https://api.vipps.no",
- [ ] `tools/build_all_css.rb:41` — FONT_CDN = "https://cdn.jsdelivr.net/gh/Nick2bad4u/nerd-fonts-woff2@v1.0.5/fonts/woff2/JetBrainsMono/Ligatures
- [ ] `tools/crawl_support.rb:61` — "https://#{apps[name]["domain"]}"

### rb_rescue_nil — 21 · confidence high

rescue that returns nil. The failure becomes indistinguishable from an empty result — the exact shape of the dead-wiring bugs this repo keeps finding. Law: `soul.absolute.code_rules.FAIL_VISIBLY`.

- [ ] `brgen/app/helpers/application_helper.rb:210` — rescue StandardError
- [ ] `brgen/app/helpers/application_helper.rb:259` — rescue StandardError
- [ ] `brgen/app/models/affiliate_conversion.rb:103` — rescue StandardError
- [ ] `brgen/app/models/channel_presence.rb:76` — rescue StandardError
- [ ] `brgen/app/models/channel_presence.rb:92` — rescue StandardError
- [ ] `brgen/app/services/tradedoubler.rb:180` — rescue StandardError
- [ ] `brgen/app/services/tradedoubler.rb:529` — rescue StandardError
- [ ] `brgen/lib/brgen/irc/server.rb:42` — rescue StandardError
- [ ] `gates/lib/deploy_drift.rb:122` — rescue StandardError
- [ ] `gates/lib/surface_schema.rb:100` — rescue StandardError
- [ ] `gates/lib/visual_quality.rb:208` — rescue StandardError
- [ ] `gates/support/cdp_session.rb:108` — rescue StandardError
- [ ] `gates/support/cdp_session.rb:117` — rescue StandardError
- [ ] `gates/support/cdp_session.rb:291` — rescue StandardError
- [ ] `gates/support/cdp_session.rb:362` — rescue StandardError
- [ ] `gates/support/geometry_autofix.rb:222` — rescue StandardError
- [ ] `gates/support/geometry_autofix.rb:233` — rescue StandardError
- [ ] `shared/app/helpers/schema_helper.rb:223` — rescue StandardError
- [ ] `shared/app/helpers/schema_helper.rb:229` — rescue StandardError
- [ ] `shared/app/services/shared/newsletter_composer.rb:158` — rescue StandardError
- [ ] `shared/app/services/shared/newsletter_composer.rb:166` — rescue StandardError

### rb_time_now — 18 · confidence high

Time.now / Date.today / DateTime.now. Timezone-unaware; use Time.current / Date.current. Law: `soul.absolute.code_rules.RTFM_FIRST`.

- [ ] `amber/app/controllers/internal_controller.rb:9` — generated_at: Time.now.utc.iso8601,
- [ ] `amber/app/models/planned_outfit.rb:10` — scope :upcoming, -> { where("planned_date >= ?", Date.today).order(:planned_date) }
- [ ] `amber/app/services/wardrobe_ai.rb:38` — Age: #{item.purchase_date ? "#{((Date.today - item.purchase_date) / 365).to_i} years" : "unknown"}
- [ ] `brgen/app/controllers/application_controller.rb:45` — "[tenant_access] tenant=#{tenant} ip=#{request.remote_ip} path=#{request.fullpath} at=#{Time.now.to_i}"
- [ ] `brgen/app/controllers/internal_controller.rb:11` — generated_at: Time.now.utc.iso8601,
- [ ] `brgen/app/models/conversation.rb:165` — conversation_participants.find_by(user:)&.update!(last_read_at: Time.now)
- [ ] `brgen/app/models/message.rb:87` — message_receipts.create!(user: u, delivered_at: Time.now)
- [ ] `brgen/app/services/amazon_associates.rb:145` — now = Time.now.utc
- [ ] `bsdports/app/controllers/internal_controller.rb:9` — generated_at: Time.now.utc.iso8601,
- [ ] `gates/lib/page_simulation.rb:45` — "generated_at" => Time.now.utc.iso8601,
- [ ] `gates/visual_contract.rb:190` — File.write(path, JSON.pretty_generate(generated_at: Time.now.utc.iso8601, results:) + "\n")
- [ ] `shared/app/services/shared/dilla_processor.rb:58` — kept = File.join(Dir.tmpdir, "dilla_#{Process.pid}_#{Time.now.to_i}.mp3")
- [ ] `shared/app/services/shared/newsletter_composer.rb:97` — Date.today
- [ ] `shared/app/services/shared/sso_token.rb:51` — "exp" => Time.now.to_i + ttl.to_i,
- [ ] `shared/app/services/shared/sso_token.rb:52` — "iat" => Time.now.to_i,
- [ ] `shared/app/services/shared/sso_token.rb:72` — return nil if payload["exp"].to_i < Time.now.to_i
- [ ] `shared/app/services/shared/sso_token.rb:90` — ttl = [payload["exp"].to_i - Time.now.to_i, 0].max + NONCE_GRACE
- [ ] `shared/app/services/shared/sso_token.rb:117` — now = Time.now.to_i

### rb_update_column — 12 · confidence high

update_column / update_columns. Skips updated_at, so `cache [record, ...]` fragments never bust. Known pub4 bug shape: the runner shows the new value and the page shows the old one. Law: `MASTER/DEBT.md`.

- [ ] `brgen/app/controllers/locations_controller.rb:22` — me.update_columns(latitude: lat, longitude: lng, location_updated_at: Time.current)
- [ ] `brgen/app/jobs/user_purge_job.rb:34` — user.update_columns(attrs)
- [ ] `brgen/app/models/message.rb:97` — update_column(:expires_at, expiry) if expires_at.nil?
- [ ] `brgen/app/models/user.rb:112` — update_columns(email_verification_token: token, updated_at: Time.current)
- [ ] `brgen/app/models/user.rb:117` — update_columns(email_verified_at: Time.current, email_verification_token: nil, updated_at: Time.current)
- [ ] `brgen/app/models/user.rb:134` — update_column(:karma, score)
- [ ] `brgen/app/services/moderation_workflow.rb:69` — content.update_columns(removed_at: Time.current, updated_at: Time.current)
- [ ] `brgen/db/seeds.rb:315` — ).tap { |restaurant| restaurant.update_column(:city, city_label) }
- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:73` — update_columns(rating: reviews.average(:rating)&.round(2) || 0)
- [ ] `brgen/engines/takeaway/app/models/takeaway/restaurant.rb:57` — update_columns(rating: avg&.round(1) || 0)
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:710` — playlist.update_column(:tracks_count, playlist.tracks.count) if playlist.tracks_count != playlist.tracks.count
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:848` — restaurant.update_column(:city, @city.name) if restaurant.has_attribute?(:city)

### rb_rescue_inline_nil — 2 · confidence high

`rescue nil` modifier. Same rule, terser. Law: `soul.absolute.code_rules.FAIL_VISIBLY`.

- [ ] `brgen/lib/brgen/irc/server.rb:53` — socket.close rescue nil
- [ ] `shared/app/services/shared/dilla_processor.rb:129` — Process.kill("TERM", wait_thr.pid) rescue nil

### time_now — 1 · confidence high

Time.now / Date.today in a view. Ignores Rails' timezone; use Time.current. Law: `soul.absolute.code_rules.RTFM_FIRST`.

- [ ] `amber/app/views/planned_outfits/index.html.erb:6` — <%= f.date_field :planned_date, min: Date.today, class: "input" %>

## Models and data integrity — 190 items

### model_assoc_no_inverse — 104 · confidence low

has_many/has_one with no inverse_of. Rails cannot always infer it; without it in-memory parent/child identity diverges and strict_loading fires on a record you already hold. Law: `WIRING_NOTES strict loading`.

- [ ] `amber/app/models/creator_profile.rb:1` — has_many :creator_wardrobe_items
- [ ] `amber/app/models/item.rb:1` — has_one :declutter_outcome
- [ ] `amber/app/models/item.rb:1` — has_many :outfit_items
- [ ] `amber/app/models/item.rb:1` — has_many :wear_logs
- [ ] `amber/app/models/item.rb:1` — has_many :affiliate_links
- [ ] `amber/app/models/item.rb:1` — has_many :declutter_challenges
- [ ] `amber/app/models/item.rb:1` — has_one :sustainability_metric
- [ ] `amber/app/models/item.rb:1` — has_one :garment_embedding
- [ ] `amber/app/models/item.rb:1` — has_one :declutter_review
- [ ] `amber/app/models/outfit.rb:1` — has_many :outfit_items
- [ ] `amber/app/models/packing_list.rb:1` — has_many :packing_list_items
- [ ] `amber/app/models/user.rb:1` — has_many :recommendations
- [ ] `amber/app/models/user.rb:1` — has_many :identity_verifications
- [ ] `amber/app/models/user.rb:1` — has_many :consent_events
- [ ] `amber/app/models/user.rb:1` — has_many :declutter_reviews
- [ ] `amber/app/models/user.rb:1` — has_many :declutter_challenges
- [ ] `amber/app/models/user.rb:1` — has_many :declutter_outcomes
- [ ] `amber/app/models/user.rb:1` — has_many :connections_requested
- [ ] `amber/app/models/user.rb:1` — has_many :connections_received
- [ ] `amber/app/models/user.rb:1` — has_many :live_streams
- [ ] `amber/app/models/user.rb:1` — has_many :sent_messages
- [ ] `amber/app/models/user.rb:1` — has_many :follows_as_follower
- [ ] `amber/app/models/user.rb:1` — has_many :follows_as_followee
- [ ] `amber/app/models/user.rb:1` — has_many :received_messages
- [ ] `amber/app/models/user.rb:1` — has_one :profile
- [ ] `amber/app/models/user.rb:1` — has_one :creator_profile
- [ ] `amber/app/models/user.rb:1` — has_one :privacy_setting
- [ ] `amber/app/models/user.rb:1` — has_many :posts
- [ ] `amber/app/models/user.rb:1` — has_many :comments
- [ ] `amber/app/models/user.rb:1` — has_many :items
- [ ] `amber/app/models/user.rb:1` — has_many :outfits
- [ ] `amber/app/models/user.rb:1` — has_many :planned_outfits
- [ ] `amber/app/models/user.rb:1` — has_many :style_preferences
- [ ] `amber/app/models/user.rb:1` — has_many :packing_lists
- [ ] `brgen/app/models/city.rb:1` — has_many :places
- [ ] `brgen/app/models/city.rb:1` — has_many :users
- [ ] `brgen/app/models/city.rb:1` — has_many :neighborhoods
- [ ] `brgen/app/models/city.rb:1` — has_many :posts
- [ ] `brgen/app/models/community.rb:1` — has_many :posts
- [ ] `brgen/app/models/community.rb:1` — has_many :community_memberships
- [ ] `brgen/app/models/conversation.rb:1` — has_many :typing_indicators
- [ ] `brgen/app/models/conversation.rb:1` — has_many :conversation_participants
- [ ] `brgen/app/models/conversation.rb:1` — has_many :messages
- [ ] `brgen/app/models/hashtag.rb:1` — has_many :taggings
- [ ] `brgen/app/models/identity_provider.rb:1` — has_many :external_identities
- [ ] `brgen/app/models/message.rb:1` — has_many :message_receipts
- [ ] `brgen/app/models/neighborhood.rb:1` — has_many :places
- [ ] `brgen/app/models/partner/membership.rb:1` — has_many :clicks
- [ ] `brgen/app/models/partner/membership.rb:1` — has_many :conversions
- [ ] `brgen/app/models/partner/program.rb:1` — has_many :memberships
- [ ] `brgen/app/models/place.rb:1` — has_many :place_check_ins
- [ ] `brgen/app/models/user.rb:1` — has_many :community_memberships
- [ ] `brgen/app/models/user.rb:1` — has_many :blocks_as_blocker
- [ ] `brgen/app/models/user.rb:1` — has_many :bookmarks
- [ ] `brgen/engines/marketplace/app/models/marketplace/category.rb:1` — has_many :children
- [ ] `brgen/engines/marketplace/app/models/marketplace/category.rb:1` — has_many :listings
- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:1` — has_many :favorites
- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:1` — has_many :deals
- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:1` — has_many :reviews
- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:1` — has_many :orders
- [ ] `brgen/engines/marketplace/app/models/marketplace/store.rb:1` — has_many :listings
- [ ] `brgen/engines/playlist/app/models/playlist/listening_party.rb:1` — has_many :party_messages
- [ ] `brgen/engines/playlist/app/models/playlist/playlist.rb:1` — has_many :playlist_tracks
- [ ] `brgen/engines/playlist/app/models/playlist/playlist.rb:1` — has_many :collaborations
- [ ] `brgen/engines/playlist/app/models/playlist/playlist.rb:1` — has_many :dilla_sketches
- [ ] `brgen/engines/playlist/app/models/playlist/set.rb:1` — has_many :set_tracks
- [ ] `brgen/engines/playlist/app/models/playlist/set.rb:1` — has_many :collaborations
- [ ] `brgen/engines/playlist/app/models/playlist/set.rb:1` — has_many :dilla_sketches
- [ ] `brgen/engines/playlist/app/models/playlist/set.rb:1` — has_many :likes
- [ ] `brgen/engines/playlist/app/models/playlist/set.rb:1` — has_one :listening_party
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :playlist_tracks
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :listens
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :timestamped_comments
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :audio_versions
- [ ] `brgen/engines/takeaway/app/models/takeaway/delivery_driver.rb:1` — has_many :orders
- [ ] `brgen/engines/takeaway/app/models/takeaway/order.rb:1` — has_many :order_items
- [ ] `brgen/engines/takeaway/app/models/takeaway/order.rb:1` — has_many :reviews
- [ ] `brgen/engines/takeaway/app/models/takeaway/restaurant.rb:1` — has_many :favorites
- [ ] `brgen/engines/takeaway/app/models/takeaway/restaurant.rb:1` — has_many :menu_items
- [ ] `brgen/engines/takeaway/app/models/takeaway/restaurant.rb:1` — has_many :orders
- [ ] `brgen/engines/takeaway/app/models/takeaway/restaurant.rb:1` — has_many :reviews
- [ ] `brgen/engines/tv/app/models/tv/channel.rb:1` — has_many :videos
- [ ] `brgen/engines/tv/app/models/tv/channel.rb:1` — has_many :shows
- [ ] `brgen/engines/tv/app/models/tv/channel.rb:1` — has_many :broadcasts
- [ ] `brgen/engines/tv/app/models/tv/channel.rb:1` — has_many :subscriptions
- [ ] `brgen/engines/tv/app/models/tv/live_stream.rb:1` — has_many :stream_chats
- [ ] `brgen/engines/tv/app/models/tv/show.rb:1` — has_many :episodes
- [ ] `brgen/engines/tv/app/models/tv/video.rb:1` — has_many :view_events
- [ ] `brgen/engines/tv/app/models/tv/video.rb:1` — has_many :video_notes
- [ ] `brgen/engines/tv/app/models/tv/video.rb:1` — has_many :comments
- [ ] `bsdports/app/models/category.rb:1` — has_many :ports
- [ ] `bsdports/app/models/maintainer.rb:1` — has_many :ports
- [ ] `bsdports/app/models/platform.rb:1` — has_many :categories
- [ ] `bsdports/app/models/platform.rb:1` — has_many :ports
- [ ] `bsdports/app/models/platform.rb:1` — has_many :import_runs
- [ ] `bsdports/app/models/port.rb:1` — has_many :dependencies
- [ ] `bsdports/app/models/port.rb:1` — has_many :dependents
- [ ] `bsdports/app/models/port.rb:1` — has_many :port_updates
- [ ] `bsdports/app/models/port.rb:1` — has_many :watches
- [ ] `bsdports/app/models/port.rb:1` — has_many :comments
- [ ] `bsdports/app/models/port.rb:1` — has_many :security_advisories
- [ ] `bsdports/app/models/user.rb:1` — has_many :sessions
- [ ] `bsdports/app/models/user.rb:1` — has_many :watches
- [ ] `bsdports/app/models/user.rb:1` — has_many :comments

### model_no_scope — 67 · confidence low

Model with no named scope. Query intent lives in controllers instead of the model. Boy Scout item, not a defect. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `amber/app/models/affiliate_link.rb:1` — affiliate_link.rb
- [ ] `amber/app/models/comment.rb:1` — comment.rb
- [ ] `amber/app/models/consent_event.rb:1` — consent_event.rb
- [ ] `amber/app/models/creator_wardrobe_item.rb:1` — creator_wardrobe_item.rb
- [ ] `amber/app/models/declutter_outcome.rb:1` — declutter_outcome.rb
- [ ] `amber/app/models/declutter_review.rb:1` — declutter_review.rb
- [ ] `amber/app/models/follow.rb:1` — follow.rb
- [ ] `amber/app/models/garment_embedding.rb:1` — garment_embedding.rb
- [ ] `amber/app/models/identity_verification.rb:1` — identity_verification.rb
- [ ] `amber/app/models/outfit_item.rb:1` — outfit_item.rb
- [ ] `amber/app/models/packing_list.rb:1` — packing_list.rb
- [ ] `amber/app/models/packing_list_item.rb:1` — packing_list_item.rb
- [ ] `amber/app/models/privacy_setting.rb:1` — privacy_setting.rb
- [ ] `amber/app/models/profile.rb:1` — profile.rb
- [ ] `amber/app/models/session.rb:1` — session.rb
- [ ] `amber/app/models/style_preference.rb:1` — style_preference.rb
- [ ] `amber/app/models/sustainability_metric.rb:1` — sustainability_metric.rb
- [ ] `amber/app/models/user.rb:1` — user.rb
- [ ] `brgen/app/models/account_merge.rb:1` — account_merge.rb
- [ ] `brgen/app/models/block.rb:1` — block.rb
- [ ] `brgen/app/models/bookmark.rb:1` — bookmark.rb
- [ ] `brgen/app/models/city.rb:1` — city.rb
- [ ] `brgen/app/models/community_membership.rb:1` — community_membership.rb
- [ ] `brgen/app/models/external_identity.rb:1` — external_identity.rb
- [ ] `brgen/app/models/follow.rb:1` — follow.rb
- [ ] `brgen/app/models/identity_assurance.rb:1` — identity_assurance.rb
- [ ] `brgen/app/models/identity_provider.rb:1` — identity_provider.rb
- [ ] `brgen/app/models/mention.rb:1` — mention.rb
- [ ] `brgen/app/models/moderation_flag.rb:1` — moderation_flag.rb
- [ ] `brgen/app/models/neighborhood.rb:1` — neighborhood.rb
- [ ] `brgen/app/models/place.rb:1` — place.rb
- [ ] `brgen/app/models/push_subscription.rb:1` — push_subscription.rb
- [ ] `brgen/app/models/reaction.rb:1` — reaction.rb
- [ ] `brgen/app/models/reputation_score.rb:1` — reputation_score.rb
- [ ] `brgen/app/models/session.rb:1` — session.rb
- [ ] `brgen/app/models/stream.rb:1` — stream.rb
- [ ] `brgen/app/models/tagging.rb:1` — tagging.rb
- [ ] `brgen/app/models/trust_signal.rb:1` — trust_signal.rb
- [ ] `brgen/app/models/user.rb:1` — user.rb
- [ ] `brgen/app/models/vote.rb:1` — vote.rb
- [ ] `brgen/engines/dating/app/models/dating/dislike.rb:1` — dislike.rb
- [ ] `brgen/engines/dating/app/models/dating/like.rb:1` — like.rb
- [ ] `brgen/engines/marketplace/app/models/marketplace/listing_favorite.rb:1` — listing_favorite.rb
- [ ] `brgen/engines/marketplace/app/models/marketplace/order.rb:1` — order.rb
- [ ] `brgen/engines/marketplace/app/models/marketplace/review.rb:1` — review.rb
- [ ] `brgen/engines/marketplace/app/models/marketplace/saved_search.rb:1` — saved_search.rb
- [ ] `brgen/engines/playlist/app/models/playlist/collaboration.rb:1` — collaboration.rb
- [ ] `brgen/engines/playlist/app/models/playlist/like.rb:1` — like.rb
- [ ] `brgen/engines/playlist/app/models/playlist/listen.rb:1` — listen.rb
- [ ] `brgen/engines/playlist/app/models/playlist/playlist_track.rb:1` — playlist_track.rb
- [ ] `brgen/engines/playlist/app/models/playlist/set_track.rb:1` — set_track.rb
- [ ] `brgen/engines/takeaway/app/models/takeaway/favorite_restaurant.rb:1` — favorite_restaurant.rb
- [ ] `brgen/engines/takeaway/app/models/takeaway/order_item.rb:1` — order_item.rb
- [ ] `brgen/engines/takeaway/app/models/takeaway/review.rb:1` — review.rb
- [ ] `brgen/engines/tv/app/models/tv/comment.rb:1` — comment.rb
- [ ] `brgen/engines/tv/app/models/tv/episode.rb:1` — episode.rb
- [ ] `brgen/engines/tv/app/models/tv/subscription.rb:1` — subscription.rb
- [ ] `brgen/engines/tv/app/models/tv/view_event.rb:1` — view_event.rb
- [ ] `bsdports/app/models/category.rb:1` — category.rb
- [ ] `bsdports/app/models/comment.rb:1` — comment.rb
- [ ] `bsdports/app/models/session.rb:1` — session.rb
- [ ] `bsdports/app/models/user.rb:1` — user.rb
- [ ] `bsdports/app/models/watch.rb:1` — watch.rb
- [ ] `shared/app/models/application_record.rb:1` — application_record.rb
- [ ] `shared/app/models/concerns/shared/sluggable.rb:1` — sluggable.rb
- [ ] `shared/app/models/shared/anonymous_post_quota.rb:1` — anonymous_post_quota.rb
- [ ] `shared/app/models/shared/reaction.rb:1` — reaction.rb

### model_no_validations — 11 · confidence medium

Model with no validations. Nothing stops a blank or duplicate row. Law: `rams_checklist.honest`.

- [ ] `amber/app/models/privacy_setting.rb:1` — privacy_setting.rb
- [ ] `brgen/app/models/mention.rb:1` — mention.rb
- [ ] `brgen/app/models/message_receipt.rb:1` — message_receipt.rb
- [ ] `brgen/app/models/session.rb:1` — session.rb
- [ ] `brgen/app/models/stream.rb:1` — stream.rb
- [ ] `brgen/app/models/tagging.rb:1` — tagging.rb
- [ ] `brgen/app/models/typing_indicator.rb:1` — typing_indicator.rb
- [ ] `brgen/engines/playlist/app/models/playlist/listen.rb:1` — listen.rb
- [ ] `brgen/engines/tv/app/models/tv/view_event.rb:1` — view_event.rb
- [ ] `bsdports/app/models/session.rb:1` — session.rb
- [ ] `shared/app/models/application_record.rb:1` — application_record.rb

### model_has_many_no_dependent — 8 · confidence high

has_many with no dependent: option. Deleting the parent orphans children or trips an FK constraint. Law: `rams_checklist.thorough`.

- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:1` — has_many :orders
- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:1` — has_many :favorites
- [ ] `brgen/engines/playlist/app/models/playlist/playlist.rb:1` — has_many :playlist_tracks
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :audio_versions
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :listens
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :playlist_tracks
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :timestamped_comments
- [ ] `bsdports/app/models/port.rb:1` — has_many :dependents

## UX and product truth — 60 items

### delete_no_confirm — 31 · confidence medium

Destructive link with no confirmation. rams_checklist.honest — an irreversible action needs an interstitial. Law: `rams_checklist.honest`.

- [ ] `amber/app/views/creator_profiles/edit.html.erb:14` — <%= button_to t("actions.remove"), creator_profile_wardrobe_item_path(handle: @profile.han
- [ ] `amber/app/views/home/index.html.erb:37` — <%= button_to t("actions.remove"), planned_outfit_path(plan), method: :delete, class: "btn
- [ ] `amber/app/views/items/show.html.erb:91` — <%= button_to t("actions.remove"), item_affiliate_link_path(@item, link), method: :delete,
- [ ] `amber/app/views/layouts/application.html.erb:55` — <%= link_to t("nav.sign_out"), session_path, data: { turbo_method: :delete }, class: "btn-
- [ ] `amber/app/views/planned_outfits/index.html.erb:19` — <%= button_to t("actions.remove"), planned_outfit_path(plan), method: :delete, class: "btn
- [ ] `amber/app/views/shared/_sidebar_nav.html.erb:31` — <%= link_to session_path, class: "nav-item", data: { turbo_method: :delete, turbo_prefetch
- [ ] `amber/app/views/users/show.html.erb:7` — <%= button_to t("actions.unfollow"), unfollow_user_path(@user), method: :delete, class: "b
- [ ] `brgen/app/views/communities/show.html.erb:10` — <%= button_to t("community.leave", default: "Leave"), leave_community_path(@community), me
- [ ] `brgen/app/views/layouts/application.html.erb:179` — <%= link_to t("nav.sign_out"), main_app.session_path, data: { turbo_method: :delete, turbo
- [ ] `brgen/app/views/layouts/application.html.erb:292` — <%= link_to t("nav.sign_out"), main_app.session_path, data: { turbo_method: :delete, turbo
- [ ] `brgen/app/views/posts/show.html.erb:80` — <%= button_to t("bookmark.unsave", default: "Unsave"), unbookmark_post_path(@post), method
- [ ] `brgen/app/views/shared/_follow_button.html.erb:4` — <%= button_to t("actions.unfollow"), main_app.unfollow_user_path(user), method: :delete,
- [ ] `brgen/app/views/users/show.html.erb:14` — <%= button_to t("block.unblock", default: "Unblock"), unblock_user_path(@user), method: :d
- [ ] `brgen/engines/dating/app/views/dating/home/_card.html.erb:42` — <%= button_to t("block.unblock", default: "Unblock"), main_app.unblock_user_path(profile.u
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/_favorite_button.html.erb:8` — method: :delete,
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/show.html.erb:129` — <%= button_to t("marketplace.remove_listing"), listing_path(@listing), method: :delete, cl
- [ ] `brgen/engines/marketplace/app/views/marketplace/saved_searches/index.html.erb:16` — <%= button_to t("actions.delete"), saved_search_path(saved_search), method: :delete, class
- [ ] `brgen/engines/playlist/app/views/playlist/listening_parties/show.html.erb:11` — <%= button_to t("playlist.end_party"), set_listening_party_path(@set), method: :delete, cl
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:30` — <%= button_to t("actions.unlike"), set_like_path(@set), method: :delete, class: "btn btn-g
- [ ] `brgen/engines/playlist/app/views/playlist/sets/show.html.erb:74` — <%= button_to t("actions.remove"), set_track_path(@set, set_track), method: :delete, class
- [ ] `brgen/engines/playlist/app/views/playlist/shared/_collaborators.html.erb:13` — <%= button_to t("actions.remove"), collaboration_path_proc.call(c), method: :delete, class
- [ ] `brgen/engines/playlist/app/views/playlist/shared/_dilla_sketches.html.erb:31` — <%= button_to t("actions.remove"), destroy_path_proc.call(sk), method: :delete, class: "bt
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:9` — <%= button_to t("takeaway.unsave"), restaurant_favorite_restaurant_path(@restaurant), meth
- [ ] `brgen/engines/tv/app/views/tv/channels/show.html.erb:14` — <%= button_to t("tv.unsubscribe"), unsubscribe_channel_path(@channel), method: :delete, cl
- [ ] `brgen/engines/tv/app/views/tv/videos/show.html.erb:60` — <%= button_to t("tv.unsubscribe"), unsubscribe_channel_path(@video.channel), method: :dele
- [ ] `bsdports/app/views/comments/_comment.html.erb:5` — <%= button_to "Delete", port_comment_path(comment.port || @port, comment), method: :delete
- [ ] `bsdports/app/views/layouts/application.html.erb:48` — <%= link_to t("nav.sign_out"), session_path, class: "btn-ghost", data: { turbo_method: :de
- [ ] `bsdports/app/views/ports/_watch_toggle.html.erb:3` — <%= button_to "Unwatch", unwatch_port_path(port), method: :delete, data: { turbo_stream: t
- [ ] `shared/app/views/comments/_comment.html.erb:36` — method: :delete,
- [ ] `shared/frontend/layouts/_nav.html.erb:22` — method: :delete,
- [ ] `shared/frontend/layouts/_nav.html.erb:24` — data: { turbo_method: :delete, turbo_prefetch: false } %>

### list_no_empty_state — 29 · confidence medium

View iterates a collection with no empty branch. ui_polish.empty_requires_action: an empty list must render the shared empty_state partial with a CTA. Law: `ui_polish.chrome_i18n.empty_requires_action`.

- [ ] `amber/app/views/ai/occasion_map.html.erb:1` — iterates without empty branch
- [ ] `amber/app/views/ai/packing_list.html.erb:1` — iterates without empty branch
- [ ] `amber/app/views/items/index.html.erb:1` — iterates without empty branch
- [ ] `amber/app/views/outfits/_outfit.html.erb:1` — iterates without empty branch
- [ ] `amber/app/views/outfits/dressing_room.html.erb:1` — iterates without empty branch
- [ ] `amber/app/views/users/show.html.erb:1` — iterates without empty branch
- [ ] `brgen/app/views/channels/_roster.html.erb:1` — iterates without empty branch
- [ ] `brgen/app/views/channels/index.html.erb:1` — iterates without empty branch
- [ ] `brgen/app/views/conversations/show.html.erb:1` — iterates without empty branch
- [ ] `brgen/app/views/messages/_reactions.html.erb:1` — iterates without empty branch
- [ ] `brgen/app/views/newsletter_mailer/edition.text.erb:1` — iterates without empty branch
- [ ] `brgen/app/views/posts/edit.html.erb:1` — iterates without empty branch
- [ ] `brgen/app/views/posts/index.html.erb:1` — iterates without empty branch
- [ ] `brgen/app/views/posts/new.html.erb:1` — iterates without empty branch
- [ ] `brgen/app/views/shared/_nav_swiper.html.erb:1` — iterates without empty branch
- [ ] `brgen/engines/dating/app/views/dating/profiles/edit.html.erb:1` — iterates without empty branch
- [ ] `brgen/engines/marketplace/app/views/marketplace/_nav_bar.html.erb:1` — iterates without empty branch
- [ ] `brgen/engines/marketplace/app/views/marketplace/listings/new.html.erb:1` — iterates without empty branch
- [ ] `brgen/engines/playlist/app/views/playlist/listening_parties/show.html.erb:1` — iterates without empty branch
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/_radio_tunnel.html.erb:1` — iterates without empty branch
- [ ] `brgen/engines/takeaway/app/views/takeaway/_nav_bar.html.erb:1` — iterates without empty branch
- [ ] `brgen/engines/takeaway/app/views/takeaway/orders/index.html.erb:1` — iterates without empty branch
- [ ] `brgen/engines/tv/app/views/tv/channels/_channel_videos.html.erb:1` — iterates without empty branch
- [ ] `brgen/engines/tv/app/views/tv/videos/new.html.erb:1` — iterates without empty branch
- [ ] `shared/app/views/notifications/read_all.turbo_stream.erb:1` — iterates without empty branch
- [ ] `shared/app/views/shared/_icon_sprite.html.erb:1` — iterates without empty branch
- [ ] `shared/app/views/shared/_reaction_bar.html.erb:1` — iterates without empty branch
- [ ] `shared/frontend/examples.html.erb:1` — iterates without empty branch
- [ ] `shared/frontend/layouts/_footer.html.erb:1` — iterates without empty branch

## Dead wiring — declarations with no reader — 192 items

### unused_css_class — 102 · confidence low

SCSS class with no ERB/JS/Ruby consumer. Dead CSS. Confirm it is not built dynamically before deleting. Law: `aesthetic_rules.FLAT_HIERARCHY aggressive_merge`.

- [ ] `amber/app/assets/stylesheets/_brand.scss:285` — .logo-bar defined 1x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_brand.scss:376` — .edge-swiper-grip defined 2x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_brand.scss:387` — .sustainability-meter defined 1x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_brand.scss:388` — .sustainability-grade defined 2x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_brand.scss:404` — .look-rail defined 3x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_brand.scss:44` — .amber-logo-gradient defined 2x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_editorial.scss:30` — .feed-post-meta-author defined 1x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_items.scss:106` — .item-photos defined 2x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_items.scss:193` — .btn-joy defined 1x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_items.scss:47` — .pairing-rationale defined 1x, no ERB/JS/RB consumer
- [ ] `amber/app/assets/stylesheets/_items_luxury.scss:7` — .luxury-card defined 9x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_affiliate.scss:39` — .mt-16 defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_affiliate.scss:45` — .text-xs defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_affiliate.scss:65` — .offline-empty defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_affiliate.scss:67` — .offline-empty__actions defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_affiliate.scss:71` — .dialog-form defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:10` — .city-home-intro-title defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:18` — .city-home-intro-body defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:212` — .local-feed-intro defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:249` — .duration-chip defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:25` — .city-home-paths defined 4x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:256` — .card-embed defined 6x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:258` — .restaurant-card defined 3x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:259` — .listing-card defined 3x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:264` — .video-card defined 3x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:290` — .article-body defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:46` — .city-home-sep defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:51` — .city-home-note defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:56` — .city-home-ai defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:60` — .city-home-ai-link defined 3x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_dating_media.scss:21` — .match-avatar defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_feed_post.scss:135` — .overflow_panel defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_maps.scss:70` — .maplibregl-popup-content defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_maps.scss:89` — .match-overlay__card defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_maps.scss:98` — .match-overlay__eyebrow defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_marketplace.scss:3` — .marketplace-page-header defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_marketplace.scss:38` — .deal-search defined 6x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_marketplace.scss:7` — .marketplace-page-header-row defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_marketplace_cards.scss:110` — .deal-price-original defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_marketplace_stores.scss:16` — .listing-grid defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_nav.scss:143` — .compose-prompt defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_nav.scss:20` — .top-left-logo defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_nav.scss:21` — .feed-brand-mark defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:64` — .nav_swiper_grip defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_popover_tooltip.scss:2` — .trigger_description defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_posts.scss:12` — .vote-col defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_posts.scss:2` — .post-card defined 3x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_posts.scss:79` — .comment-form-wrap defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_root.scss:214` — .guest-demo-path defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_root.scss:228` — .guest-demo-hint defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:71` — .radio-skip-link defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:37` — .ui-status defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/app/assets/stylesheets/_widgets.scss:6` — .sidebar-card__head defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:65` — .playlist-index defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist.scss:83` — .radio-start-message defined 3x, no ERB/JS/RB consumer
- [ ] `brgen/engines/playlist/app/assets/stylesheets/_vertical_playlist_tunnel.scss:121` — .radio-start-eyebrow defined 1x, no ERB/JS/RB consumer
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv.scss:82` — .show-card defined 2x, no ERB/JS/RB consumer
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv_cards.scss:19` — .live-stream-card defined 2x, no ERB/JS/RB consumer
- [ ] `bsdports/app/assets/stylesheets/application.scss:397` — .port-comment defined 1x, no ERB/JS/RB consumer
- [ ] `bsdports/app/assets/stylesheets/application.scss:70` — .search-result defined 2x, no ERB/JS/RB consumer
- [ ] `bsdports/app/assets/stylesheets/application.scss:78` — .advisory-tag defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_animations.scss:41` — .animate-fade-in defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_animations.scss:42` — .animate-slide-in-up defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_animations.scss:43` — .animate-slide-in-right defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_animations.scss:44` — .animate-scale-in defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_animations.scss:45` — .animate-spin defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_animations.scss:46` — .animate-shimmer defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_animations.scss:51` — .animate-heartbeat defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_animations.scss:52` — .animate-expand-layout defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_layout_chrome.scss:48` — .prose-measure defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_minimal.scss:221` — .badge-category defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_minimal.scss:226` — .badge-version defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_minimal.scss:418` — .notification-group defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_search_yep.scss:41` — .live_results defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:142` — .pixel-img defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:400` — .nearby-chat-widget-fallback defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:209` — .overflow-menu defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:218` — .pad-fluid defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:222` — .feed-item defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:242` — .tooltip-wrapper defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:246` — .tooltip defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:266` — .input-group defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:270` — .input-group__icon defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:278` — .input-group__input defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:306` — .dropzone defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:419` — .field_with_errors defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:43` — .text-base defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:44` — .text-lg defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:47` — .bg-surface defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:477` — .embed-container defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:48` — .full-bleed defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:53` — .truncate-2 defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:54` — .truncate-3 defined 2x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:569` — .logo-carousel defined 3x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:571` — .logo-slide defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:68` — .h-dvh defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:69` — .min-h-dvh defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:70` — .h-svh defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:71` — .min-h-svh defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:72` — .w-fit defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:73` — .w-min defined 1x, no ERB/JS/RB consumer
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:74` — .w-max defined 1x, no ERB/JS/RB consumer

### orphan_partial — 28 · confidence low

Partial with no render call found. Verify against dynamic render paths before deleting — the icon partials are reached via the `icon` helper, so those are scanner false positives. Law: `MASTER/DEBT.md inert config`.

- [ ] `amber/app/views/shared/_jox_logo.html.erb` — no render "shared/jox_logo" or "jox_logo" found
- [ ] `amber/app/views/shared/_pagination.html.erb` — no render "shared/pagination" or "pagination" found
- [ ] `amber/public/assets/layouts/_flash.html-0108dfe0.erb` — no render "/Users/mac/Documents/GitHub/pub4/RAILS/amber/public/assets/layouts/flash.html-0108dfe0" or "flash.html-0108df
- [ ] `amber/public/assets/layouts/_footer.html-ba3c30c2.erb` — no render "/Users/mac/Documents/GitHub/pub4/RAILS/amber/public/assets/layouts/footer.html-ba3c30c2" or "footer.html-ba3c
- [ ] `amber/public/assets/layouts/_meta.html-410972dc.erb` — no render "/Users/mac/Documents/GitHub/pub4/RAILS/amber/public/assets/layouts/meta.html-410972dc" or "meta.html-410972dc
- [ ] `amber/public/assets/layouts/_nav.html-0bc00dde.erb` — no render "/Users/mac/Documents/GitHub/pub4/RAILS/amber/public/assets/layouts/nav.html-0bc00dde" or "nav.html-0bc00dde" 
- [ ] `brgen/app/views/shared/_city_switcher.html.erb` — no render "shared/city_switcher" or "city_switcher" found
- [ ] `brgen/app/views/shared/_email_subscribe.html.erb` — no render "shared/email_subscribe" or "email_subscribe" found
- [ ] `brgen/engines/marketplace/app/views/marketplace/_subnav.html.erb` — no render "marketplace/subnav" or "subnav" found
- [ ] `bsdports/app/views/shared/_jox_logo.html.erb` — no render "shared/jox_logo" or "jox_logo" found
- [ ] `bsdports/public/assets/layouts/_flash.html-0108dfe0.erb` — no render "/Users/mac/Documents/GitHub/pub4/RAILS/bsdports/public/assets/layouts/flash.html-0108dfe0" or "flash.html-010
- [ ] `bsdports/public/assets/layouts/_footer.html-ba3c30c2.erb` — no render "/Users/mac/Documents/GitHub/pub4/RAILS/bsdports/public/assets/layouts/footer.html-ba3c30c2" or "footer.html-b
- [ ] `bsdports/public/assets/layouts/_meta.html-410972dc.erb` — no render "/Users/mac/Documents/GitHub/pub4/RAILS/bsdports/public/assets/layouts/meta.html-410972dc" or "meta.html-41097
- [ ] `bsdports/public/assets/layouts/_nav.html-0bc00dde.erb` — no render "/Users/mac/Documents/GitHub/pub4/RAILS/bsdports/public/assets/layouts/nav.html-0bc00dde" or "nav.html-0bc00dd
- [ ] `shared/app/views/shared/_action_bar.html.erb` — no render "shared/action_bar" or "action_bar" found
- [ ] `shared/app/views/shared/_ad_slot.html.erb` — no render "shared/ad_slot" or "ad_slot" found
- [ ] `shared/app/views/shared/_btn.html.erb` — no render "shared/btn" or "btn" found
- [ ] `shared/app/views/shared/_search_loading.html.erb` — no render "shared/search_loading" or "search_loading" found
- [ ] `shared/app/views/shared/_theme_bootstrap.html.erb` — no render "shared/theme_bootstrap" or "theme_bootstrap" found
- [ ] `shared/app/views/shared/icons/_camera.html.erb` — no render "shared/icons/camera" or "camera" found
- [ ] `shared/app/views/shared/icons/_chart.html.erb` — no render "shared/icons/chart" or "chart" found
- [ ] `shared/app/views/shared/icons/_close.html.erb` — no render "shared/icons/close" or "close" found
- [ ] `shared/app/views/shared/icons/_menu.html.erb` — no render "shared/icons/menu" or "menu" found
- [ ] `shared/app/views/shared/icons/_mic.html.erb` — no render "shared/icons/mic" or "mic" found
- [ ] `shared/app/views/shared/icons/_smile.html.erb` — no render "shared/icons/smile" or "smile" found
- [ ] `shared/app/views/shared/icons/_sparkles.html.erb` — no render "shared/icons/sparkles" or "sparkles" found
- [ ] `shared/app/views/shared/icons/_sun.html.erb` — no render "shared/icons/sun" or "sun" found
- [ ] `shared/frontend/layouts/_flash.html.erb` — no render "/Users/mac/Documents/GitHub/pub4/RAILS/shared/frontend/layouts/flash" or "flash" found

### unread_css_var — 27 · confidence medium

CSS custom property defined and never read. A token with no var() consumer. Declaration without a reader. Law: `MASTER/DEBT.md inert config`.

- [ ] `shared/app/assets/stylesheets` — --luxury-accent defined, never read via var(--luxury-accent)
- [ ] `shared/app/assets/stylesheets` — --line-height-base defined, never read via var(--line-height-base)
- [ ] `shared/app/assets/stylesheets` — --app-accent defined, never read via var(--app-accent)
- [ ] `shared/app/assets/stylesheets` — --turbo-progress-bar-color defined, never read via var(--turbo-progress-bar-color)
- [ ] `shared/app/assets/stylesheets` — --elev-2 defined, never read via var(--elev-2)
- [ ] `shared/app/assets/stylesheets` — --maps-accent-soft defined, never read via var(--maps-accent-soft)
- [ ] `shared/app/assets/stylesheets` — --accent-hover defined, never read via var(--accent-hover)
- [ ] `shared/app/assets/stylesheets` — --playlist-success defined, never read via var(--playlist-success)
- [ ] `shared/app/assets/stylesheets` — --food-card-radius defined, never read via var(--food-card-radius)
- [ ] `shared/app/assets/stylesheets` — --c-text defined, never read via var(--c-text)
- [ ] `shared/app/assets/stylesheets` — --c-accent defined, never read via var(--c-accent)
- [ ] `shared/app/assets/stylesheets` — --c-danger defined, never read via var(--c-danger)
- [ ] `shared/app/assets/stylesheets` — --c-code defined, never read via var(--c-code)
- [ ] `shared/app/assets/stylesheets` — --weight-medium defined, never read via var(--weight-medium)
- [ ] `shared/app/assets/stylesheets` — --layout-max defined, never read via var(--layout-max)
- [ ] `shared/app/assets/stylesheets` — --chrome-bg defined, never read via var(--chrome-bg)
- [ ] `shared/app/assets/stylesheets` — --blue defined, never read via var(--blue)
- [ ] `shared/app/assets/stylesheets` — --grey defined, never read via var(--grey)
- [ ] `shared/app/assets/stylesheets` — --color-background defined, never read via var(--color-background)
- [ ] `shared/app/assets/stylesheets` — --gradient-hero defined, never read via var(--gradient-hero)
- [ ] `shared/app/assets/stylesheets` — --gradient-card-scrim defined, never read via var(--gradient-card-scrim)
- [ ] `shared/app/assets/stylesheets` — --text-display defined, never read via var(--text-display)
- [ ] `shared/app/assets/stylesheets` — --ease-linear defined, never read via var(--ease-linear)
- [ ] `shared/app/assets/stylesheets` — --ease-in-out defined, never read via var(--ease-in-out)
- [ ] `shared/app/assets/stylesheets` — --ease-spring defined, never read via var(--ease-spring)
- [ ] `shared/app/assets/stylesheets` — --z-modal defined, never read via var(--z-modal)
- [ ] `shared/app/assets/stylesheets` — --showcase-chip defined, never read via var(--showcase-chip)

### target_no_controller — 18 · confidence medium

data-*-target with no matching registered controller. The stimulus_wiring gate covers data-action; targets are the gap. Law: `UI_REFINEMENTS stimulus_wiring gate`.

- [ ] `views` — data-radio-tunnel-target used, no matching registered controller 'radio-tunnel'
- [ ] `views` — data-filter-target used, no matching registered controller 'filter'
- [ ] `views` — data-nested-form-target used, no matching registered controller 'nested-form'
- [ ] `views` — data-clipboard-target used, no matching registered controller 'clipboard'
- [ ] `views` — data-reveal-target used, no matching registered controller 'reveal'
- [ ] `views` — data-flash-target used, no matching registered controller 'flash'
- [ ] `views` — data-checkbox-select-all-target used, no matching registered controller 'checkbox-select-all'
- [ ] `views` — data-toggle-target used, no matching registered controller 'toggle'
- [ ] `views` — data-dropdown-target used, no matching registered controller 'dropdown'
- [ ] `views` — data-map-target used, no matching registered controller 'map'
- [ ] `views` — data-popover-target used, no matching registered controller 'popover'
- [ ] `views` — data-tiptap-editor-target used, no matching registered controller 'tiptap-editor'
- [ ] `views` — data-nav-swiper-target used, no matching registered controller 'nav-swiper'
- [ ] `views` — data-dating-intro-target used, no matching registered controller 'dating-intro'
- [ ] `views` — data-tabs-target used, no matching registered controller 'tabs'
- [ ] `views` — data-marketplace-logo-target used, no matching registered controller 'marketplace-logo'
- [ ] `views` — data-playlist-player-target used, no matching registered controller 'playlist-player'
- [ ] `views` — data-character-counter-target used, no matching registered controller 'character-counter'

### unused_locale_key — 14 · confidence medium

Locale key with no reader. A translated string nothing renders. Inert config — the pub4 defect class. Law: `MASTER/DEBT.md inert config`.

- [ ] `amber/config/locales/en.yml` — empty.no_outfits_body
- [ ] `amber/config/locales/en.yml` — wardrobe.by_body_region
- [ ] `amber/config/locales/nb.yml` — empty.no_outfits_body
- [ ] `amber/config/locales/nb.yml` — wardrobe.by_body_region
- [ ] `brgen/config/locales/en.yml` — nearby.waiting_body
- [ ] `brgen/config/locales/en.yml` — nearby.waiting_title
- [ ] `brgen/config/locales/en.yml` — home.intro_body
- [ ] `brgen/config/locales/en.yml` — home.ask_ai_title
- [ ] `brgen/config/locales/en.yml` — empty.no_listings_search
- [ ] `brgen/config/locales/nb.yml` — home.intro_body
- [ ] `brgen/config/locales/nb.yml` — home.ask_ai_title
- [ ] `brgen/config/locales/nb.yml` — empty.no_listings_search
- [ ] `brgen/config/locales/nb.yml` — nearby.waiting_title
- [ ] `brgen/config/locales/nb.yml` — nearby.waiting_body

### dead_stimulus_controller — 2 · confidence high

Stimulus controller registered but never referenced. Ships JS that can never run. Law: `MASTER/DEBT.md inert config`.

- [ ] `shared/frontend/stimulus_boot.js` — registered 'futurism', no data-controller reference in any ERB
- [ ] `shared/frontend/stimulus_boot.js` — registered 'x-action', no data-controller reference in any ERB

### value_no_declaration — 1 · confidence high

data-*-value with no static values declaration. The value is written and never read. Law: `MASTER/DEBT.md inert config`.

- [ ] `views` — data-action-target-gid-value has no `targetGid:` in static values

## Cleanup and altitude — 159 items

### rb_long_method — 81 · confidence medium

Method longer than 30 lines. Same rule at method scale. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `amber/app/controllers/ai_controller.rb:29` — suggest_outfits spans 33 lines
- [ ] `amber/app/helpers/application_helper.rb:37` — responsive_image_tag spans 32 lines
- [ ] `brgen/app/controllers/messages_controller.rb:13` — create spans 31 lines
- [ ] `brgen/app/controllers/search_controller.rb:8` — index spans 33 lines
- [ ] `brgen/app/controllers/users_controller.rb:42` — create spans 32 lines
- [ ] `brgen/app/helpers/application_helper.rb:18` — responsive_image_tag spans 31 lines
- [ ] `brgen/app/helpers/application_helper.rb:162` — record_public_href spans 47 lines
- [ ] `brgen/app/helpers/application_helper.rb:230` — notification_href spans 31 lines
- [ ] `brgen/app/jobs/dilla_render_job.rb:6` — perform spans 31 lines
- [ ] `brgen/app/services/amazon_associates.rb:64` — import! spans 33 lines
- [ ] `brgen/app/services/thread_summarizer.rb:17` — call spans 31 lines
- [ ] `brgen/app/services/tradedoubler.rb:231` — parse spans 36 lines
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/checkouts_controller.rb:7` — create spans 31 lines
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:581` — seed_posts spans 31 lines
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:658` — seed_live_posts spans 31 lines
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:831` — seed_takeaway spans 31 lines
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:865` — seed_tv spans 33 lines
- [ ] `bsdports/app/services/nvd_cve.rb:18` — crossref spans 45 lines
- [ ] `gates/lib/affiliate_honesty.rb:37` — run spans 32 lines
- [ ] `gates/lib/apps_yml.rb:48` — validate_app spans 38 lines
- [ ] `gates/lib/calibration.rb:15` — run spans 32 lines
- [ ] `gates/lib/constitutional_scan.rb:135` — scan_target spans 32 lines
- [ ] `gates/lib/constitutional_scan.rb:177` — maybe_ratchet spans 31 lines
- [ ] `gates/lib/cross_app.rb:49` — run spans 36 lines
- [ ] `gates/lib/css_constitution.rb:154` — scan spans 33 lines
- [ ] `gates/lib/css_minify_integrity.rb:42` — check_app spans 38 lines
- [ ] `gates/lib/design_metrics.rb:73` — check_token_type_and_measure spans 36 lines
- [ ] `gates/lib/design_metrics.rb:127` — check_token_contrast spans 33 lines
- [ ] `gates/lib/design_metrics.rb:193` — check_touch_targets spans 43 lines
- [ ] `gates/lib/design_metrics.rb:322` — optional_browser_hit_targets spans 40 lines
- [ ] `gates/lib/domain_alignment.rb:28` — run spans 31 lines
- [ ] `gates/lib/flow_journey.rb:88` — check_step spans 35 lines
- [ ] `gates/lib/flow_journey.rb:143` — check_assertions spans 35 lines
- [ ] `gates/lib/frontend_auditor.rb:18` — self spans 38 lines
- [ ] `gates/lib/gate_mutation.rb:89` — run spans 31 lines
- [ ] `gates/lib/generated_asset.rb:78` — stale? spans 41 lines
- [ ] `gates/lib/geometry.rb:51` — run spans 33 lines
- [ ] `gates/lib/geometry.rb:193` — check_contrast spans 32 lines
- [ ] `gates/lib/human_walkthrough.rb:113` — live_checks spans 32 lines
- [ ] `gates/lib/journey_invariant.rb:30` — run spans 39 lines
- [ ] `gates/lib/journey_invariant.rb:97` — check_back_button spans 31 lines
- [ ] `gates/lib/keyboard_flow.rb:98` — walk_tab_order spans 42 lines
- [ ] `gates/lib/layout_geometry.rb:113` — live_first_screen spans 35 lines
- [ ] `gates/lib/layout_search.rb:53` — emit_report! spans 31 lines
- [ ] `gates/lib/layout_search.rb:86` — enforce! spans 37 lines
- [ ] `gates/lib/layout_snapshot.rb:44` — run spans 36 lines
- [ ] `gates/lib/layout_snapshot.rb:173` — compare spans 32 lines
- [ ] `gates/lib/master_web_assets.rb:23` — self spans 31 lines
- [ ] `gates/lib/mobile_flow.rb:102` — run spans 39 lines
- [ ] `gates/lib/mobile_flow.rb:170` — probe spans 32 lines
- [ ] `gates/lib/page_simulation.rb:42` — run spans 39 lines
- [ ] `gates/lib/page_simulation.rb:124` — simulate_live spans 31 lines
- [ ] `gates/lib/production.rb:46` — check_app spans 36 lines
- [ ] `gates/lib/reflow.rb:197` — check_breakpoints spans 33 lines
- [ ] `gates/lib/shared_wiring.rb:36` — run spans 43 lines
- [ ] `gates/lib/stimulus_components.rb:31` — self spans 31 lines
- [ ] `gates/lib/user_flow.rb:38` — run_once spans 100 lines
- [ ] `gates/lib/user_flow.rb:234` — scan_directory_contract spans 31 lines
- [ ] `gates/lib/user_flow.rb:313` — run_live_step spans 32 lines
- [ ] `gates/rails_runtime.rb:67` — runtime_gate! spans 32 lines
- [ ] `gates/release.rb:53` — run spans 34 lines
- [ ] `gates/runner.rb:150` — list_gates spans 35 lines
- [ ] `gates/support/dom_surface_schema.rb:30` — check spans 44 lines
- [ ] `gates/support/exemplar_structure.rb:30` — score spans 40 lines
- [ ] `gates/support/gate_autofix.rb:40` — run_with_remeasure spans 31 lines
- [ ] `gates/support/gate_calibration.rb:97` — evaluate spans 33 lines
- [ ] `gates/support/gate_calibration.rb:175` — suggest_weights spans 36 lines
- [ ] `gates/support/geometry_autofix.rb:140` — rebuild_css spans 35 lines
- [ ] `gates/support/layout_search.rb:87` — build_candidate spans 46 lines
- [ ] `gates/support/layout_search.rb:143` — detect_variant spans 33 lines
- [ ] `gates/support/page_inventory.rb:349` — brgen_route_by_convention spans 38 lines
- [ ] `gates/support/page_inventory.rb:444` — amber_route_by_convention spans 31 lines
- [ ] `gates/visual_contract.rb:144` — capture spans 31 lines
- [ ] `shared/app/helpers/schema_helper.rb:122` — product_schema spans 32 lines
- [ ] `shared/app/models/concerns/shared/notifiable.rb:14` — deliver_notification spans 31 lines
- [ ] `shared/app/services/shared/frontend_auditor.rb:125` — scan_style spans 36 lines
- [ ] `shared/config/environments/production_baseline.rb:4` — apply_production_baseline spans 31 lines
- [ ] `tools/build_all_css.rb:90` — sync_static_tokens! spans 67 lines
- [ ] `tools/build_all_css.rb:222` — verify_face_css spans 32 lines
- [ ] `tools/crawl_browser.rb:53` — crawl_target spans 32 lines
- [ ] `tools/crawl_probe.rb:13` — run_browser_crawl spans 36 lines

### css_vendor_prefix — 24 · confidence low

Vendor prefix outside the known-needed set. Autoprefixer-era residue; most are no-ops on every browser `allow_browser versions: :modern` admits. Law: `aesthetic_rules.FLAT_HIERARCHY`.

- [ ] `amber/app/assets/stylesheets/_base.scss:17` — -moz-osx-font-smoothing: grayscale;
- [ ] `amber/app/assets/stylesheets/_items.scss:34` — .wardrobe-more-tools > summary::-webkit-details-marker { display: none; }
- [ ] `brgen/app/assets/stylesheets/_marketplace.scss:60` — .deal-cats::-webkit-scrollbar {
- [ ] `brgen/app/assets/stylesheets/_marketplace_cards.scss:120` — display: -webkit-box;
- [ ] `brgen/app/assets/stylesheets/_marketplace_cards.scss:130` — display: -webkit-box;
- [ ] `brgen/app/assets/stylesheets/_marketplace_cards.scss:142` — display: -webkit-box;
- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:268` — #sections::-webkit-scrollbar {
- [ ] `brgen/app/assets/stylesheets/_marketplace_top_offers.scss:51` — .top-offers-rail::-webkit-scrollbar {
- [ ] `brgen/app/assets/stylesheets/_marketplace_top_offers.scss:114` — display: -webkit-box;
- [ ] `brgen/app/assets/stylesheets/_nav.scss:52` — .feed-tabs::-webkit-scrollbar { display: none; }
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:23` — .nav_swiper_bar::-webkit-scrollbar { display: none; }
- [ ] `brgen/app/assets/stylesheets/_posts.scss:129` — .comment-reply-toggle::-webkit-details-marker { display: none; }
- [ ] `brgen/app/assets/stylesheets/_root.scss:51` — -moz-osx-font-smoothing: grayscale;
- [ ] `brgen/engines/dating/app/assets/stylesheets/_vertical_dating_intro.scss:95` — .dating-profile-more > summary::-webkit-details-marker { display: none; }
- [ ] `shared/app/assets/stylesheets/_chat_reactions.scss:175` — .comment-reply-toggle::-webkit-details-marker { display: none; }
- [ ] `shared/app/assets/stylesheets/_minimal.scss:52` — -moz-osx-font-smoothing: grayscale;
- [ ] `shared/app/assets/stylesheets/_shell.scss:79` — .app-shell::-webkit-scrollbar { width: 8px; }
- [ ] `shared/app/assets/stylesheets/_shell.scss:80` — .app-shell::-webkit-scrollbar-thumb { background: var(--hover); }
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:144` — image-rendering: -moz-crisp-edges;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:56` — display: -webkit-box;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:214` — .overflow-menu::-webkit-scrollbar {
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:327` — progress::-webkit-progress-bar {
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:331` — progress::-webkit-progress-value {
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:538` — display: -webkit-box;

### rb_no_frozen_literal — 20 · confidence high → **0 real, scanner bug**

Missing `# frozen_string_literal: true`. Law: `style.yml line_order`.

**Closed 2026-08-03 with no edits, because all twenty are false positives and
the rule itself was wrong.** The scanner tested `src.start_with?("# frozen…")`,
which is false for any file with a shebang on line 1 — and all twelve
`gates/*.rb` and `tools/*.rb` entries below are shebang files that already carry
the comment on line 2. I "fixed" them, produced twelve duplicate magic comments,
and `git diff --stat` came back empty after normalising, which is what proved it.

The other eight are `db/schema.rb` / `db/*_schema.rb`: generated files that must
*not* carry it. `bsdports/db/schema.rb` has one added by hand, and running any
migration strips it again — see the entry for that file under P0.4.

Anchor a future version of this rule on the first non-shebang line, and skip
`db/*schema.rb` entirely.

- [ ] `amber/db/schema.rb:1` — missing magic comment
- [ ] `brgen/db/cable_schema.rb:1` — missing magic comment
- [ ] `brgen/db/cache_schema.rb:1` — missing magic comment
- [ ] `brgen/db/queue_schema.rb:1` — missing magic comment
- [ ] `brgen/db/schema.rb:1` — missing magic comment
- [ ] `bsdports/db/cable_schema.rb:1` — missing magic comment
- [ ] `bsdports/db/cache_schema.rb:1` — missing magic comment
- [ ] `bsdports/db/schema.rb:1` — missing magic comment
- [ ] `gates/rails_runtime.rb:1` — missing magic comment
- [ ] `gates/release.rb:1` — missing magic comment
- [ ] `gates/runner.rb:1` — missing magic comment
- [ ] `gates/visual_contract.rb:1` — missing magic comment
- [ ] `tools/build_all_css.rb:1` — missing magic comment
- [ ] `tools/crawl_browser.rb:1` — missing magic comment
- [ ] `tools/crawl_probe.rb:1` — missing magic comment
- [ ] `tools/design_tokens.rb:1` — missing magic comment
- [ ] `tools/generate_face_root_css.rb:1` — missing magic comment
- [ ] `tools/migrate_stimulus_components.rb:1` — missing magic comment
- [ ] `tools/sync_auth_schema.rb:1` — missing magic comment
- [ ] `tools/sync_dialect_tokens.rb:1` — missing magic comment

### rb_file_too_long — 13 · confidence medium

Ruby file over 300 lines. SIMPLEST_WORKS refuses god classes; decompose. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `amber/app/services/wardrobe_ai.rb:376` — 376 lines
- [ ] `amber/db/schema.rb:550` — 550 lines
- [ ] `brgen/app/services/tradedoubler.rb:533` — 533 lines
- [ ] `brgen/db/schema.rb:1462` — 1462 lines
- [ ] `brgen/db/seeds.rb:539` — 539 lines
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:903` — 903 lines
- [ ] `brgen/lib/brgen/plausible_content.rb:425` — 425 lines
- [ ] `gates/lib/design_metrics.rb:389` — 389 lines
- [ ] `gates/lib/page_simulation.rb:360` — 360 lines
- [ ] `gates/lib/user_flow.rb:368` — 368 lines
- [ ] `gates/support/cdp_session.rb:543` — 543 lines
- [ ] `gates/support/geometry_probe.rb:510` — 510 lines
- [ ] `gates/support/page_inventory.rb:532` — 532 lines

### scss_file_too_long — 7 · confidence low

SCSS partial over 400 lines. SIMPLEST_WORKS: split by surface. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `amber/app/assets/stylesheets/_brand.scss:441` — 441 lines
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:405` — 405 lines
- [ ] `bsdports/app/assets/stylesheets/application.scss:532` — 532 lines
- [ ] `shared/app/assets/stylesheets/_minimal.scss:642` — 642 lines
- [ ] `shared/app/assets/stylesheets/_shell.scss:565` — 565 lines
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:540` — 540 lines
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:578` — 578 lines

### nbsp_entity — 5 · confidence low

&nbsp; entity. Usually a spacing hack; use padding/gap. Law: `layout_rules.whitespace.gap_over_margin`.

- [ ] `brgen/app/views/nearby/widget.html.erb:9` — <span>~10&nbsp;km</span>
- [ ] `brgen/engines/dating/app/views/dating/profiles/show.html.erb:43` — &nbsp;
- [ ] `brgen/engines/dating/app/views/dating/profiles/show.html.erb:45` — &nbsp;
- [ ] `brgen/engines/dating/app/views/dating/profiles/show.html.erb:54` — &nbsp;
- [ ] `brgen/engines/marketplace/app/views/marketplace/_nav_bar.html.erb:49` — <span class="nav-line-1">&nbsp;</span>

### class_soup — 4 · confidence low

Element with 6+ classes. UI_REFINEMENTS "Full ERB class-soup -> bare semantic HTML" is still open. Law: `aesthetic_rules.FLAT_HIERARCHY`.

- [ ] `amber/app/views/ai/occasion_map.html.erb:5` — 6 classes: occasion-card occasion-card--<%= items.size < 2 ?
- [ ] `bsdports/app/views/ports/_row.html.erb:9` — 8 classes: data-state <%= age && age >
- [ ] `bsdports/app/views/ports/show.html.erb:24` — 8 classes: data-state <%= update_age && update_age >
- [ ] `shared/app/views/shared/_feed_card.html.erb:21` — 7 classes: feed-card-avatar-placeholder monogram monogram--<%= monogram.ord % 6

### view_too_long — 4 · confidence low

View over 150 lines. SIMPLEST_WORKS — extract partials. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `amber/app/views/layouts/application.html.erb:153` — 153 lines
- [ ] `brgen/app/views/layouts/application.html.erb:307` — 307 lines
- [ ] `brgen/app/views/pwa/manifest.json.erb:156` — 156 lines
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/_player.html.erb:173` — 173 lines

### rb_todo — 1 · confidence medium

TODO/FIXME in Ruby.  Law: `MASTER/DEBT.md`.

- [ ] `shared/app/helpers/shared/consent_helper.rb:10` — # rather than a TODO, and so wiring a CMP later is one method body rather

## Scan provenance

Every item above came from a scanner run against the working tree on
2026-08-03, not from reading a previous checklist. The three scanners are
kept in the session scratchpad rather than committed, because most rules
here duplicate a MASTER scanner or a `RAILS/gates` gate once the item is
closed — the right end state is a gate, not a script.

Counts: 1851 raw findings, 1851 classified into the sections above.

Fifteen rules fired zero times. That is the more useful half of the result,
because it is what prior polish waves actually closed, and each is cheaper to
hold at zero than to re-drive to zero:

`css_shadow` — no ornamental box-shadow or text-shadow anywhere in app SCSS.
`css_no_reduced_motion` — every animating sheet carries a guard.
`ctrl_no_strong_params` — no `params[]` reaches `new`/`update` directly.
`rb_bare_rescue`, `rb_rescue_exception` — FAIL_VISIBLY holds.
`rb_string_interp_sql` — no interpolation in a query fragment.
`rb_save_unchecked` — no unchecked `save`.
`img_no_alt`, `icon_control_no_label`, `table_no_scope`, `time_no_datetime` —
the accessible-name and semantics floor holds.
`no_turbo_frame_id` — every frame is identified.
`unregistered_stimulus_file` — no controller file is orphaned.
`rb_n_plus_one_risk`, `todo_comment` — clean.

## How to re-run

```zsh
RAILS/bin/triangle up
ruby RAILS/test/design_contract_test.rb
ruby RAILS/shared/test/lib/design_tokens_test.rb
ruby RAILS/gates/runner.rb stimulus_wiring
ruby RAILS/gates/runner.rb frontend_auditor
cd RAILS/brgen && bin/rails test
```
