# Efficient checks → repair → proof

This is the default workflow for a bounded repair pass. It deliberately measures first, repairs only the owning tree, then repeats the same checks. It is not a substitute for the release battery or for evidence that requires a running browser, deployed host, audio review, or operator credentials.

## 1. Measure without writes

From the repository's `MASTER/` directory:

```zsh
bin/operator check --scan-only --tree=RAILS
```

If the source of debt may be in MASTER's runtime, scanner, or law tooling, measure that tree separately:

```zsh
bin/operator check --scan-only --tree=MASTER
```

The `architecture` check is a source-level boundary check. It does not run the protocol architecture tournament; that exploration belongs to the model-backed `/fix` workflow and should be invoked only for a named target when the measured debt justifies it.

## 2. Inspect the product design stack

For a RAILS product/layout pass, run the declared composite rather than hand-maintaining a parallel list of leaves:

```zsh
bin/operator check --scan-only --only=layout_suite --tree=RAILS
```

The registry declares `layout_suite` as the composite for CSS constitution, typography contract, scale, source layout and related frontend checks. Rendered geometry and browser diagnostics count as measured only when their preconditions are satisfied. If browser checks report blocked, skipped, or inconclusive, source-level success is not rendered-UX proof.

## 3. Measure constitutional coverage debt explicitly

```zsh
bin/operator check --scan-only --only=constitutional_scan --tree=RAILS
```

Repeat for `MASTER` if MASTER's own law/tooling surfaces are in scope. The catalogue and detector coverage are different facts: a clean scan does not prove that every declared Law has a deterministic detector, nor that every relevant runtime surface was exercised. Laws without a decisive detector remain INCONCLUSIVE; do not turn absent evidence into a green result.

## 4. Repair the smallest owning tree

Only after the measured output identifies the owner:

```zsh
bin/master /fix RAILS
```

Use `bin/master /fix MASTER` only when MASTER itself is the repair target. Keep OPENBSD for host/network/deployment debt and STUDIO for media/toolchain debt. A four-tree run is a deliberate long-running campaign, not the default first step. Use the repository's configured model lane and explicit budget/free-lane policy; do not silently cycle through unavailable providers.

## 5. Re-measure and retain evidence

After the repair, rerun the exact pre-repair command(s), for example:

```zsh
bin/operator check --scan-only --tree=RAILS
bin/operator check --scan-only --only=layout_suite --tree=RAILS
bin/operator check --scan-only --only=constitutional_scan --tree=RAILS
```

Record each command as PASS, FAIL, INCONCLUSIVE, BLOCKED, TIMEOUT, or DELIVERY_FAILED according to its actual result. Preserve the command output and commit identity. A source diff, authored regression, Vercel status, or copied-method harness is not a substitute for running the repository test or host check it claims to cover.

## Coverage map

| Concern | Instrument | Boundary |
|---|---|---|
| Four-tree boundary architecture | `architecture` check | Source-level boundary, not candidate tournament |
| Architecture alternatives/candidates | `/fix` on a named tree | Expensive, model-backed exploration |
| CSS, typography, scale and source layout | `layout_suite` | Browser/rendered proof requires browser preconditions |
| Law catalogue and executable scan | `constitutional_scan` plus `/fix` | Detector gaps stay explicit |
| Code and multi-file repair | `/fix` on the owning tree | Must be followed by checks |
| Host, DNS, PF and deployed response | OPENBSD checks + operator evidence | Repository source checks cannot prove host state |
| Audio/video and media pipelines | STUDIO checks + actual tools/assets | Source inspection alone cannot prove runtime output |

The goal is not to make every possible concern green in one command. It is to reduce the measured debt without paying for unrelated work, and to keep every unmeasured surface visible.
