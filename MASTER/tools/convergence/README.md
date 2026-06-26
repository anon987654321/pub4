# Convergence tools

Restored from the useful parts of `pub3`.

This is intentionally smaller than the original archive. It gives pub4 an
evidence gate without importing unsafe permissions, old shell assumptions, or
large monolithic code.

## Run

```sh
ruby MASTER/tools/convergence/evidence_gate.rb
```

Optional:

```sh
PUB4_EVIDENCE_THRESHOLD=0.95 ruby MASTER/tools/convergence/evidence_gate.rb
```

## Score model

The gate follows the pub3 score shape:

- tests: 35%
- static safety: 25%
- complexity: 15%
- architecture: 15%
- security: 10%

The score is deliberately conservative and transparent.

## What it catches

- missing test files
- missing production gates
- broad unsafe command patterns
- long Ruby methods
- very large files outside archive/vendor paths
- tracked secret-looking files
- old archive assumptions that should not return

## What it is not

- not a replacement for RuboCop
- not a replacement for Brakeman
- not a replacement for bundler-audit
- not an auto-fixer
- not a permission bypass system