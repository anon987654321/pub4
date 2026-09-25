# brgen

**A social network with no global timeline, because the city you live in is the
only feed that ever mattered.** brgen is one Rails process serving many hosts.
Rails 8.1 on SQLite behind Falcon, with Hotwire, Solid Queue, Solid Cache and
relayd. `AGENTS.md` is the agent map.

A city is an apex, and the apex is the social feed. Each vertical is a namespaced
subapp on a subdomain of *that* apex — not a path, and not a second deploy. That
holds for every row in `Brgen::DomainRegistry::ENTRIES` and not only for Bergen
and Los Angeles. An apex is the city with a vowel dropped: `brgen.no`,
`oshlo.no`, `lsangeles.com`, `lndon.uk`, `chcago.us`.

The host app serves the apex feed. Six mountable engines under `engines/` serve
the rest: marketplace, dating, takeaway, tv, maps and playlist, each on the
subdomain of its own name. Messenger is not an engine — it is host routes on
`messenger.<apex>`. The marketplace subdomain is the one localised word,
`markedsplass` in Norway, `marketplace` in the United States, `marktplatz` in
Germany; the others are the same word everywhere. `ai.brgen.no` is MASTER and not
a vertical at all.

Tenancy is `acts_as_tenant` on `city_id`, taken from the apex.
`Brgen::DomainRegistry` resolves the city from the hostname, each apex is an
isolated experience with no cross-city switcher, and development defaults to
Bergen. Shared concerns arrive through `pub4-shared`. The backlog is `apps.yml`
under `brgen.features`; the parity gaps against the apps brgen is measured by,
and the four features whose tables exist with nothing reading them, are in
`../TODO.md`.

Seeding draws curated Bergen content from `Brgen::BergenDemoSeeder` and its bulk
volume from `Brgen::PlausibleContent` — Norwegian copy, real Bergen streets and
bydeler, category-consistent listings — rather than raw Faker. `SEED_SCALE`
defaults to 10 in development, and `SKIP_BERGEN_DEMO=1` leaves the curated set
out. Per-city users get names in the city's own language through
`Brgen::CityContent.with_faker_locale`. Set `Faker::Config.locale` on its own and
you get English instead, because Faker's data is region-tagged as `nb-NO` while
the app declares only bare locales.

`AffiliateProduct` is the persisted inventory, and the deals sidebar reads that
table rather than calling out on every render. Real import is blocked until
brgen.no is an approved TradeDoubler publisher — apply as a publisher first, then
per advertiser programme — so `affiliate:import` needs `TRADEDOUBLER_TOKEN` and
does nothing without it. `affiliate:health` reports counts, staleness and token
status; `affiliate:seed_placeholders` and `affiliate:drop_placeholders` work
offline. A placeholder row carries `placeholder: true`, is excluded from `.real`,
and is labelled in the UI. It is never payable inventory.

`bin/rails test` needs no environment variables. `Operator::DeployPaths` resolves the
`MASTER/tools/` and `MASTER/` scripts from the checkout it lives in, through
`Rails.root` and then its own `__dir__`, falling back to the deployed
`/home/dev/pub4` layout last. Set `PUB4_ROOT` or `PUB4_RAILS_ROOT` only to point
at a different tree than the one the code was loaded from.

### Bringing it up

```zsh
doas zsh RAILS/brgen/brgen.sh
curl -fsS http://127.0.0.1:38182/up
curl -fsS http://127.0.0.1:38182/health
```

## Vertical engines

<!-- doc_paths: ignore -->
# brgen verticals as mountable engines

brgen is one Falcon process. The main feed lives at the city apex. Each vertical
below is a **subdomain of that apex** — a namespaced engine, not a fourth Rails
app. Every `Brgen::DomainRegistry::ENTRIES` city gets this, not only Bergen:
`dating.oshlo.no`, `dating.lndon.uk`, `dating.lsangeles.com`. Apexes are usually
the city with a vowel dropped. Topology: `AGENTS.md`.

