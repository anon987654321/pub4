# Debt Register

This file separates known debt from ordinary TODO work.

## Current Tracks

### Self-Test Debt

`rake selftest` currently fails on known ROBUSTNESS, LINEARITY, ABSTRACTION, and DENSITY findings. `SINGULARITY` is clean. Triage each finding as:

- true violation to fix
- scanner false positive
- rule exemption needed
- rule threshold too strict
- known debt to leave alone during unrelated work

### Constitution Scan Debt

`rake constitution` is broader than `rake selftest` and still reports thousands of self-scan findings. Do not chase zero. Track the count down by removing false positives and fixing high-signal violations.

### Web Face Verification

The WebGL primer guard has source/test coverage, but the recurring "tap to start does nothing" class still needs manual real-browser verification when boot assets change.

### Host TTS Binaries

TTS end-to-end audio depends on host binaries such as `edge-tts` and `espeak`. Web wiring can be correct while synthesis is unavailable locally.

## Not Debt

- Two `Master::` spines.
- Split rule registries.
- Local `knowledge/` corpus.
- Generated `output/` artifacts.
- Deferred WebGL boot.
