# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

Scope: `RAILS/`. The repo-wide entrypoint is `../CLAUDE.md`; MASTER is primary configuration. Authority order is
`MASTER/data/soul.yml` > `MASTER/data/laws.yml` >
the executable Law tree `MASTER/law/` >
this file.

This file is a pointer. `README.md` in this directory is the maintained
long-form reference (check tables, rendered-check semantics, deploy blockers,
subdomain map) and `apps.yml` is feature truth — do not restate either here. The
root `CLAUDE.md` was once deleted wholesale for exactly that drift.

## Commands

```zsh
ruby MASTER/checks/runner.rb --all          # every registered check
ruby MASTER/checks/runner.rb --list         # check names
ruby MASTER/checks/runner.rb production     # one check, or a composite
ruby RAILS/test/<name>_test.rb            # one contract test — bare ruby, no bundle
cd RAILS/<app> && bin/ci                  # per-app RuboCop, Brakeman, bundler-audit, tests
cd RAILS/<app> && bin/rails test test/models/item_test.rb:42   # one app test
MASTER/bin/operator triangle up                     # boot all 4 surfaces on the ports checks probe
npm ci && npm run build:pwa               # rebuild the Workbox service worker
```

`RAILS/test/*.rb` are standalone Minitest files run under bare `ruby` — they
read source as text and never boot Rails. App tests under `RAILS/<app>/test/`
need the app bundle. Ruby 4.0.5 is pinned by `.ruby-version` at the repo root
and in each app directory, so app commands resolve the same interpreter from any
cwd.

Which check proves the work: source change → the check that owns it (`runner.rb
--list`); app code → that app's `bin/ci`; anything measuring rendered layout →
`MASTER/bin/operator triangle up` first, or the live half silently passes having measured
nothing.

## Architecture

**One engine, three apps.** `shared/` is the `pub4-shared` gem, mounted by
`path: '../shared'` in each app's Gemfile. It carries models, controllers,
views, Stimulus controllers, policies and lints that all three apps share.
Concerns come in through `Shared.concern(:Votable)`, routes through an
`instance_eval` of `__shared/config/routes/social.rb` in each app's `routes.rb`. A
change in `shared/` lands in three apps at once — check all three before
assuming a fix is local.

**Shared deploys as a sibling, not a subdirectory.** The copy-tree deploy puts
the tracked app at `/home/<app>/app` and its own copy of the engine at
`/home/<app>/shared`. Every app vendors a separate copy; syncing to the wrong
one makes precompile a silent no-op. `MASTER/contracts/studio.rb` resolves the canonical STUDIO media entrypoints from the source or deployed tree; callers do not reach into sibling implementation directories.

**brgen's verticals are mountable engines**, not namespaced controllers. Marketplace
contains the food-ordering Takeaway engine as a nested package; it is exposed at
`/food` on the marketplace host. Subdomain constraints in `brgen/config/routes.rb`
via `Brgen::DomainRegistry` map `markedsplass`,
`dating`, `tv` and the rest onto them. Messenger and the MASTER relay are not
engines. Tooling that globs `<app>/app/**` misses engine code — four scanners
stopped seeing 57 views when the verticals moved, and the falling finding count
read as improvement rather than blindness.

**Checks are declared once.** Every check is a row in `checks/checks.yml` carrying
its `require`, `Deploy::*` class, pass line, and parent composite; `runner.rb`
and `OPENBSD/lib/check_environment.rb` both read that file by check name. Adding a
check is one row — not a new script. Most run in-process returning a
`Deploy::CheckResult`; only `release`, `rails_runtime` and `visual_contract`
subprocess.

**Source checks read text; rendered checks measure Chrome.** The `rendered_suite`
family drives real Chrome over CDP through `checks/support/cdp_session.rb` —
stdlib only, no ferrum/selenium, because checks run under bare `ruby` outside any
app bundle. Without Chrome they degrade to warnings rather than failing, so a
green run does not by itself mean anything was measured.

**MASTER governs this tree.** `cd MASTER && ruby bin/check --ladder` runs the same `/scan
→ /fix → /critique → /review` chain over `RAILS/` that MASTER runs on itself,
and `/fix` mutates the working tree. `MASTER_CHECK_SCAN_ONLY=1` for preflight.

## Traps

