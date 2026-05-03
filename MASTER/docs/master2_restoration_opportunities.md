# MASTER2 Restoration — Status

Date: 2026-04-30

## What exists in MASTER2 (not yet in MASTER)

- `lib/workflow/convergence.rb` — plateau/oscillation detection for sweep loops. High value.
- `lib/violation_hooks.rb` — JSONL persistent violation log. Useful for trend analysis.
- `lib/analysis/openbsd_config_validator.rb` — OpenBSD config validation (partially restored to `data/openbsd.yml`).
- `lib/code_review/` and `lib/review/` — legacy review engines. Architecture diverges from current MASTER; requires staged porting.

## Completed restorations

- `data/openbsd.yml` — pf/nsd/httpd/smtpd/relayd/acme-client/doas/sshd/ntpd/unbound validators.
- `data/workflow.yml` — `principle_groups` and `scan_profiles` (enables `/scan quick`, `/scan critical`).
- `data/workflow.yml` — `conflicts` strategy (DRY vs WET resolution).

## Recommended next batches

1. Port `Workflow::Convergence` into `lib/master/sweep.rb` — adds oscillation/plateau early-stop.
2. Port `ViolationHooks` — write `.constitutional_violations.jsonl` on each scan hit.
3. Review `lib/code_review/` against current scan rules before porting.
