# Mr. Damascy 🧆

**Fra Damaskus med kjærlighet** — from Damascus with love, grilled in Bergen.

> "Bestefar solgte shawarma ved Souq al-Hamidiyah i Damaskus. Hvitløkssausen lages hver morgen — toum som dere husker den."
> *(Grandfather sold shawarma by Souq al-Hamidiyah in Damascus. The garlic sauce is made every morning — toum the way you remember it.)*

Mr. Damascy is a mobile-first Rails 8 PWA for ordering shawarma and kebab from **one Bergen kitchen** — Solheimsgaten 60, 5054 Bergen at **Danmarksplass** (the real Mr. Damascy restaurant, mr-damascy.webflow.io). Opening hours follow the restaurant: **Man–Fre 11–21, Lør–Søn 14–21**. It carries Damascus/Syrian warmth (Ahlan! Yalla! Sahtein!) wrapped around Bergen street-kebab culture: kvartover-honest portions, a proud free salad bar, and a kebabrull when the west-coast rain sets in. There is no Foodora, no courier marketplace, no commission between you and the kitchen — you order and pay with **Vipps Express** in fewer steps than any delivery app, and the money lands directly with the people at the grill.

---

## What it is

- **A PWA**, not an app-store app. Install from the browser (manifest + service worker + offline page), runs standalone on the home screen.
- **One kitchen.** No multi-tenant marketplace — a single seeded menu ("a world tour of kebab"), one board for the kitchen, one run list for the courier.
- **Fewer steps than Foodora.** The single confirm screen + Vipps Express means ~3 app screens and 0 card fields. Returning customers reorder in **2 taps** ("Yalla igjen").
- **Fair.** No platform cut. Tip goes 100 % to the courier, entered *after* delivery on the tracking page.

### Feature list

| Area | What you get |
|---|---|
| Menu | Category chips, item sheets with origin stories (12 cities), heat scale (Uten/Mild/Middels/Sterk!), weight badge ("450 g — kvartover-ærlig"), free salatbar chips, 1-tap quick add |
| Reorder | "Yalla igjen" card on the menu — last order rebuilt into the cart in one tap (2 taps to paid for returning users) |
| Cart | Cart bar fixed above the tab bar, quantity stepper, auto-applied best promo (no code fields), mode toggle (delivery/pickup) |
| Checkout | **One confirm screen**: prefilled address, live postcode zone check (fee + ETA), two payment rows (Vipps + card/Stripe), totals, "Betal med Vipps" primary + "Betal med kort" secondary CTA |
| Payment | **Two lanes** (operator-mandated): Vipps Express (mock in dev) and **Stripe Checkout** for card/Apple Pay/Google Pay. Each order stores its `payment_method`; both converge on the same captured+confirmed states. `payment_steps` stores 3 — "Betalte i 3 steg" chip on orders |
| Photos | Every dish has a generated studio photo (flat mint background, no text) with a provenance sidecar in `app/assets/images/food/provenance.json`; items without a photo fall back to their emoji tile |
| Tracking | Public tracking by token: 5-step timeline with 8-point star milestones, ETA polling, courier line, tip chips (0/20/40 kr) + star review after delivery — "Takk for handelen — Sahtein! صحتين" |
| Loyalty | **Sahtein-kortet**: 10 star stamps (one per order), the 10th wrap is free (auto-applied at checkout when ≥ 9 unredeemed stamps) |
| Auth | Phone-first, passwordless: mock OTP `1234` in dev/test. Roles: customer / staff / courier / admin |
| Staff board | Orders grouped in columns (Mottatt / Bekreftet / På grillen / Klar), big touch targets, one advance button per order |
| Courier runs | Ready-for-pickup and on-the-way lists with addresses, pickup/deliver buttons |
| Offline | Service worker (`damascy-v1`): network-first navigations with a friendly offline page fallback, cache-first for assets/icons |

---

## Foodora vs Mr. Damascy — the step math

This comparison **is** the product. Every screen and field removed is a customer kept.

