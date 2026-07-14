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

Recent: small improvements to fallback diagnostics and boot comments (see web/app/views/chat/index.html.erb).

### Host TTS Binaries

**operator-priority** — TTS end-to-end audio depends on host binaries such as `edge-tts` and `espeak`. Web wiring can be correct while synthesis is unavailable locally. Check `GET /health` deploy.tts_socket and `test -S .master/tts.sock` on vm23.

### Media-Generation Capability Reintroduced After Severance

**operator-priority** — `b381f0015` (2026-07-08) severed media-generation capability (video, LoRA, comfyui, repligen, ~9.3k lines) per `core/ABSORPTION.md`'s "accretion and dies" call. `842d563fa`, 17 hours later, added `lib/reach/lora_pipeline.rb` and `lib/reach/video_chain.rb` back, wired through `command_registry/reach_commands.rb` and `ground/tool_contract.rb`. An autonomous training loop (Ragnhild LoRA — see recurring "Sync/Training sync: Ragnhild lora deliverables" commits) has been actively developing on top of the reintroduced pipeline since, through at least 2026-07-14.

This is a direct reversal of a recorded decision, not drift — `core/ABSORPTION.md` line 130 still lists the severance as done. Triage as one of:

- the severance decision is stale and should be updated to reflect that media generation is back in scope (rewrite `core/ABSORPTION.md`'s progress note)
- the reintroduction is itself the debt, and `lora_pipeline.rb`/`video_chain.rb` should be re-severed once the Ragnhild training loop's current work is safe to interrupt
- media generation should be expressed as `core/world.rb` handlers per the original absorption plan, not live in `lib/reach/` at all

Not chasing this during unrelated `lib/`/`core/` work — flagging so it doesn't get treated as settled.

## Not Debt

- Two `Master::` spines.
- Split rule registries.
- Local `knowledge/` corpus.
- Generated `output/` artifacts.
- Deferred WebGL boot.
