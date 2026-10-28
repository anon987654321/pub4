# Efficient checks → repair → proof

This is the short field guide for a bounded repair pass: measure the relevant surfaces, repair only the owning tree, then repeat the same proof. The detailed command boundaries and coverage limits are in [`efficient_repair_workflow.md`](efficient_repair_workflow.md).

Run these commands from `MASTER/` using the repository-selected Ruby and bundle.

## 1. Measure architecture and the product design stack without check autofix

```zsh
bundle exec ruby checks/runner.rb --scan-only architecture layout_suite
```

This invokes **check registry names** directly. `architecture` is the inexpensive Phoenix boundary check. `layout_suite` is the composite for CSS constitution, typography, scale, source design contracts, and the rendered suite. Do not rerun its individual leaves by hand.

Browser-backed results count only when their preconditions are met. Missing browsers, skipped routes, zero rendered cells, blocked checks, or inconclusive measurements are not rendered-UX proof.

**Important command distinction:** `bin/operator check --only=...` accepts CheckChain **stage names** such as `lexical`, `source`, `rehearse`, and `suites`. It does not accept check registry names such as `layout_suite` or `constitutional_scan`.

## 2. Measure the full constitutional scan debt when it is in scope

```zsh
bundle exec ruby checks/runner.rb --scan-only constitutional_scan
```

The default scan population is six targets: RAILS/brgen, RAILS/amber, RAILS/bsdports, RAILS/__shared, OPENBSD, and MASTER. This scan can take many minutes and is **not** narrowed by `bin/operator check --tree=RAILS`. `CHECK_SCAN_CHANGED=1` narrows it to changed targets, which is useful for a focused follow-up but is not full-corpus evidence.

A completed catalogue scan still does not prove that every declared Law has a decisive detector or that every runtime surface was exercised. Undetected or unmeasured coverage remains debt; do not report it as clean.

## 3. Repair only the tree that owns the findings

For the RAILS product/layout surface:

```zsh
bin/master /fix RAILS
```

Use `bin/master /fix MASTER` when the runtime, scanner, or Law tooling is the owner. Keep OPENBSD for host/network/deployment debt and STUDIO for media/toolchain debt. The protocol architecture tournament is part of model-backed `/fix` on a named target; it is not the small `architecture` check. Four-tree `/fix` is a deliberate long-running campaign, not the default first pass.

## 4. Re-measure and retain evidence

Repeat the exact read-only check commands used before repair:

```zsh
bundle exec ruby checks/runner.rb --scan-only architecture layout_suite
# Also repeat this if the full constitutional scan was part of the acceptance scope:
bundle exec ruby checks/runner.rb --scan-only constitutional_scan
```

For broader deterministic proof of the selected RAILS tree, the operator CheckChain has a separate stage interface:

```zsh
bin/operator check --scan-only --tree=RAILS --only=lexical,source,rehearse,suites,ratchets,sprawl
```

That broader run may take substantially longer; omitting `council` is deliberate and does not claim model-backed critique ran. The unfiltered `bin/operator check --scan-only --tree=RAILS` includes the configured council stage and may invoke model-backed critique despite being scan-only.

Record each command's actual result as PASS, FAIL, INCONCLUSIVE, BLOCKED, TIMEOUT, or DELIVERY_FAILED. Preserve its output and commit identity. A source diff, authored regression, third-party CI status, or copied-method harness is not a substitute for running the repository test or host check being claimed.

## Coverage map

| Concern | Instrument | Boundary |
|---|---|---|
| Four-tree boundary architecture | `architecture` registry check | Source-level boundary, not candidate tournament |
| Architecture alternatives/candidates | `/fix` on a named tree | Expensive, model-backed exploration |
| CSS, typography, scale and source layout | `layout_suite` | Rendered proof requires browser preconditions |
| Law catalogue and executable scan | `constitutional_scan` plus `/fix` | Detector gaps stay explicit |
| Code and multi-file repair | `/fix` on the owning tree | Must be followed by the same checks |
| Host, DNS, PF and deployed response | OPENBSD checks + operator evidence | Repository source checks cannot prove host state |
| Audio/video and media pipelines | STUDIO checks + actual tools/assets | Source inspection alone cannot prove runtime output |

The goal is to reduce measured debt without paying for unrelated work, while keeping every unmeasured surface visible.
