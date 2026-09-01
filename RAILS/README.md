# Rails apps

**Three production apps, one shared engine, and one process that answers to a
hundred hostnames.** brgen is the city network, amber is wardrobe intelligence,
bsdports is ports search — 3 active production Rails apps, matching `apps.yml`.
All three run Rails 8.1 on SQLite behind Falcon and relayd, on Ruby 3.4, with
`config.assume_ssl` on and no `force_ssl`. Feature
truth is `apps.yml`; ports and domains are there too, so nothing here restates
them.

brgen is not a folder of apps. Every city apex in `Brgen::DomainRegistry` serves
the feed, and the verticals are namespaced engines on subdomains of that apex —
`dating.brgen.no`, `dating.lsangeles.com`, `marketplace.lndon.uk`. Apexes are
usually the city with a vowel dropped. Read `brgen/AGENTS.md` before touching a
vertical, and `brgen/ENGINES.md` before adding one.

`shared/` is the `pub4-shared` gem, mounted through `path: '../shared'`. The
copy-tree deploy puts each app at `/home/<app>/app` and gives it its own copy of
the engine at `/home/<app>/shared` — a sibling, never a subdirectory, and syncing
to the wrong one makes precompile a silent no-op. Health lives at `/up` for
liveness and `/health` for Solid Cache, Solid Queue and DB depth; secrets live in
`/etc/<app>.env` on the VPS and no `config/master.key` is in git. `_deploy.sh` is
the orchestrator, `deploy.sh` a thin shim, and the per-app scripts source the
shared contract.

### Gates

Every gate is one row in `gates/gates.yml`, carrying its `require`, its
`Deploy::*` class, its pass line, and the composite that runs it as a leaf.
`runner.rb` reads that file and so does `OPENBSD/lib/gate_environment.rb`, by
gate name rather than by path, which is why adding a gate is a row and not a
script. That file replaced four hand-maintained tables that had to agree with
each other and thirty-seven shim scripts whose only job was to require a class
the runner had already loaded. Listing the gates again here would rebuild the
disagreement, so `runner.rb --list` is the list.

Most gates run in-process and return a `Deploy::GateResult`. Only `release`,
`rails_runtime` and `visual_contract` still subprocess, for bundle steps and
argument forwarding, and they declare `script:` instead of `require:` and
`class:`. `rails_runtime` calls `Deploy::ProductionGate.run(skip_nested: true)`
directly so nested master gates do not run twice under `--all`;
`GATE_SKIP_NESTED=1` asks `runner.rb production` for the same skip.

The source gates read text. The rendered suite measures what Chrome actually laid
out, over the DevTools Protocol through `gates/support/cdp_session.rb`, which
speaks the protocol over a WebSocket built from stdlib alone — ferrum and
selenium exist only inside app bundles and gates run under bare `ruby`. Chrome is
found through `CHROME_PATH` or the usual locations, and without it every rendered
gate degrades to a warning, so a green run is not by itself evidence that
anything was measured.

That distinction is the whole argument for the suite. A source gate asserts
`_nav.scss` contains the string `min-height: 44px`. `geometry` asserts the box is
44px tall — the `--tap-min` token — at that viewport in a real browser, that nothing covers its centre
pixel, and that its text clears WCAG AA against its composited background — with
`var()`, `oklch` and `color-mix` resolved, which parsing hex out of a stylesheet
structurally cannot do. Chrome launches with `--host-resolver-rules`, so
`markedsplass.brgen.no` and the other verticals are probed as verticals; Selenium
could not set a `Host` header, which is why the older optional probe skipped
markedsplass entirely.

Baselines are committed as geometry, not as pictures. `visual_contract` reads its
baseline from whatever PNG sits at the destination path and then overwrites it,
and those PNGs are gitignored — so a regression is reported once, becomes the new
baseline, and does not exist at all on a fresh checkout. `layout_snapshot` writes
rect and style JSON instead: tracked, reviewable, immune to antialiasing and GPU
differences, and its diffs read `nav.tab-bar: h 48→32` rather than "8,214 pixels
changed". New baselines are accepted only under `GATE_SNAPSHOT_UPDATE=1`, and
deliberately not under `GATE_AUTOFIX`, because blessing a regression is the
behaviour this replaces.

