# MASTER2

LLM pipeline with adversarial council, axiom enforcement, and safe autonomy. Ruby. OpenBSD-first.

## Installation

```sh
bundle install
export OPENROUTER_API_KEY="your-key"
./bin/master
```

## Quick Start

```bash
# Interactive REPL
./bin/master

# Direct commands
./bin/master refactor lib/session.rb
./bin/master fix --all
./bin/master scan deploy/
./bin/master health
```

## Architecture

### Core Modules

| File | Responsibility |
|------|---------------|
| `result.rb` | Result monad (do not duplicate) |
| `logging.rb` | Unified logging system |
| `db_jsonl.rb` | JSONL storage |
| `llm.rb` | All LLM/OpenRouter logic including context window management |
| `session.rb` | Session persistence with crash recovery |
| `pledge.rb` | OpenBSD pledge() integration |

### Safe Autonomy

| File | Responsibility |
|------|---------------|
| `staging.rb` | Self-modification staging area |
| `enforcement.rb` | Axiom enforcement (single entry point) |

### UI/UX

| File | Responsibility |
|------|---------------|
| `ui.rb` | TTY toolkit integration |
| `help.rb` | Command help system |
| `undo.rb` | Undo/redo stack |
| `commands.rb` | Command routing |
| `confirmations.rb` | User confirmation gates |
| `error_suggestions.rb` | Error recovery hints |

### Analysis

| File | Responsibility |
|------|---------------|
| `pipeline.rb` | Pipeline processing (with stages.rb) |
| `stages.rb` | Seven-stage pipeline |
| `code_review.rb` | All static analysis (smells, violations, bug hunting) |
| `introspection.rb` | All self-analysis (critique, reflection) |

### Execution

| File | Responsibility |
|------|---------------|
| `executor.rb` | Tool dispatch, permission gates, safety guards |
| `executor/react.rb` | ReAct pattern |
| `executor/pre_act.rb` | Pre-Act pattern |
| `executor/rewoo.rb` | ReWOO pattern |
| `executor/reflexion.rb` | Reflexion pattern |
| `executor/tools.rb` | Tool definitions |

### Shell & Speech

| File | Responsibility |
|------|---------------|
| `shell.rb` | Shell integration |
| `questions.rb` | Interactive Q&A |
| `speech.rb` | Text-to-speech (Piper/Edge/Replicate) |

### Web UI

| File | Responsibility |
|------|---------------|
| `server.rb` | Falcon web server |
| `views/cli.html` | Web interface |

### Agents & Media

| File | Responsibility |
|------|---------------|
| `agent.rb` | Agent orchestration |
| `postpro_bridge.rb` | Post-processing bridge |
| `repligen_bridge.rb` | Replicate integration |

## Execution Patterns

Four patterns, auto-selected by task type:

| Pattern | Use Case | Behavior |
|---------|----------|----------|
| **ReAct** | Exploration | Tight thought→action→observation loop |
| **Pre-Act** | Multi-step workflows | Plan first, then execute |
| **ReWOO** | Cost-sensitive reasoning | Single LLM call with placeholders |
| **Reflexion** | Fix/debug/refactor | Execute → critique → retry |

## Pipeline Stages

Seven stages, chained via Result monad:

1. **Intake** — Parse input
2. **Guard** — Block dangerous patterns
3. **Route** — Select model by budget/tier
4. **Debate** — Council deliberation (optional)
5. **Ask** — Query LLM
6. **Lint** — Axiom enforcement
7. **Render** — Typography refinement

First error short-circuits. No exceptions.

## REPL Commands

```
help          Show all commands
refactor      Multi-model file review with 6-phase analysis
hunt          8-phase bug analysis
critique      Constitutional validation
learn         Show matching learned patterns
conflict      Detect principle conflicts
chamber       Council deliberation
ideate        Creative brainstorming
evolve        Self-improvement cycle
fix           Auto-fix code violations
browse        Web browsing (Ferrum)
speak         Text-to-speech
model         Switch LLM model
models        List available models
pattern       Switch execution pattern
patterns      List execution patterns
opportunities Analyze codebase for improvements
selftest      Run MASTER through itself
axioms-stats  Show language axioms statistics
session       Session management
budget        Show remaining budget
health        System health check
```

## Dependencies

### Core Stack

- **ruby_llm** (1.11+) — OpenRouter client
- **Falcon** (0.47+) — Async web server
- **TTY toolkit** — Terminal UI (reader, spinner, table, prompt, etc.)
- **Stoplight** (4.0+) — Circuit breaker
- **Pastel** — Terminal colors
- **Rouge** — Syntax highlighting
- **Nokogiri** (1.19+) — HTML/XML parsing

### OpenBSD-First Design

MASTER2 embraces OpenBSD's security model:

- **doas** — Privilege escalation (replaces sudo)
- **pledge()** — System call restrictions via `pledge.rb`
- **rcctl** — Service management
- **unveil()** — Filesystem access control (planned)

Portable to macOS, Linux, and other Unix systems.

## Budget & Rate Limiting

- **$10.00** session cap
- **30 requests/minute** rate limit
- **Circuit breaker**: 3 failures → 5-minute cooldown
- **Auto-retry**: Exponential backoff (1s, 2s, 4s)

### Model Tiers

| Tier | Models | Use Case |
|------|--------|----------|
| **premium** | Claude-3.5-Sonnet, GPT-4o | High-quality reasoning |
| **strong** | Claude-3-Haiku, GPT-4o-mini | Balanced quality/cost |
| **fast** | Qwen/QwQ-32B, DeepSeek-R1 | Quick iteration |
| **cheap** | Llama-3.1-8B, DeepSeek-Coder | Bulk operations |

## Axioms

Timeless rules enforced at six layers:

| Layer | Scope | Examples |
|-------|-------|----------|
| **Literal** | Line | Variable naming, formatting |
| **Lexical** | Unit | Method complexity, size |
| **Conceptual** | File | SRP, DRY, KISS |
| **Semantic** | Framework | API consistency |
| **Cognitive** | System | Mental model clarity |
| **Language Axiom** | Universal | Strunk & White, SOLID |

**ABSOLUTE** axioms halt on violation. **PROTECTED** axioms warn.

### Sources

- The Pragmatic Programmer (DRY, KISS, POLA)
- SOLID Principles (SRP, OCP)
- Clean Code (naming, functions)
- Strunk & White (omit needless words)
- Bringhurst (typography hierarchy)
- Nielsen (usability heuristics)

## Council

Twelve personas. Three hold veto:

- **Security Officer** — Guards CIA triad
- **The Attacker** — Finds exploits
- **The Maintainer** — 3 AM debuggability

Consensus requires 70% weighted agreement.

## Self-Test

> A system that asserts quality must achieve its own standards.

```bash
./bin/master
master> selftest
```

Runs:
- Static analysis
- Axiom validation
- Pipeline safety
- Council review (LLM)

If MASTER fails its own review, it has failed.

## License

MIT
