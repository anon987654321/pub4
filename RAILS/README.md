# Rails apps

**Three Rails apps, one shared engine, and one process that answers to a hundred
hostnames, each built so that a stranger on a phone sees a single, quiet product
and never the machinery beneath it.** brgen is the city network, amber is the
wardrobe, and bsdports is a search of the ports tree. They run on SQLite behind
Falcon, on one box called vm23, and everything they share lives in one engine
so that a fix made once is made everywhere.

This README is the entry to the tree. Feature truth is `apps.yml`, which also
holds the ports, the domains and the stack versions, so nothing here restates
them. Planned work that is not yet real sits in `apps.horizon.yml` and is
marked for agents to ignore. The backlog is the file `TODO.md` at the repository
root. Rules for working in the tree are in `CLAUDE.md` beside this file, and each
app keeps its own notes in an `AGENTS.md`.

brgen is not a folder of apps. Every city apex in `Brgen::DomainRegistry` serves
the feed, and the verticals are engines reached on subdomains of that apex, so
`dating.brgen.no` and `dating.lsangeles.com` are the same code under two city
names. The verticals sit beside the host as directories named `brgen_` and the
vertical: dating, maps, marketplace, messenger and radio, which holds the playlist
and tv engines. Food ordering is nested inside marketplace. Anything that counts
brgen's code must read the host and every `brgen_*` directory, or it measures
about half the app and calls the result health. Read `brgen/AGENTS.md` before you
touch a vertical, and `brgen/README.md` before you add one.

The shared engine is the `pub4-shared` gem and lives in `__shared`. Each app
loads it by local path. On the box, the copy-tree deploy puts each app at
`/home/<app>/app` and gives it its own copy of the engine at `/home/<app>/shared`,
a sibling and never a subdirectory. Syncing to the wrong one makes the asset
precompile a silent no-op. `__shared/README.md` describes what the engine owns.
The MASTER web face, which serves `ai.brgen.no`, is a fourth Rails surface in
`master_web`, and its own `CLAUDE.md` governs it.

Everything that builds, tests or probes these apps now lives under MASTER. The
old RAILS `bin` directory is gone, and its work moved into `MASTER/tools/rails`,
reached through the operator: `triangle` boots brgen, amber, bsdports and the
face on the ports the live gates probe, `premerge` runs the premerge proof, `ci`
runs each app's own `bin/ci`, and `coverage` runs the full coverage pass. Each app
also keeps its own `bin/ci` for RuboCop, Brakeman, bundler-audit and the tests.
The design tokens come from `MASTER/data/tokens.yml`, and the shared engine's
`design_tokens.yml` is a file generated from it, not a second source.

Production is one box. A deploy sheds amber and bsdports, and relayd keeps
answering TLS with their ports closed, so the outage looks like a hang and not a
server error. The deploy command restores them. If you deploy by hand, check
ports 61352 and 47312. Health is `/up` for liveness and `/health` for the depth of
Solid Cache, Solid Queue and the database. Secrets live in `/etc/<app>.env` on the
box, and no `config/master.key` is in git. `_deploy.sh` is the orchestrator,
`deploy.sh` a thin shim, and each app's own script sources the shared contract.
The apps default to Norwegian, so tests assert through I18n keys and never through
English literals.

Strict loading is on in every environment. Reading a lazy association off a record
fetched by id raises in test and in production, so check that before you report a
server error. Money is stored as integer minor units.

The gates are rows in `MASTER/gates/gates.yml`, run by `MASTER/gates/runner.rb`,
which can list them. Most run in process. The source gates read text, and the
rendered gates drive Chrome over the DevTools Protocol with a small stdlib
session, and measure what the browser laid out. Without Chrome the rendered gates
degrade to warnings, so a green run is not by itself evidence that anything was
measured. A gate can only see what it globs. Shared views once sat outside every
gate because the page inventory read each app's views and never the engine's, and
the inventory now names them explicitly.

Media work goes through the contract in `MASTER/contracts/studio.rb`. STUDIO owns
postpro, replicate and dilla, and Rails does not load their classes. Provider
tokens belong in the app's env file on the box and never in credentials or source.
All three apps compile the same service worker from the engine's `pwa` directory,
and the styled error pages in the engine's `public` directory are copied into each
app at deploy.

## Running it

```zsh
ruby MASTER/gates/runner.rb --list
ruby MASTER/gates/runner.rb --all
MASTER/bin/operator triangle up
MASTER/bin/operator premerge --list
cd RAILS/brgen && bin/ci
```
