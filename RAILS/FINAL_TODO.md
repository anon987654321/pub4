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

- [x] The front page becomes unresponsive to any JS evaluation about 3 seconds
      after load. **Withdrawn as unmeasurable by me, then found by someone with
      the right tool. Both halves are true and the second one matters more.**

      **The renderer really was spinning.** `951dcd00d` names it:
      `nearby_chat`'s `connect()` observes `this.element` with
      `{childList, subtree}` and calls `#syncLabelsFromFrame` from the callback,
      which assigned `textContent` to `tabLabel` and `headerLabel`
      unconditionally — and both targets live *inside* the observed element.
      Assigning `textContent` replaces the text node even when the string is
      identical, so every callback produced the mutation that triggered the next
      one. 100% CPU, and the load event never fired.

      That is on the page I was probing, in the chat widget I was fixing. So my
      original reading was pointing at something real. What was wrong was the
      confidence and the method, not the symptom.

      **My measurement was still not evidence, and that is the lesson to keep.**
      CDP `Runtime.evaluate` flipped with whether Ferrum's request interception
      happened to be enabled, and once one `send_message` timed out every later
      command on that session failed identically — which is what produced the
      flat 6.01s rows that looked reproducible. An earlier bisect "isolating"
      tiptap failed the same way. A reading that changes when you toggle an
      unrelated setting cannot name a cause, even when a cause exists.

      The correct tool did name it: pausing the spinning V8 through CDP showed
      the stack as `#syncLabelsFromFrame` <- `MutationObserver`, in a loop. Use
      `Performance.getMetrics`, a `Tracing` capture, or a V8 pause — none of
      which need the page's main thread — and never repeated `evaluate` calls on
      one session.

      Worth noting how long it hid: `ci.rb` runs the system-test step only when
      not `vps_host`, so this hung every local `bin/ci` for brgen indefinitely
      while deploys stayed green, because the VPS skips the one step that opens
      a browser. Five runs were killed at 5–10 minutes each with no output.

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

### P0.5 Two first-visit coaches in one slot, one of them for a keyboard that isn't there

Found by screenshotting **live** `brgen.no` after the deploy, not by a scanner.
Both coaches fire on the same first visit, into the same bottom-centre position.

- [x] `shared/frontend/feed_hotkey_controller.js` — the hotkey coach reads
      "Keyboard: press ? anytime for shortcuts (j/k to move, / to search)" and
      showed on a 390×844 touch viewport, where there is no keyboard, no `?` and
      no j/k. `#maybeShowCoach` gated on "is this a feed surface" and on the
      dismissed flag, and on nothing about input capability. **Fixed:** it now
      also requires `(hover: hover) and (pointer: fine)`. The shortcuts stay
      bound regardless, for a tablet with a paired keyboard.

- [ ] `.tab-bar-coach` (`_shell.scss:410`) and `.hotkey-coach`
      (`_shell.scss:496`) are both `position: fixed; left: 50%;
      transform: translateX(-50%)` at the bottom edge — 2.75rem + safe-area and
      1rem respectively — and they render at the same time. `.hotkey-coach`
      carries `z-index: var(--z-toast, 1100)` against `.tab-bar-coach`'s
      `calc(var(--z-nav, 80) + 1)` = 91, so the hotkey box paints over the menu
      coach and covers its **"Vis meny" button** — the one control that coach
      exists to point at.

      The pointer gate above removes the collision on touch, which is where it
      was observed, but not on a desktop first visit: there both still fire into
      the same slot. Two onboarding hints at once is also a Hick's-law problem
      before it is a z-index one.

      Not fixed here because it needs a product decision, not a CSS nudge: which
      coach wins on first visit, or are they sequenced (menu first, keyboard on
      the visit after)? Picking one silently would be inventing UX. Both are
      one-shot and localStorage-flagged (`pub4:tab-bar:open`,
      `pub4:hotkey-coach:dismissed`), so sequencing them is cheap once the order
      is chosen.

### P0.6 Found on live bsdports after deploying it

Two things a source scanner cannot see, both visible on `https://bsdports.org/ports`
right now.

- [ ] **The ports index is empty in production.** It renders
      "Ingen porter funnet" — no rows at all — on a site whose entire purpose is
      browsing OpenBSD ports. The app is healthy (`rcctl` ok, `/up` 200, deploy
      stamp `ok` at `53ef4aec0`), the search chrome renders, the empty state is
      correct and translated; there is simply no port data. So the ports import
      has either never run against production or stopped running, and every
      surface downstream of it — categories, maintainers, dependency graphs,
      advisories, and the `ports/show` page translated in `05f408d7b` — has
      nothing to render. Nothing fails loudly, which is why it can sit like this.

- [ ] **The index mixes languages in one viewport.** Under the `nb` heading
      "OpenBSD-porter" the lead paragraph is English — "Answer three questions
      quickly: what package is this, can this machine install it, and what does
      the local advisory index know?" — immediately above Norwegian search copy
      ("Søk i navn, eksakte pkgpaths, maintainere…"). The empty state's own
      follow-ups are English too: "Try another query — e.g. git, python, or a
      category." and "Browse all ports". `ports/show` is fully translated as of
      `05f408d7b`; `ports/index` is not, and the seam is visible in a single
      screenful.
---

## Scanner findings — verdicts

Every rule below was re-run after the scanners themselves were corrected, and
the rules with a large count were then checked by hand against the files. The
count is not the finding; the verdict is.

- **fixed** — real, and closed in this branch.
- **artifact** — the rule was wrong. Corrected, with what it was measuring.
- **policy** — the pattern is permitted here, usually by the repo's own linter.
- **judgement** — real shape, but each instance is a behaviour change that
  needs a decision rather than a sweep. `PRESERVE_FIRST` applies.
- **open** — real, safe, and not done. These are the ones worth picking up.