| | Foodora (baseline) | Mr. Damascy (Vipps Express) |
|---|---|---|
| Screens to a paid order | ≈ **8**: app → restaurant → menu → item → cart → checkout form → confirm → bank/card OTP | ≈ **3** app screens (menu → item/cart → confirm) + 1 Vipps approval |
| Form fields | ≈ **7**: address, phone, time slot, payment-method dropdown, tip, promo code, tips on confirm | **0** promo fields, **0** card fields, **0** dropdowns — address + postcode, prefilled for returning users |
| Payment | Card entry + bank OTP | Vipps fingerprint (or Vipps code) |
| Tip | Forced during checkout | Optional, *after* delivery, on the tracking page |
| Promo | Hunt for codes | Best promo applied automatically ("SAHTEIN10 lagt inn automatisk") |
| Returning order | Full journey again | **2 taps**: "Yalla igjen" → confirm → Vipps |

### Vipps Express — sequence

```
 Customer          Mr. Damascy (Rails)           Vipps (mock in dev)
    │  menu → "+ Legg i" → cart bar        │                        │
    │  "Betal med Vipps"  ────────────────▶│                        │
    │                        validate zone │ + min basket           │
    │                        build Order (snapshots, promo, totals)  │
    │                        VippsClient.init_payment                │
    │                        payment_state = authorised              │
    │◀─── 302 redirect to vipps_url ───────│                        │
    │                        GET /vipps/mock?token=… (mock page)     │
    │  fingerprint / "Godkjenn med Vipps" ─│                        │
    │─────────── PATCH /vipps/mock/approve ────────────────────────▶ │ (real: Vipps app)
    │                        payment_state = captured                │
    │                        state = confirmed                       │
    │◀─── redirect /track/:token ──────────│                        │
    │  "Sahtein! صحتين" + live timeline    │  poll /track/:token/status every 10 s
    │                        (staff advance! → courier pickup!/deliver!)
    │◀─── delivered: tip chips + review ───│                        │
```

---

## Foodora & Wolt APIs — what we use and what we deliberately don't

The delivery platforms have real APIs, but they pull in opposite directions relative to the mission (cut out the middleman, keep the customer):

| | Foodora (Delivery Hero) | Wolt Drive |
|---|---|---|
| What the API is for | The **Restaurant Integration API** (POS integration) pushes orders that were *placed on Foodora's marketplace* into a merchant POS plugin — PGP-gated credentials, Integration Middleware, the Delivery Hero Vendor App in the accept loop | The **Wolt Drive API** is a last-mile carrier API for *your own* orders: your checkout, your brand (white-label), Wolt just sends a courier and streams status webhooks |
| Puts a middleman back in the loop? | **Yes** — marketplace commission, and the customer relationship belongs to Foodora | **No** — courier logistics only, invisible to the customer if you disable their logo |
| Our decision | **Not integrated.** Receiving Foodora orders would defeat the purpose. If Mr. Damascy ever wants the marketplace as a *channel*, the staff board is the seam: a plugin endpoint could feed those orders into `Staff::BoardController` like any other order | **Integrated as the overflow lane** (`app/services/wolt_drive_client.rb`) — when Bergen's own couriers are all out, the staff board books a Wolt courier for a ready order |

**How the Wolt Drive lane works:** staff press **"Send med Wolt"** on a ready delivery order → `WoltDriveClient.shipment_promise` (the documented availability/fee/ETA quote) → `WoltDriveClient.request_delivery` → the order stores `external_delivery_id` + `external_delivery_url` → the board shows who is carrying the bag. Mock mode (default, like Vipps) assigns "Bergen Bud" instantly with zero credentials; real mode needs `WOLT_DRIVE_MOCK=0` plus `WOLT_DRIVE_API_TOKEN` and `WOLT_DRIVE_CLIENT_ID` (Bearer token from your Wolt Drive contact person), and posts the documented `POST /v1/clients/{client_id}/deliveries` payload (pickup = Strandgaten 47, dropoff = the order address, items, tip). Wolt's own docs (developer.wolt.com/docs/wolt-drive) also offer a zero-code path — **Wolt Drive Web** at drive.wolt.com — which is the same overflow lane with no integration at all.

