# AGENTS.md — contributor contract for mrdamascy

**Read `APP_SPEC.md` first, in full.** It is the single source of truth for this app (routes §3, schema §4, services §5, controllers §6, views §7, Stimulus §8, SCSS §9, locales §10, seeds §11, Vipps Express §12, research credits §13, tests §14, docs §15, validator §16). Implement exactly against it — no deviations, no extra gems, no schema drift. **Operator-mandated deltas of 2026-11-02 are part of the spec** (see the header of APP_SPEC.md): the real Danmarksplass kitchen identity, the Stripe Checkout second payment lane, the restaurant's own logo, as a vector trace and the generated food photos.

## Where this app lives

```
RAILS/mrdamascy/                   ← you are here (standalone Rails 8 app, amber pattern)
```

Integration rules with the monorepo:

- The app lived inside `RAILS/__other/` until 2026-11-02, deliberately outside the contract roots while under construction. It is now a first-class app at `RAILS/mrdamascy/` with an `apps.yml` entry; it still must not break or be broken by `MASTER/`, or the contract-tested apps (amber, brgen, bsdports, radio …).
- **Do not touch** `MASTER/`, `apps.yml`, other apps, or anything above the app root. Do not edit `APP_SPEC.md` (proposals go through the spec owner).
- Do not depend on `__shared/` (no `Shared::` libs, no shared coverage/test_defaults tooling) — this app is standalone and self-contained, same pattern as amber's core but with its own plain `test_helper.rb`.

## File map

```
mrdamascy/
├── APP_SPEC.md              # ← source of truth, read first
├── README.md                # brand story, Foodora comparison, run guide
├── AGENTS.md                # this contract
├── config/
│   ├── routes.rb            # §3 verbatim + §8's checkout/zone + the operator-mandated stripe/* trio
│   ├── application.rb       # module MrDamascy
│   └── locales/
│       ├── nb.yml           # DEFAULT locale (Norwegian first)
│       └── en.yml           # full mirror — identical key tree, both complete
├── db/
│   ├── migrate/             # 20261101000001…, id: :integer, only §4 tables/columns
│   └── seeds.rb             # idempotent world-tour catalog (destroy_all → reseed)
├── app/
│   ├── models/              # User, Session, Kitchen, DeliveryZone, MenuCategory,
│   │                        # MenuItem, ItemOption, Cart, CartItem, Order, OrderItem,
│   │                        # PromoCode, LoyaltyStamp, Review
│   ├── controllers/         # menu, carts, checkout, vipps, orders, reviews, sessions,
│   │                        # loyalty, pages, pwa, staff/board, courier/runs
│   ├── services/            # vipps_client.rb, stripe_client.rb, payment_gateway.rb,
│   │                        # wolt_drive_client.rb, promo_applier.rb
│   ├── views/               # §7 list, partials in shared/, stripe/mock.html.erb
│   ├── javascript/controllers/  # item_sheet, cart_bar, zone_check, vipps_mock, track, toast
│   └── assets/stylesheets/  # _tokens, _base, _buttons, _cards, _tab_bar, _menu, _cart,
│                            # _checkout, _tracking, _staff, _loyalty, _forms, _utilities
└── test/
    ├── test_helper.rb       # sign_in helpers + inline seed helpers, no fixtures
    ├── models/              # menu_item, order, promo_applier, delivery_zone
    └── controllers/         # menu, carts, checkout_flow (crown), staff_board, track_tip
```

## Conventions (hard rules)