| rule | count | verdict |
|---|---:|---|
| `hardcoded_copy` | 129 | open |
| `css_important` | 128 | policy |
| `model_assoc_no_inverse` | 104 | judgement |
| `unused_css_class` | 102 | judgement |
| `css_transition_no_easing` | 83 | open |
| `css_off_grid` | 83 | artifact |
| `rb_long_method` | 81 | open |
| `magic_hex` | 75 | artifact |
| `css_px_width` | 72 | artifact |
| `model_no_scope` | 67 | policy |
| `ctrl_no_rate_limit` | 64 | judgement |
| `css_magic_hex` | 56 | judgement |
| `css_animation_present` | 52 | policy |
| `delete_no_confirm` | 29 | artifact |
| `orphan_partial` | 28 | artifact |
| `list_no_empty_state` | 28 | artifact |
| `unread_css_var` | 27 | open |
| `css_font_px_hardcoded` | 25 | open |
| `css_vendor_prefix` | 24 | open |
| `rb_rescue_nil` | 21 | policy |
| `form_no_label` | 18 | open |
| `count_in_view` | 18 | fixed |
| `target_no_controller` | 18 | artifact |
| `unused_locale_key` | 14 | open |
| `rb_file_too_long` | 13 | open |
| `rb_time_now` | 13 | fixed |
| `rb_update_column` | 12 | fixed |
| `model_no_validations` | 11 | artifact |
| `css_autofix_scar` | 11 | policy |
| `ctrl_index_no_pagination` | 11 | judgement |
| `css_font_px_small` | 10 | open |
| `rb_env_fetch_no_default` | 10 | artifact |
| `inline_style` | 9 | policy |
| `css_zindex_magic` | 9 | open |
| `css_display_none_override` | 9 | open |
| `rb_puts` | 8 | artifact |
| `model_has_many_no_dependent` | 8 | artifact |
| `scss_file_too_long` | 7 | open |
| `img_no_dims` | 6 | artifact |
| `heading_skip` | 5 | judgement |
| `placeholder_hardcoded` | 5 | fixed |
| `rb_hardcoded_domain` | 5 | artifact |
| `rb_unscoped_all` | 5 | artifact |
| `rb_skip_forgery` | 5 | policy |
| `nbsp_entity` | 5 | judgement |
| `raw_html_safe` | 4 | policy |
| `class_soup` | 4 | open |
| `view_too_long` | 4 | open |
| `css_blur` | 3 | policy |
| `button_div` | 3 | artifact |
| `submit_hardcoded` | 3 | fixed |
| `target_blank_no_rel` | 2 | artifact |
| `dead_stimulus_controller` | 2 | fixed |
| `rb_rescue_inline_nil` | 2 | fixed |
| `img_no_lazy` | 2 | fixed |
| `css_radius_large` | 2 | fixed |
| `form_no_autocomplete` | 2 | artifact |
| `css_line_height_tight` | 2 | artifact |
| `rb_todo` | 1 | artifact |
| `time_now` | 1 | fixed |
| `value_no_declaration` | 1 | fixed |

### Verdict notes

**`count_in_view`** — 18 findings, _fixed_. The worst instance is fixed and it was worse than a COUNT: `search/_live_search_results` called `records.blank?` on seven relations, which loads every matching row, purely to decide whether to render a section it then limited to 8. Now takes 8 first and asks whether any came back.

**`css_animation_present`** — 52 findings, _policy_. Informational by construction — the rule reports every animation so each can be checked for a reduced-motion guard. `css_no_reduced_motion` fired 0, so the guards are all present.

**`css_important`** — 128 findings, _policy_. Largely allowed by the repo's own linter. `Shared::FrontendAuditor::ALLOWED_IMPORTANT_PATTERN` permits `!important` inside `prefers-reduced-motion` and `print` blocks, which is what most of these are (`animation: none !important`). The 24 in `_root.scss` are the documented "no chrome around the wordmark" set. Stripping them is a cascade change, not a cleanup — PRESERVE_FIRST.

**`css_magic_hex`** — 56 findings, _judgement_. Needs reading per site for the same reasons as the view-level rule — fallback values inside `var()` and dialect token definitions are correct, and the difference is not mechanical.

**`css_off_grid`** — 83 findings, _artifact_. Substantially wrong: the grid array omitted 44, so the rule flags `min-height: 44px` — the touch target `ux_laws.fitts.target_min_px` mandates. Others land in `_jsfiddle_chrome.scss`, which `FrontendAuditor::PEN_STYLE_PATH_PATTERN` exempts as a product pen keeping exact CSS.

**`css_px_width`** — 72 findings, _artifact_. Mostly `@media (min-width: 768px)` — breakpoints, not element widths. The regex matched `min-width` anywhere.

**`list_no_empty_state`** — 28 findings, _artifact_, ~0 real. The rule asked one
file whether it both iterates and handles empty, and in this codebase those two
things live in different files. `posts/index` renders its list through
`live_search_index` → `posts/_live_search_results`, and *that* partial carries
`<% if @posts.any? %>` with a `shared/empty_state` and a CTA; same for
`items/index` → `items/_live_search_results`. The only `.each` left in the index
itself is a bounded sidebar (`Community.popular.limit(8)`).

Ten of the 28 are per-item partials, which structurally cannot hold the empty
state for the collection that renders them. Five are forms iterating `<select>`
options. The rest are chrome (nav bars, the icon sprite), a mailer text template,
a turbo-stream with no UI, and the shared examples page.

The decisive evidence is that `Pub4::EmptyStateLint` sits at **baseline 0** and
passes: every empty state in the family already has an action, which is the
`NO_DEAD_ENDS` invariant this rule was reaching for. It was measuring file
structure and calling it product coverage.

**`target_no_controller`** — 17 findings, _artifact_, 0 real, and the rule is
retired. It resolved identifiers only against `application.register()` calls, so it
missed the `COMPONENT_REGISTRATIONS` table and every per-app controller file, and
reported `character-counter`, `clipboard`, `dropdown`, `popover`, `tiptap-editor`,
`nav-swiper` and eleven others as unregistered. `stimulus_wiring` now checks
targets as its fourth leg, against the same registration set it uses for
identifiers, which is the correct version of this idea.

**`css_autofix_scar`** — 11 findings, _policy_, deliberately kept. Ten are the
marker `/* autofix: removed box-shadow (flat UI) */`, and they are a trail rather
than litter: `shared/_focus_ring.scss`'s header cites them by name to explain why
that file exists — "a flat-UI pass stripped the box-shadow that had been the
indicator and left the `outline: none` beside it untouched, so the ring silently
vanished". Deleting the markers would leave that explanation pointing at
annotations that no longer exist, which is the drift this repo keeps paying for.
The eleventh finding *is* that header.

**`raw_html_safe`** — 4 findings, _policy_, none exploitable. Audited each for
whether user input can reach it, which is the only question that matters:

- `two_factor_setups/show` renders `@qr.html_safe` — a TOTP QR generated
  server-side from the provisioning URI, never from a request.
- `shared/_link_converter` does `raw(Tradedoubler.epi_for(…).to_json)` on a city
  slug and a subapp name, both resolved from `Brgen::DomainRegistry`'s
  allowlist, not from params.
- `dating/_match` interpolates a `Date`.
- `tv/home` wrapped a static `<span class="live-badge">Live</span>`. Replaced with
  `tag.span(t("tv.live_badge"), class: "live-badge")`, which escapes and also puts
  the badge, the "Live now" heading and its aria-label through the locale — that
  string was hardcoded English on a `default_locale: nb` surface.

**`rb_skip_forgery`** — 5 findings, _policy_, all defensible:

- `Shared::InternalTokenAuth` gates loopback/internal service callers on a shared
  secret. CSRF is meaningless for a token-authenticated non-browser caller.
- `posts#share` and `items#share` both keep `require_real_user` and a
  `rate_limit`; a forged request could force a share the user is entitled to make
  anyway.
- `fingerprints#create` (brgen, amber) is a JS beacon with no form to carry a
  token. This is the weakest of the five — a forged request could set a victim's
  fingerprint — but it is the conventional shape for a beacon, and the value is
  not a credential.

Nothing here needs changing. Recorded so the next sweep does not re-audit it.