**Foodora escape hatch (not built):** if marketplace reach is ever wanted, request credentials from Delivery Hero (PGP key), build the plugin URL, and receive their orders into the kitchen board — but every such order pays Foodora's commission. That is a channel decision, not a technology one.

---

## A world tour of kebab — the menu

One kitchen, twelve origin stories. The research credits are part of the brand honesty — the About page and the item sheets name the shops we learned from:

| Item (nb) | Origin | Heat | Price | Credits & inspiration |
|---|---|---|---|---|
| Damaskus Kylling Shawarma 🌯 | Damaskus | Mild | 129 kr | **Damascus street stalls** — the brand's soul: toum & tarator, Souq al-Hamidiyah, knefeh |
| Beirut Lam Shawarma 🥙 | Beirut | Mild | 139 kr | **Joseph & Jabbour, Beirut** — lean, flavourful lamb shawarma, pomegranate onion |
| Berlin Gemüse Kebap 🥬 | Berlin | Mild | 139 kr | **Hasir (1971 — invented the döner sandwich), Mustafa's Gemüse Kebap, Rüyam & Imren Grill** — veg-forward, generous sauces, no queues (order ahead) |
| Adana Sterk Dürum 🔥 | Adana | Sterk! | 149 kr | **Dürümzade, Istanbul** — dürüm with pure street-food energy |
| Bergen Kebab-i-Dürum 🧔 | Bergen | Middels | 139 kr | **Emil's Kebab (Støletorget — Bergens beste ifølge BT, Wolt Awards 2023) + Bergen kebab culture** — clean gloves, kvartover, salatbar, kebabrull |
| Dubai Gatens Shawarma 🍟 | Dubai | Mild | 135 kr | **Dubai shawarma carts** — fries inside the wrap |
| Blomkål-Pita Miznon-stil 🥦 | Tel Aviv | Uten | 129 kr | **Miznon (Tel Aviv/NYC/Paris)** — cauliflower as the star, playful voice |
| Bursa İskender 🧈 | Bursa | Mild | 189 kr | **İskender, Bursa (since 1867)** — butter + tomato + yoghurt ritual |
| Gaziantep Ali Nazik 🍆 | Gaziantep | Middels | 179 kr | **Gaziantep — UNESCO kebab city** — Ali Nazik + baklava |
| Familie Fest-Mezze 🫓 | Damaskus | Mild | 449 kr | Every Damascus dinner table — sharing platter (1 200 g) |
| Stockholm Kebabpizza 🍕 | Stockholm | Middels | 169 kr | **Stockholm** — the kebabpizza invention (weekend item) |
| Sydney Snackpack HSP 🍟 | Sydney | Middels | 149 kr | **Sydney late-night** — the Halal Snack Pack cult (secret menu badge) |