| Subapp | Engine | Subdomain (Bergen / LA) |
|---|---|---|
| marketplace | `engines/marketplace` | markedsplass.brgen.no / marketplace.lsangeles.com |
| dating | `engines/dating` | dating.\* |
| takeaway | `engines/takeaway` | takeaway.\* |
| tv | `engines/tv` | tv.\* |
| maps | `engines/maps` | maps.\* |
| playlist | `engines/playlist` | playlist.\* |
| messenger | host `config/routes.rb` (not an engine) | messenger.\* |

Marketplace is the only localized subdomain word. Messenger was never extracted.

brgen main keeps the x.com-style social feed; the marketplace engine owns every
listing there is; the rest are their own hosts.

There is no listing model in the host app. Both tiers are one `Marketplace::Listing`, which
`belongs_to :store, optional: true` — a listing with a store is a shop's
product, a listing without one is a person selling a chair. The casual tier is
therefore expressible but not built: no separate surface, no seeds that exercise
it, and the storefront's own chrome around it. Building it out is a product
decision; saying it already exists in a place it does not is how a reader goes
looking for a model that was never there.

`tv` was the pilot (2026-08-02). This is the recipe it proved — follow it
exactly; the two starred steps are non-obvious and cost a boot each to find.

## What stays in the host

- Shared models (`User`, `Session`, `Community`, `Conversation`, `Message`),
  auth, `acts_as_tenant`, the design system — these live in the `pub4-shared`
  engine and every vertical engine depends on it. Engines never redefine them.
- **Existing migrations.** They have already run; `schema.rb` is the truth. Do
  NOT move applied migrations into an engine — you would risk re-running them or
  breaking schema history. The engine owns its `db/migrate` only for *future*
  migrations. Cross-vertical migrations (e.g. `add_city_scope_to_subapp_tables`)
  were never a single vertical's to take.

## Recipe (per vertical `v`, namespace `Ns`, e.g. tv/Tv)

1. **Skeleton** under `engines/v/`:
   - `brgen-v.gemspec` — `spec.name = "brgen-v"`, `spec.files =
     Dir["{app,config,db,lib}/**/*"]`, `add_dependency "rails"`, `add_dependency
     "pub4-shared"`.
   - `lib/v.rb` — `require "v/version"; require "v/engine"`.
   - `lib/v/version.rb`, `lib/v/engine.rb` — the engine class is
     `isolate_namespace Ns` and `include Shared::VerticalEngine`, nothing else.
     That module (`shared/lib/shared/vertical_engine.rb`) is the boot shape all
     six verticals share: `<<` (never `+=`) on `config.autoload_paths` because
     Rails 8.1 freezes those arrays mid-boot, `config.paths["db/migrate"] <<`,
     and initializers that `append_view_path` and push `app/javascript` onto
     `config.assets.paths`. It derives every path from
     the including class's own `root` and names its initializers after the
     namespace, so `Dating::Engine` still registers `dating.view_paths`.
     Each vertical wrote that body out by hand until 2026-08-28, when six
     copies that differed only in the module name became one.

2. **★ Gemfile** — `gem 'brgen-v', path: 'engines/v', require: 'v'`. The
   `require:` is load-bearing. Bundler auto-requires a dashed path gem by its
   dashed name (`brgen-v` → `brgen/v`), but the entry file is `lib/v.rb`, so
   without `require: 'v'` the engine class is undefined when routes are drawn:
   `uninitialized constant Ns::Engine`.

3. **Move code** (preserve history with `git mv`):
   - `app/{controllers,models,views}/v` →
     `engines/v/app/{controllers,models,views}/v`
   - vertical controllers (`v_*_controller.js`) → `engines/v/app/javascript/...`;
     the vertical's styles stay in brgen's one `application.scss`, scoped under
     `body.vertical-v`
   - the vertical's tests → `engines/v/test/...`

