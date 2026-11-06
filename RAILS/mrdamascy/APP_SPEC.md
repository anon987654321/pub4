# APP_SPEC.md — mrdamascy (RAILS/mrdamascy)

Single source of truth for the **Mr. Damascy** app. Every contributor/agent implements exactly against this document. The app lives at `RAILS/mrdamascy` — a standalone Rails 8 app (same pattern as `RAILS/amber`), a first-class RAILS app path since 2026-11-02 (promoted out of the retired `__other/` junk drawer).

**What it is:** a mobile-first PWA for ordering shawarma & kebab from one Bergen kitchen (Solheimsgaten 60, 5054 Bergen at **Danmarksplass** — the real restaurant), built to make ordering+paying (Vipps Express, plus card via Stripe) **fewer steps than Foodora**, wrapped in Damascus/Syrian warmth and Bergen street-kebab culture.

**Operator-mandated deltas (2026-11-02, binding like the rest of this spec):** (1) the kitchen is the real Danmarksplass restaurant — Solheimsgaten 60, 5054 Bergen, Man–Fre 11–21 · Lør–Søn 14–21, phone 955 55 600; (2) a **second payment lane, Stripe Checkout**, rides beside Vipps (`orders.payment_method`, `StripeClient`, `PaymentGateway`, three `stripe/*` routes, mock stand-in + signed webhook); (3) the logo is the restaurant's own mark — the white-and-gold "Mr. Damascy" wordmark with the chef's hat and moustache in use on its signage and website — as a vector trace of its bitmap (96.3 % pixel match, restored 2026-11-03 after a revert had brought back a generated stand-in; never regenerate); (4) every menu item carries a generated studio photo (`app/assets/images/food/`, provenance sidecar, emoji fallback).

---

## 1. Brand & design tokens

- Name: **Mr. Damascy** — "Fra Damaskus med kjærlighet". Greetings sprinkled in copy: `Ahlan!`, `Yalla!`, `Sahtein!` (+ Arabic `صحتين` on confirmation only).
- Logo assets exist in `public/` (icon.svg, logo.svg, icon-*.png, icon-maskable-*.png, apple-touch-icon.png, favicon*, og-card.png). They are a **vector trace of the restaurant's own mark** (commit d27be96e26, restored 2026-11-03) — it is already in use at the restaurant, so it must not be redesigned; regenerate the rasters only from these SVGs.
- **Palette** (CSS custom properties, white background, light minty pastels derived from the logo):

```css
:root {
  --paper:#FFFFFF; --surface:#F3FBF7; --mint-100:#E4F6EE; --mint-200:#C9EDDD;
  --mint-300:#A6E1CB; --mint-500:#4FB894; --mint-600:#3A9A7B; --mint-700:#2F7D64;
  --ink:#2E3033; --ink-soft:#6C7076; --gold:#FDC72E; --gold-deep:#E8A81C;
  --pom:#C94F4F; --line:#E6EAE8; --danger:#C94F4F;
  --radius:20px; --radius-sm:14px; --shadow:0 10px 30px rgba(46,48,51,.08);
}
```

- Heat scale colors: 0 neutral, 1 mint-500 (Mild), 2 gold (Middels), 3 pom (Sterk!).
- Damascus motif: 8-point star. CSS pattern via inline SVG data-URI background on `.star-pattern` (hero header, loyalty card, staff board header). Keep it subtle (mint-100/mint-200, ~6% visible).
- Type: system stack `-apple-system, "Segoe UI", Roboto, "Noto Sans", sans-serif`. Base 16px, mobile-first, max content width 480px centered (desktop shows phone-width column on `--surface`).
- Flat, generous white space, 20px radii, no heavy shadows.

## 2. Stack conventions (match amber/pub4)

- Rails 8 style: importmap + Stimulus + Turbo, Propshaft, Solid (cache/queue/cable) with SQLite, minitest.
- Money is **integer øre** everywhere (`*_ore` columns). Helper `money(1500)` → `"15 kr"`.
- No gems beyond Rails defaults; `VippsClient` uses `Net::HTTP` (stdlib).
- Auth: phone-number + mock OTP (dev/test code `1234`), plain `Session` model with token cookie. Roles: `customer/staff/courier/admin` (enum on users).
- App module namespace `MrDamascy` (mirror `amber/config/application.rb` structure).
- `.ruby-version` = `3.3.6`.

## 3. Routes (config/routes.rb — final, no deviations)

(Operator addition 2026-11-02: the three `stripe/*` routes below the vipps block — mock stand-in `get "stripe/mock"`, `patch "stripe/mock/approve"`, webhook `post "stripe/callback"`.)