`geometry` and `reflow` do autofix, and the shape of it is deliberate. They write
corrective rules into a generated `_autofix_geometry.scss` per app, register the
`@use`, and rebuild CSS before remeasuring. Additive and quarantined, because a
rendered violation names a selector rather than a source rule and the cascade
rather than any one declaration produced the box — so rewriting a guessed rule
would be a guess. Delete the partial and its `@use` line to revert. Rounds and
dry-run come from the shared `GateAutofix` policy through `GATE_AUTOFIX`,
`GATE_AUTOFIX_DRY` and `GATE_AUTOFIX_ROUNDS`. Token colours are never rewritten:
`design_metrics` prints the hex that would clear AA and leaves the brand decision
to a person.

`apps_yml` validates that app directories and deploy scripts exist, that ports
and domains are unique, and that every feature carries `status: done` or
`planned`. Horizon features in `apps.horizon.yml` stay `agent: ignore`. Deploy
blockers are in the repo-root `TODO.md` with an owner, unblock criteria and the
check that covers each — kept there rather than here because two of the five
sentences this file used to carry about them had gone stale unnoticed.

A gate can only see what it globs. Three endpoints answered 500 in production
while 148 simulated pages passed, because `PageInventory` globbed each app's own
`app/views` and never `shared/app/views` — account settings, notifications, both
password screens and two-factor sat outside every gate at once.
`PageInventory::SHARED_PAGES` declares them now, and `uncovered_shared_views`
fails `page_simulation` on any non-partial shared view without a row.

### Routing, assets and media

Subdomain constraints live in `brgen/config/routes.rb` and resolve through
`Brgen::DomainRegistry`, which maps the marketplace aliases, playlist, takeaway,
tv, maps, dating, messenger's conversations and the MASTER relay onto their
modules. Scoped roots use single-prefixed helpers — `marketplace_root_path`, not
`marketplace_marketplace_root_path` — and `ApplicationHelper#marketplace_root_url`
delegates to `Rails.application.routes.url_helpers` so it does not shadow the
route helper. `runner.rb domain_alignment` holds the DNS, registry, inventory and
relayd sides in agreement.

The operator half of domain switching is `/domain <name>` in the CLI through
`SubdomainOrchestrator`, and the browser half is `window.MASTER_ACTIVE_DOMAIN`,
read by `MASTER/web/public/chat_actions.js`. The dedicated domain bar has no
source in the tree: only the precompiled
`MASTER/web/public/assets/domain_cluster-3bf218f7.js` survives, so it ships and
cannot be rebuilt. Treat it as vendored until someone restores the source.

All three apps compile the same network-first-for-HTML service worker from
`shared/pwa/service_worker.js`, served at `/service-worker` and rebuilt with `npm
ci && npm run build:pwa` from this directory. `/offline` renders the shared
partial, and the styled 404, 422 and 500 pages in `shared/public/` are copied
into each app's `public/` at deploy.

Rails resolves MASTER's media tools through `Pub4::DeployPaths`, which handles
both the source checkout and the VPS copy-tree; never compute those paths from
`Rails.root`. Newsletter hero rendering can use the same postpro and repligen
pair MASTER uses. Provider tokens belong in the app's `/etc/<app>.env` and not in
Rails credentials or source. MASTER's natural-language media routing is local to
the agent runtime, so Rails callers should go through the shared service boundary
and keep their jobs observable and retryable.

Per-app notes are in `<app>/AGENTS.md`, working rules in `CLAUDE.md` beside this
file, and the backlog in the repo-root `TODO.md`.

### Running it

```zsh
ruby RAILS/gates/runner.rb --all           # every registered gate
ruby RAILS/gates/runner.rb --list          # what there is to run
ruby RAILS/gates/runner.rb rendered_suite  # the browser-backed ones
RAILS/bin/triangle up                      # boot the surfaces the live gates probe
cd RAILS/<app> && bin/ci                   # RuboCop, Brakeman, bundler-audit, tests
cd MASTER && ruby bin/gate                 # MASTER's own chain over this tree
```
