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

`bin/rails test` needs no environment variables. `Pub4::DeployPaths` resolves the
`studio/` and `MASTER/` scripts from the checkout it lives in, through
`Rails.root` and then its own `__dir__`, falling back to the deployed
`/home/dev/pub4` layout last. Set `PUB4_ROOT` or `PUB4_RAILS_ROOT` only to point
at a different tree than the one the code was loaded from.

### Bringing it up

```zsh
doas zsh RAILS/brgen/brgen.sh
curl -fsS http://127.0.0.1:38182/up
curl -fsS http://127.0.0.1:38182/health
```
