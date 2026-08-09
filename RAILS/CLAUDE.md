# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Scope: `RAILS/`. Repo-wide rules are in `../CLAUDE.md`; authority order is
`MASTER/data/soul.yml` > `MASTER/data/rules.yml` > `../CLAUDE.md` > this file.

This file is a pointer. `README.md` in this directory is the maintained
long-form reference (gate tables, rendered-gate semantics, deploy blockers,
subdomain map) and `apps.yml` is feature truth — do not restate either here.
The root `CLAUDE.md` was once deleted wholesale for exactly that drift.

## Commands

```zsh
ruby RAILS/gates/runner.rb --all          # every registered gate
ruby RAILS/gates/runner.rb --list         # gate names
ruby RAILS/gates/runner.rb production     # one gate, or a composite
ruby RAILS/test/<name>_test.rb            # one contract test — bare ruby, no bundle
cd RAILS/<app> && bin/ci                  # per-app RuboCop, Brakeman, bundler-audit, tests
cd RAILS/<app> && bin/rails test test/models/item_test.rb:42   # one app test
RAILS/bin/triangle up                     # boot all 4 surfaces on the ports gates probe
npm ci && npm run build:pwa               # rebuild the Workbox service worker
```

`RAILS/test/*.rb` are standalone Minitest files run under bare `ruby` — they read
source as text and never boot Rails. App tests under `RAILS/<app>/test/` need the
app bundle. Ruby 3.4.9 is pinned by `.ruby-version` at the repo root and in each
app directory, so app commands resolve the same interpreter from any cwd.

Which check proves the work: source change → the gate that owns it
(`runner.rb --list`); app code → that app's `bin/ci`; anything measuring rendered
layout → `RAILS/bin/triangle up` first, or the live half silently passes having
measured nothing.

## Architecture

**One engine, three apps.** `shared/` is the `pub4-shared` gem, mounted by
`path: '../shared'` in each app's Gemfile. It carries models, controllers, views,
Stimulus controllers, policies and lints that all three apps share. Concerns come
in through `Shared.concern(:Votable)`, routes through an `instance_eval` of
`shared/config/routes/social.rb` in each app's `routes.rb`. A change in `shared/`
lands in three apps at once — check all three before assuming a fix is local.

**Shared deploys as a sibling, not a subdirectory.** The copy-tree deploy puts the
tracked app at `/home/<app>/app` and its own copy of the engine at
`/home/<app>/shared`. Every app vendors a separate copy; syncing to the wrong one
makes precompile a silent no-op. `Pub4::DeployPaths` resolves OPENBSD tools across
both source-checkout and copy-tree shapes — never compute paths from `Rails.root`.

**brgen's verticals are mountable engines**, not namespaced controllers:
`brgen/engines/{marketplace,dating,playlist,takeaway,tv}`. Subdomain constraints
in `brgen/config/routes.rb` via `Brgen::DomainRegistry` map `markedsplass`,
`dating`, `tv` and the rest onto them. Messenger and the MASTER relay are not
engines. Tooling that globs `<app>/app/**` misses engine code — four scanners
stopped seeing 57 views when the verticals moved, and the falling finding count
read as improvement rather than blindness.

**Gates are declared once.** Every gate is a row in `gates/gates.yml` carrying its
`require`, `Deploy::*` class, pass line, and parent composite; `runner.rb` and
`OPENBSD/lib/gate_environment.rb` both read that file by gate name. Adding a gate
is one row — not a new script. Most run in-process returning a
`Deploy::GateResult`; only `release`, `rails_runtime` and `visual_contract`
subprocess.

**Source gates read text; rendered gates measure Chrome.** The `rendered_suite`
family drives real Chrome over CDP through `gates/support/cdp_session.rb` — stdlib
only, no ferrum/selenium, because gates run under bare `ruby` outside any app
bundle. Without Chrome they degrade to warnings rather than failing, so a green
run does not by itself mean anything was measured.

**MASTER governs this tree.** `cd MASTER && ruby bin/gate` runs the same
`/scan → /fix → /critique → /review` chain over `RAILS/` that MASTER runs on
itself, and `/fix` mutates the working tree. `MASTER_GATE_SCAN_ONLY=1` for
preflight.

## Traps

- **Visual/CSS work:** read `shared/WIRING_NOTES.md` "Visual design system" first.
  Tokens live in `shared/app/assets/stylesheets/_dialect_tokens.scss`; flat only,
  no shadow/blur/glow. Most layout "bugs" here are stale deployed CSS — diff live
  against source before changing anything.
- **Stale fragment caches:** `update_column` skips `updated_at`, so `[record, …]`
  cache keys do not bust and a page keeps rendering the old value while the
  console shows the new one.
- **`visual_contract` baselines are gitignored** and overwritten on read — a
  regression reports once and becomes the baseline. `layout_snapshot` commits
  reviewable rect/style JSON instead; accept new baselines only under
  `GATE_SNAPSHOT_UPDATE=1`.
- **Deploy sheds amber and bsdports**, and TLS keeps answering, so the outage
  looks like `curl 000` rather than a 5xx. Check ports 61352 and 47312 directly.
- **Horizon features** in `apps.horizon.yml` are `agent: ignore` — do not
  implement unprompted.
