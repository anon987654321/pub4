# Real-world interaction campaign

The campaign fixture `test/interaction_campaign_400.json` defines 400 distinct action-and-fault scenarios across twenty user-facing and operator surfaces. Each surface has twenty scenarios and exercises the full twenty-mode fault catalogue.

## Surfaces

| Surface | Cases |
| --- | ---: |
| Brgen identity and sessions | 20 |
| Brgen feed, posts and communities | 20 |
| Marketplace discovery and seller workflow | 20 |
| Marketplace cart, checkout, orders, returns and payouts | 20 |
| Dating profile and swipe workflows | 20 |
| Messenger and conversations | 20 |
| Takeaway and group ordering | 20 |
| Maps, nearby discovery, events and location privacy | 20 |
| Radio, playlists and embedded audio | 20 |
| TV, video feed, watch-time and broadcasts | 20 |
| Amber wardrobe inventory and media | 20 |
| Amber outfits and wardrobe analytics | 20 |
| Amber social, connections and messaging | 20 |
| BSDPorts search, dependencies and advisories | 20 |
| MASTER web face and shell | 20 |
| MASTER web chat, auth and streaming | 20 |
| MASTER CLI commands and configuration | 20 |
| MASTER /fix lifecycle and delivery | 20 |
| PWA install, offline store and service worker | 20 |
| Cross-app security, accessibility and recovery | 20 |
| **Total** | **400** |

## Fault catalogue

Every surface is paired once with each of these modes: baseline, empty state, invalid input, duplicate action, expired session, network disconnect, server failure, slow response, concurrent change, unauthorized actor, CSRF failure, page refresh, history navigation, mobile viewport, keyboard-only use, reduced motion, offline-to-online recovery, malformed response, rate limit and restart recovery.

This cross-product makes the scenario inventory auditable; it does not assert that every injected fault is meaningful for every action. The actual runner must validate each pairing and skip or adapt irrelevant injections with an explicit reason rather than silently passing them.

## Evidence and status semantics

Each case carries source paths, a specific action, an adversarial condition and an expected outcome. The current records use `assessment: SOURCE_EXPECTATION_ONLY` and `runtime_status: NOT_RUN`.

A source-derived expectation is a test oracle, not an observed outcome. Do not change a case to `PASS` without saved runtime evidence, or to `FAIL` without a reproducible failure record. Use `BLOCKED` when the environment, credentials or fixture prerequisites prevent execution and `SKIPPED` only with a recorded reason. Keep production data and live payment endpoints out of this campaign.

The manifest contract is covered by `test/interaction_campaign_contract_test.rb` and is included by the existing recursive `RAILS/test/run_all.rb` contract runner.

## Run order

Use the repository's canonical runners, which select the app-specific Ruby and Bundler context:

```text
ruby MASTER/tools/rails/premerge.rb --contracts
ruby MASTER/tools/rails/premerge.rb --apps
ruby MASTER/tools/rails/premerge.rb --pwa
ruby MASTER/tools/rails/premerge.rb --coverage
ruby MASTER/tools/rails/premerge.rb --gates
```

After the contract suite is green, execute the applicable Rails system/request tests with isolated databases, deterministic seed data and provider stubs. Use the existing MASTER browser and smoke runners for the face and transport. Persist a per-case runtime evidence record before changing any status. Run concurrency and load tests separately: 400 scenarios run sequentially are not a 400-user load test.

## Known execution boundary

This commit adds the matrix and its structural guard; it does not claim that the 400 application interactions have executed. At authoring time, the connected Vercel Sandbox service refused both new and resumed sessions because the account's usage limit had been exceeded, and the public application URLs were not accessible to the inspection tool. Those are execution blockers, not application passes or failures.
