# Free compute in MASTER — the design of record

Written 2026-10-27 from the operator's ask ("are there any clever ways we can
add free models / get free compute in MASTER? anything exciting on GitHub,
ar5iv.org, etc.") and a same-day research pass over the providers' own docs.
Every number carries its date; every lane carries its gate. This file is the
record, not a promise: no lane here was callable at write time (no network, no
Ruby runtime in the writing session), and the gates say exactly what turns
each one from prose into wiring.

## What already runs free

The tree already rides free compute three ways, and none of them are new:

- **OpenRouter free slugs.** `data/models.yml` pins
  `nvidia/nemotron-3-super-120b-a12b:free` as the free anchor and
  `openrouter.use_live_catalog: true` merges every live `:free` slug from the
  SQLite provider catalog (pool.rb refreshes it when a day old). Key rotation
  (`OPENROUTER_API_KEY` ×3, LRU) spreads per-key limits.
- **Keyless web-chat.** The ferrum lane (`web-chat:` prefix) drives chat
  sites through headless Chrome with no API key at all — ToS-sensitive and
  correctly gated behind `MASTER_WEB_CHAT` / keyless auto-activation, never
  a default when paid keys exist.
- **Local models.** `ollama:` ids route to the operator's own hardware —
  zero marginal cost, zero logging, the only lane whose quota is the RAM.

## The one executable correction (landed with this file)

`openrouter.daily_quota_per_model` was 200 against a "~200/day/key" comment.
OpenRouter's own terms as of 2026-10-27: **free models default to 50
requests/day per model**, and a one-time $10 credit raises the allowance to
**1,000/day**. The router used the stale number to decide when to skip a
slug, so it hammered four times past the real limit and read the resulting
429s as provider flapping. Corrected to 50 in the same commit as this file.
Also recorded there: **GitHub Models was fully retired 2026-07-30**
(playground, catalog, inference API and BYOK all withdrawn; GitHub points
new work at Azure AI Foundry) — the guard comment exists so no future pass
adds a dead provider to a fallback chain, the exact failure mode
`tools/model_catalog_check.rb` was written to catch.

## The 2026 free-tier landscape (dated numbers)

Provider terms move; the dates make drift visible.

| Lane | Free allowance (as of) | Notes |
| --- | --- | --- |
| OpenRouter free models | 50 RPD per model; $10 one-time credit → 1,000 RPD (2026-10) | `openrouter/free` router + model fallback chains; free providers may log prompts |
| Groq free tier | llama-3.1-8b-instant 30 RPM / 14,400 RPD / 500K TPD; llama-3.3-70b 1,000 RPD; gpt-oss-120b/20b 1,000 RPD (2026-03 docs snapshot) | 72× the OpenRouter per-key allowance; OpenAI-compatible endpoint; cached tokens don't count against limits |
| Groq Whisper STT | whisper-large-v3 / -turbo: 20 RPM / 2,000 RPD / 7,200 audio-seconds per hour (2026-03) | The genuinely clever one for MASTER: a free server-side STT lane beside the client-side whisper_mel.js path |
| OVHcloud AI Endpoints | keyless anonymous 2 RPM per IP per model; 400 RPM with a key (2026-10) | No signup at all; EU-hosted; a genuine emergency last resort, not a workhorse |
| Kilo Code free pool | 200 req/hour per IP, no key (2026-10) | Router may log prompts; trial-grade |
| LLM7.io free token | 1 RPS / 60 RPM / 250 req/h / 100K tokens per 24h (2026-10) | Catalog rotates frequently |
| Ollama Cloud | session limits reset every 5h, weekly limits (2026-10) | OpenAI-compatible at ollama.com/v1 |
| Alibaba API-Inference | 2,000 RPD free (2026-10) | Requires real-name verification |
| Gemini API free tier | slashed 2025-12 — headline models cut to ~20 RPD (2026-10) | Spend-based caps on top; fine for a trickle, not a lane |
| GitHub Models | **retired 2026-07-30** | Not a lane. Guard comment lives in models.yml |

Sources: OpenRouter and Groq official docs; docs.github.com retirement
notice; provider changelogs as listed in the pass-3 ideation record
(`data/ideations/master_web_dilla_free.yml`).

## The clever lanes, ranked

1. **Groq as the volume lane** (design only; gate: a key + wiring on a Ruby
   host). An OpenAI-compatible base URL is the whole trick — RubyLLM 2 owns
   the registry, and MASTER already supplies only the OpenRouter
   unknown-model fallback (`lib/io/ruby_llm_patch.rb`). A `groq:` section
   mirroring the openrouter one (keys_env, its own daily quota rows) plus the
   8B workhorse at 14,400 RPD would out-carry every OpenRouter free key
   combined. Its free Whisper is the second prize: MASTER does STT
   client-side (whisper_mel.js, smart_turn) — a Groq lane would give the
   server a free transcription fallback for degraded clients.
2. **OVH as the last resort** (gate: none — it is keyless). 2 RPM is
   nothing per minute and everything in an outage: a lane that answers when
   every keyed lane has burned its day. Rate-limit awareness belongs in the
   router before this is safe to leave on.
3. **OpenRouter free with the corrected quota** (landed). With 50/day as
   the truth, the router skips honestly; the $10 unlock note is the operator
   lever when 50 is too few.
4. **arXiv/ar5iv as the knowledge lane** (pattern, not code). ar5iv serves
   full-text HTML of arXiv papers — the citation habit `lib/core/model.rb`
   already exercises (arXiv 2408.02442 in the schema comment) generalises:
   research claims in comments and docs should name the arXiv id, and ar5iv
   is the free full-text endpoint an operator can read or fetch by hand.
   Deliberately NOT built: a scheduled harvester crawling papers into a
   corpus would be unbounded fetches on a 1-vCPU, 1 GB box — the resource
   crisis CLAUDE.md documents, re-run on purpose. The knowledge ask is
   served by recording where the full text lives, not by feeding a crawler
   nobody asked to maintain.

## Gates

- **Groq wiring**: first Ruby host with network + a `GROQ_API_KEY`; add the
  `groq:` section, its quota rows, and extend `tools/model_catalog_check.rb`
  reach (its OpenRouter-only `live_ids` needs a second source or a
  Groq-specific check before groq ids in chains are verifiable).
- **OVH lane**: same host, plus rate-limit awareness in the router (2 RPM is
  below the router's retry cadence today).
- **Quota truth**: re-check provider terms on each pass; the dates in the
  table above are the comparison points.
- **GitHub Models**: none. It is retired. The comment in models.yml is the
  guard.
