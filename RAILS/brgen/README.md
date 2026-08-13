# brgen

Hyperlocal city network — one app, many verticals per host.

## Surfaces

Posts, marketplace, dating, playlist, TV, takeaway, maps, messaging. Tenant: `acts_as_tenant` on `city_id`.

Subdomains: `tv`, `dating`, `playlist`, `takeaway`, marketplace aliases, `maps`, `messenger`. MASTER: `ai.brgen.no`.

## Stack

Rails 8.1 · SQLite · Falcon · Hotwire · Solid Queue/Cache · relayd

```zsh
doas zsh RAILS/brgen/brgen.sh
curl -fsS http://127.0.0.1:38182/up
curl -fsS http://127.0.0.1:38182/health
```

## Cities

`Brgen::DomainRegistry` resolves city from hostname (`oshlo.no`, `lsangeles.com`, `brgen.no`, …). Each apex is an isolated experience — no cross-city switcher. Dev defaults to Bergen.

Shared concerns via `pub4-shared`. Backlog: `apps.yml` → `brgen.features`.
Parity gaps against the apps brgen is measured by — and the four features whose
tables exist with nothing reading them — are in `../TODO.md`.

## Seeds

```zsh
bin/rails db:seed                  # dev default SEED_SCALE=10
SEED_SCALE=1 bin/rails db:seed     # fast replant
SKIP_BERGEN_DEMO=1 bin/rails db:seed
```

Curated Bergen content lives in `Brgen::BergenDemoSeeder`; the bulk volume draws
from `Brgen::PlausibleContent` (Norwegian copy, real Bergen streets/bydeler,
category-consistent listings) rather than raw Faker. Per-city users are named in
the city's own language via `Brgen::CityContent.with_faker_locale` — set
`Faker::Config.locale` on its own and you get English, because Faker's data is
region-tagged (`nb-NO`) while the app only declares bare locales.

## Affiliate

```zsh
bin/rails affiliate:health              # counts, staleness, token status
bin/rails affiliate:import              # needs TRADEDOUBLER_TOKEN
bin/rails affiliate:seed_placeholders   # flagged demo rows, no network
bin/rails affiliate:drop_placeholders
```

`AffiliateProduct` is the persisted inventory; the deals sidebar reads the table
rather than calling out per render. Real import is blocked until brgen.no is an
approved TradeDoubler publisher (apply as publisher, then per advertiser
programme). Placeholder rows carry `placeholder: true`, are excluded from
`.real`, and are labelled in the UI — they are never payable inventory.

## Tests

```zsh
bin/rails test
```

No env vars needed. `Pub4::DeployPaths` resolves `studio/` and `MASTER/` scripts
from the checkout it lives in (via `Rails.root`, else its own `__dir__`), falling
back to the deployed `/home/dev/pub4` layout last. Set `PUB4_ROOT` /
`PUB4_RAILS_ROOT` only to point at a *different* tree than the one the code is
loaded from.
