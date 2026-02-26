# MASTER2 — LLM Context

MASTER2 is a 30,000-line Ruby constitutional AI agent running on OpenBSD.
It governs itself via 80 axioms and manages a portfolio of Rails 8 mobile-first PWAs.
Built from scratch — no framework, no scaffold — pure Ruby with pledge(2) sandboxing.

## What it does

Every user intent flows through a staged pipeline. Each stage earns the right to proceed:

```
intake → compress → guard → route → council → execute → lint → render
```

The executor picks a strategy (ReAct / PreAct / ReWOO / Reflexion) based on task complexity.
The constitutional engine checks output against 80 axioms. The Result monad wraps every
return — Ok or Err, never nil, never an unhandled exception.

## Core files (read order)

| File | Purpose |
|------|---------|
| `data/axioms.yml` | 80 axioms — the constitution |
| `data/system_prompt.yml` | Identity, behavior, safety rules |
| `lib/master.rb` | Entry point — wires all modules |
| `lib/boot.rb` | Environment detection, banner, smoke tests |
| `lib/pipeline.rb` | Stage-based orchestration engine |
| `lib/executor.rb` | Strategy pattern for LLM interaction |
| `lib/result.rb` | Ok/Err monad for every return value |
| `lib/llm.rb` | Replicate + OpenRouter with circuit breaker |
| `lib/review/constitution.rb` | Axiom compliance checker |
| `lib/commands.rb` | REPL command dispatch |

## Data files — single source of truth

28 YAML files in `data/`. No hardcoded fallbacks in `lib/`.

| File | Governs |
|------|---------|
| `axioms.yml` | 80 axioms across 11 categories |
| `constitution.yml` | Golden rule, protection levels, enforcement |
| `council.yml` | 12 adversarial personas, 3 veto holders |
| `models.yml` | LLM provider/model/tier mappings |
| `personas.yml` | 8 agent personality definitions |
| `system_prompt.yml` | Runtime identity and behavior |
| `phases.yml` | Cognitive load allocation per phase |
| `quality_thresholds.yml` | Smell thresholds and enforcement levels |
| `language_rules.yml` | Ruby, Rails, zsh, HTML, CSS, JS rules |
| `platform.yml` | OpenBSD commands, forbidden patterns |

## Architecture

```
bin/master (CLI + REPL)
│
├── lib/pipeline.rb         7 stages, Result monad (first error halts)
├── lib/executor.rb         ReAct / PreAct / ReWOO / Reflexion
├── lib/llm.rb              Replicate primary, OpenRouter fallback
├── lib/circuit_breaker.rb  Auto-disables failing providers
├── lib/commands.rb         REPL dispatch + SHORTCUTS + CommandRegistry
├── lib/council.rb          12-persona adversarial debate
├── lib/review/             Constitutional scanner + enforcer + fixer
├── lib/server/             Falcon web server: SSE, /chat, /tts, /metrics
├── lib/speech/             Piper + Edge + Replicate TTS backends
├── lib/session/            Conversation state, replay, memory
├── lib/nlu.rb              Signal detection: conversational, shell, code
├── lib/ui/                 REPL, dashboard, autocomplete, output
└── data/*.yml              28 config files — the single source of truth
```

## Request flow

```
Pipeline.call(input)
  → Stages: intake → compress → guard → route → council → ask → lint → render
  → Executor: selects pattern based on complexity
  → LLM.ask: tier fallback with circuit breaker
  → Result.ok(response) | Result.err(reason)
```

## Three critical axioms

1. **FAIL_VISIBLY** — every error logged and surfaced, never swallowed
2. **ONE_SOURCE** — every fact lives in exactly one place
3. **SELF_APPLY** — MASTER2's own code must pass its own rules

## Golden rule

**PRESERVE_THEN_IMPROVE_NEVER_BREAK** — never delete working code, never break existing behavior, improve surgically.

## Platform

OpenBSD 7.8 · Ruby 3.4 · zsh · pledge(2) · pf(4) · httpd(8) · relayd(8)
No bash, sed, awk, sudo, systemctl, apt, nginx. Pure zsh builtins for shell.

## Commands (REPL)

```
ask, scan, fix, refactor, autofix, evolve, chamber, hunt, critique, conflict,
model, models, pattern, patterns, persona, personas, session, summary, forget,
capture, schedule, heartbeat, policy, budget, health, doctor, bootstrap,
status, history, context, speak, browse, snapshot, codify, style-guides,
axioms-stats, opportunities, queue, harvest, workflow, help, clear, exit
```

Free-form text falls through to the LLM as conversation.

## Gotchas

- `Commands.dispatch` returns: `Result` (handled), `:exit`, or `nil` (→ LLM fallthrough)
- `rescue nil` is banned — always rescue specific exceptions
- Files over 300 lines should be split along module boundaries
- Require order matters: `refinement.rb` before `pressure_pass.rb`
- Budget system removed — OpenRouter handles credit limits
- Tests need `skip_unless_llm` guard or they hang

## ENV vars

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENROUTER_API_KEY` | *(required)* | LLM API key |
| `REPLICATE_API_KEY` | *(optional)* | Media + primary LLM |
| `MASTER_TOKEN` | `SecureRandom.hex(16)` | Web UI auth |
| `MASTER_TRACE` | `0` | Verbosity: 0=silent, 3=debug |
| `MASTER_PRESCAN` | `true` | REPL startup code scan |

## Communication style

dmesg-inspired. Terse, factual. No filler.

```
llm0 at tier1: claude-4.5-sonnet 1234→567tok $0.02 123ms
file0 at executor0: modified lib/logging.rb (fixed visibility)
boot: 45ms
```
