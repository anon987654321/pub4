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

Each case resolves a specific action, adversarial condition and expected outcome through canonical surface, action and fault records. Evidence paths, surface-level contracts and each surface's `focused_test_paths` are stored once. MASTER `/fix` reads that same mapping to choose existing focused tests for baseline/candidate comparisons; it does not copy a second test map into Ruby. The current records use `assessment: SOURCE_EXPECTATION_ONLY` and `runtime_status: NOT_RUN`.

A source-derived expectation is a test oracle, not an observed outcome. Do not change a case to `PASS` without saved runtime evidence, or to `FAIL` without a reproducible failure record. Use `BLOCKED` when the environment, credentials or fixture prerequisites prevent execution and `SKIPPED` only with a recorded reason. Keep production data and live payment endpoints out of this campaign.

The manifest contract is covered by `test/interaction_campaign_contract_test.rb` and is included by the existing recursive `RAILS/test/run_all.rb` contract runner. The fixture is normalized to avoid repeating surface contracts, action text, fault instructions and evidence paths in every row.

MASTER `/fix` uses the campaign to propose several materially different repairs, compare candidates against the target Law and focused tests, reject observed regressions and restore the original before each next trial. This is not a claim to have executed all 400 scenarios. A candidate test run is scoped to existing tests selected from `focused_test_paths`; the broader browser/acceptance scenario is still NOT_RUN until that exact behavior is driven and evidence is saved. Candidate telemetry keeps the distinction explicit: `scenario_oracles_consulted` is an oracle count, `status` is the result of the focused tests, and `scenario_runtime_status: NOT_RUN` means no individual campaign interaction was executed by that event.

## Execute mapped cases

The evidence runner drives only case-specific adapters declared in the manifest:

```text
ruby RAILS/test/run_interaction_campaign.rb --list
ruby RAILS/test/run_interaction_campaign.rb --case RI-011
ruby RAILS/test/run_interaction_campaign.rb --all
```

The current exact adapters are RI-001 (valid signup), RI-003 (malformed email), RI-010 (protected route) and RI-011 (expired session plus CSRF refusal). RI-001 creates a member with unique credentials and confirms the account remains unverified pending email confirmation. RI-010 opens a protected community route as an unauthenticated visitor and expects a redirect. RI-011 opens an authenticated community form, invalidates the server-side session, then verifies both an invalid CSRF request and a stale-session write leave persisted state unchanged. The runner invokes the exact named Minitest method and requires exactly one run with at least one assertion. It hashes the manifest bytes used for selection and the mapped test source before and after execution; a mid-run source change is BLOCKED. It records the command, test-source SHA-256, captured-output SHA-256, run counts and redacted log under the ignored `.master/interaction_campaign_runs/` directory. `log_sha256` fingerprints the redacted log separately; common API keys, bearer values, GitHub tokens and cookie headers are redacted before the log is written. A failing assertion is FAIL; a timeout, absent summary or non-executed named test is BLOCKED. Cases without an exact action/fault adapter are recorded as SKIPPED with a reason, never inferred PASS from a passing neighbouring test file.

The checked-in manifest remains the authored inventory and is not rewritten by a local run. Its rows stay `NOT_RUN` until observed evidence is deliberately promoted; the run ledger reports the outcome for that specific execution. The `--all` command deliberately exits as incomplete while unmapped cases remain, even if every mapped adapter passes.

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
