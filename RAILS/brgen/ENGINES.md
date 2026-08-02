# brgen verticals as mountable engines

brgen's subdomain verticals are being pulled out of the host app into mountable
Rails engines under `engines/`, so each subapp (tv, dating, takeaway, playlist,
marketplace, messenger) has focused ownership instead of drowning in brgen main.
brgen main keeps the x.com-style social feed and the craigslist/airbnb-style
personal classifieds; the marketplace engine is the Amazon-style multi-seller
storefront; the rest are their own domains.

`tv` was the pilot (2026-08-02). This is the recipe it proved — follow it exactly;
the two starred steps are non-obvious and cost a boot each to find.

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
   - `brgen-v.gemspec` — `spec.name = "brgen-v"`, `spec.files = Dir["{app,config,db,lib}/**/*"]`, `add_dependency "rails"`, `add_dependency "pub4-shared"`.
   - `lib/v.rb` — `require "v/version"; require "v/engine"`.
   - `lib/v/version.rb`, `lib/v/engine.rb` — the engine class **mirrors `Shared::Engine`**: `isolate_namespace Ns`, `<<` (never `+=`) on `config.autoload_paths` (Rails 8.1 freezes those arrays mid-boot), `config.paths["db/migrate"] <<`, and initializers that `append_view_path` and push `app/assets/stylesheets` + `app/javascript` onto `config.assets.paths`.

2. **★ Gemfile** — `gem 'brgen-v', path: 'engines/v', require: 'v'`.
   The `require:` is load-bearing. Bundler auto-requires a dashed path gem by its
   dashed name (`brgen-v` → `brgen/v`), but the entry file is `lib/v.rb`, so
   without `require: 'v'` the engine class is undefined when routes are drawn:
   `uninitialized constant Ns::Engine`.

3. **Move code** (preserve history with `git mv`):
   - `app/{controllers,models,views}/v` → `engines/v/app/{controllers,models,views}/v`
   - vertical assets (`_vertical_v*.scss`, `v_*_controller.js`) → `engines/v/app/assets/...`
   - the vertical's tests → `engines/v/test/...`

4. **Internal helper rename.** Under `isolate_namespace`, the engine's own routes
   are unprefixed. Rewrite every `v_X_(path|url)` → `X_\2` inside `engines/v/app`.
   (Do NOT touch `v_model:` form-param keys — those derive from the class name,
   not routes, and keep the prefix.)

5. **Engine routes** — move the vertical's route block into
   `engines/v/config/routes.rb` as `Ns::Engine.routes.draw do … end`, unprefixed.

6. **★ Host mount** — in `config/routes.rb`, replace the
   `constraints(subdomain: V_SUBDOMAINS) { scope module: "v" … }` block with a
   **top-level** mount:
   `mount Ns::Engine, at: "/", as: "v", constraints: { subdomain: V_SUBDOMAINS }`.
   Do NOT wrap the mount in a `constraints(subdomain:) do … end` block: nested,
   the routes still work but Rails does not register the `as:` mounted-helper
   proxy, and every host `v.X_url` silently breaks.

7. **Host refs** — the handful of host files that link into the subdomain
   (`application_helper`, `sitemaps_controller`, some tests) call `v_X_url` →
   rewrite to `v.X_url`. These generate cross-subdomain URLs with
   `host:`/`subdomain:` and now resolve through the mounted proxy, e.g.
   `tv.channel_url("foo", host: "brgen.no", subdomain: "tv") → http://tv.brgen.no/channels/foo`.

8. **Gates are already engine-aware** — `coverage_ratchet_test` and
   `turbo_broadcast_contract_test` glob `engines/*/app`, so no per-vertical gate
   edits are needed EXCEPT: extracting a vertical can drop a host coverage floor
   when a flat host test was basename-colliding with a same-named `Ns::` class
   (that was a double-count, not coverage). Lower the floor to the true count and
   say why in `FLOORS`.

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
controller or two reusing shared models, no migrations. Do steps 1, 2, 5, 6, 7 only.

## Not an engine: master

`master` (ai.brgen.no) is a separate application with its own deploy, not a brgen
vertical. It is already more separated than an engine; do not fold it into brgen.