```ruby
Rails.application.routes.draw do
  root "menu#show"
  get "menu", to: "menu#show"
  get "menu/:id", to: "menu#item", as: :menu_item
  get "about", to: "pages#about"

  resource :session, only: [:new, :create, :destroy]
  post "session/request_code", to: "sessions#request_code"

  resource :cart, only: [:show] do
    post :add_item, controller: "carts"
    patch "items/:line_id", action: :update_item, controller: "carts", as: :update_item
    delete "items/:line_id", action: :remove_item, controller: "carts", as: :remove_item
  end

  resource :checkout, only: [:show, :create], controller: "checkout"

  resources :orders, only: [:index, :show]
  get "track/:token", to: "orders#track", as: :track
  get "track/:token/status", to: "orders#status", as: :track_status
  post "track/:token/tip", to: "orders#tip", as: :order_tip
  post "orders/:id/review", to: "reviews#create", as: :order_review

  get "loyalty", to: "loyalty#show"

  namespace :staff do
    resource :board, only: [:show]
    patch "orders/:id/advance", to: "board#advance", as: :advance_order
  end

  namespace :courier do
    resource :runs, only: [:show]
    patch "orders/:id/pickup", to: "runs#pickup", as: :pickup_order
    patch "orders/:id/deliver", to: "runs#deliver", as: :deliver_order
  end

  get "vipps/mock", to: "vipps#mock"          # dev/test Vipps-app stand-in
  patch "vipps/mock/approve", to: "vipps#approve"
  get "vipps/login_mock", to: "vipps#login_mock" # dev/test Vipps-login stand-in
  post "vipps/callback", to: "vipps#callback"   # real Vipps webhook (ePayment events)

  # PWA
  get "manifest.json", to: "pwa#manifest", as: :pwa_manifest
  get "service-worker.js", to: "pwa#service_worker", as: :pwa_service_worker
  get "offline", to: "pwa#offline"
end
```

## 4. Models & schema (db/migrate + app/models)

Use two timestamps prefixes: `20261101000001` … incrementing. All tables `id: :integer` default.

- **User**: `phone:string` (unique, format `\A\d{8,12}\z`), `name:string`, `role:integer` (default 0; enum customer:0 staff:1 courier:2 admin:3), `default_address:string`, `default_postcode:string`. `has_many :sessions`, `has_many :loyalty_stamps`, `has_many :orders`.
- **Session**: `user:references`, `token:string` (unique, SecureRandom.hex(16)).
- **Kitchen** (single row seeded): `name, slug, address, postcode, phone`, `opening_hours:string` (text like "Man–Søn 11–23"), `rating:float` default 4.9.
- **DeliveryZone**: `postcode:string` (unique), `name:string`, `fee_ore:integer`, `min_basket_ore:integer`, `eta_minutes:integer`.
- **MenuCategory**: `kitchen:references`, `name:string` (nb), `name_en:string`, `slug:string`, `emoji:string`, `position:integer`. `has_many :menu_items`.
- **MenuItem**: `menu_category:references`, `name:string`, `name_en:string`, `description:string`, `description_en:string`, `price_ore:integer`, `origin:string` (one of the city list below), `emoji:string`, `heat:integer` (0–3), `badges:string` (comma list e.g. `"signature,veg"`), `weight_g:integer` (portion honesty for the Quarter-Kilo promise), `position:integer`, `available:boolean` default true. `has_many :item_options`.
- **ItemOption**: `menu_item:references`, `name:string`, `name_en:string`, `price_ore:integer` default 0, `kind:string` (`sauce|topping|extra`), `default_on:boolean` default false, `position:integer`.
- **Cart**: `user:references` (nullable), `session_key:string` (anonymous), `delivery_mode:string` default `"delivery"`. `has_many :cart_items, dependent: :destroy`. Scopes `.for(user_or_session)`. One open cart per identity (find_or_create).
- **CartItem**: `cart:references`, `menu_item:references`, `quantity:integer` default 1, `option_ids:string` (comma list of selected ItemOption ids), `note:string`, `unit_price_ore:integer` (snapshot incl. options at add-time). Methods: `line_total_ore`, `options_list` (from ids).
- **Order**: `user:references`, `kitchen:references`, `state:string` default `"placed"` (`placed→confirmed→preparing→ready→picked_up→delivered`, plus `cancelled`), `delivery_mode:string`, `address:string`, `postcode:string`, `phone:string`, `subtotal_ore:integer`, `delivery_fee_ore:integer`, `discount_ore:integer` default 0, `tip_ore:integer` default 0, `total_ore:integer`, `promo_code:string`, `eta_minutes:integer`, `tracking_token:string` (unique, hex(10)), `payment_state:string` default `"pending"` (`pending|authorised|captured|failed`), `vipps_order_id:string`, `vipps_url:string` (generic PSP columns: payment reference + hosted url, whatever the lane), `payment_method:string` default "vipps" (`vipps|stripe`), `payment_steps:integer` default 3, `express:boolean` default true, `placed_at:datetime`. `has_many :order_items, dependent: :destroy`. State machine as plain methods: `advance!` (staff), `pickup!`, `deliver!`, `cancel!` with guard conditions; `after_create :award_stamp_later` NOT needed — stamps awarded on `deliver!`.
- **OrderItem**: `order:references`, `menu_item_id:integer`, `name:string` (denorm), `emoji:string`, `quantity:integer`, `unit_price_ore:integer`, `options_text:string` (human list), `line_total_ore:integer`.
- **PromoCode**: `code:string` unique, `kind:string` (`percent|fixed|free_delivery`), `value:integer`, `min_basket_ore:integer` default 0, `active:boolean` default true, `description:string`.
- **LoyaltyStamp**: `user:references`, `order:references` (nullable), `redeemed:boolean` default false, `awarded_at:datetime`.
- **Review**: `order:references`, `user:references`, `rating:integer` (1–5), `body:text`.

