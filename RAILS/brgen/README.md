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

This paragraph used to say brgen main also kept "the craigslist/airbnb-style
personal classifieds". It does not and never did:
`brgen/app/models/marketplace.rb` is a table-name-prefix module and there is no
listing model in the host app. Both tiers are one `Marketplace::Listing`, which
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
