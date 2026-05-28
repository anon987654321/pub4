# pub4 backlog

## Critical

- Verify face renders at https://ai.brgen.no/ — open fresh private window, tap primer, confirm WebGL face + ecology particles appear (all sw.js/Cache-Control fixes deployed but unconfirmed e2e)
- /triad 3rd step is a buggy on/off toggle, not deliberation — fix council turn to emit actual multi-persona verdict

## MASTER web

- face.js cleanup: strip `"use strict"`, column-aligned TINT padding, magic numbers (0.055, 0.025, 4.6), unused `const dt`, redundant `scene.add(vertPoints)` (VPS auto-commit cruft)
- app/assets/{app.js,chat.js,application.css,canvas.css} unreferenced by any view — audit and delete or wire up
- cognition_ecology.js z-index fix deployed — verify particles visible over face in browser

## Infrastructure

- VPS pf.conf pushed (hardened) — confirm bruteforce table + synproxy active: `doas pfctl -s rules`
- smtpd.conf: VPS running stock OpenBSD version, DEPLOY same — review if mail relay needed
- TTS broken: `bin/tts-worker` may be missing or edge-tts not installed — `which edge-tts` on VPS; fix or document

## Architecture

- MASTER 7-module refactor (approved 2026-05-08): now/loop/judge/voice/ground/reach/trace — pass-by-pass on VPS
- Defrag/dedup/rename plan (2026-05): priority-1 = Master::Orient + slim AGENTS/CLAUDE + .zshrc fix
- 18 priority gaps tracked in master.yml + master.json — run `/scan deep lib/` to surface current state
- Verify prompt caching active on non-Claude models (OpenRouter/auto) — `llm_dispatcher.rb:271` only gates on `claude_model?`
