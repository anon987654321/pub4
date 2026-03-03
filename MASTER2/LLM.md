# MASTER2 — LLM Context

Ruby constitutional AI agent on OpenBSD. 30,000 lines, no framework.
80 axioms. 12 adversarial personas. A portfolio of Rails 8 PWAs.

## Pipeline

```
intake → guard → route → execute → lint → render
```

Executor picks a strategy per task: ReAct / PreAct / ReWOO / Reflexion.
Every return is `Result.ok(value)` or `Result.err(reason)`. Never nil.

## Core files

| File | Purpose |
|------|---------|
| `data/axioms.yml` | 80 axioms — the constitution |
| `data/models.yml` | Model registry, tier order, fallback chain |
| `data/system_prompt.yml` | Identity, behavior, safety |
| `lib/master.rb` | Entry point |
| `lib/pipeline.rb` | Staged orchestration |
| `lib/executor.rb` | Strategy pattern + session continuity |
| `lib/result.rb` | Ok/Err monad |
| `lib/llm.rb` | Replicate primary, free OpenRouter fallback |
| `lib/circuit_breaker.rb` | Auto-disables failing providers |
| `lib/review/constitution.rb` | Axiom compliance |
| `lib/commands.rb` | REPL dispatch |

## Data files

28 YAML files in `data/`. No hardcoded fallbacks in `lib/`.

| File | Governs |
|------|---------|
| `axioms.yml` | 80 axioms, 11 categories |
| `constitution.yml` | Golden rule, protection levels |
| `council.yml` | 12 adversarial personas, 3 veto holders |
| `models.yml` | LLM tiers: premium → strong → fast → cheap → free |
| `language_rules.yml` | Ruby, Rails, zsh, HTML, CSS, JS rules |
| `platform.yml` | OpenBSD commands, forbidden patterns |

## Architecture

```
bin/master
├── lib/pipeline.rb         staged pipeline, Result monad
├── lib/executor.rb         ReAct/PreAct/ReWOO/Reflexion + session history
├── lib/llm.rb              Replicate(0) → free OpenRouter(1) → paid(2)
├── lib/circuit_breaker.rb  Stoplight, 3 failures trip, 300s cooldown
├── lib/commands.rb         REPL dispatch, SHORTCUTS, CommandRegistry
├── lib/council.rb          12-persona adversarial debate
├── lib/review/             Constitutional scanner + enforcer + fixer
├── lib/server/             Falcon: SSE, /chat, /tts, /metrics
├── lib/speech/             Piper + Edge + Replicate TTS
├── lib/session/            Conversation state, replay, memory
├── lib/nlu.rb              Signal detection
├── lib/ui/                 REPL, dashboard, autocomplete
└── data/*.yml              28 config files — single source of truth
```

## Request flow

```
pipeline.call(input)
  → guard → executor (pattern selection)
  → LLM.ask: Replicate first, free OpenRouter fallback
  → credit exhaustion: opens paid circuits, preserves free + Replicate
  → Result.ok(response) | Result.err(reason)
```

## Model priority (March 2026)

```
Replicate (has credits):
  gpt-5.2 · gpt-5 · claude-opus-4.6 · grok-4          [premium]
  claude-4-sonnet · gemini-3.1-pro · deepseek-r1        [strong]
  gemini-3-flash · gpt-4o-mini · kimi-k2.5              [fast]

Free OpenRouter (no credits needed):
  qwen3-coder · hermes-3-405b · qwen3-80b · gpt-oss-120b [fallback]
```

## Three critical axioms

1. **FAIL_VISIBLY** — errors logged and surfaced, never swallowed
2. **ONE_SOURCE** — every fact lives in exactly one place
3. **SELF_APPLY** — MASTER2's code must pass MASTER2's rules

## Golden rule

**PRESERVE_THEN_IMPROVE_NEVER_BREAK**

## Platform

OpenBSD 7.8 · Ruby 3.4 · zsh · pledge(2) · pf(4) · httpd(8) · relayd(8)
No bash, sed, awk, sudo, systemctl. Pure zsh builtins.

## Commands (REPL)

Free-form text → LLM directly. Commands:

```
scan, fix, refactor, evolve, chamber, model, models, pattern, patterns,
persona, personas, session, summary, forget, capture, schedule, heartbeat,
policy, health, doctor, bootstrap, status, history, context, speak, browse,
snapshot, codify, style-guides, axioms-stats, opportunities, help, exit
```

## Gotchas

- `Commands.dispatch` returns: `Result` (handled), `:exit`, `nil` (→ LLM fallthrough)
- `rescue nil` banned — rescue specific exceptions
- `free_model?` check prevents credit-exhaustion from killing zero-cost fallbacks
- Session history injected into `direct_ask` for inter-model continuity
- Require order: `refinement.rb` before `pressure_pass.rb`
- Tests need `skip_unless_llm` guard or they hang

## ENV vars

| Variable | Purpose |
|----------|---------|
| `REPLICATE_API_KEY` | Primary LLM + media generation |
| `OPENROUTER_API_KEY` | OpenRouter fallback + free models |
| `MASTER_TOKEN` | Web UI auth (`SecureRandom.hex(16)`) |
| `MASTER_TRACE` | Verbosity: 0=silent, 3=debug |
| `MASTER_PRESCAN` | REPL startup scan (default: true) |

## Communication style

dmesg-inspired. Terse, factual. No filler.

```
llm0: claude-4-sonnet 1234→567tok $0.02
executor0: modified lib/logging.rb
boot0: 45ms
```