- **Money in øre.** Every money column is an integer named `*_ore` (`price_ore`, `fee_ore`, `min_basket_ore`, `total_ore`, …). Helper `money(1500)` → `"15 kr"`. Never floats, never decimal columns.
- **i18n namespaces are fixed** (§10): `app, nav, menu, origins, cart, checkout, vipps, orders, loyalty, staff, courier, auth, flash, about, offline, footer` — plus the sub-namespaces `menu.heat` (0–3 labels) and `orders.states` (7 states). Every `t()` key used anywhere must exist in **both** `nb.yml` and `en.yml` with identical key trees. Norwegian carries the warmth (Ahlan!/Yalla!/Sahtein!), English mirrors it.
- **Origins are lowercase city slugs** stored on `menu_items.origin` (`damaskus, beirut, berlin, adana, bergen, dubai, tel_aviv, bursa, gaziantep, familie, stockholm, sydney`) and resolved in views via `t("origins.#{item.origin}")`.
- **No gems beyond Rails defaults.** `VippsClient` and `StripeClient` use `Net::HTTP` from stdlib; `PaymentGateway` is the single dispatch seam between the two lanes (`orders.payment_method`, default `vipps`). No OmniAuth, no Devise, no sidekiq, no rspec.
- **Auth** is phone + mock OTP (`1234` in dev/test) with a plain `Session` model and a `session_token` cookie. Roles are an integer enum on users: customer 0, staff 1, courier 2, admin 3.
- **Mobile-first 480 px shell.** Bottom tab bar (Meny/Bestill/Klubb/Mer), max-w-[480px] main, desktop shows the phone column on `--bg-page`. Design tokens from §1, aligned with MASTER/data/tokens.yml (flat UI: no box-shadow/blur/gradient ornament; radii ≤ 16px + pill; MASTER shared_chrome type scale via --text-* tokens; 8px spacing rhythm; every interactive target ≥ 44px, primary CTAs 48px; contrast ≥ 4.5:1 for text — mint-700 `#276b55` is the action tone, mint-600 is boundary-only). 8-point star pattern on hero, loyalty card, staff header.
- **One Bergen outlet.** Kitchen: Solheimsgaten 60, 5054 Bergen at Danmarksplass (`db/seeds.rb`, `test/test_helper.rb`); delivery zones are central-Bergen postcodes 5003–5221 including the kitchen's own 5054; `config.time_zone = "Europe/Oslo"` is correct for Bergen too — do not "fix" it.
- **Wolt Drive is the overflow courier lane.** `Staff::BoardController#wolt_dispatch` books a last-mile courier for a ready delivery order via `WoltDriveClient` (mock by default — `WOLT_DRIVE_MOCK=0` + `WOLT_DRIVE_API_TOKEN` + `WOLT_DRIVE_CLIENT_ID` for real mode). The client mirrors the documented two-step Drive flow: `shipment_promise` (POST `/shipment-promises` — availability, fee, ETA, quoted before dispatch) then `request_delivery` (POST `/deliveries`) with `delivery_status` polling until a webhook receiver exists. Orders store `external_delivery_id`/`external_delivery_url`. Foodora's Restaurant Integration API is deliberately NOT integrated (marketplace commission — see README).
- **CSP is active** (`config/initializers/content_security_policy.rb`): nonce-bearing `script-src 'self'`, `object_src none`, `frame_ancestors self`, report-only until `MRDAMASCY_CSP_ENFORCE=1`. No inline `<script>`/`<style>` blocks and no inline `style=` attributes anywhere — the importmap bootstrap is the only nonce'd inline script.
- **No hardcoded strings in views.** Every user-facing literal rides an I18n key present in **both** locales; the skip link (`nav.skip`) and checkout's honest payment failure (`checkout.payment_unavailable`) included. State/heat/origin labels resolve dynamically (`t("orders.states.#{state}")`, `t("menu.heat.#{n}")`, `t(origin_story_key(origin))`).
- **Views present assigns.** Queries, aggregations and mode decisions live in controllers/models (`MenuCategory#available_items` preloaded catalog, `ApplicationController#cart_count`/`cart_subtotal_ore` for the shell, `CheckoutController#load_checkout_vars`); views never query, never `rescue`, never `defined?`-guard controller helpers.
- **Facts get their own elements.** Order item summaries, option lists and run metadata render as `ul.fact-list` items — no joined `" · "` glyph strings between facts.
- **Stimulus controllers (only these six):** `item_sheet`, `cart_bar`, `zone_check`, `vipps_mock`, `track`, `toast`. Every `data-controller` in a view must have its file present. **Import discipline (Propshaft):** controller modules import each other only through the importmap pins (`controllers/application`, `controllers/<name>_controller`) — a relative `./x` inside a digested URL resolves undigested and 404s, which silently kills every Stimulus binding (fixed 2026-11-02; do not reintroduce).
- **State machine (plain methods on Order, no gem):**
  - `advance!` (staff): placed → confirmed → preparing → ready (staff stops at ready)
  - `pickup!` (courier): ready → picked_up
  - `deliver!` (courier): picked_up → delivered (awards the LoyaltyStamp)
  - `cancel!`: only before preparing
  - Guards refuse illegal jumps (raise or `false`); payment flow is `pending → authorised (init) → captured (approve)`.

