# Decisions

This file records intentional shapes that may otherwise look like bugs.

## Two Master Spines

`lib/` and `kernel/` are intentionally separate load paths. `lib/` is the gem, CLI, loop, judge, reach, trace, voice, and web-facing runtime. `kernel/` is a small isolated constitutional fold loaded on its own path by kernel tests and `bin/master-kernel`.

As of `b61d73a7d`, kernel types live under `Master::Kernel::` (not top-level `Master::`) so namespace audits no longer collide with lib constants. `bin/nsaudit` skips only the kernel entrypoint file, not the whole tree.

Namespace tooling should treat `bin/master-kernel` as the kernel load entrypoint.

## Rule Data Stays Split

`data/rules.yml` is the constitutional rule registry. `data/rules/*.yml` are scanner shards by scope. `data/design_rules.yml`, `data/llm_output_rules.yml`, and `data/rule_deps.yml` each have separate consumers. Merging them would reduce proximity to their owners.

## Local Knowledge Stays Local

`knowledge/` is gitignored and skipped by scanners/snapshots, but it still powers `Master::Reach::SearchKnowledge`. Do not move it unless the search tool learns the new location first.

## Deferred WebGL Boot Is Sacred

The face runtime must not create a WebGL context before the primer tap. The guard in `web/app/views/chat/index.html.erb` protects the tap-to-start path from eager or stale assets.

## Self-Test Is A Loud Gate

`rake selftest` runs `rules.yml.self_test` against MASTER itself. It is allowed to fail while known debt remains; the point is to make debt visible and triageable.