**`delete_no_confirm`** — 29 findings, _artifact_, 4 real and fixed. The rule flags
any `method: :delete`, and REST DELETE is not the same thing as destructive.
Seventeen are toggles (unfollow, unlike, unwatch, unsubscribe, unsave, unbookmark,
unblock, leave community) undone by clicking the same button again; four are
sign-out; one — `shared/comments/_comment` — already had `turbo_confirm`, on the
line after the one flagged. Putting "Are you sure?" in front of unfollowing
someone is friction pretending to be care.

The four that are irreversible now confirm, with copy that says what happens:
deleting a `Marketplace::Listing` (which declares
`has_many :orders, dependent: :destroy`, so the order history goes with it),
ending a listening party for everyone listening, deleting a saved search, and
deleting a port comment.

**`model_no_validations`** — 11 findings, _artifact_, 0 real. `belongs_to` has been
required by default since Rails 5, so ten of these join and event records
(`Mention`, `Tagging`, `Tv::ViewEvent`, `Playlist::Listen`, `MessageReceipt`,
`TypingIndicator`, `Stream`, `PrivacySetting`, two `Session`s) already validate
presence of their associations — the rule only looked for an explicit `validates`.
The eleventh is `ApplicationRecord`, an abstract base class.

**`ctrl_index_no_pagination`** — 11 findings, _judgement_, ~2 real and not done.
`channels#index` is a small fixed set per city, `playlist/playlists#index` renders
nothing (immersive surface), and most of the rest are user-scoped and small. The
two that genuinely grow without bound are `bookmarks#index` and amber's
`connections#index`.

Not fixed here because `pagy` in the controller without pagination markup in the
view silently truncates at the default limit — which is worse than the unbounded
query, and is the "no silent caps" rule in this file's own header. Each of the two
needs controller *and* view, so it is a small piece of real work rather than a
one-line lint fix.

**`inline_style`** — 9 findings, _policy_. Seven are the correct pattern rather than
a violation: `style="--swatch: <%= … %>"` passes a runtime colour as a custom
property, which a stylesheet cannot do; `layouts/mailer` needs inline CSS because
email clients have no custom properties; `_ad_slot`'s `display:block` is required
by the ad script; and `users/new`'s `position:absolute;left:-9999px` is a honeypot
that must not be identifiable by class name. The takeaway order-progress width and
the icon sprite are the only two that could move to a custom property.

**`heading_skip`** — 5 findings, _judgement_. Real against the flat heading order
screen readers use — every one is an `<h3>` in an `<aside>` following an `<h1>`.
Not fixed because no stylesheet normalises `h2`/`h3`, so promoting them changes
rendered size on five sidebars. Either accept that, or promote and add one rule
sizing sidebar headings; both are visual decisions.

**`nbsp_entity`** — 5 findings, _judgement_. `~10&nbsp;km` in the chat widget is
correct typography and should stay. The other four are spacing hacks — three
separating inline meta on the dating profile, one reserving a line in the
marketplace nav — and replacing them means a flex `gap`, which changes layout.

**`css_blur`** — 3 findings, _policy_. Two are prose in a comment. The third,
`_popover_tooltip.scss:49`, is a real `filter: drop-shadow()` and the comment above
it documents why, which is what `pixel_perfection.exception_policy` requires of a
scoped exception.

**`img_no_dims`** — 6 findings, _artifact_. All six are `responsive_image_tag`,
which emits `srcset` and `sizes`; the rule looked for `width:`/`height:` and does
not know the helper's `widths:` argument.

**`button_div`** — 3 findings, _artifact_. Two are `click@window->dropdown#hide`,
a document-level listener rather than a control, and one is a modal backdrop.
Neither needs to be focusable.

**`css_line_height_tight`** — 2 findings, _artifact_. Both are on titles, and
`typography.line_height` allows 1.0–1.2 for headings; the rule applied the body
floor of 1.4 to everything.

**`target_blank_no_rel`** and **`form_no_autocomplete`** — _artifact_ after fixing
the one real instance of each. `_master_embed` already had `rel: "noopener"` and
`_newsletter_cta` already had `autocomplete: "email"`, both on the line after the
one flagged. This is the same single-line-regex fault as `rb_no_frozen_literal`
and `model_has_many_no_dependent`; it has now produced false positives in five
separate rules, and is the first thing to fix in any future version of these
scanners.

**`model_has_many_no_dependent`** — 8 findings, _artifact_, 1 real and fixed.
Same single-line-regex bug as `rb_no_frozen_literal`: the rule matched
`^\s*has_many :name(rest of that line)` and tested only that line for
`dependent:`. Every multi-line declaration keeps its options on the
continuation line —

```ruby
has_many :listens, class_name: "Playlist::Listen",
         foreign_key: :playlist_track_id, dependent: :destroy
```

— so `Playlist::Track`'s four associations, `Playlist::Playlist#playlist_tracks`
and `Marketplace::Listing#favorites` all already declared it and all six were
reported missing. I applied the "fix" first, which appended a second
`dependent: :destroy` to the end of line one and broke three files' syntax; the
revert is what proved they were already correct.

The one real gap was `Port#dependents` (`bsdports/app/models/port.rb:12`) — a
single-line declaration, and the only association on that model without it while
`:dependencies`, `:port_updates`, `:watches`, `:comments` and
`:security_advisories` all had it. Deleting a port left `Dependency` rows whose
`depends_on_id` pointed at nothing, and `:reverse_deps` reads through exactly
those rows. Fixed.

- [ ] `Marketplace::Listing#orders` reads like the same gap and is not: it
  already declares `dependent: :destroy`, which for orders is a decision rather
  than an oversight — destroying a listing destroys its order history. Left as
  found. Whether it should be `:restrict_with_error` instead (a listing with
  orders cannot be deleted) is a product call about financial records, not a
  lint fix.

**`rb_rescue_nil`** — 21 findings, _policy_. Checked every site: these are
deliberate, documented degradation, not swallowed errors.
`AffiliateConversion.parse_time` returning nil for an unparseable timestamp in a
third-party webhook payload is normal control flow; `ChannelPresence.read`
carries the comment "a presence count is never worth failing a request over";
`schema_url_for` and `story_url` omit a JSON-LD field rather than take a page
down over a routing gap.

What `soul.yml`'s FAIL_VISIBLY actually forbids is a bare `rescue` or
`rescue Exception`, and both of those rules fired **zero** times across the
whole tree. Adding a log line to 21 intentional fallbacks would add noise and
call it rigour. Left alone deliberately.

**`css_transition_no_easing`** — 83 findings, _open_. Real against `aesthetic_rules.CINEMA_PALETTE`, and safe to fix, but 83 declarations across four apps' stylesheets is a visual change to timing on every one. Wants one operator decision on the easing token, then a sweep.

**This rule and `unread_css_var` are the same finding from both ends, which is
the useful part.** Verifying the 27 unread custom properties by hand left 15 with
no reader at all, and three of them are `--ease-linear`, `--ease-in-out` and
`--ease-spring`. So the design system declares its easing curves and nothing
references them, while 83 transitions animate with no easing function. Neither
half looks broken on its own: the tokens are present, the transitions work.