## Who owns what (task split used to build this)

| Task | Owns |
|---|---|
| 5 | Models, migrations, seeds (§4, §11) |
| 6 | Routes, controllers, services (§3, §5, §6) |
| 7 | Views, Stimulus, SCSS, PWA assets (§7–§9) |
| 8 | Locales (§10), test suite (§14), README + AGENTS (§15) |

Cross-task contracts introduced by task 8's tests (keep these exact or update the tests in the same commit). The model layer already implements most of these — the tests are written against it:

- `PromoApplier.call(subtotal_ore:, delivery_fee_ore:, mode:, user: nil)` → `{ promo:, discount_ore:, delivery_fee_ore: }` (result shape confirmed by `Order#apply_promo_result!`); free-delivery promos zero `delivery_fee_ore` (not `discount_ore`); ≥ 9 unredeemed stamps → discount = cheapest wrap `price_ore`.
- `DeliveryZone.for_postcode(postcode)` (whitespace-tolerant lookup) and `DeliveryZone#covers?(subtotal_ore)` — the min-basket rule the checkout relies on.
- Order flow: `Order#snapshot_from_cart!(cart)` (denormalised order_items + subtotal) → `Order#compute_totals!(zone, promo_result = nil)` (fee/eta/total; pickup = 0 fee, nil eta) → `Order#apply_promo_result!(result)` → `Order#add_tip!(ore)` (raises `ArgumentError` on non-positive — the 0-kr tip chip must be skipped controller-side).
- `Order` auto-generates `tracking_token` (unique, hex(10)) via `before_validation` and never overwrites an explicit one.
- Checkout `create` accepts `params[:order] = { address, postcode, phone, delivery_mode }`.
- `OrdersController#tip` accepts `params[:tip_ore]` (chips 0/20/40 kr → 0/2000/4000 øre).
- `ReviewsController#create` accepts `params[:review] = { rating, body }`.
- Cart identity: `Cart.for(user, session_key)` — signed-in carts key on `user_id`, guest carts on the `session_key` cookie (`Cart#add_item!` merges identical lines and snapshots `unit_price_ore`).
- Sessions: `Session.create!(user:, token:)` + `cookies[:session_token]` (mirrors `SessionsController#create`; the model auto-assigns `SecureRandom.hex(16)` when blank).
- Track page renders `orders.thanks` = "Takk for handelen — Sahtein! صحتين" after delivery (the crown test greps it).

## Commands

```bash
bundle install
rails db:prepare && rails db:seed     # seeds are idempotent (destroy/rebuild)
rails s                               # http://localhost:3000 — login OTP mock: 1234
rails test                            # minitest, transactional, no fixtures
```

Seeds rebuild from scratch: `rails db:seed` (destroys and reseeds kitchen, zones, categories/items/options, promos, demo users incl. admin 90000001 / staff 90000002 / courier 90000003 / customer 90000004 with 6 stamps).

## Vipps mock vs real

