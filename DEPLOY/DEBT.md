# Debt Register

## Current Tracks

### MASTER Web Asset Discipline

Ad-hoc deploys can skip asset precompile and Falcon restart. This causes stale UI and dead-tap regressions. Prefer full deploy paths or explicitly run the precompile/restart sequence.

### TTS Host Binary

MASTER speech needs `edge-tts` or `espeak` on vm23. Web routes can be correct while audio remains silent.

### macOS Ruby Mismatch

Some Rails release/frontend gates assume OpenBSD `ruby34`/`bundle34` behavior and can be noisy under macOS Ruby. Wrappers should skip clearly or choose the right Ruby.

### Frontend Auditor Findings

`DEPLOY/rails/frontend_auditor_gate.rb` reports open accessibility/cosmetic findings until the shared frontend rule set is satisfied.

### Solid Queue Worker Proof

Scheduled jobs need VPS proof that the queue worker runs under Falcon and survives deploy/restart.

## Not Debt

- OpenBSD-specific scripts.
- tmux for long deploys.
- Serial CI on vm23.
- relayd TLS termination.
- Loopback-only app ports.
