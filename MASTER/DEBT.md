# Debt Register

This file separates known debt from ordinary TODO work.

## Tag Legend

- **agent-ignore** — do not chase during narrow patches (constitution scan noise, horizon features).
- **operator-priority** — humans should fix before declaring deploy healthy.

## Current Tracks

### Self-Test Debt

**agent-ignore** — triage only when the task explicitly targets scan rules.

`rake selftest` currently fails on known ROBUSTNESS, LINEARITY, ABSTRACTION, and DENSITY findings. `SINGULARITY` is clean. Triage each finding as:

- true violation to fix
- scanner false positive
- rule exemption needed
- rule threshold too strict
- known debt to leave alone during unrelated work

### Constitution Scan Debt

**agent-ignore** — `rake constitution` is broader than `rake selftest` and still reports thousands of self-scan findings. Do not chase zero. Track the count down by removing false positives and fixing high-signal violations.

### Web Face Verification

The WebGL primer guard has source/test coverage, but the recurring "tap to start does nothing" class still needs manual real-browser verification when boot assets change.

### Host TTS Binaries

**operator-priority** — TTS end-to-end audio depends on host binaries such as `edge-tts` and `espeak`. Web wiring can be correct while synthesis is unavailable locally. Check `GET /health` deploy.tts_socket and `test -S .master/tts.sock` on vm23.

## Not Debt

- Two `Master::` spines.
- Split rule registries.
- Local `knowledge/` corpus.
- Generated `output/` artifacts.
- Deferred WebGL boot.