- **Mock (default, dev/test):** `VippsClient.init_payment` sets `vipps_order_id = "mock-#{tracking_token}"` and `vipps_url = /vipps/mock?token=…`. The mock page (`vipps#mock`) is a styled stand-in: amount, merchant "Mr. Damascy", "Godkjenn med Vipps" → `PATCH /vipps/mock/approve` → captured + confirmed → redirect to tracking with "Sahtein! صحتين". **Never raises in mock mode.**
- **Real:** `ENV["VIPPS_MOCK"] = "0"` plus `VIPPS_SUBSCRIPTION_KEY`, `VIPPS_MSN`, `VIPPS_CLIENT_ID`, `VIPPS_CLIENT_SECRET` (and `VIPPS_WEBHOOK_SECRET`; optional `VIPPS_API_BASE` for `apitest.vipps.no`). The client speaks the **Vipps ePayment API v1**: `POST /accesstoken/get` (token cached in-process) → `POST /epayment/v1/payments` (`WALLET`, `WEB_REDIRECT`, stable `Idempotency-Key`s, reference `mrdamascy-<tracking_token>`) → order stays `pending` until Vipps reports `AUTHORIZED` → immediate capture via `POST /epayment/v1/payments/{reference}/capture` → captured + confirmed. The `AUTHORIZED` event arrives two ways, both funnelled through `VippsClient.sync_payment!`: the webhook `POST /vipps/callback` (secret in the Authorization header, constant-time verified, CSRF-exempt) and the tracking page (load + 10 s poll). `VippsClient` also powers **Logg inn med Vipps** (Login API, `access-management-1.0` OAuth2: authorize → code → userinfo → verified phone/name/address into `users.default_*`, 47-prefix phone normalised to 8 digits so Vipps and OTP are one identity).
- **Real-mode honesty guards (2026-11-01 /fix):** missing credentials or a failed Vipps call raise `VippsClient::NotAvailable`, which `CheckoutController` renders as an honest "payment could not start" screen (HTTP 503, cart intact — locale key `checkout.payment_unavailable`). Both mock Vipps endpoints answer 404 outside mock mode (`VippsController#refuse_in_real_mode`), so a mock approval can never capture an order no PSP reserved. Regression: `CheckoutFlowTest "the mock Vipps page answers 404 in real mode"`.

## Stripe mock vs real

- **Mock (default, dev/test):** `StripeClient.init_payment` sets the PSP reference `mock-stripe-<token>` and points `vipps_url` at `/stripe/mock?token=…` — a stand-in for Stripe's hosted Checkout, styled like the Vipps mock. "Betal med kort" → `PATCH /stripe/mock/approve` → captured + confirmed → tracking with Sahtein. **Never raises in mock mode.**
- **Real:** `ENV["STRIPE_MOCK"] = "0"` plus `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` (optional `STRIPE_API_BASE`). The client speaks **Stripe Checkout Sessions**: `POST /v1/checkout/sessions` (form-encoded, exact øre `unit_amount`, stable `Idempotency-Key`s, `client_reference_id`/metadata = our token) → hosted page → `success_url` lands on tracking. The order stays `pending` until `payment_status: paid` arrives via the **webhook** (`POST /stripe/callback`, HMAC `Stripe-Signature` verified constant-time, ±5 min tolerance) or the tracking poll — both funnelled through `StripeClient.sync_payment!`.
- **Honesty guards (mirroring Vipps):** missing credentials or a failed call raise `StripeClient::NotAvailable` → the checkout's honest "payment could not start" screen; mock endpoints answer 404 in real mode, so a mock approval can never capture an order no PSP reserved.

## Before you commit

Run the §16 checks: `ruby -c` on every `.rb`, `ERB.new(s).src` compile on every view, YAML load of both locale files, and the cross-checks (t() keys exist in nb **and** en; partial paths exist; `*_path`/`*_url` helpers exist; `data-controller`s have files; migrations reference only §4 columns; and no unfinished-marker comments anywhere — this app ships warm, finished copy only).