4. **Internal helper rename.** Under `isolate_namespace`, the engine's own
   routes are unprefixed. Rewrite every `v_X_(path|url)` → `X_\2` inside
   `engines/v/app`. (Do NOT touch `v_model:` form-param keys — those derive from
   the class name, not routes, and keep the prefix.)

5. **Engine routes** — move the vertical's route block into
   `engines/v/config/routes.rb` as `Ns::Engine.routes.draw do … end`,
   unprefixed.

6. **★ Host mount** — in `config/routes.rb`, replace the `constraints(subdomain:
   V_SUBDOMAINS) { scope module: "v" … }` block with a **top-level** mount:
   `mount Ns::Engine, at: "/", as: "v", constraints: { subdomain: V_SUBDOMAINS
   }`. Do NOT wrap the mount in a `constraints(subdomain:) do … end` block:
   nested, the routes still work but Rails does not register the `as:`
   mounted-helper proxy, and every host `v.X_url` silently breaks.

7. **Host refs** — the handful of host files that link into the subdomain
   (`application_helper`, `sitemaps_controller`, some tests) call `v_X_url` →
   rewrite to `v.X_url`. These generate cross-subdomain URLs with
   `host:`/`subdomain:` and now resolve through the mounted proxy, e.g.
   `tv.channel_url("foo", host: "brgen.no", subdomain: "tv") →
   http://tv.brgen.no/channels/foo`.

8. **Gates are already engine-aware** — `coverage_ratchet_test` and
   `turbo_broadcast_contract_test` glob `engines/*/app`, so no per-vertical gate
   edits are needed EXCEPT: extracting a vertical can drop a host coverage floor
   when a flat host test was basename-colliding with a same-named `Ns::` class
   (that was a double-count, not coverage). Lower the floor to the true count
   and say why in `FLOORS`.

## Verify (do not skip — a code read is not enough here)

```
bundle install
RAILS_ENV=test bundle exec rails runner 'Rails.application.reload_routes!
  puts Ns::Channel.table_name          # -> v_channels  (isolate_namespace prefix)
  o = Class.new { include Rails.application.routes.mounted_helpers }.new
  puts o.v.some_url("x", host: "brgen.no", subdomain: "v")'
ruby test/coverage_ratchet_test.rb ; ruby test/turbo_broadcast_contract_test.rb
```

`mounted_helpers` is built lazily — call `reload_routes!` first or a fresh
`rails runner` will report the `v` helper missing when it is actually fine.

## messenger is the exception

messenger owns 0 models and 0 tables — it is `root "conversations#index"` over
the host's shared `Conversation`/`Message`. Its engine is thin: routes + a
controller or two reusing shared models, no migrations. Do steps 1, 2, 5, 6, 7
only.

## Not an engine: master

`master` (ai.brgen.no) is a separate application with its own deploy, not a
brgen vertical. It is already more separated than an engine; do not fold it into
brgen.

## IRC bridge

A pure-Ruby IRC gateway that maps brgen's city channels onto the real IRC
protocol, so someone on Libera.Chat / EFnet / Undernet / Newnet can point a
client at brgen and land in the same `#brgen` room a phone browser sees.
Messages cross both ways; the modes (`@` op / `+` voice) and roster we already
built map straight onto IRC's `MODE` and `NAMES`.

## What's built (and tested)

- `lib/brgen/irc/message.rb` — parse/build one IRC protocol line.
- `lib/brgen/irc/session.rb` — a connection state machine: `NICK`/`USER`
  registration, `JOIN`, `PART`, `PRIVMSG`, `NAMES`, `PING`, `QUIT`, plus `#poll`
  for relaying web-side messages. No sockets — unit-tested against a fake
  bridge.
- `lib/brgen/irc/bridge.rb` — the seam to brgen's models: channel lookup
  (`Conversation.find_or_create_channel`), posting (`Message.create!` via a
  per-nick bridged user), history, roster (with `@`/`+`), and web→IRC deltas.
