# Decisions

This file records intentional shapes that may otherwise look like bugs.

## Two Master Spines

`lib/` and `core/` are intentionally separate load paths. `lib/` is the gem, CLI, loop, judge, reach, trace, voice, and web-facing runtime. `core/` is a small isolated constitutional fold loaded on its own path by the core tests and `bin/master-core`.

Core types live under `Master::Core::` (not top-level `Master::`) so they coexist with lib constants in one process — the runtime cutover loads `core/` into the CLI via the bridge. `bin/nsaudit` loads the core entrypoint explicitly; the two-spine design is deliberate, not accidental duplication. (The module was named `Master::Kernel` until it was renamed to `Master::Core` to stop shadowing Ruby's built-in `::Kernel`.)

Namespace tooling should treat `bin/master-core` as the core load entrypoint.

## Rule Data Stays Split

`data/rules.yml` is the constitutional rule registry. `data/rules/*.yml` are scanner shards by scope. `data/design_rules.yml`, `data/llm_output_rules.yml`, and `data/rule_deps.yml` each have separate consumers. Merging them would reduce proximity to their owners.

## Local Knowledge Stays Local

`knowledge/` is gitignored and skipped by scanners/snapshots, but it still powers `Master::Reach::SearchKnowledge`. Do not move it unless the search tool learns the new location first.

## Deferred WebGL Boot Is Sacred

The face runtime must not create a WebGL context before the primer tap. The guard in `web/app/views/chat/index.html.erb` protects the tap-to-start path from eager or stale assets.

## Self-Test Is A Loud Gate

`rake selftest` runs `rules.yml.self_test` against MASTER itself. It is allowed to fail while known debt remains; the point is to make debt visible and triageable.