Plus Tilbehør 🍟 (Hvitløks-Pommes, Halloumi-Pommes, Kısır, Syltebolle), Drikke 🥤 (Ayran, Şalgam, Tamarind, Jallab, Myntesitronlimonade), Desserter 🍮 (Baklava fra Gaziantep, Knefeh fra Damaskus, Ma'moul), and the **Damascy Boss-boks** 🎁 (wrap + pommes + drikke + baklava-bite — meal-deal energy borrowed from **GDK**, together with the loyalty card idea).

---

## Tech stack

- **Rails 8** (importmap + Turbo + Stimulus, Propshaft, Solid Cache/Queue/Cable, SQLite) — no gems beyond Rails defaults. `VippsClient` is plain `Net::HTTP`.
- Money is **integer øre** everywhere (`*_ore` columns); helper `money(1500)` → `"15 kr"`.
- **minitest**, no fixtures — tests seed inline and run transactionally.
- Mobile-first shell: max 480 px column, minty pastel palette from the logo, 8-point Damascus star motif, bottom tab bar (Meny / Bestill / Klubb / Mer), safe-area aware.
- Stimulus controllers: `item_sheet`, `cart_bar`, `zone_check`, `vipps_mock`, `track`, `toast`.
- i18n: **Norwegian first** (`config/locales/nb.yml` is the default locale), full English mirror in `en.yml`. Same key tree in both.

## Run it

```bash
bundle install
rails db:prepare     # create + migrate
rails db:seed        # world-tour menu, zones, promos, demo users
rails s
```

Then open http://localhost:3000.

- **Login (mock):** tap Mer → Logg inn → enter any 8-digit phone → the dev notice shows *"Mock-SMS: koden er 1234"* → enter `1234`. Demo users are seeded: admin `90000001` (Hassan), staff `90000002` (Umm Yusuf), courier `90000003` (Kader), customer `90000004` (Ola Nordmann, 2 delivered orders + 6 stamps).
- **Vipps (mock):** checkout redirects to a mock Vipps approval page styled like the app — amount, merchant "Mr. Damascy", button "Godkjenn med Vipps" (dev/test only; no real money moves). Approve → order is captured + confirmed → you land on live tracking with "Sahtein! صحتين".
- To rebuild all demo data from scratch: `rails db:seed` (idempotent — destroys and reseeds the catalog, zones, promos and demo users).

## Tests

```bash
rails test
```

Ten files per APP_SPEC §14, including the crown integration test (`test/controllers/checkout_flow_test.rb`): seeds kitchen/zone/menu inline, adds to cart via session, POSTs checkout, asserts the redirect to the mock Vipps URL with token, PATCHes approve (asserts `payment_state: captured` + `state: confirmed`), and GETs the public track page by token asserting "Sahtein". Also: staff-advance authorization, tip-updates-total, promo best-pick + 10th-stamp free wrap, zone min-basket rule, order totals + state machine, and menu rendering. No fixtures, no database_cleaner — Rails transactional tests only.

## PWA install notes

- Manifest at `/manifest.json` (name "Mr. Damascy — Shawarma & Kebab", short name "Damascy", standalone, shortcuts: Yalla igjen → `/cart`, Spor ordre → `/orders`).
- Service worker at `/service-worker.js` (version `damascy-v1`, `Service-Worker-Allowed: /`), precaches `/offline`, icons, logo. Navigations are network-first with the offline fallback page; assets and icons are cache-first.
- Install: on iOS "Add to Home Screen", on Android/Chrome the install prompt from the omnibox. Theme `#FFFFFF`, background `#F3FBF7`.

## Real Vipps (production)

Mock mode is the default (`ENV["VIPPS_MOCK"]` unset ≠ `"0"`). To go live:

```bash
VIPPS_MOCK=0
VIPPS_SUBSCRIPTION_KEY=...
VIPPS_MSN=...             # merchant serial number
VIPPS_CLIENT_ID=...
VIPPS_CLIENT_SECRET=...
VIPPS_WEBHOOK_SECRET=...  # the secret Vipps sends in the webhook's Authorization header
# optional: VIPPS_API_BASE=https://apitest.vipps.no  (Vipps test environment)
```

With `VIPPS_MOCK=0` the client speaks the **Vipps ePayment API v1** (`api.vipps.no/epayment/v1`): an access token from `/accesstoken/get` (cached in-process), `POST /epayment/v1/payments` creates a `WALLET` payment with `userFlow: "WEB_REDIRECT"` and a stable `Idempotency-Key`, and the returned `paymentRedirectUrl` becomes the order's `vipps_url`. The order stays `pending` until Vipps says `AUTHORIZED` — reported either by the **webhook** (`POST /vipps/callback`, secret verified constant-time) or by the tracking page's own poll sync — and then we capture immediately and confirm the order. Same API also powers **Logg inn med Vipps** (`access-management-1.0` OAuth2: verified phone + name + address, so checkout arrives prefilled — one tap, no forms).

In mock mode the client never raises and never touches the network.

## Real Stripe (production)

The second payment lane (operator-mandated) is Stripe Checkout — hosted card entry, Apple Pay and Google Pay included by Stripe. Mock mode is the default (`ENV["STRIPE_MOCK"]` unset ≠ `"0"`); the dev stand-in lives at `/stripe/mock`. To go live:

```bash
STRIPE_MOCK=0
STRIPE_SECRET_KEY=sk_live_...      # or sk_test_... for Stripe test mode
STRIPE_WEBHOOK_SECRET=whsec_...    # signing secret of the /stripe/callback endpoint
```

With `STRIPE_MOCK=0` the client speaks the **Stripe Checkout Sessions REST API** (`api.stripe.com/v1`, Net::HTTP only — no gems): `POST /v1/checkout/sessions` creates a hosted session in NOK with the exact øre total and a stable `Idempotency-Key`; the returned `url` becomes the order's redirect target and `success_url` lands back on the tracking page. The order stays `pending` until Stripe reports `payment_status: paid` — via the **webhook** (`POST /stripe/callback`, HMAC-signed `Stripe-Signature` verified constant-time with a ±5 min timestamp tolerance) or the tracking page's own poll sync — and then the order is captured+confirmed. Session id and hosted url reuse the order's generic PSP columns (`vipps_order_id`/`vipps_url`), and each order carries its `payment_method` (`vipps` default, `stripe`) so syncs always route to the right client via `PaymentGateway`.

Honesty guards mirror Vipps exactly: missing `STRIPE_SECRET_KEY` or a failed call raises `StripeClient::NotAvailable` → honest "payment could not start" screen (cart intact, orphan cancelled); signature failures answer 400; the mock Stripe page answers 404 in real mode, so a mock approval can never capture an order no PSP reserved.


Three real-mode honesty guards: missing credentials or a failed Vipps call raise `VippsClient::NotAvailable`, which the checkout renders as an honest "payment could not start — nothing reserved" screen (HTTP 503, cart intact, orphan order cancelled); the webhook answers 401 to anything without the webhook secret; and the mock Vipps pages answer 404, so a mock approval can never capture a real order.


## brgen_takeaway — the planned multi-restaurant future

Mr. Damascy is the **first restaurant** destined for the planned `RAILS/brgen_takeaway` app (the food-ordering vertical the marketplace already stubs at `/food`). The integration path, deliberately left as a seam rather than built ahead of need (YAGNI):

- **No schema coupling.** mrdamascy is standalone (own SQLite, own auth, `MrDamascy` module) — brgen_takeaway can adopt its `orders`/`menu_items` shapes without dragging the engine along.
- **The payment lanes are per-order, not per-app.** `orders.payment_method` + `PaymentGateway` mean a takeaway umbrella can add its own PSPs alongside Vipps/Stripe without touching either client.
- **The tracking seam is already public.** `track/:token` + `track/:token/status` (JSON) are token-scoped and unguessable — exactly the surface a takeaway app needs to embed live order status.
- **Suggested landing path when brgen_takeaway starts:** mount mrdamascy's kitchen identity as the first `Kitchen`, re-use the øre-integer money rule and the 8-point-star design tokens, and let takeaway own discovery while mrdamascy keeps checkout + payment (the two things the commission argument is about).
- The app is self-contained: nothing here depends on the monorepo. Since 2026-11-02 it lives as a first-class app at `RAILS/mrdamascy/` (promoted out of the retired `RAILS/__other/` junk drawer; recorded in `RAILS/apps.yml`).

## Repository notes

- This app lives at `RAILS/mrdamascy` — a first-class RAILS app path since 2026-11-02. See `APP_SPEC.md` (the single source of truth) and `AGENTS.md` (contributor contract).
- Logo assets in `public/` are the **operator's originals — the marks already in use at the restaurant — retained byte-for-byte**. Do not regenerate or redesign them; a VTracer re-trace was attempted and rolled back (see `docs/fix-ledger.md`).
- Webflow reference screenshots of the current site (`docs/webflow-reference/mrdamascy_1..3.png`) and live app screenshots (`screenshots/01–11`) document both the original and this build.