- **Visual/CSS work:** read `__shared/README.md` first: the visual design system
  and the layout chrome contract every surface shares are there.
  Tokens live in `__shared/app/assets/stylesheets/_dialect_tokens.scss`; flat
  only, no shadow/blur/glow. Most layout "bugs" here are stale deployed CSS —
  diff live against source before changing anything.
- **Stale fragment caches:** `update_column` skips `updated_at`, so `[record,
  …]` cache keys do not bust and a page keeps rendering the old value while the
  console shows the new one.
- **`browser_diagnostics` runs through the same CDP session as the rendered
  checks.** It records console/runtime exceptions, HTTP/resource failures and a
  screenshot for every reachable route/viewport in `geometry_surfaces.yml`;
  artifacts live outside the repo under the system temp directory. Console
  warnings/errors remain soft until `CHECK_STRICT_SOFT=1`; uncaught exceptions,
  document/server errors, and missing first-party scripts/stylesheets fail. It
  is part of `rendered_suite`.
- **`visual_contract` is a compatibility route matrix over the canonical CDP
  browser session.** `layout_snapshot` holds the committed structural baseline.
  `browser_diagnostics` also compares approved PNG references in
  `MASTER/checks/data/visual_baselines/` for opted-in surfaces and writes diff
  heatmaps with pixel counts. Missing pixel baselines are soft until
  `CHECK_PIXEL_BASELINE_STRICT=1`. Approval is a separate operator action using
  `MASTER/tools/approve_visual_baselines.rb`, which promotes the exact reviewed
  artifact and protects existing references unless `--replace` is explicit.
  Structural baselines still require `CHECK_SNAPSHOT_UPDATE=1`.
- **Deploy sheds amber and bsdports**, and TLS keeps answering, so the outage
  looks like `curl 000` rather than a 5xx. Check ports 61352 and 47312 directly.
- **App suites run in the checkout.** `cd RAILS/<app> && RBENV_VERSION=4.0.5
  rbenv exec bundle exec rails test` prepares its own sqlite from the checked-in
  schema. The local fleet (`bin/operator triangle up`) serves this checkout, so
  a view change shows in the rendered checks as soon as it is saved.
- **Horizon features** in `apps.horizon.yml` are `agent: ignore` — do not
  implement unprompted.

## Editing frontend code

Stimulus packages are vendored, never fetched from a CDN;
`__shared/README.md` explains the check that holds
it and why a `pin` costs a `modulepreload`.

The visual design and product dialect are operator-owned. By default, restore or
ask; never invent a layout fix. The explicit campaign in
`RAILS/visual_completion.yml` authorizes `/fix RAILS` to complete measured
layout, type-scale, leading, and spacing-rhythm defects in app frontend files,
using existing primitives and tokens. It does not authorize palette or semantic
colour changes, font-family changes, canonical token edits, or a new visual
identity. Browser evidence, functional/accessibility checks, and focused tests
are required. Structural snapshots may be promoted only after the rendered
quality check passes and the snapshot joins the same rollback-safe `/fix`
transaction. Missing baselines or inconclusive measurements remain blockers.

Hidden swipe-reveal navigation is intended.

Split large mixed HTML/CSS/JS documents before editing them, and never ask a
model to rewrite one unless the output is a minimal unified diff. Structure goes
in `app/views`, styles in `app/assets/stylesheets`, Stimulus controllers in
`app/javascript/controllers` (or `shared/frontend/` when more than one app uses
them), and chart config, animations, fonts and SVG icons each in their own file.

Extract styling verbatim. Do not normalize, minify, rename classes, drop vendor
prefixes, collapse custom animations into generic transitions, or replace CSS
custom properties with literals while moving code. Do not alter chart options
while editing chart data. Prefer an additive class over changing an existing
one, and leave `PROTECTED` sections alone unless the task names them.

Scanners hold the parts of this that one file can show: `NO_JQUERY`,
`NO_INLINE_ASSETS_IN_SHELL`, `NO_MULTIPLE_LANGUAGES`, `NO_INLINE_STYLES`,
`MAGIC_COLOR`. The rest are properties of a diff, so they are checked by reading
one. The laws in `MASTER/data/laws.yml` govern visual decisions; rendered token values come from `MASTER/data/tokens.yml` through `Operator::MasterDesign`. Do not duplicate palettes, rhythm scales, or viewport values in app code.
