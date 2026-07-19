# Convergence tools

Convergence tooling restores the useful parts of pub3’s evidence gate for pub4 without importing unsafe permissions, old shell assumptions, or large monolithic code. The gate is intentionally smaller than the original archive but still gives pub4 a conservative, transparent quality bar before changes ship.

Run ruby MASTER/tools/convergence/evidence_gate.rb to evaluate the tree. Set PUB4_EVIDENCE_THRESHOLD (for example 0.95) when you need a stricter pass threshold. The score follows the pub3 shape: tests 35%, static safety 25%, complexity 15%, architecture 15%, and security 10%.

The gate catches missing test files, missing production gates, broad unsafe command patterns, long Ruby methods, very large files outside archive or vendor paths, tracked secret-looking files, and old archive assumptions that should not return. It is not a replacement for RuboCop, Brakeman, or bundler-audit, not an auto-fixer, and not a permission bypass system.