- `lib/brgen/irc/server.rb` — the socket harness (thread per client + a 2s poll
  thread, write mutex, per-thread AR connection).
- `bin/irc-gateway` — boots Rails and starts the server.
- `test/lib/brgen/irc_test.rb` — protocol + full session flows (10 examples).

brgen channels are anonymous by design, so a web viewer sees an IRC poster as an
anon handle; the nick is preserved on the IRC side. Only the known city channels
(`#brgen`, `#marketplace`, …) are joinable — a guessed `#slug` returns `403`.

## Going live (deliberate operator steps — not enabled by default)

The gateway binds `127.0.0.1:6667` and starts nothing on its own. To expose it:

1. **Install nothing extra** — it's pure Ruby, runs on the app's own bundle.
2. **Open a listener.** Either relayd-terminate TLS on 6697 and forward to
   `127.0.0.1:6667` (recommended — gives `ircs://`), or add a pf pass rule for
   6667 and set `IRC_HOST=0.0.0.0`. Plain 6667 is cleartext; prefer 6697.
3. **Enable the service.** Add `irc_gateway` to `pkg_scripts` in
   `/etc/rc.conf.local`, then `doas rcctl enable irc_gateway && doas rcctl start
   irc_gateway`. The rc.d script is `OPENBSD/etc/rc.d/irc_gateway`.
4. **DNS.** Point `irc.brgen.no` at the box so clients `/connect irc.brgen.no`.

## Known limits / next

- No `NICKSERV`/SASL auth — nicks are first-come per connection (fine for an
  anonymous bridge; add collision handling before a busy launch).
- Poll-based web→IRC relay (2s). A SolidCable/Redis subscription would cut
  latency and DB load at scale.
- DMs (`PRIVMSG` to a nick) aren't bridged yet — channels only.
- Per-nick bridged `User` rows accumulate; add a sweep like guest pruning.
## Goal

Markedsplass (`marketplace.*` / `markedsplass.brgen.no`) keeps its seller and order
domain in `Marketplace::*`. Solidus is an optional commerce kernel for catalog,
cart and fulfillment, introduced by staged dual-write on a larger Postgres host.

## Gems

| Gem | Role | Note |
|-----|------|------|
| `solidus` (~> 4.7) | Core commerce (catalog, cart, checkout, admin) | Official |
| `solidus_starter_frontend` | Customer storefront (cart, product, checkout UI) | Official Nebulab starter |
| `solidus_multi_domain` (optional) | Multi-store / multi-domain | Aligns with city apexes |

Native `Marketplace::*` remains the public seller/order domain. Solidus is optional for the commerce kernel and can be introduced by dual-write on a larger Postgres host.

## Amazon.com feature map

| Amazon surface | Solidus target | Status |
|----------------|----------------|--------|
| Product detail page (title, images, price, variants) | Spree::Product / Variants + starter frontend PDP | planned |
| Search + facets (category, brand, price) | Solidus search + taxons; FTS bridge from live_search | planned |
| Cart + checkout + payment | Solidus order state machine + payment methods | planned |
| Seller / marketplace (1P + 3P) | Solidus native marketplace features + BRGEN Marketplace::* seller/order state | planned |
| Reviews + ratings | Spree reviews extension or keep Marketplace::Review | planned |
| Order tracking / history | Spree::Order customer account | planned |
| Wishlists / saved | Favorites → Solidus wishlist or keep listing_favorites | planned |
| Recommendations | later (AI) | planned |
| City geo scoping | City tenant on Spree::Store / multi_domain | planned |

## Mount plan (no big-bang)

1. Add Solidus gems behind `SOLIDUS_MARKETPLACE=1` on the staging host.
2. `bin/rails g solidus:install` offline / staging only (creates spree_* tables).
3. Mount engines **only** under marketplace subdomain constraints.
4. Keep native listings controllers until cutover; dual-write optional.
5. Wire solidus_starter_frontend routes for storefront.
6. Multi-vendor: evaluate Solidus native marketplace capabilities against BRGEN’s Seller/Store/Offer semantics; do not install the retired `solidus_marketplace` gem.