That makes the decision cheaper than it first appears. It is not "pick an easing
value for 83 sites" — the values are already chosen and committed. It is one
question: are those three the intended curves? If yes, the sweep is mechanical
and the tokens stop being inert in the same pass. `--brand-mark-inline` was this
same shape — a named value declared for a bug, applied to one of the two bars
that needed it (P0.1).

The other twelve unread properties are `--showcase-chip`,
`--line-height-base`, `--elev-2`, `--maps-accent-soft`, `--playlist-success`,
`--food-card-radius`, `--c-danger`, `--c-code`, `--layout-max`, `--blue`,
`--grey`, `--luxury-accent`. `--blue` and `--grey` are pre-token names and read
as residue; the rest each want the same question as the easing three — give it a
reader or delete it. Deleting an unread declaration is not a visual change,
because by definition nothing renders from it.

**`ctrl_no_rate_limit`** — 64 findings, _judgement_. 64 controllers with a `create` and no `rate_limit`. Defence in depth, not a bug, and a mechanical sweep would throttle legitimate use at an arbitrary threshold. The subset worth doing deliberately is the write endpoints reachable without authentication.

**`dead_stimulus_controller`** — 2 findings, _fixed_. Both real, and the sweep found more. `futurism` stays (it is registered defensively and is the mechanism for fixing the 169-controller front page). `dialog`, `scroll-to`, `sound` and `speech-recognition` were imported, registered, pinned *and* vendored across four apps with no `data-controller` for any of them anywhere — removed.

**`emoji_in_view`** — 0 findings, _artifact_. 0 of 26 real. The character class included U+2190–21FF and U+2600–27BF, so it caught typographic arrows, stars, checks and a music note. Those are Swiss typography, not emoji; the WIRING rule is about feed action icons. Narrowed to pictographs; now fires 0.

