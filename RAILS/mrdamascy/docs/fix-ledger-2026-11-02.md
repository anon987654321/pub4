# /fix ledger — RAILS/__other/mrdamascy — 2026-11-02

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