## Staging enable (safe path)

Gems are **already declared** in `Gemfile` behind `SOLIDUS_MARKETPLACE=1`.
Initializer: `config/initializers/solidus_marketplace.rb` (`Brgen::SolidusMarketplace`).
Routes mount `Spree::Core::Engine` at `/solidus` under marketplace subdomains only
when `Brgen::SolidusMarketplace.mountable?` (flag + gems loaded).

```bash
cd RAILS/brgen
export SOLIDUS_MARKETPLACE=1
bundle install
# Staging host only — not on hot 1GB vm23 with all apps up:
bin/rails g solidus:install
# Commit spree_* migrations; dual-run native listings until cutover.
```

Contract: `ruby RAILS/test/solidus_staging_contract_test.rb` (no gems required).

## Production caution

1 GB OpenBSD VPS cannot run Solidus install/migrate while master+brgen+amber are
hot. Do Solidus schema work on a larger host or during a maintenance window with
amber stopped (`ALLOW_AMBER_DOWN=1 sh OPENBSD/bin/deploy-smoke.sh` after).

## Amazon Associates setup

You already have Associates approval in **Sweden, Netherlands, France** (and others).
PA-API is dead; we use **tags now** + **Creators API** once you have 10 qualifying sales / 30 days.

## 1. ENV (VPS `/etc/brgen.env` or equivalent)

### Required for tagging (do this first)

```bash
# One tag per marketplace you are approved in. NO global fallback.
AMAZON_ASSOCIATE_TAG_SE=your-se-tag-21
AMAZON_ASSOCIATE_TAG_NL=your-nl-tag-21
AMAZON_ASSOCIATE_TAG_FR=your-fr-tag-21
AMAZON_ASSOCIATE_TAG_DE=your-de-tag-21   # optional but useful for NO readers

# Default market for imports / Nordic surface (SE is a real storefront)
AMAZON_MARKET=SE
```

### Creators API (after 10 sales)

```bash
AMAZON_CREATORS_CLIENT_ID=amzn1.application-oa2-client.…
AMAZON_CREATORS_CLIENT_SECRET=amzn1.oa2-cs.v1.…
AMAZON_CREATORS_VERSION=3.2          # EU credentials
```

Legacy aliases still accepted: `AMAZON_ACCESS_KEY` / `AMAZON_SECRET_KEY` map to client id/secret.

## 2. Install the adapter

Replace:

- `RAILS/shared/app/services/shared/amazon_associates.rb` ← new file in this folder
- Add `RAILS/brgen/lib/tasks/affiliate_amazon.rake` ← new rake tasks

`Shared::AmazonMarketplace` already has SE/NL/FR/DE — no change required unless you want different SERVED_BY defaults.

## 3. Phase 1 — earn with tags only (no API)

```bash
cd /home/brgen/app   # or your deploy path
bin/rails affiliate:amazon_status

# Seed real ASINs (you choose products that fit brgen)
AMAZON_SEED_ASINS=B0xxxxx,B0yyyyy bin/rails affiliate:amazon_seed[SE]

bin/rails affiliate:health
```

Or in console:

```ruby
AmazonAssociates.seed_asins!([
  { asin: "B0XXXX", title: "Concrete product name", market: "SE", category: "electronics" },
  { asin: "B0YYYY", title: "Another product", market: "NL", category: "home" },
])
```

Links are built via `Shared::AmazonMarketplace.product_url` with the correct tag.
They appear through the existing `Affiliate.deals` → sidebar like TradeDoubler.

Drive traffic → get **10 qualifying sales in 30 days** → Creators API unlocks.

## 4. Phase 2 — catalog import

Once Creators credentials exist and eligibility is green:

```bash
bin/rails affiliate:amazon_status   # configured? should be true
bin/rails affiliate:import          # pulls Amazon + TradeDoubler
```