Delivery-zone rule: order postcode must match an active DeliveryZone and subtotal ≥ `min_basket_ore`.

## 5. Services

- **VippsClient** (`app/services/vipps_client.rb`) — Net::HTTP only, two documented APIs:

  **ePayment API v1** (`api.vipps.no/epayment/v1`; override base with `ENV["VIPPS_API_BASE"]`, e.g. `https://apitest.vipps.no`). Mock mode (`ENV["VIPPS_MOCK"] != "0"`, the default) never touches the network: `init_payment(order:)` sets `vipps_order_id = "mock-#{order.tracking_token}"`, `vipps_url` = the mock approval page and marks the payment `authorised`. Real mode (`VIPPS_MOCK=0`): `POST /accesstoken/get` (client_id/secret/subscription key/MSN from ENV `VIPPS_CLIENT_ID, VIPPS_CLIENT_SECRET, VIPPS_SUBSCRIPTION_KEY, VIPPS_MSN`; token cached in-process, mutex-guarded, refreshed before expiry), then `POST /epayment/v1/payments` with `{ amount: {value: total_ore, currency:"NOK"}, paymentMethod: {type:"WALLET"}, reference: "mrdamascy-<token>", returnUrl: track_url, userFlow: "WEB_REDIRECT", customer.phoneNumber (47-prefixed when known) }` under stable `Idempotency-Key`s; parses `paymentRedirectUrl` into `vipps_url` and keeps the order `pending` — money is reserved only when the customer approves.

  **Reconciliation seam** — `sync_payment!(order:)` is idempotent and converges from either path: `GET /epayment/v1/payments/{reference}` → `AUTHORIZED` → `capture_payment!` (POST `…/capture`, `modificationAmount`, idempotent; confirms a `placed` order, never rewinds a kitchen-advanced one); `ABORTED/EXPIRED/TERMINATED` → `failed`. Transport errors are swallowed by the poll (next poll/webhook retries), never a 500.

  **Login API** (`api.vipps.no/access-management-1.0`): `login_authorize_url` (scopes `openid email phoneNumber address`, state + nonce), `exchange_login_code!` (form-encoded, Basic client auth), `login_userinfo!` (Bearer). `login_phone` normalises the 47-prefixed profile phone to the 8-digit local form so Vipps and OTP identities are one customer row.

  **Never raise in mock mode; never silently fake success in real mode** — wiring gaps raise `NotAvailable` and the checkout says so honestly.
- **PromoApplier** (`app/services/promo_applier.rb`): given cart subtotal + mode → picks the best active promo the order qualifies for (percent → fixed → free_delivery by computed saving), returns `{promo:, discount_ore:, delivery_fee_ore:}`. Also honors 10th-stamp free wrap: if user has ≥9 unredeemed stamps → discount = cheapest wrap `price_ore` (kind implicit `loyalty`).
- **StripeClient** (`app/services/stripe_client.rb`) — the second lane, Net::HTTP only. Mock mode (`ENV["STRIPE_MOCK"] != "0"`, default) never touches the network: `init_payment` sets the order's PSP reference `mock-stripe-<token>`, `vipps_url` to the `/stripe/mock` approval page and marks `authorised`. Real mode (`STRIPE_MOCK=0`): `POST /v1/checkout/sessions` (form-encoded, Bearer `STRIPE_SECRET_KEY`, stable `Idempotency-Key`, `unit_amount` = exact øre total, `currency: nok`, `client_reference_id`/`metadata[tracking_token]` = ours) → the hosted `url` redirects the customer, `success_url` returns to tracking; `sync_payment!` polls `GET /v1/checkout/sessions/{id}` → `paid` captures+confirms (never rewinds the kitchen), `expired` fails, transport errors are swallowed by the poll. `verify_signature!` validates the `Stripe-Signature` HMAC (SHA-256 over `t.payload`, constant-time, ±5 min). Missing credentials raise `NotAvailable` before any HTTP.
- **PaymentGateway** (`app/services/payment_gateway.rb`) — the one dispatch seam: `normalize!` (unknown → vipps), `init!(order, method:)`, `sync!(order)` route to VippsClient or StripeClient by `order.payment_method`. Used by CheckoutController and both tracking syncs.
- **OrderTotals** (fold into Order model): `compute_totals!(cart, zone)` sets subtotal/fee/discount/total/eta; called before create in CheckoutController.

