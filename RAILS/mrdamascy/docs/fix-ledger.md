# Mr Damascy /fix ledger

One chronological record of the app's repair passes. The entries retain their
original verification state; the 2026-11-01 source-only pass was not suite
verified, while the 2026-11-02 pass records the later full-suite/browser run.

## 2026-11-01 — source-level pass

Terminal state: **DONE for source-level coverage; suite verification NOT_RUN** (no Rails
bundle in this sandbox — `rails test` could not execute; recorded per fix hygiene #8).

Instrument: `scripts/fix_mrdamascy.py` — 19 checks (APP_SPEC §16.1–16.9 + ports of
MASTER checks css_brace_balance, schema_migration/route_controllers, pwa_installable,
payment_honesty, stimulus wiring, locale parity, and law detectors from
law/{css,html,javascript,brand,rails,fix_hygiene}.rb). Instrument sanity: first run
found 46–1065 findings (including deliberate probe bugs later fixed in the port), so a
green run is not a vacuous pass. Final run: **0 findings, 18 PASS, 1 SKIP/NOT_RUN.**

## Repairs applied (impact order)

Critical — payment & correctness:
1. `VippsController` — mock endpoints gated on `mock_mode?` via halting
   `head :not_found`; in real mode a mock approval could previously capture an
   order no PSP reserved. Regression test added (`checkout_flow_test.rb`,
   real-mode 404 for GET mock + PATCH approve). [payment_honesty]
2. `views/loyalty/show` — read `@stamps`, which no controller sets (always
   empty card), and called `t("loyalty.progress", n:)` on a nested hash →
   guaranteed crash with raise_on_missing_translations. Rewritten on
   `@stamp_slots/@unredeemed/@free_wrap_ready` + real keys
   `loyalty.progress.remaining|.ready`, `loyalty.filled` with count+total.
3. `views/courier/runs/show` — read `@orders`, never set (page always empty).
   Now renders `@ready_orders` / `@on_the_way_orders`.
4. `ReviewsController` — ignored `params[:review]` (AGENTS.md contract) so the
   test-posted rating collapsed to 1. Accepts both shapes, mirroring
   `checkout_params`. [fix_hygiene D: one dispatch path]
5. `Order#snapshot_from_cart!` — used `order_items.create!` on a possibly-new
   order (RecordInvalid on the documented OrderTest path) and was duplicated
   as an inline build-loop in `CheckoutController#create`. One implementation:
   builds on new records, creates on persisted; subtotal via `sum(&:…)`.
   [RAILS_THIN_CONTROLLER_SEMANTIC + fix_hygiene D: twin deleted]
6. `CheckoutController` — `rescue_from VippsClient::NotAvailable` renders the
   confirm screen honestly (503, cart intact, `checkout.payment_unavailable`
   nb+en) instead of a raw 500; `load_checkout_vars` honors the cart page's
   `?mode=` toggle and provides `@returning_customer` (query removed from view).

MASTER laws:
7. CSP activated (nonce-bearing, `object_src none`, `frame_ancestors self`,
   report-only until `MRDAMASCY_CSP_ENFORCE=1`). [security_headers source contract]
8. Skip link + `main#main-content`. [SKIP_TO_MAIN, WCAG 2.4.1]
9. View purity: all queries/`rescue StandardError`/`defined?` guards removed
   from 12 views; menu catalog preloads `MenuCategory#available_items` (with
   options) so views present; shell aggregation moved to
   `ApplicationController#cart_count/cart_subtotal_ore`. [RAILS_VIEW_PURITY,
   N_PLUS_ONE, MODIFIER_SILENT_RESCUE]
10. `join(" · ")` glyph strings (6 sites) → `ul.fact-list` elements.
    [NO_DOT_SEPARATED_META / LINEARITY]
11. Mock-OTP paragraph deleted from `sessions/new` — it leaked "1234" in every
    environment; dev notice already renders via the flash toast. [fail_visibly,
    fix_hygiene D: dual path]
12. `is-hidden !important` → native `hidden` attribute in zone_check; class
    deleted. [NO_IMPORTANT]
13. Logical properties: `margin-left/right`, `border-left` → `inline-start/end`.
    [LOGICAL_PROPERTIES]
14. Off-palette hexes promoted to tokens (`--gold-100/150`, `--gold-ink/-deep`,
    `--pom-100`, `--fog`, `--on-dark-dim`); `#ffffff` text → `var(--paper)`.
    Rendered values unchanged. [MAGIC_COLOR]
15. `.muted` → `.ink-soft` app-wide (one consistent role name).
    [PRESENTATIONAL_CLASS_NAME]
16. JS: `data?.ok` optional chaining, redundant `&&`-guard removed, dead
    `@cache_version` assign → constant. [OPTIONAL_CHAINING, SIMULATION]
17. `VippsClient` real mode: explicit `open_timeout: 5, read_timeout: 10`.
    [EXPLICIT_HTTP_TIMEOUT]
18. Raw `item.origin` (underscored slug) in item sheet/card → `origin_label`;
    origin story resolved via `origin_story_key` helper (14-line hash deleted).
19. Track timeline keeps progress lit through `picked_up` (was: visual reset).
    [AESTHETIC_RAMS_SEMANTIC — honest progress]
20. Service-worker dead assign removed; docs moved with behavior
    (README real-mode guards, AGENTS.md CSP/I18n/view-purity/fact-list rules).

## Fix-hygiene checklist
A numeric ranks n/a · B extract-then-match n/a · C regex fixtures n/a (no new
extractors) · D dual paths: #5, #11 merged/deleted · E source pins n/a ·
F event topics n/a · G limits/guidance n/a. All edits re-read after write;
`ruby -c` × 73, ERB compile × 22, YAML × 2 re-verified green.

## NOT_RUN / remaining (named, with reason)
- `rails test` (and `db:migrate` → real `db/schema.rb`): no Rails bundle in the
  sandbox — the suite is authored and syntax-verified only. Run
  `bundle install && rails db:prepare && rails test` on a machine that can.
- **Strict loading** (MASTER law, every environment): deliberately not enabled —
  ~6 production sites (`OrdersController#index/show/track`, `ReviewsController`,
  `Staff::BoardController#advance`, `Session#user` in `current_user`) and ~8
  test touch-points still lazy-load associations. Present-tense reason recorded
  at the owning boundary (`app/models/application_record.rb`): flip
  `strict_loading_by_default = true` in the same commit that adds the includes,
  proven by the running suite.
- Rendered/browser checks (rendered_geometry, mobile_flow, viewport_spill,
  tap_target 44px): need a booted app + Chromium — NOT_RUN here.
- Waived, with reason: loading-shimmer and sheet-footer gradients (fade to
  transparent — functional edge, spared by the law); `--shadow` token (declared
  operator value, APP_SPEC §1 "no heavy shadows" — RENDERED_VALUES boundary).

Files changed: 5 controllers + 3 models + 1 service + 17 views + 9 stylesheets +
2 JS + 2 locales + 1 initializer + 1 test + README + AGENTS.md = 43 files.

---

# /fix ledger — pass 2 — 2026-11-01 (post-re-analysis of latest pub4 e32ad6e)

Trigger: user re-analysis order ("reanalytze latest github pub4"). `git pull --ff-only`
13c3f05..e32ad6e (3553 mode-only diffs reset first, zero content drift). Latest
MASTER/README + AGENTS.md re-read: /fix definition unchanged in substance —
"One verb that writes", DONE/PLATEAU/BLOCKED/VALIDATION_FAILED, layout loop of
`bin/operator design` for single-app RAILS targets, visual pass "missing live
evidence remains inconclusive". design_baseline.yml unchanged (30 rule_ceilings).
New upstream work is brgen MapLibre clustering + Turbo-stream consolidation —
no convention change affecting __other/.

Instrument re-run: 30 design Laws audited by hand across 23 views + 15 SCSS
(MOBILE_FIRST, LOGICAL_PROPERTIES, MAGIC_COLOR, NO_IMPORTANT, NO_LONG_TRANSITION,
MEASURE_OPTIMUM, BEM_IN_VIEWS, NO_INLINE_STYLES, SINGLE_H1, HTML_LANG, META_CHARSET,
SKIP_TO_MAIN, IMG_ALT, BUTTON_OVER_ANCHOR, ARIA_*, FORM_LABEL, TABINDEX, UTILITY_...)
— all green from pass 1. Visual/measured sweep then found the chrome-level defects
pass 1's law checks cannot see:

Repairs applied (pass 2):
1. **Brand fact** — logo.svg + og-card.png read "SHAWARMA · KEBAB · OSLO";
   the only outlet is Bergen. `scripts/make_logo.py` fixed, assets regenerated
   (logo.svg, og-card.png; PNG icon set re-derived from icon.svg which had no text).
2. **Emoji chrome → SVG icon set** — tab bar (🧆🛍⭐⋯) replaced with inline
   stroke SVGs (Lucide ISC: utensils/bag/ellipsis) + the khatam 8-point star as
   filled polygon, all `currentColor` so .tab-active recolors them; `_tab_bar.scss`
   .tab-icon rebuilt as a 24px flex box. Emoji render unpredictably per platform —
   the badge still positions on `.tab-icon` (now the bag SVG wrapper).
3. **One partial for mode glyphs** — `shared/_mode_icon.html.erb` (bike =
   delivery, storefront = pickup). Replaced 🛵 in orders/show, orders/track,
   staff board card; 🏃 → storefront in orders/show pickup branch; 📞 → phone
   SVG on the board card; 🫀 → SVG heart in the Vipps mock approve button.
   `.mode-icon` (mint-700, vertical-align −2px) in _utilities.scss;
   `.vipps-heart` in _buttons.scss. Hero ⭐ rating → gold khatam SVG
   (`.hero-rating`, gold-deep) in menu/show.
4. Deliberate keeps: item/category emoji tiles (content, flat-pastel design
   language — items have no photography), typographic ★/✓/✦ glyphs, README
   title emoji (prose, not a view).

Verification (pass 2): `ruby -c` × 78 (76 app/config/db/test + Rakefile +
config.ru) OK; ERB compile × 23 OK; YAML × 7 OK; node --check × 9 OK;
re-audit of all law detectors green; visual render verified via regenerated
`download/mrdamascy-ui-preview.png` (SVG chrome, BERGEN, Vipps button honest).
Suite execution remains NOT_RUN (no Rails bundle in sandbox) — same record as pass 1.

Files changed (pass 2): make_logo.py + logo.svg + og-card.png (regenerated) +
layout + menu/show + orders/show + orders/track + staff/_order_card + vipps/mock +
new shared/_mode_icon + _tab_bar.scss + _menu.scss + _utilities.scss +
_buttons.scss + APP_SPEC.md + AGENTS.md + README.md + wolt_drive_client.rb +
wolt_drive_client_test.rb = 20 files.

## Wolt/Foodora API decision (research-backed, pass 2)
- Wolt Drive API (developer.wolt.com/docs/wolt-drive): two-step flow confirmed —
  step 1 `/shipment-promises` (availability+fee+ETA), step 2 `/deliveries`, then
  webhooks + tracking URL. Client now implements BOTH steps (`shipment_promise`
  added, mock quotes 49 kr/35 min; real mode documented). Zero-code fallback
  documented: Wolt Drive Web (drive.wolt.com).
- Foodora (Delivery Hero Restaurant Integration API): confirmed POS-plugin-only
  (PGP credentials, local rep, vendor app accept loop) — no white-label courier
  API; integrating would re-insert the middleman + commission. Deliberately not
  integrated; the staff board remains the seam if a marketplace channel is ever
  wanted.

## 2026-11-02 — promoted app and live verification

Terminal state: **DONE — suite verified.** 126 runs, 497 assertions,
0 failures, 0 errors, 0 skips (Ruby 3.4.7 / Rails 8.2.0.alpha, SQLite).
APP_SPEC §16 cross-checks all pass (syntax, ERB compile, YAML + locale
parity 437 keys, used-key resolution 220, controller files, no
unfinished markers, migration table guard). All work verified live
against `rails s` with a real browser session.

## Operator-mandated work (user directive, 2026-11-02)

1. **Real kitchen identity.** The restaurant is the actual Mr. Damascy at
   Danmarksplass: Solheimsgaten 60, 5054 Bergen, phone 955 55 600,
   hours Man–Fre 11–21 · Lør–Søn 14–21 (from the live webflow site, cross-
   checked against its contact page). Updated `db/seeds.rb` (kitchen + new
   own zone 5054 Danmarksplass), `test/test_helper.rb` seed kitchen,
   locales nb/en (pickup note/line, about story, footer hours/address/
   line), `wolt_drive_client.rb` pickup coordinates (60.3757, 5.3379 from
   the restaurant's Google Maps listing), menu_item/application comments,
   `menu_controller_test` hours assertion.
2. **Logo = exact trace of the operator's bitmap.** VTracer (color,
   stacked, spline) at 96.3 % exact pixel match (residual = edge
   antialiasing). Rebuilt `public/logo.svg` (bg kept, exact),
   `logo-transparent.svg` (all background-colour paths removed, verified
   0 dark-opaque px), `icon.svg` (960² brand tile), and every raster
   (152/192/512, maskable 192/512, apple-touch 180, favicon.ico 16/32/48,
   og-card 1200×630). Instrument: `scripts/build_logo_assets.py`,
   fidelity harness `scripts/logo_to_svg.py`.
   **Resolution (2026-11-02, operator revert): the rebuild was rolled
   back.** The logo is already in use at the restaurant, so the original
   `public/` assets were restored byte-for-byte (revert `acf86ae`) and
   the two extra files (`logo-transparent.svg`, `icon-maskable.svg`)
   were dropped to match the pre-existing icon set. APP_SPEC, README and
   AGENTS now describe the assets as retained originals; do not
   regenerate. The 96.3 % figure above survives only as the fidelity
   record of the discarded attempt.
   **Reversed 2026-11-03:** the restored "originals" were the generated
   chef illustration (DejaVu text, three <text> nodes), not the
   restaurant's mark; the owner chose the trace, so d27be96e26's assets
   are back in public/ and the docs describe them as the restaurant's own.
3. **Second payment lane — Stripe Checkout.** Additive migration
   `20261101000020_add_payment_method_to_orders` (orders.payment_method,
   default "vipps", indexed). `StripeClient` (Net::HTTP, Checkout Sessions
   API, exact-øre unit_amount, Idempotency-Key, HMAC webhook signature
   ±5 min, mock-by-default, `NotAvailable` fail-fast) mirrors
   `VippsClient`. `PaymentGateway` = single dispatch seam
   (normalize!/init!/sync!). `StripeController` (mock/approve/callback,
   CSRF-exempt webhook, checkout_session-object filter, 404 guard in real
   mode). Routes: the three `stripe/*` (documented in routes.rb header).
   Checkout: two `button_tag` CTAs submit their own payment_method value
   (no script, no card fields — Stripe hosts card entry). Locales nb/en
   `stripe.*` + `checkout.stripe_*` (parity-checked). Tests: 25 new
   (client contract, webhook matrix, card-lane crown, unknown-PSP
   fallback, real-mode 404 guard, tracking-poll capture).
4. **Food photos, MASTER artwork lane g3 style.** 25 generated studio
   shots (flat pale-mint background, no text/watermark per
   artwork.yml `text_in_artwork: forbidden_for_diffusion`), square-cropped
   → 640px JPG q82 (~1.9 MB total), promoted to
   `app/assets/images/food/` with `provenance.json` sidecar
   (pipeline/house rules/per-file). Views: `.item-photo` card tile +
   `.sheet-photo` sheet hero via `ApplicationHelper#food_photo` name map,
   emoji fallback for any unmapped item. Instrument:
   `scripts/gen_food_photos.sh` + `scripts/promote_food_photos.py`.

## Repairs applied (found during live verification)

5. **Stimulus was silently dead in the browser.** `controllers/index.js`
   imported `./application` (and each controller) with *relative*
   specifiers; from Propshaft's digested URL those resolve to undigested
   paths → 404 → the whole module graph failed, so no Turbo, no Stimulus,
   no zone feedback, no mock-approve shimmer — while every server-side
   test still passed (they bypass JS). Fixed by importing through the
   importmap pins (`controllers/application`,
   `controllers/<name>_controller`); verified live: zone_check renders
   "Klar i 15 min · levering 29 kr", mock approval completes via the real
   click path. Guard comment added in `controllers/index.js` and AGENTS.md
   import-discipline rule.
6. **Checkout CTAs printed their values.** `f.submit(label, name:, value:)`
   renders the *value* as the label ("vipps"/"stripe"). Switched to
   `button_tag ... do` blocks so the localized labels ("Betal med Vipps"/
   "Betal med kort") render while each button still submits its own
   `payment_method` value.

## Reference material captured

- `RAILS/__other/mrdamascy_1.png` — webflow frontpage (full page)
- `RAILS/__other/mrdamascy_2.png` — webflow contact page (email
  mr.damascy@hotmail.com, phone 95555600, address, form)
- `RAILS/__other/mrdamascy_3.png` — webflow "Om Oss" page (brand story)
- App screenshots `screenshots/07–11` — live menu with photos, item
  sheet, dual-lane checkout, mock Stripe page, confirmed tracking page.
- `brgen_takeaway` integration path documented in README (per-order
  payment lanes, public token tracking seam, øre-integer money rule).