`AmazonAssociates.import!` uses SearchItems; `deals` falls back to live search only if the table is empty.

## 5. Norway readers

- No `amazon.no`.
- `Shared::AmazonMarketplace` maps `NO → DE` by default.
- If you prefer SE for Nordic users, set `AMAZON_MARKET=SE` and ensure `AMAZON_ASSOCIATE_TAG_SE` is set (you have SE approval).

## 6. Checklist

- [ ] Set `AMAZON_ASSOCIATE_TAG_SE` / `_NL` / `_FR` (and DE if approved)
- [ ] `bin/rails affiliate:amazon_status` shows tags
- [ ] Seed a small set of high-intent ASINs
- [ ] Confirm sidebar shows non-placeholder Amazon rows
- [ ] Confirm a test click lands on the right storefront with `?tag=`
- [ ] After 10 sales: create Creators API credential (EU / 3.2)
- [ ] Set Creators ENV → `affiliate:import`

## Files in this package

| File | Action |
|------|--------|
| `amazon_associates.rb` | Replace `RAILS/shared/app/services/shared/amazon_associates.rb` |
| `affiliate_amazon.rake` | Add as `RAILS/brgen/lib/tasks/affiliate_amazon.rake` |
| `SETUP.md` | This guide |

## Enhanced conversions

## Why Data Manager API

From **15 June 2026**, new adopters of offline / enhanced click conversion upload via Google Ads API `ConversionUploadService` are blocked (`CUSTOMER_NOT_ALLOWLISTED_FOR_THIS_FEATURE`).

**Data Manager API** `events:ingest` is the supported path:

```http
POST https://datamanager.googleapis.com/v1/events:ingest
```

## Files

| File | Role |
|------|------|
| `google_enhanced_conversions.rb` | Hashing + event build + ingest |
| `google_enhanced_conversions_job.rb` | Async job on order paid |

## Google Ads setup

1. Create a conversion action:
   - Type / source: **Website (Import from clicks)** / `UPLOAD_CLICKS`
   - Count: One
   - Value: Use different values
2. Note the **conversion action id** and **customer id** (10 digits).
3. OAuth token (or service account) with permission to ingest events for that Ads account.
4. Turn on enhanced conversions in the Ads UI (unified toggle).

## ENV

```bash
GOOGLE_ENHANCED_CONVERSIONS=1
GOOGLE_ADS_CUSTOMER_ID=1234567890
GOOGLE_ADS_CONVERSION_ACTION_ID=9876543210
GOOGLE_ADS_ACCESS_TOKEN=ya29.<oauth token>
# optional MCC:
# GOOGLE_ADS_LOGIN_CUSTOMER_ID=...
```

## Wire-up

On payment success (after `paid_at` / `payment_status=paid`):

```ruby
GoogleEnhancedConversionsJob.perform_later(order.id)
```

Order should expose when possible:

- `id` → `transactionId` (dedupe key)
- `paid_at`
- `total_cents` or `total`
- `currency` (default NOK)
- `gclid` (from session/cookie at landing or checkout)
- `email` / `phone` (hashed; never sent raw)
- `ad_user_data_consent` (true/false if known)
- line items with `offer_id` like `brgen-123` (matches Merchant feed)

Optional DB column:

```ruby
add_column :marketplace_orders, :google_conversion_uploaded_at, :datetime
add_column :marketplace_orders, :gclid, :string
```

## Hashing rules

- Email: lowercase, trim; for `@gmail.com` / `@googlemail.com` strip `.` in local part; SHA-256 hex
- Phone: normalize to digits (prefer E.164 from your app); SHA-256 hex
- Encoding declared as `HEX` on the ingest request

## Consent

Only send `consent.adUserData` when you know the answer.
Do not default to `CONSENT_GRANTED`.

## Validate

```ruby
GoogleEnhancedConversions.upload_purchase!(order, validate_only: true)
```

## Relation to browser tag