**`hardcoded_copy`** — 129 findings, _open_. 129 English strings on a `default_locale: nb` site. Real and the largest remaining group. One is fixed (`nearby/_alert`'s "is nearby" and "Dismiss"); the rest need translation, not a script.

**`i18n_key_undefined`** — 0 findings, _artifact_. 0 of 26 real. The locale flattener recorded only scalar leaves, so every pluralised `{one:, other:}` key looked undefined, and engine views were scoped to the engine's own locales instead of the host app's. Corrected; the 2 remaining were Rails' own `errors.messages.*`, now excluded.

**`i18n_missing_nb`** — 0 findings, _fixed_. The one hit was `hello: "Hello world"` — Rails scaffold residue in `shared/config/locales/en.yml`, sole key, no reader anywhere. File removed.

**`magic_hex`** — 75 findings, _artifact_. ~0 of 75 real. 25 are in `_mailer_styles`, where WIRING_NOTES requires inline hex because email clients have no custom properties; 6 are PWA manifest `theme_color`, which must be literal JSON; 21 are SVG artwork fills in the brand logos and the dressing-room mannequin; 7 are `var(--token, #fallback)` fallbacks, which is the correct pattern.

**`model_assoc_no_inverse`** — 104 findings, _judgement_. 104 associations. Adding `inverse_of` changes in-memory object identity and interacts with `strict_loading_by_default = true`, which this family runs in every environment. That is a behaviour change per association, not a sweep.

**`model_no_scope`** — 67 findings, _policy_. Not a defect. Boy Scout item when next touching each model.

**`orphan_partial`** — 28 findings, _artifact_. Substantially wrong: the icon partials are reached through the `icon` helper, not a literal `render`, and the `public/assets/layouts/*.erb` entries were fingerprinted build output the scanner walked into. But 5 were real — see below.

**`rb_env_fetch_no_default`** — 10 findings, _artifact_. 10 of 93 real, and the rule was backwards. `ENV["X"].present?`, `ENV["CI"] == "1"` and `ENV["BUNDLE_GEMFILE"] ||=` are all correct: nil *is* the signal, and `ENV.fetch` there would raise instead of falling back. Narrowed to a bare read consumed as a value.

**`rb_hardcoded_domain`** — 5 findings, _artifact_. 5 of 66 real. The rest are third-party API endpoint constants (openrouter.ai, api.stripe.com, api.open-meteo.com, reddit.com) — correct as constants. Narrowed to our own hosts, which DomainRegistry owns.

**`rb_no_frozen_literal`** — 0 findings, _artifact_. 0 of 20 real. Rule anchored on line 1, so every shebang file that already had the comment on line 2 looked bare; the other 8 were generated schema dumps that must not carry it. Rule corrected; now fires 0.

**`rb_puts`** — 8 findings, _artifact_. 8 of 69 real. `db/seeds.rb` and `*/script/` write to stdout by design; only `app/` matters.

**`rb_time_now`** — 13 findings, _fixed_. 5 of 18 real, all fixed: `Conversation#mark_read_for!`, `Message` delivery receipts, amber's `PlannedOutfit.upcoming` scope, `WardrobeAI` item age, and the newsletter composer. The other 13 are correct as written — `Time.now.utc` for AWS request signing, `Time.now.to_i` for JWT `exp`/`iat` and for a temp filename, both zone-independent by definition.

**`rb_unscoped_all`** — 5 findings, _artifact_. 0 of 7 real. Two were `.all?`, the Enumerable predicate. The rest are a small fixed category list for a form select, and two relations that either pass through a paginator or get bounded in the view — see the fix under count_in_view.

**`rb_update_column`** — 12 findings, _fixed_. 3 of 12 real, all fixed: `User#update_karma!`, `Marketplace::Listing#update_rating!`, `Takeaway::Restaurant#update_rating!` now bump `updated_at`, so the displayed value leaves the fragment cache. `User`'s two other writers already did this, which is what identified the omission. The rest are seeds, a purge that is erasing the row anyway, and a location ping where bumping the timestamp on every GPS update would bust caches constantly — deliberately left.

**`unread_css_var`** — 27 findings, _open_. 27 custom properties with no `var()` reader. Real dead-config shape, and each needs checking against the JS that may read it via `getPropertyValue` before removal.

**`unused_css_class`** — 102 findings, _judgement_. 102 selectors with no literal match in ERB/JS/Ruby. Class names are also composed at runtime, so a literal search cannot prove death. Confirm per selector before deleting; low confidence by design.


## Itemised findings

Grouped by theme, most-frequent rule first, every item with its `file:line`.

## i18n and copy — 137 items

### hardcoded_copy — 129 · **open**

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

### placeholder_hardcoded — 5

Hardcoded placeholder text. Same rule — `placeholder:` is chrome copy. Law: `design_rules.ui_polish.chrome_i18n`.

- [ ] `brgen/engines/playlist/app/views/playlist/playlists/_player.html.erb:108`
- [ ] `brgen/engines/playlist/app/views/playlist/shared/_dilla_sketches.html.erb:70` — Paste JSON state from lab
- [ ] `bsdports/app/views/comments/create.turbo_stream.erb:5` — Add a comment…
- [ ] `bsdports/app/views/ports/show.html.erb:125` — Add a comment…
- [ ] `shared/frontend/examples.html.erb:27`

### submit_hardcoded — 3

Hardcoded submit button label. Submit labels are the highest-traffic chrome string on a form. Law: `design_rules.ui_polish.chrome_i18n`.

- [ ] `bsdports/app/views/comments/create.turbo_stream.erb:8` — <p><%= f.submit "Comment" %></p>
- [ ] `bsdports/app/views/ports/show.html.erb:128` — <p><%= f.submit "Comment" %></p>
- [ ] `shared/app/views/two_factor_setups/show.html.erb:15` — <%= f.submit "Enable 2FA", class: "btn btn-primary" %>

## Design tokens and magic values — 165 items

### magic_hex — 75 · **artifact**

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

### css_magic_hex — 56 · **judgement**

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

### css_font_px_hardcoded — 25

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

### inline_style — 9

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

### css_important — 128 · **policy**

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
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:99` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:100` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:88` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_nearby.scss:89` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_posts.scss:186` — animation: none !important;
- [ ] `brgen/app/assets/stylesheets/_posts.scss:187` — transition: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:70` — @media (prefers-reduced-motion: reduce) { *, *::before, *::after { animation: none !important; transition: non
- [ ] `brgen/app/assets/stylesheets/_root.scss:87` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:88` — border-radius: 0 !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:89` — outline: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:91` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:147` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:148` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:149` — border-width: 0 !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:150` — border-style: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:151` — border-color: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:152` — border-radius: 0 !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:153` — outline: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:154` — outline-offset: 0 !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:163` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:164` — outline: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:166` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:182` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:183` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:184` — outline: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:194` — background: transparent !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:195` — border: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:199` — outline: var(--focus-ring, 2px solid var(--accent)) !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:205` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:210` — display: none !important;
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

### css_autofix_scar — 11

`autofix:` comment left in the sheet. GATE_AUTOFIX stripped a property and left a marker; the declaration around it usually no longer needs to exist. Law: `aesthetic_rules.NO_ASCII_DECORATION`.

- [ ] `brgen/app/assets/stylesheets/_root.scss:90` — /* autofix: removed box-shadow (flat UI) */
- [ ] `brgen/app/assets/stylesheets/_root.scss:155` — /* autofix: removed box-shadow (flat UI) */
- [ ] `brgen/app/assets/stylesheets/_root.scss:165` — /* autofix: removed box-shadow (flat UI) */
- [ ] `brgen/app/assets/stylesheets/_root.scss:185` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_focus_ring.scss:10` — * Several of those suppressors are annotated `autofix: removed box-shadow (flat
- [ ] `shared/app/assets/stylesheets/_shell.scss:157` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell.scss:211` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell.scss:223` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell.scss:233` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:113` — /* autofix: removed box-shadow (flat UI) */
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:126` — /* autofix: removed box-shadow (flat UI) */

### css_zindex_magic — 9

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

### css_display_none_override — 9

display: none !important. Hiding an element the layout still renders. Delete the render instead of hiding the output. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `brgen/app/assets/stylesheets/_root.scss:205` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_root.scss:210` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:62` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:78` — display: none !important;
- [ ] `brgen/app/assets/stylesheets/_vertical_shell.scss:83` — display: none !important;
- [ ] `brgen/engines/dating/app/assets/stylesheets/_vertical_dating_shell.scss:58` — display: none !important;
- [ ] `shared/app/assets/stylesheets/_auth_form.scss:22` — display: none !important;
- [ ] `shared/app/assets/stylesheets/_shell.scss:312` — display: none !important;
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:523` — display: none !important;

### css_blur — 3

filter: blur / drop-shadow / backdrop-filter. Same flat rule. If deliberate it needs a documented exception at point of use. Law: `pixel_perfection.exception_policy`.

- [ ] `brgen/app/assets/stylesheets/_popover_tooltip.scss:4` — a drop-shadow behind the visible one since filter: drop-shadow() wasn't
- [ ] `brgen/app/assets/stylesheets/_popover_tooltip.scss:12` — filter: drop-shadow(), same shadowed-arrow look as the original.
- [ ] `brgen/app/assets/stylesheets/_popover_tooltip.scss:49` — filter: drop-shadow(0 2px 3px rgba(0, 0, 0, 0.35));

## 8px rhythm and geometry — 85 items

### css_off_grid — 83 · **artifact**

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

### css_radius_large — 2

border-radius above 16px. forbid_arbitrary_radius_px_above: 16. Law: `pixel_perfection.forbid_arbitrary_radius_px_above`.

- [ ] `amber/app/assets/stylesheets/_items.scss:89` — border-radius: 999px;
- [ ] `shared/app/assets/stylesheets/_search_yep.scss:8` — border-radius: 30px;

## Motion and easing — 135 items

### css_transition_no_easing — 83 · **open**

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
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:77` — transition: color var(--transition-fast), background var(--transition-fast), border-color var(--transition-fas
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:100` — transition: none !important;
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

### css_animation_present — 52 · **policy**

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
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:99` — animation: none !important;
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

### form_no_label — 18

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

### css_font_px_small — 10

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

### heading_skip — 5

Heading level skipped. Breaks the document outline screen-reader users navigate by. Law: `rams_checklist.understandable`.

- [ ] `amber/app/views/ai/occasion_map.html.erb:6` — h1 -> h3
- [ ] `brgen/app/views/communities/show.html.erb:50` — h1 -> h3
- [ ] `brgen/app/views/posts/index.html.erb:18` — h1 -> h3
- [ ] `brgen/app/views/posts/show.html.erb:90` — h1 -> h3
- [ ] `brgen/engines/marketplace/app/views/marketplace/orders/show.html.erb:28` — h1 -> h3

### button_div — 3

div/span carrying a click action. Not focusable, not keyboard-activatable, not announced as a control. Law: `ux_laws.fitts`.

- [ ] `brgen/app/views/layouts/application.html.erb:173` — <div class="sidebar-dropdown" data-controller="dropdown" data-action="click@window->dropdo
- [ ] `brgen/app/views/layouts/application.html.erb:283` — <div class="mobile-sheet-backdrop" data-bottom-sheet-target="backdrop" data-action="click-
- [ ] `brgen/app/views/posts/_post.html.erb:41` — <div class="feed-action-menu" data-controller="dropdown" data-action="click@window->dropdo

### form_no_autocomplete — 2

password/email field with no autocomplete. Blocks password managers. Law: `rams_checklist.useful`.

- [ ] `brgen/app/views/shared/_email_subscribe.html.erb:6` — <%= f.email_field :email, name: "email_subscription[email]",
- [ ] `shared/app/views/shared/_newsletter_cta.html.erb:7` — <%= form.email_field :email, name: "email_subscription[email]",

### css_line_height_tight — 2

line-height below 1.4. typography.line_height.body_min 1.4, accessibility_min 1.5. Law: `typography.line_height`.

- [ ] `brgen/app/assets/stylesheets/_marketplace_nav_bar.scss:29` — line-height: 1.2;
- [ ] `brgen/engines/tv/app/assets/stylesheets/_vertical_tv_cards.scss:115` — .tv-card-title { display: block; font-weight: 600; color: var(--text); line-height: 1.3; text-decoration: none

## Responsive and mobile — 72 items

### css_px_width — 72 · **artifact**

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
- [ ] `brgen/app/assets/stylesheets/_root.scss:246` — @media (min-width: 1265px) {
- [ ] `brgen/app/assets/stylesheets/_root.scss:251` — @media (min-width: 769px) and (max-width: 1264px) {
- [ ] `brgen/app/assets/stylesheets/_root.scss:256` — @media (max-width: 768px) {
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

## Performance — 42 items

### count_in_view — 18 · **fixed**

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

### ctrl_index_no_pagination — 11

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

### img_no_dims — 6

image_tag with no width/height. Missing intrinsic size causes layout shift (CLS). Law: `pixel_field.performance`.

- [ ] `brgen/app/views/maps/places/_card.html.erb:4` — <%= responsive_image_tag(place.photo, alt: place.name, loading: "lazy", class: "place-card
- [ ] `brgen/app/views/maps/places/show.html.erb:13` — <%= responsive_image_tag(@place.photo, alt: @place.name, class: "place-hero__image") %>
- [ ] `brgen/app/views/posts/_post.html.erb:72` — media: (post.image.attached? ? link_to(responsive_image_tag(post.image, alt: post.title, l
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:52` — <%= responsive_image_tag(item.photo, alt: item.name, loading: "lazy", class: "menu-row__ph
- [ ] `brgen/engines/takeaway/app/views/takeaway/restaurants/show.html.erb:85` — <%= responsive_image_tag(item.photo, alt: item.name, loading: "lazy", class: "menu-row__ph
- [ ] `brgen/engines/tv/app/views/tv/videos/_tv_video.html.erb:5` — <%= responsive_image_tag(tv_video.thumbnail, alt: tv_video.title, loading: "lazy", class: 

### rb_unscoped_all — 5 · **artifact**

Unbounded .all in a controller. No LIMIT; grows with the table. Law: `pixel_field.performance`.

- [ ] `brgen/app/controllers/search_controller.rb:24` — @results[:channels] = apply_live_search(Tv::Channel.all, columns: %w[name description], vertical: "tv")
- [ ] `brgen/app/controllers/search_controller.rb:28` — @results[:places] = apply_live_search(Place.all, columns: %w[name kind], vertical: "maps")
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/listings_controller.rb:56` — @categories = Marketplace::Category.all
- [ ] `brgen/engines/marketplace/app/controllers/marketplace/listings_controller.rb:77` — @categories = Marketplace::Category.all
- [ ] `brgen/engines/tv/app/controllers/tv/shows_controller.rb:7` — scope = (@channel ? @channel.shows : Tv::Show.all).published

### img_no_lazy — 2

image_tag with no loading:.  Law: `pixel_field.performance`.

- [ ] `brgen/app/views/maps/places/show.html.erb:13` — <%= responsive_image_tag(@place.photo, alt: @place.name, class: "place-hero__image") %>
- [ ] `shared/app/views/shared/_avatar.html.erb:5` — <%= image_tag(main_app.url_for(local_assigns[:user].avatar), class: "avatar #{size_class}"

## Security — 75 items

### ctrl_no_rate_limit — 64 · **judgement**

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

### rb_skip_forgery — 5

skip_before_action :verify_authenticity_token. Confirm each is a webhook with its own signature check. Law: `soul.absolute.protection_tiers`.

- [ ] `amber/app/controllers/fingerprints_controller.rb:7` — skip_before_action :verify_authenticity_token, only: :create
- [ ] `amber/app/controllers/items_controller.rb:14` — skip_before_action :verify_authenticity_token, only: [ :share ]
- [ ] `brgen/app/controllers/fingerprints_controller.rb:7` — skip_before_action :verify_authenticity_token, only: :create
- [ ] `brgen/app/controllers/posts_controller.rb:19` — skip_before_action :verify_authenticity_token, only: [ :share ]
- [ ] `shared/app/controllers/concerns/shared/internal_token_auth.rb:11` — skip_before_action :verify_authenticity_token, raise: false

### raw_html_safe — 4

raw() or .html_safe in a view. Each one is an XSS surface; confirm the source cannot be user input. Law: `soul.absolute.protection_tiers`.

- [ ] `brgen/app/views/shared/_link_converter.html.erb:6` — var epi = <%= raw(
- [ ] `brgen/engines/dating/app/views/dating/matches/_match.html.erb:9` — content: capture { %(<p class="feed-card-meta">Matched on #{match.created_at.to_date}</p>)
- [ ] `brgen/engines/tv/app/views/tv/home/index.html.erb:21` — content: capture { %(<span class="live-badge">Live</span>).html_safe },
- [ ] `shared/app/views/two_factor_setups/show.html.erb:6` — <div class="auth-form-qr"><%= @qr.html_safe %></div>

### target_blank_no_rel — 2

target=_blank without rel=noopener. Reverse tabnabbing. Law: `soul.absolute.protection_tiers`.

- [ ] `bsdports/app/views/ports/show.html.erb:92` — <%= link_to adv.identifier, adv.nvd_url, target: "_blank" %>
- [ ] `shared/app/views/shared/_master_embed.html.erb:28` — target: "_blank",

## Correctness — 72 items

### rb_rescue_nil — 21 · **policy**

rescue that returns nil. The failure becomes indistinguishable from an empty result — the exact shape of the dead-wiring bugs this repo keeps finding. Law: `soul.absolute.code_rules.FAIL_VISIBLY`.

- [ ] `brgen/app/helpers/application_helper.rb:206` — rescue StandardError
- [ ] `brgen/app/helpers/application_helper.rb:255` — rescue StandardError
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

### rb_time_now — 13 · **fixed**

Time.now / Date.today / DateTime.now. Timezone-unaware; use Time.current / Date.current. Law: `soul.absolute.code_rules.RTFM_FIRST`.

- [ ] `amber/app/controllers/internal_controller.rb:9` — generated_at: Time.now.utc.iso8601,
- [ ] `brgen/app/controllers/application_controller.rb:45` — "[tenant_access] tenant=#{tenant} ip=#{request.remote_ip} path=#{request.fullpath} at=#{Time.now.to_i}"
- [ ] `brgen/app/controllers/internal_controller.rb:11` — generated_at: Time.now.utc.iso8601,
- [ ] `brgen/app/services/amazon_associates.rb:145` — now = Time.now.utc
- [ ] `bsdports/app/controllers/internal_controller.rb:9` — generated_at: Time.now.utc.iso8601,
- [ ] `gates/lib/page_simulation.rb:45` — "generated_at" => Time.now.utc.iso8601,
- [ ] `gates/visual_contract.rb:190` — File.write(path, JSON.pretty_generate(generated_at: Time.now.utc.iso8601, results:) + "\n")
- [ ] `shared/app/services/shared/dilla_processor.rb:58` — kept = File.join(Dir.tmpdir, "dilla_#{Process.pid}_#{Time.now.to_i}.mp3")
- [ ] `shared/app/services/shared/sso_token.rb:51` — "exp" => Time.now.to_i + ttl.to_i,
- [ ] `shared/app/services/shared/sso_token.rb:52` — "iat" => Time.now.to_i,
- [ ] `shared/app/services/shared/sso_token.rb:72` — return nil if payload["exp"].to_i < Time.now.to_i
- [ ] `shared/app/services/shared/sso_token.rb:90` — ttl = [payload["exp"].to_i - Time.now.to_i, 0].max + NONCE_GRACE
- [ ] `shared/app/services/shared/sso_token.rb:117` — now = Time.now.to_i

### rb_update_column — 12 · **fixed**

update_column / update_columns. Skips updated_at, so `cache [record, ...]` fragments never bust. Known pub4 bug shape: the runner shows the new value and the page shows the old one. Law: `MASTER/DEBT.md`.

- [ ] `brgen/app/controllers/locations_controller.rb:22` — me.update_columns(latitude: lat, longitude: lng, location_updated_at: Time.current)
- [ ] `brgen/app/jobs/user_purge_job.rb:34` — user.update_columns(attrs)
- [ ] `brgen/app/models/message.rb:97` — update_column(:expires_at, expiry) if expires_at.nil?
- [ ] `brgen/app/models/user.rb:112` — update_columns(email_verification_token: token, updated_at: Time.current)
- [ ] `brgen/app/models/user.rb:117` — update_columns(email_verified_at: Time.current, email_verification_token: nil, updated_at: Time.current)
- [ ] `brgen/app/models/user.rb:139` — update_columns(karma: score, updated_at: Time.current)
- [ ] `brgen/app/services/moderation_workflow.rb:69` — content.update_columns(removed_at: Time.current, updated_at: Time.current)
- [ ] `brgen/db/seeds.rb:315` — ).tap { |restaurant| restaurant.update_column(:city, city_label) }
- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:75` — update_columns(rating: reviews.average(:rating)&.round(2) || 0, updated_at: Time.current)
- [ ] `brgen/engines/takeaway/app/models/takeaway/restaurant.rb:59` — update_columns(rating: avg&.round(1) || 0, updated_at: Time.current)
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:710` — playlist.update_column(:tracks_count, playlist.tracks.count) if playlist.tracks_count != playlist.tracks.count
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:848` — restaurant.update_column(:city, @city.name) if restaurant.has_attribute?(:city)

### rb_env_fetch_no_default — 10 · **artifact**

ENV["..."] instead of ENV.fetch. ENV[] returns nil silently; on the VPS a missing /etc/*.env key becomes a nil deep in a request. FAIL_VISIBLY. Law: `soul.absolute.code_rules.FAIL_VISIBLY`.

- [ ] `brgen/app/controllers/webhooks/tradedoubler_controller.rb:33` — ENV["TRADEDOUBLER_CONVERSIONS_TOKEN"].presence
- [ ] `brgen/app/services/amazon_associates.rb:43` — def access_key = ENV["AMAZON_ACCESS_KEY"].presence
- [ ] `brgen/app/services/amazon_associates.rb:44` — def secret_key = ENV["AMAZON_SECRET_KEY"].presence
- [ ] `brgen/app/services/amazon_associates.rb:45` — def partner_tag = ENV["AMAZON_PARTNER_TAG"].presence
- [ ] `brgen/app/services/tradedoubler.rb:46` — ENV["TRADEDOUBLER_CONVERSIONS_TOKEN"].presence
- [ ] `brgen/app/services/tradedoubler.rb:50` — ENV["TRADEDOUBLER_WEBSITE_ID"].presence
- [ ] `brgen/app/services/tradedoubler.rb:426` — ENV["TRADEDOUBLER_LANGUAGE"].presence # e.g. nb, no, en
- [ ] `gates/support/cdp_session.rb:44` — ENV["CHROME_PATH"],
- [ ] `gates/visual_contract.rb:199` — drift_max: ENV["VISUAL_DRIFT_MAX_RATIO"]&.then { |value| Float(value) }
- [ ] `shared/app/services/shared/demo_media/catalog.rb:28` — slug = ENV["DEMO_MEDIA_CITY"].presence

### rb_puts — 8 · **artifact**

puts in application code. Goes nowhere under a daemonised rc.d service. Use Rails.logger. Law: `soul.absolute.code_rules.SURFACE_ERRORS_FIRST`.

- [ ] `shared/lib/pub4/adhoc_empty_lint.rb:23` — puts "adhoc_empty_lint: #{findings.size} free-form empty line#{'s' unless findings.size == 1} " \
- [ ] `shared/lib/pub4/adhoc_empty_lint.rb:26` — puts " …" if findings.size > 20
- [ ] `shared/lib/pub4/chrome_i18n_lint.rb:83` — puts "chrome_i18n_lint: #{kind} #{count} (baseline #{baseline})#{note}"
- [ ] `shared/lib/pub4/chrome_i18n_lint.rb:89` — puts " …" if offenders.size > 30
- [ ] `shared/lib/pub4/dialect_token_drift_check.rb:13` — puts "dialect_token_drift_check: ok (shared_chrome/luxury values match design_tokens.yml everywhere)"
- [ ] `shared/lib/pub4/empty_state_lint.rb:31` — puts "empty_state_lint: #{findings.size} render#{'s' unless findings.size == 1} without action:/actions: " \
- [ ] `shared/lib/pub4/fallback_drift_lint.rb:49` — puts "fallback_drift_lint: ok (no stale var() fallbacks found)"
- [ ] `shared/lib/pub4/rhythm_lint.rb:40` — puts "rhythm_lint: ok (#{allowed.size}-value rhythm, all spacing tokens compliant)"

### rb_hardcoded_domain — 5 · **artifact**

Hardcoded external URL. brgen is multi-domain; a literal host defeats DomainRegistry and the 30 configured city TLDs. Law: `brgen/lib/brgen/domain_registry.rb`.

- [ ] `brgen/app/models/affiliate_voucher.rb:63` — track_url: voucher.track_url.presence || voucher.landing_url.presence || "https://brgen.no",
- [ ] `brgen/app/services/newsletter_edition_builder.rb:143` — "https://brgen.no"
- [ ] `brgen/lib/brgen/bergen_demo_seeder.rb:10` — LOCAL_AUDIO_BASE = ENV.fetch("RADIO_BERGEN_AUDIO_BASE", "https://ai.brgen.no")
- [ ] `shared/app/services/shared/demo_media.rb:72` — ENV.fetch("DEMO_MEDIA_USER_AGENT", "BrgenDemoSeed/1.0 (+https://brgen.no; demo content)")
- [ ] `shared/config/initializers/master_web.rb:3` — Rails.application.config.x.master_web_url = ENV.fetch("MASTER_WEB_URL", "https://ai.brgen.no")

### rb_rescue_inline_nil — 2

`rescue nil` modifier. Same rule, terser. Law: `soul.absolute.code_rules.FAIL_VISIBLY`.

- [ ] `brgen/lib/brgen/irc/server.rb:53` — socket.close rescue nil
- [ ] `shared/app/services/shared/dilla_processor.rb:129` — Process.kill("TERM", wait_thr.pid) rescue nil

### time_now — 1

Time.now / Date.today in a view. Ignores Rails' timezone; use Time.current. Law: `soul.absolute.code_rules.RTFM_FIRST`.

- [ ] `amber/app/views/planned_outfits/index.html.erb:6` — <%= f.date_field :planned_date, min: Date.today, class: "input" %>

## Models and data integrity — 190 items

### model_assoc_no_inverse — 104 · **judgement**

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

### model_no_scope — 67 · **policy**

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

### model_no_validations — 11

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

### model_has_many_no_dependent — 8 · **artifact (1 real, fixed)**

has_many with no dependent: option. Deleting the parent orphans children or trips an FK constraint. Law: `rams_checklist.thorough`.

- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:1` — has_many :orders
- [ ] `brgen/engines/marketplace/app/models/marketplace/listing.rb:1` — has_many :favorites
- [ ] `brgen/engines/playlist/app/models/playlist/playlist.rb:1` — has_many :playlist_tracks
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :audio_versions
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :listens
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :playlist_tracks
- [ ] `brgen/engines/playlist/app/models/playlist/track.rb:1` — has_many :timestamped_comments
- [ ] `bsdports/app/models/port.rb:1` — has_many :dependents

## UX and product truth — 57 items

### delete_no_confirm — 29

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
- [ ] `brgen/app/views/layouts/application.html.erb:299` — <%= link_to t("nav.sign_out"), main_app.session_path, data: { turbo_method: :delete, turbo
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

### list_no_empty_state — 28

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

## Dead wiring — declarations with no reader — 192 items

### unused_css_class — 102 · **judgement**

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

### orphan_partial — 28 · **artifact**

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

### unread_css_var — 27 · **open**

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

### target_no_controller — 18

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

### unused_locale_key — 14

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

### dead_stimulus_controller — 2 · **fixed**

Stimulus controller registered but never referenced. Ships JS that can never run. Law: `MASTER/DEBT.md inert config`.

- [ ] `shared/frontend/stimulus_boot.js` — registered 'futurism', no data-controller reference in any ERB
- [ ] `shared/frontend/stimulus_boot.js` — registered 'x-action', no data-controller reference in any ERB

### value_no_declaration — 1

data-*-value with no static values declaration. The value is written and never read. Law: `MASTER/DEBT.md inert config`.

- [ ] `views` — data-action-target-gid-value has no `targetGid:` in static values

## Cleanup and altitude — 139 items

### rb_long_method — 81

Method longer than 30 lines. Same rule at method scale. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `amber/app/controllers/ai_controller.rb:29` — suggest_outfits spans 33 lines
- [ ] `amber/app/helpers/application_helper.rb:37` — responsive_image_tag spans 32 lines
- [ ] `brgen/app/controllers/messages_controller.rb:13` — create spans 31 lines
- [ ] `brgen/app/controllers/search_controller.rb:8` — index spans 33 lines
- [ ] `brgen/app/controllers/users_controller.rb:42` — create spans 32 lines
- [ ] `brgen/app/helpers/application_helper.rb:18` — responsive_image_tag spans 31 lines
- [ ] `brgen/app/helpers/application_helper.rb:158` — record_public_href spans 47 lines
- [ ] `brgen/app/helpers/application_helper.rb:226` — notification_href spans 31 lines
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

### css_vendor_prefix — 24

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
- [ ] `brgen/app/assets/stylesheets/_nav_swiper.scss:46` — .nav_swiper_bar::-webkit-scrollbar { display: none; }
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

### rb_file_too_long — 13

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

### scss_file_too_long — 7

SCSS partial over 400 lines. SIMPLEST_WORKS: split by surface. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `amber/app/assets/stylesheets/_brand.scss:441` — 441 lines
- [ ] `brgen/app/assets/stylesheets/_chrome_polish.scss:405` — 405 lines
- [ ] `bsdports/app/assets/stylesheets/application.scss:532` — 532 lines
- [ ] `shared/app/assets/stylesheets/_minimal.scss:642` — 642 lines
- [ ] `shared/app/assets/stylesheets/_shell.scss:565` — 565 lines
- [ ] `shared/app/assets/stylesheets/_shell_widgets.scss:540` — 540 lines
- [ ] `shared/app/assets/stylesheets/_zen_shell.scss:578` — 578 lines

### nbsp_entity — 5

&nbsp; entity. Usually a spacing hack; use padding/gap. Law: `layout_rules.whitespace.gap_over_margin`.

- [ ] `brgen/app/views/nearby/widget.html.erb:9` — <span>~10&nbsp;km</span>
- [ ] `brgen/engines/dating/app/views/dating/profiles/show.html.erb:43` — &nbsp;
- [ ] `brgen/engines/dating/app/views/dating/profiles/show.html.erb:45` — &nbsp;
- [ ] `brgen/engines/dating/app/views/dating/profiles/show.html.erb:54` — &nbsp;
- [ ] `brgen/engines/marketplace/app/views/marketplace/_nav_bar.html.erb:49` — <span class="nav-line-1">&nbsp;</span>

### class_soup — 4

Element with 6+ classes. UI_REFINEMENTS "Full ERB class-soup -> bare semantic HTML" is still open. Law: `aesthetic_rules.FLAT_HIERARCHY`.

- [ ] `amber/app/views/ai/occasion_map.html.erb:5` — 6 classes: occasion-card occasion-card--<%= items.size < 2 ?
- [ ] `bsdports/app/views/ports/_row.html.erb:9` — 8 classes: data-state <%= age && age >
- [ ] `bsdports/app/views/ports/show.html.erb:24` — 8 classes: data-state <%= update_age && update_age >
- [ ] `shared/app/views/shared/_feed_card.html.erb:21` — 7 classes: feed-card-avatar-placeholder monogram monogram--<%= monogram.ord % 6

### view_too_long — 4

View over 150 lines. SIMPLEST_WORKS — extract partials. Law: `soul.absolute.code_rules.SIMPLEST_WORKS`.

- [ ] `amber/app/views/layouts/application.html.erb:153` — 153 lines
- [ ] `brgen/app/views/layouts/application.html.erb:314` — 314 lines
- [ ] `brgen/app/views/pwa/manifest.json.erb:156` — 156 lines
- [ ] `brgen/engines/playlist/app/views/playlist/playlists/_player.html.erb:173` — 173 lines

### rb_todo — 1

TODO/FIXME in Ruby.  Law: `MASTER/DEBT.md`.

- [ ] `shared/app/helpers/shared/consent_helper.rb:10` — # rather than a TODO, and so wiring a CMP later is one method body rather
