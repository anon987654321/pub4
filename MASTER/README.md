# MASTER

Constitutional AI coding agent. Ruby. OpenBSD-first. ~6K LOC.

```
Intake → Infer → Route → Guard → Execute → Council → Lint → Prune → Memo → Render
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
  agent.rb           LLM interface — multi-model routing, ReAct agentic loop
  pipeline.rb        10-stage result chain
  stages/
    intake.rb        normalize input, strip injection attempts
    infer.rb         NLP → command (English + Norwegian)
    route.rb         dispatch to command handlers or agent
    guard.rb         injection detection, tool-tier enforcement
    execute.rb       run tool calls via Governor
    council.rb       6-persona deliberation on dangerous changes
    lint.rb          axiom coverage scan
    prune.rb         strip hedges and preambles from LLM output
    memo.rb          extract and persist memory from responses
    render.rb        format final output
  tools/             read_file, write_file, str_replace, ast_edit, batch_replace,
                     list_dir, search_files, search_knowledge, web_search,
                     shell, git_context, symbol_lookup, tree, apply_diff, ask_llm, clean
  scan/              10 scan rules — EXPLICIT, IMMUTABLE, CQS, SELF_EXPLAINING,
                     STRUNK_WHITE, long_method, bare_rescue, god_class, pola, srp
  routing/           model router with fallback chains
  scan/rules/        rubocop_rule, reek_rule, conceptual_rule, axiom_coverage_rule
  council/           6 council personas loaded from data/council.yml
  security/          injection guard — 9 regex patterns, permissions
  swarm/             multi-worker parallel dispatch (analyst/coder/researcher/reviewer)
  memory.rb          key-value store, persisted to .master/memory.yml
  personality.rb     switchable voice persona, injects axioms into system prompt
  axioms.rb          loads data/axioms.yml — kernel rules + top-25 philosophy
  semantic_cache.rb  prompt deduplication with SHA256 LRU + TTL
  circuit_breaker.rb rate + budget + fault gating on LLM calls
  autoloop.rb        self-repair cycle (scan → fix → commit → repeat)
  sweep.rb           full-codebase refactor pass to convergence
  code_index.rb      live structural model — Prism AST, symbol graph
  diff_stager.rb     staged diff context for agent prompts
  cognitive_monitor.rb  working-memory token budget tracker

data/
  axioms.yml         kernel axioms (enforced) + top-25 philosophy (advisory)
  constitution.yml   golden rule, protection levels, anti-simulation
  council.yml        6 council personas with voting weights
  strunk.yml         preamble/hedge/ending patterns for Prune stage
  principles.yml     KISS, DRY, YAGNI, SRP with anti-patterns
  quality_thresholds.yml  method/class/file size limits
  exemplars.yml      council PRAISE vote registry
  fallback_models.yml     model fallback chains per task type
  features.yml       toggleable feature flags
  language_rules.yml + language_axioms.yml + zsh_patterns.yml

knowledge/
  style_guides/      ruby.adoc (141KB), rails.adoc (53KB)
  axioms/, constitution/, language_axioms/  — searchable YAML knowledge
  ruby_llm/          34 source files from ruby_llm gem
  system_prompts/    130+ CL4R1T4S system prompts

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
| Prune | Strip preambles, hedges, filler from LLM output |
| Memo | Extract remember/decision/preference patterns, persist to memory |
| Render | Format and emit final response |

---

## Commands

```
/scan [path]          run axiom scan
/fix                  propose repairs for scan violations
/sweep [path]         full-codebase refactor loop to convergence
/autoloop [n]         self-repair cycle, n iterations (default 8)
/council on|off       toggle council deliberation
/explain              show pipeline stages and axiom coverage
/memory               list / recall / remember / forget / search
/mode none|light|deep reasoning depth
/task [type]          set task type for model routing
/swarm <role> <task>  dispatch to worker
/persona [name]       switch voice persona
/cache clear|stats    manage semantic cache
/diff [path]          show staged diff with context
/model list           show available models and current
/commit [msg]         LLM-generated or manual git commit
/why <rule>           explain an axiom or scan rule
/knowledge add <url>  fetch and index a URL into knowledge base
/undo                 revert last file change
/dmesg                show ring buffer log
/cost                 show session cost
/tokens               estimate context size
```

---

## Models

Default: `meta-llama/llama-3.3-70b-instruct:free` (OpenRouter free tier, ~8 req/min).

Routing via `data/fallback_models.yml` per task type (code / review / chat / sweep).
Escalates to stronger model automatically on circuit-breaker or low-confidence signals.

---

## Constitution

Kernel rules (`[K]`) are enforced by code at runtime:

- **PRESERVE_FIRST** — undo snapshot before every write
- **SIMPLEST_WORKS** — Council Skeptic + god_class scan
- **FAIL_VISIBLY** — bare_rescue scan, Result monad everywhere
- **ONE_SOURCE** — duplicate_code scan
- **GUARD_EXPENSIVE** — CircuitBreaker before every LLM call
- **DEGRADE_GRACEFULLY** — tool timeout wrappers
- **BE_CONCISE** — Prune stage on every response

Philosophy rules (`[P]`) are advisory and do not block. See `data/axioms.yml`.

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

OpenBSD rc.d service: `rcctl start masterweb`

---

## Deployment (OpenBSD)

- Reverse proxy: relayd on port 3000 → Falcon on 127.0.0.1:10002
- TLS: terminated at relayd layer (`config.force_ssl = false`)
- DNS: `ai.brgen.no` → 185.52.176.18, DNSSEC signed
- Process supervisor: `rcctl` via `/etc/rc.d/masterweb`

---

## License

MIT