## 6. Controllers

- **ApplicationController**: `helper :money`; `current_user` (from session token), `current_cart`, `require_role!(:staff|:courier)`, locale handling (`I18n.locale = params[:locale] || :nb`); `turbo_stream` capable.
- **MenuController**: `show` (kitchen, categories w/ items incl. options, hero: rating, open hours, zone blurb, "Yalla igjen" reorder card when `current_user&.orders&.last`), `item` (one item w/ options; renders full page; the item sheet behavior is Stimulus on the same markup).
- **CartsController**: `show` (lines, totals preview, promo hint, Vipps CTA), `add_item` (params: `menu_item_id, quantity, option_ids[], note`; Turbo Stream update of cart bar + flash; also responds html redirect), `update_item` (qty), `remove_item`.
- **CheckoutController**: `show` — the **single confirm screen**: "Logg inn med Vipps" card for guests (one tap prefills everything), address+postcode (prefilled from user), phone (guests), mode toggle (delivery/pickup), payment row (Vipps, fixed — "Raskere enn Foodora: ingen kortfelter"), auto-applied promo line, totals, one CTA "Betal med Vipps". `create` — validates zone/min basket, builds order from cart snapshots, normalises `payment_method` and dispatches `PaymentGateway.init!` (owns the payment state; on real-mode failure of either lane the orphan order is cancelled, the cart survives and the checkout says so honestly), redirect to `order.vipps_url` (mock page or real PSP). On zone failure: re-render with alert.
- **VippsController**: `mock` (dev/test only page styled like a Vipps approval: amount, merchant "Mr. Damascy", button "Godkjenn med Vipps" + inline SVG heart), `approve` (finds order by token, capture-side effects: `payment_state=captured`, `state=confirmed` only from `placed`, redirect `track_path(token)` with flash "Sahtein! صحتين"), `callback` — the **real webhook** (`POST /vipps/callback`, CSRF-exempt): Vipps carries the webhook secret (ENV `VIPPS_WEBHOOK_SECRET`) in the Authorization header; constant-time compare → 401 on mismatch; body events `[{reference:, state:, …}]` drive `VippsClient.sync_payment!`; 200 always once verified, 400 on bad JSON. `login_mock` — dev/test stand-in for the Vipps consent screen (posts phone+name to the session callback).
- **OrdersController**: `index` (user's orders w/ status chips), `show`, `track` (public by token; syncs the Vipps payment on load — the customer lands here straight from the Vipps app; timeline of states, courier blurb, poll Stimulus, tip form after delivered, review form), `status` (json: `{state, eta, payment_state, updated_at}`; also runs `VippsClient.sync_payment!` — the 10 s poll is the reconciliation heartbeat when the webhook was missed), `tip` (updates tip, thanks flash).
- **ReviewsController**: `create` (from track page; flash "Takk!").
- **LoyaltyController**: `show` — Sahtein Card: 10 star slots (filled = stamps), progress text, how-it-works.
- **SessionsController**: `new` ("Logg inn med Vipps" CTA first, SMS fallback below), `request_code` (mock: stores code in session flash, shows it in dev notice "Mock-SMS: koden er 1234"), `create` (verify `1234` or stored code; find_or_create user by phone), `vipps_auth` (starts the OAuth2 dance; mock mode bounces to `vipps/login_mock`; real mode redirects to the Vipps authorize URL; state stored in session), `vipps_callback` (state-verified; mock: phone+name from the stand-in form; real: code → token → userinfo → profile; fills blank name/address/postcode, never clobbers; `?to=checkout` returns the customer to the confirm screen), `destroy`.
- **Staff::BoardController**: `show` (active orders grouped by state as columns/cards; big touch targets; advance button per order), `advance` (moves state, Turbo Stream replace card).
- **Courier::RunsController**: `show` (ready-to-pickup + out-for-delivery lists w/ addresses; pickup/deliver buttons).
- **StripeController**: `mock` (dev/test only stand-in for Stripe's hosted Checkout, same capture semantics as the Vipps mock), `approve` (idempotent capture-side effects via `StripeClient.mark_captured`), `callback` — the **real webhook** (`POST /stripe/callback`, CSRF-exempt): verifies the HMAC `Stripe-Signature`, acts only on `checkout_session` objects, funnels into `StripeClient.sync_payment!`; 200 on verified, 400 on bad signature/JSON. Mock endpoints answer 404 in real mode (`refuse_in_real_mode`).
- **PwaController**: `manifest` (json view), `service_worker` (js view, `response.headers["Service-Worker-Allowed"] = "/"`), `offline` (static friendly page).

## 7. Views & partials (app/views)

- `layouts/application.html.erb` — mobile shell: `<meta name="theme-color" content="#FFFFFF">`, manifest link, apple-touch link, top brand bar (logo.svg h-8 + "Mr. Damascy"), `<main>` (max-w-[480px]), bottom **tab bar** with inline SVG stroke icons (currentColor, Lucide ISC + the khatam star): Meny (`root_path`, utensils), Bestill (`cart_path` w/ count badge), Klubb (`loyalty_path`, 8-point star), Mer (`about_path`, ellipsis). Flash toasts. Turbo morph on.
- `shared/_mode_icon.html.erb` — one partial for delivery-mode glyphs (bike = delivery, storefront = pickup, phone for board cards); stroke SVGs sized for inline body text so no surface hand-rolls its own.
- `menu/show.html.erb` — hero (`star-pattern` mint surface): logo mark, "Fra Damaskus med kjærlighet", rating (gold khatam SVG + 4.9), hours, zone/eta line; **Yalla igjen** reorder card (last order, 1-tap rebuild → adds same items to cart → redirect cart); category chips anchor nav (sticky under header); sections per category; `shared/_item_card` per item.
- `shared/_item_card.html.erb` — card: emoji tile on mint-100, name, origin chip ("Damaskus", flag-free), heat dots, weight badge (e.g. "450 g" — Quarter-Kilo promise), price, "+ Legg til" quick-add button (topping-less items add directly; items with required options go to item page), `data: { turbo_frame: "_top" }`.
- `menu/item.html.erb` — item sheet: big emoji header on star-pattern, origin story blurb (I18n `origins.<origin>`), description, heat picker (radio chips), salatbar chips (kind=topping, free), extras, qty stepper, note field, sticky "Legg i kurv · {price}".
- `carts/show.html.erb` — lines (emoji, name, options as small text, qty stepper, remove), subtotal, auto-promo hint ("SAHTEIN10 lagt inn automatisk"), mode toggle, "Betal med Vipps" CTA (gold Vipps-orange? no — Vipps brand orange #FF5B24 button; keep — it's the recognized payment color), under CTA: "3 steg · ingen kortfelter · trygg betaling".
- `checkout/show.html.erb` — confirm: address block (prefilled, postcode with zone check feedback via Stimulus `zone_check`), eta estimate, payment row (Vipps logo text, "Sist brukt" chip when returning), promo line (auto-applied, green), totals, big CTA. One screen only. `checkout/create` posts from here.
- `vipps/mock.html.erb` — mint header, Vipps wordmark styled text (#FF5B24), merchant, amount, "Godkjenn" button (patch `vipps/mock/approve`), "Avbryt" link → cart. Dev/test only.
- `stripe/mock.html.erb` — same chrome, Stripe blurple wordmark, "Betal med kort" button (patch `stripe/mock/approve`, vipps_mock Stimulus shimmer). Dev/test only.
- Item photos: `shared/_item_card` renders the dish photo (`.item-photo`) via the `ApplicationHelper#food_photo` map (name → `food/<slug>.jpg`), emoji tile as fallback; `menu/item` sheet head shows `.sheet-photo` hero. Photos are generated studio shots with provenance in `app/assets/images/food/provenance.json`.
- `orders/index.html.erb`, `orders/show.html.erb` — cards with state chip colors (placed mint, confirmed gold, preparing gold-deep, ready mint-700, delivered ink-soft).
- `orders/track.html.erb` — live tracking: big state icon steps (5 steps with 8-point star milestones), ETA, courier line ("Kader henter maten din" when courier role exists), poll `track_status` every 10s (Stimulus `track`), after `delivered`: tip chips (0/20/40 kr) + review stars + "Takk for handelen — Sahtein! صحتين".
- `loyalty/show.html.erb` — Sahtein Card: 10 8-point stars, filled=gold, empty=mint-200; progress "2 stjerner til en gratis wrap!"; rules list; CTA to menu.
- `staff/board/show.html.erb` — columns Placed/Confirmed/Preparing/Ready; order cards with items summary, phone, mode; advance button ("Bekreft", "Begynn", "Klar!", —). Header with star-pattern.
- `courier/runs/show.html.erb` — two lists (Ready for pickup / On the way) with address + total + buttons.
- `sessions/new.html.erb` — phone-first login: big phone input, "Send kode", dev code notice, brand blurb.
- `pages/about.html.erb` — brand story: Damascus heritage (grandfather's shawarma stall at Souq al-Hamidiyah → Bergen), Foodora-free fairness (betal direkte til kjøkkenet), world-tour menu credits, Vipps security note.
- `pwa/manifest.json.erb` — name "Mr. Damascy — Shawarma & Kebab", short_name "Damascy", `start_url: "/"`, display standalone, lang nb, theme #FFFFFF, background #F3FBF7, icons (192/512 + maskable both), shortcuts: [Yalla igjen → `/cart`, Spor ordre → `/orders`], description.
- `pwa/service-worker.js.erb` — v `damascy-v1`; precache `/offline`, `/icon-192.png`, `/icon-512.png`, `logo.svg`; fetch: network-first for navigations w/ `/offline` fallback; cache-first for `/assets/`, `/icon*`, `/logo*`.
- `shared/_toast.html.erb`, `shared/_cart_bar.html.erb` (fixed above tab bar: "Kurv · 3 varer · 387 kr → Betal", Stimulus `cart_bar` refresh target), `shared/_empty.html.erb`.

## 8. Stimulus controllers (app/javascript/controllers)

`application.js` (boot `@hotwired/turbo-rails` + `controllers/index.js` eager-load), then:
- `item_sheet_controller.js` — qty stepper, option chip toggle (max sauces 2), sticky price update.
- `cart_bar_controller.js` — refreshes count/total from `turbo_stream` events (listens `turbo:frame-load` / custom `cart:changed`).
- `zone_check_controller.js` — on postcode input, fetch `/checkout?postcode=` partial check via `data[zone]` json embedded — simpler: fetch `track`-less endpoint: reuse `checkout#show` with `Accept: application/json`? Keep: fetch(`/checkout/zone?postcode=X`) — **add route** `get "checkout/zone", to: "checkout#zone"` returning json `{ok, fee_ore, eta, name}`. (Add to routes §3.) Feedback inline "Klar i 25 min · levering 29 kr".
- `vipps_mock_controller.js` — fake approve progress (400ms shimmer then submit).
- `track_controller.js` — polls status json, swaps step classes, reloads page on state change.
- `toast_controller.js` — auto-dismiss flash.

## 9. SCSS (app/assets/stylesheets)

`application.scss` imports: `_tokens.scss` (§1 vars + star-pattern data-uri), `_base.scss` (reset-lite, typography, focus rings), `_buttons.scss` (`.btn`, `.btn-primary` mint-600, `.btn-vipps` #FF5B24, `.btn-gold`), `_cards.scss` (item cards, `.chip`, `.badge`), `_tab_bar.scss` (safe-area aware), `_menu.scss`, `_cart.scss` (+cart bar), `_checkout.scss`, `_tracking.scss` (timeline + steps), `_staff.scss`, `_loyalty.scss`, `_forms.scss`, `_utilities.scss`. All flat/mint pastels, no scrollbars visible on mobile, `scroll-behavior: smooth`, `env(safe-area-inset-bottom)` padding on tab bar.

## 10. Locales (config/locales/nb.yml default, en.yml)

Namespaces: `app` (brand, tagline), `nav` (meny, bestill, klubb, mer), `stripe` (mock page: merchant, amount, approve, cancel, mock_note), `menu` (hero lines, add, quick_add, salatbar, heat: {0: Uten, 1: Mild, 2: Middels, 3: "Sterk!"}, origin_chip), `origins` (12 entries — 2-sentence story each: damaskus, beirut, berlin, adana, bergen, dubai, tel_aviv, bursa, gaziantep, familie, stockholm, sydney), `cart`, `checkout` (address, postcode, zone_ok/zone_fail, mode, vipps_cta/stripe_row/stripe_note/stripe_cta, steps_note "3 steg · ingen kortfelter", promo_auto), `vipps` (mock title/amount/approve/cancel), `orders` (states x7, eta, tip, review, thanks "Sahtein! صحتين"), `loyalty` (title Sahtein-kortet, progress), `staff` (+ wolt_cta/wolt_dispatched/wolt_courier/wolt_failed), `courier`, `auth` (phone, send_code, mock_code), `flash` (added, removed, promo_applied, zone_error, welcome "Ahlan!", logged_out), `about`, `offline`, `footer`. Norwegian copy carries the warmth; `en.yml` mirrors in English. All ERB `t()` keys must exist in **both** files.

## 11. Seeds (db/seeds.rb) — "World tour of kebab" catalog

Destroy/reseed idempotently (`Kitchen.destroy_all` etc.). Kitchen: "Mr. Damascy — Danmarksplass", addr "Solheimsgaten 60, 5054 Bergen", phone 955 55 600, hours "Man–Fre 11–21 · Lør–Søn 14–21", rating 4.9. Zones include the kitchen's own 5054 (Danmarksplass).

Zones (postcode, name, fee, min, eta) — central-Bergen postcodes: 5003 Bergen sentrum 39/200/25; 5004 Strandgaten 29/150/15; 5006 Vågsbunnen 29/150/20; 5007 Bergenhus vest 35/150/25; 5008 Nøstet 35/150/25; 5009 Møhlenpris 35/150/25; 5015 Nygård 39/200/30; 5017 Årstad 39/200/30; 5020 Møllendal 45/250/35; 5141 Fyllingsdalen 49/300/40; 5160 Laksevåg 49/300/40; 5221 Nesttun 55/300/45. (All are real Bergen postcodes; the kitchen delivers as far as its own couriers comfortably ride.)

Categories & items (name nb, origin, heat, price kr, emoji, badges, weight_g):
- **Wraps & Ruller** 🌯: Damaskus Kylling Shawarma (Damaskus, 1, 129, 🌯, signature, 450); Beirut Lam Shawarma (Beirut, 1, 139, 🥙); Berlin Gemüse Kebap (Berlin, 1, 139, 🥬, veg); Adana Sterk Dürum (Adana, 3, 149, 🔥); Bergen Kebab-i-Dürum (bergen, 2, 139, 🧔, salatbar); Dubai Gatens Shawarma (Dubai, 1, 135, 🍟, "pommes i rullen"); Blomkål-Pita Miznon-stil (Tel Aviv, 0, 129, 🥦, veg,signature).
- **Tallerker** 🍽️: Bursa İskender (Bursa, 1, 189, 🧈, signature, 550); Gaziantep Ali Nazik (Gaziantep, 2, 179, 🍆); Familie Fest-Mezze (Damaskus, 1, 449, 🫓, sharing, 1200); Stockholm Kebabpizza — helg (Stockholm, 2, 169, 🍕); Sydney Snackpack HSP (Sydney, 2, 149, 🍟, secret).
- **Tilbehør** 🍟: Hvitløks-Pommes 59 🍟; Halloumi-Pommes 79 🧀; Kısır Bulgursal 49 🥗 (veg); Syltebolle 29 🥒.
- **Drikke** 🥤: Ayran 35 🥛; Şalgam 35 🍅; Tamarind-drikk 39 🍹; Jallab 39 🍇; Myntesitronlimonade 45 🍋.
- **Desserter** 🍮: Baklava fra Gaziantep 69 🍯; Knefeh fra Damaskus 79 🧀 (signature); Ma'moul 59 🌰.
- **Damascy Boss-boks** 🎁 (own category "Bokser"): Boss-boks (wrap + pommes + drikke + baklava-bite, 199, 🎁, deal).

ItemOptions: on every wrap — sauces (Toum 0 default_on, Tarator 0, Yoghurt-urt 0, Syrisk sterk chili 0; kind sauce), toppings kind topping default some on (salat, tomat, agurk, rødløk, rødkål, mais, jalapeño, sylteagurk — all 0); extras (Ekstra kjøtt 25, Dobbel ost 15, Ekstra brød 10). Iskender: extra smør 10, ekstra yoghurt 15. Boss-boks: drikkevalg kind extra.

PromoCodes: SAHTEIN10 (percent 10, min 0, "Første bestilling"), YALLA25 (fixed 2500 øre, min 25000), GRATISLEVERING (free_delivery, min 30000), FAMILIE15 (percent 15, min 40000).

Users: admin "Hassan" 90000001, staff "Umm Yusuf" 90000002, courier "Kader" 90000003, customer "Ola Nordmann" 90000004 (2 delivered orders + 6 stamps seeded for demo realism). OTP mock fixed `1234`.

## 12. Vipps Express — fewer steps than Foodora (core differentiator)

**Foodora baseline (documented in README):** app → restaurant → menu → item → cart → checkout form (address, phone, time slot, payment-method dropdown, tip, promo code) → confirm screen → bank/kort OTP → done. ≈ **8 skjermer / 7 felt**.

**Mr. Damascy Vipps Express:** menu → item sheet "+ Legg i" → cart bar "Betal med Vipps" → confirm (1 screen, prefilled, auto-promo) → Vipps-app (fingerprint) → live tracking. = **3 app-skjermer + 1 Vipps-bekreftelse**, 0 kortfelter, 0 promo-felter, tip valgfritt *etterpå* på tracking-siden. Returning users: "Yalla igjen" → confirm → Vipps = **2 trykk**. `order.payment_steps` stores 3; display "Betalte i 3 steg" chip on order.

## 13. "Best of the world's kebab" — adopted features (research-driven)

| From | Take | In the app |
|---|---|---|
| Hasir & Mustafa's Gemüse Kebap, Berlin | veg-forward gemüse kebab + endless queue | Berlin Gemüse Kebap item; preorder-in-minutes (no queues: order ahead, pickup mode) |
| Rüyam & Imren Grill, Berlin | sauce generosity, big portions | free extra sauce options, weight_g honesty badge |
| Joseph & Jabbour, Beirut | lean, flavorful lamb shawarma | Beirut Lam Shawarma, granateple-løk |
| İskender (Bursa, since 1867) | butter+tomato+yoghurt ritual | Bursa İskender tallerken |
| Gaziantep (kebab UNESCO city) | Alinazik, baklava | Ali Nazik + Baklava |
| Dürümzade, Istanbul | dürüm street energy | Adana Sterk Dürum |
| Damascus street stalls | the brand's soul; toum & tarator | Damaskus Kylling Shawarma, knefeh, brand story |
| Miznon (Tel Aviv/NYC/Paris) | cauliflower as star, playful voice | Blomkål-Pita, playful copy |
| Emil's Kebab, Bergen (Støletorget) | Bergen's best kebab (BT), Wolt Awards 2023, clean-gloves discipline | Bergen Kebab-i-Dürum + free salatbar chips |
| Norwegian kebab tongue | kvartover, middagskebab, mild/stærk | weight badge "kvartover-ærlig", heat scale nb labels |
| German Doner Kebab (GDK) | app loyalty + Boss-box meal deals | Sahtein-kortet stamps + Damascy Boss-boks |
| Sydney late-night | Halal Snack Pack cult | Sydney Snackpack HSP (secret menu badge) |
| Stockholm | kebabpizza invention | Kebabpizza (weekend item) |
| Dubai shawarma carts | fries inside the wrap | Dubai Gatens Shawarma |

## 14. Tests (test/)

- `test/test_helper.rb` — mirror amber (fixtures off, parallelize, fixtures path if used).
- `models/menu_item_test.rb` — heat range, price presence, scope available.
- `models/order_test.rb` — totals math (subtotal+fee−discount+tip), state machine transitions incl. invalid jumps, token uniqueness.
- `models/promo_applier_test.rb` — picks best promo; loyalty 10th-stamp free wrap.
- `models/delivery_zone_test.rb` — min basket rule.
- `controllers/menu_controller_test.rb` — root renders catalog w/ seeded items.
- `controllers/carts_controller_test.rb` — add/update/remove via session cart.
- `controllers/checkout_flow_test.rb` — the crown test: add item → checkout create → redirected to mock vipps → approve → order captured+confirmed → track renders "Sahtein"; also zone failure path.
- `controllers/staff_board_test.rb` — advance requires staff, advances state.
- `controllers/track_tip_test.rb` — public track by token, tip updates total.
- `services/vipps_client_test.rb` — mock-mode no-network contract; real-mode ePayment v1 + Login flows against stubbed HTTP (headers, idempotency keys, state mapping, capture never rewinds the kitchen, transport errors swallowed by the poll, 47-prefix phone normalisation).
- `controllers/vipps_callback_test.rb` — webhook: 401 without/with wrong secret, AUTHORIZED captures + confirms, replays idempotent, ABORTED → failed without cooking, unknown reference ignored, bad JSON → 400.
- `controllers/vipps_login_test.rb` — mock loop (auth → stand-in → callback → signed in; state mismatch refused; ?to=checkout returns to confirm) and real-mode profile mapping (fills blanks, never clobbers, one identity per phone).
- `controllers/vipps_poll_sync_test.rb` — tracking page load and 10 s status poll complete an AUTHORIZED payment; ABORTED shows failed; captured orders trigger zero Vipps calls.
- `services/stripe_client_test.rb` — mock no-network contract; real-mode Checkout Sessions flow against stubbed HTTP (form-encoded params, exact øre `unit_amount`, idempotency key, hosted url mapping, paid/expired state mapping, capture never rewinds the kitchen, transport errors swallowed, `verify_signature!` accept/reject matrix incl. stale timestamps and missing secret).
- `controllers/stripe_callback_test.rb` — webhook: 400 without/wrong/stale signature, `checkout.session.completed` captures + confirms, replays idempotent, unpaid sessions don't cook, unknown sessions/irrelevant event types answer 200, bad JSON → 400, metadata token fallback.
- `controllers/checkout_flow_test.rb` also covers the card lane end-to-end (mock Stripe approve → captured+confirmed → track Sahtein), the unknown-PSP fallback to vipps, the mock Stripe 404 guard in real mode, and the tracking-page sync completing a real-mode Stripe payment.

## 15. README.md & AGENTS.md (repo docs inside app root)

README: brand story (Damaskus→Bergen), feature list, **comparison table Foodora vs Mr. Damascy steps**, Vipps Express sequence diagram (ASCII), Foodora/Wolt API decision table, world-tour menu w/ research credits (§13 table + shop names), run instructions (`bundle install && rails db:prepare && rails db:seed && rails s`), test instructions, PWA install note, Vipps real-mode env vars. AGENTS.md: app contract — file map, conventions (øre, locales keys, no gems), "read APP_SPEC.md first", don't touch MASTER/contract-tested apps.

## 16. Cross-check rules (validator will enforce)

1. Every `.rb` passes `ruby -c`. 2. Every ERB compiles (`ERB.new(s).src`). 3. YAML loads (nb/en). 4. Every `t("...")` in views/controllers exists in **both** locale files. 5. Every `render partial:` / `<%= render "x/y" %>` file exists. 6. Every `*_path`/`*_url` helper used in views/controllers exists in routes. 7. Every Stimulus `data-controller` used in views has a file in `app/javascript/controllers/`. 8. Migrations reference only §4 tables/columns. 9. No placeholders (TODO/XXX/待补充) in final files.
