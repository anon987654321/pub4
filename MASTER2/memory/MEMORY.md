# MEMORY.md — Durable Brain (OpenCrabs pattern)
# Curated by MASTER2. Loaded every turn. Edit to shape cross-session behavior.
# Append-only during sessions. Compacted nightly by session_compaction job.
# Keep under 200 lines. Most recent last.

## Architecture Decisions
2026-02-07: Falcon chosen over Puma — async/fiber matches OpenBSD pledge(2) better.
2026-02-07: ruby_llm gem handles streaming/retry/model-switching. OpenRouter = 400+ models.
2026-03-05: Lane Queue added — serial execution default prevents session state races.

## Known Gotchas
- OpenBSD pledge(2): re-arm after fork. bin/master does not fork.
- LibreSSL on OpenBSD: never `gem "openssl"` — conflicts with system LibreSSL.
- Gemfile.lock gitignored — OpenBSD and Linux gem paths differ.
- doas requires /etc/doas.conf entry. sudo not installed on OpenBSD.
- Falcon web server: no blocking IO in handlers (fiber context).
- lsof not available on OpenBSD — use fstat(1) for port inspection.

## User Preferences
- dmesg-style output for all multi-step operations.
- Proactive heartbeat check-ins (OpenClaw-style).
- Voice-first workflow: TTS all responses, STT all input.
- Hates filler, hedging, bullet lists.
- Platform: OpenBSD primary, Android Termux development.