- Browser gtag can still fire Purchase on the success page.
- Server upload uses the same `transactionId` (order id) so Google can dedupe.
- Server path is the source of truth for paid state (webhook), not thank-you JS.

## Do not

- Upload unpaid orders
- Send plain-text email/phone
- Reuse `transactionId` across different orders
- Call legacy `UploadClickConversions` as a new adopter without allowlist

## Install path

```text
RAILS/brgen/app/services/google_enhanced_conversions.rb
RAILS/brgen/app/jobs/google_enhanced_conversions_job.rb
```

## Payment webhooks

Stripe and Vipps keep their existing host routes. Dintero lives inside the
marketplace engine so its callback and webhook route share the engine's
subdomain constraints.

## Dintero

| Item | Value |
|------|-------|
| Checkout | Shopping API order/session + signed callback |
| Webhook | `POST /webhooks/dintero` |
| Webhook secret | `DINTERO_HOOK_SECRET` (HMAC-SHA1 over raw body) |
| Seller payout | payout destination must report `ACTIVE`; each selected line carries its split |
| Capture/refund | separate Dintero operations; local paid/refunded state follows webhook confirmation |

Create checkout sessions with an explicit `merchant_reference`. Keep the browser
return separate from the signed callback. Dintero is the source of truth for
authorization, capture, and refund; browser redirects never settle money.

Operator enablement is explicit: set `DINTERO_CHECKOUT_ENABLED=1` only after the
test account passes the checkout, capture, refund, replay, and payout-destination
contracts. Register the hook subscription with `bin/rails dintero:hooks:create`.

## Stripe

| Item | Value |
|------|--------|
| URL | `https://<host>/webhooks/stripe` |
| Events | `checkout.session.completed`, `checkout.session.async_payment_succeeded` |
| Secret | `STRIPE_WEBHOOK_SECRET` (`whsec_…`) |

Verification:

1. Parse `Stripe-Signature` → `t` + one or more `v1`
2. Reject if `|now - t| > 300s`
3. `HMAC_SHA256(secret, "#{t}.#{raw_body}")` hex vs any `v1` (constant-time)
4. Multiple `v1` supported (key rotation)

Order resolution: `client_reference_id` (`order_id:` / `checkout_id:`) or `metadata`.

## Vipps

| Item | Value |
|------|--------|
| URL | `https://<host>/webhooks/vipps` |
| Events | at least `epayments.payment.authorized.v1`, `epayments.payment.captured.v1` |
| Secret | `VIPPS_WEBHOOK_SECRET` (base64 from registration response) |

Register once:

```bash
curl -X POST https://api.vipps.no/webhooks/v1/webhooks \
  -H "Authorization: Bearer $TOKEN" \
  -H "Ocp-Apim-Subscription-Key: $VIPPS_SUBSCRIPTION_KEY" \
  -H "Merchant-Serial-Number: $VIPPS_MSN" \
  --data '{"url":"https://HOST/webhooks/vipps","events":["epayments.payment.authorized.v1","epayments.payment.captured.v1"]}'
```

Save returned `secret` → `VIPPS_WEBHOOK_SECRET`.

Verification (Vipps docs):

1. `x-ms-content-sha256` == base64(SHA256(raw_body))
2. String to sign: `POST\n{pathAndQuery}\n{x-ms-date};{host};{content-hash}`
3. HMAC-SHA256 with decoded webhook secret → base64 → match `Authorization` Signature=

Paid events: `AUTHORIZED`, `CAPTURED` with `success: true`.

Order resolution: reference `brgen-order-{id}-…` set by `VippsCheckout.start!`.

## After paid (both)

1. `mark_paid!` / payment_status fields (idempotent)
2. Optional `gclid` from Stripe metadata
3. `GoogleEnhancedConversionsJob` if `GOOGLE_ENHANCED_CONVERSIONS=1` and Ads ENV set

## Shared helper
`Webhooks::PaymentPaid` — used by both controllers so mark-paid + conversion enqueue stay in one place.
