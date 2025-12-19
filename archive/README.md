# Archive Directory

This directory contains historical versions and deprecated files that are preserved for reference but are no longer actively used.

## Master.yml Variants

- `master.yml.v71.7.0` - Historical version 71.7.0
- `master.yml.v71.8.0.backup` - Historical version 71.8.0 backup
- `master.yml.v73.0.0.backup` - Historical version 73.0.0 backup
- `master.yml.v74.1.0` - Historical version 74.1.0 (before tool policy modernization)
- `master.yml.broken` - Broken configuration kept for reference
- `master.yml.claude72` - Claude-specific version 72.1.0
- `master.yml.gist` - Gist export of configuration
- `master.yml.solutions` - Alternative solutions analysis that informed current design

The canonical master.yml is now v74.3.0+ in the repository root with distilled rationale from solutions incorporated as a non-normative appendix.

## CLI Files

- `cli.rb.backup` - Minimal backup from 2025-12-15
- `cli_new.rb` - Alternative CLI implementation with circuit breaker and backoff patterns

Valuable patterns from cli_new.rb (circuit breaker, exponential backoff) are documented here for future reference but not currently integrated into the main cli.rb.

## Purpose

These files are archived to:
1. Preserve historical context and evolution of the configuration
2. Enable recovery if needed via git history
3. Reduce root directory sprawl while maintaining references
4. Document alternative approaches considered
