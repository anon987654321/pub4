# MASTER

Constitutional AI coding agent. Ruby. OpenBSD-first. ~6K LOC.

```
Intake → Infer → Route → Guard → Execute → Council → Lint → Strunk → Memo → Render
```

---

## What it does

MASTER is a self-governing terminal agent that writes, reviews, and repairs code
under a constitutional rule set enforced at runtime — not just advisory.

It runs a 10-stage pipeline on every message. Each stage returns a `Result` monad.
An `Err` at any stage short-circuits the rest. No exceptions escape.

---

## Architecture

```
lib/master/
  agent.rb           LLM interface — multi-model routing, Nemotron 3 thinking mode
  pipeline.rb        10-stage result chain
  stages/
    intake.rb        parse user message
    infer.rb         NLP → command (English + Norwegian)
    route.rb         dispatch to command handlers or agent
    guard.rb         injection detection, tool-tier enforcement
    execute.rb       run tool calls
    council.rb       6-persona deliberation on dangerous changes
    lint.rb          axiom coverage scan
    strunk.rb        strip hedges and preambles from LLM output
    memo.rb          extract and persist memory from responses
    render.rb        format final output
  tools/             read_file, write_file, str_replace, list_dir, search_files,
                     web_search, zsh, replace, ask_llm
  scan/              10 scan rules — EXPLICIT, IMMUTABLE, CQS, bare_rescue, etc.
  routing/           model router with fallback chains
  reasoning/         thinking mode wrappers (none / light / deep)
  council/           6 council personas loaded from data/council.yml
  security/          injection guard — 9 regex patterns
  swarm/             multi-worker parallel dispatch
  memory.rb          key-value store, persisted to .master/memory.yml
  personality.rb     switchable voice persona
  semantic_cache.rb  prompt deduplication with TTL
  circuit_breaker.rb rate + budget + fault gating on LLM calls
  auto_loop.rb       self-repair cycle (scan → fix → repeat)
  sweep.rb           full-codebase refactor pass

web/                 Rails 8 web UI — Falcon async server
exe/master           CLI entry point
```

---

## Web UI

Audio-reactive canvas. 2000 neurons. 49 orb states.

- Ambient pad engine: Madlib warmth × FlyLo cosmic textures × Dilla drift
- Drum sequencer: 88 BPM trip-hop, swing + micro-jitter humanization
- 12 TTS voice FX modes: dark / demon / radio / underwater / ghost / oracle /
  glitch / cathedral / broken / whisper / megaphone
- SSE streaming responses from the pipeline
- Speech recognition with wake word
- Swipe left/right to change orb geometry
- Tab to reveal chat log, double-tap canvas on mobile

Runs at `http://ai.brgen.no:3000`.

---

## Pipeline stages

| Stage | What it does |
|---|---|
| Intake | Normalize input, strip injection attempts |
| Infer | NLP intent classification — maps natural language to slash commands |
| Route | Dispatch to built-in command or agent |
| Guard | Injection guard + tool-tier approval |
| Execute | Tool calls via Governor (safe / guarded / dangerous tiers) |
| Council | 6-persona review on dangerous or multi-file changes |
| Lint | Axiom coverage scan (quick / standard / hunt / deep) |
| Strunk | Strip preambles, hedges, filler from LLM output |
| Memo | Extract remember/decision/preference patterns, persist to memory |
| Render | Format and emit final response |

---

## Commands

```
/scan [path]     run axiom scan
/fix             propose repairs for scan violations
/sweep [path]    full-codebase refactor loop
/autoloop [n]    self-repair cycle, n iterations (default 8)
/council on|off  toggle council deliberation
/explain         show pipeline stages and axiom coverage
/memory          list / recall / remember / forget
/mode none|light|deep   reasoning depth
/task [type]     set task type for model routing
/swarm <role> <task>    dispatch to worker
/persona [name]  switch voice persona
/undo            revert last file change
/dmesg           show ring buffer log
/cost            show session cost
/tokens          estimate context size
```

---

## Models

Default priority order:

1. `nvidia/nemotron-3-nano-30b-a3b:free` — OpenRouter free tier
2. `claude-opus-4-6` — Anthropic (if `ANTHROPIC_API_KEY` set)
3. `gpt-4o` — OpenAI (if `OPENAI_API_KEY` set)

Nemotron 3 thinking mode: `reasoning_content` extracted and appended as
`<think>` block at `:deep` reasoning depth.

---

## Constitution

Kernel rules (`[K]`) are enforced by code at runtime:

- **PRESERVE_FIRST** — undo snapshot before every write
- **SIMPLEST_WORKS** — Council Skeptic + god_class scan
- **FAIL_VISIBLY** — bare_rescue scan, Result monad everywhere
- **ONE_SOURCE** — duplicate_code scan
- **GUARD_EXPENSIVE** — CircuitBreaker before every LLM call
- **DEGRADE_GRACEFULLY** — tool timeout wrappers
- **BE_CONCISE** — Strunk stage on every response

Philosophy rules (`[P]`) are advisory and do not block. See `master.md`.

---

## Setup

```sh
gem install bundler
bundle install

# Set at least one API key:
export ANTHROPIC_API_KEY=...
export OPENROUTER_API_KEY=...
export OPENAI_API_KEY=...

# CLI
bundle exec ruby exe/master

# Web (production)
cd web
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 \
  bundle exec falcon serve --bind http://127.0.0.1:10002
```

OpenBSD rc.d service: `rcctl start master`

---

## Deployment (OpenBSD)

- Reverse proxy: relayd on port 3000 → Falcon on 127.0.0.1:10002
- TLS: terminated at relayd layer (`config.force_ssl = false`)
- DNS: `ai.brgen.no` → 185.52.176.18, DNSSEC signed
- Process supervisor: `rcctl` via `/etc/rc.d/master`

---

## License

MIT
