# MASTER2 — Self-Governing AI Development Partner

MASTER2 is a Ruby gem that turns any LLM into a self-governing development
partner. It enforces 68 axioms (from SOLID, Unix, Nielsen, Strunk & White)
through a constitutional review pipeline, so generated code is correct,
minimal, and auditable by design. It targets OpenBSD and Rails 8 projects.

**Problem it solves**: LLMs generate plausible but sloppy code — wrong idioms,
silent failures, god objects, truncated output. MASTER2 catches these at
generation time through axiom-driven review, before code reaches production.

## How It Works (30-second summary)

1. User gives a task → `Session` creates context
2. `Pipeline` runs stages: parse → plan → execute → review → deliver
3. `Executor` picks a strategy (ReAct / PreAct / ReWOO / Reflexion)
4. `LLM` calls an AI provider (OpenAI / Anthropic / Ollama) within budget
5. `Review::Constitution` checks output against 68 axioms
6. `QualityGates` enforces smell thresholds before commit
7. `Result` monad wraps every return (Ok/Err) — no silent failures

## System Architecture at a Glance

MASTER2 is a self-enforcing constitutional AI system that validates and improves code against 68 axioms. The data flow is:

```
User Input → Pipeline → Executor → LLM → Output
             ↓          ↓         ↓
          Stages     Patterns  CircuitBreaker
             ↓          ↓         ↓
          Guard      Tools    RateLimit
             ↓          ↓         ↓
          Council    Context  Logging
```

**Boot Flow:** `boot.rb` → loads `master.rb` → initializes `DB`, `LLM`, `Pipeline`, `Executor`

**Request Flow:** `Pipeline.call(input)` → `Stages` (intake, guard, route, council, ask, lint, render) → `Executor` (React/PreAct/ReWOO/Reflexion patterns) → `LLM.ask` → `CircuitBreaker.run` → `ruby_llm` API call

**Data Sources:** `data/*.yml` (constitution, axioms, council, language rules, patterns) are the single source of truth. No hardcoded fallbacks.

## Core Files (read in this order)

| File | Purpose |
|------|---------|
| `data/axioms.yml` | The 68 axioms — constitutional law |
| `data/budget.yml` | Spending caps, token limits, tier thresholds |
| `data/phases.yml` | Cognitive load budget per phase |
| `lib/master.rb` | Entry point — wires all modules |
| `lib/boot.rb` | Environment detection, autoloading |
| `lib/pipeline.rb` | Stage-based execution engine |
| `lib/executor.rb` | Strategy pattern for LLM interaction |
| `lib/result.rb` | Ok/Err monad for every return value |
| `lib/review/constitution.rb` | Axiom compliance checker |
| `lib/quality_gates.rb` | Smell thresholds (lines, complexity) |

## Data Sources — Single Source of Truth

Every tunable lives in `data/*.yml`. No hardcoded fallbacks in `lib/`.

| File | Governs |
|------|---------|
| `axioms.yml` | 68 axioms with tags and descriptions |
| `budget.yml` | `spending_cap`, `max_chat_tokens`, tier thresholds |
| `phases.yml` | Cognitive load allocation per phase |
| `smells.yml` | Max method lines, class lines, complexity |
| `models.yml` | LLM provider/model/tier mappings |
| `personas.yml` | Agent personality definitions |
| `constitution.yml` | Review pipeline configuration |

## Three Most Critical Axioms

1. **FAIL_VISIBLY** — Every error must be logged and surfaced, never swallowed
2. **ONE_SOURCE** — Every fact lives in exactly one place
3. **SELF_APPLY** — MASTER2's own code must pass its own rules

## File Responsibilities & Axiom Categories

Note: Line counts are approximate and may change as code evolves.

| File | Responsibility | Primary Axioms | Lines |
|------|---------------|----------------|-------|
| `lib/master.rb` | Module loader, namespace | PRESERVE_THEN_IMPROVE_NEVER_BREAK | 100 |
| `lib/boot.rb` | System initialization, banner | FAIL_VISIBLY | 98 |
| `lib/pipeline.rb` | Request orchestration | ONE_JOB, REFLOW | 213 |
| `lib/executor.rb` | Multi-pattern execution | PATTERNS_OVER_PROCEDURES | 290 |
| `lib/llm.rb` | OpenRouter API client | CIRCUIT_BREAKER, GUARD_EXPENSIVE | 206 |
| `lib/db_jsonl.rb` | JSONL database (axioms, council) | ONE_SOURCE | 209 |
| `lib/session.rb` | Conversation state | AUTOSAVE | 222 |
| `lib/result.rb` | Railway monad | EXPLICIT | 124 |
| `lib/circuit_breaker.rb` | Failure handling, rate limits | DEADLINES | 145 |
| `lib/logging.rb` | Unified logging (dmesg-style) | FAIL_VISIBLY | 257 |
| `lib/stages.rb` | Pipeline stages (guard, lint) | GUARD, LINT_BEFORE_SHIP | 315 |
| `lib/ui.rb` | Terminal UI, colors, spinners | UI_CONSISTENCY | 280 |
| `lib/council.rb` | Adversarial review (12 personas) | COUNCIL_REVIEW | 198 |
| `lib/shell.rb` | Safe command execution | GUARD | 135 |
| `data/constitution.yml` | Golden rule, constraints | SELF_APPLY | 297 |
| `data/axioms.yml` | 68 axioms across 11 categories | ALL | 2100 |
| `data/council.yml` | 12 personas, 3 veto holders | COUNCIL_REVIEW | 234 |

## Additional Context — Target Platform & Requirements

Target platform: OpenBSD 7.8, Ruby 3.4, zsh. No python, bash, awk, sed, sudo.

MASTER2 is a Constitutional AI code quality system that enforces software quality through:
- **68 axioms** across 11 categories (DRY, SOLID, security, performance, etc.)
- **12 adversarial personas** in a council with veto power
- **Multi-model deliberation** (chamber/swarm modes) for complex decisions
- **Autonomous execution** with ReAct, PreAct, ReWOO, Reflexion patterns
- **Convergence detection** to avoid infinite loops and oscillation
- **Budget management** with circuit breakers and graceful degradation

## What MASTER2 Provides Over Traditional Code Review

Traditional code review is reactive, inconsistent, and human-bottlenecked. MASTER2 provides:
1. **Proactive** — catches issues before commit (pre-commit hooks)
2. **Consistent** — same standards applied every time via axioms
3. **Constitutional** — immutable governance rules prevent drift
4. **Adversarial** — multiple personas debate to find hidden flaws
5. **Autonomous** — can self-improve and fix issues without human intervention
6. **Explainable** — every decision traced back to specific axiom violations

## Architecture Map

```
Entry Points:
  bin/master (CLI) ─┬─> lib/master.rb (bootstrap)
  sbin/agentd ------┘    │
                         v
                    lib/boot.rb (initialization + smoke tests)
                         │
                         v
                    ┌────┴────┐
                    v         v
         lib/pipeline.rb   lib/session.rb
         (orchestration)   (state management)
                │              │
                v              │
         lib/executor.rb       │
         (autonomous execution)│
                │              │
                v              │
         ┌──────┴──────┐      │
         v             v      │
    lib/agent.rb   lib/chamber.rb
    (lifecycle)    (multi-model)
         │             │       │
         v             v       v
    lib/llm.rb ────────┴───────┘
    (LLM interface)

Data Flow:
  data/axioms.yml ─────> DB (lib/db_jsonl.rb) ─> Review/Enforcement
  data/constitution.yml > Governance rules     > Pipeline stages
  data/council.yml ────> Personas             > Chamber debates
```

## Execution Model

### 1. CLI Command Flow
```
$ master refactor file.rb
  │
  v
Commands.refactor(file)
  │
  v
Pipeline.new.call(task)
  │
  v
Stages: intake → compress → guard → route → council → ask → lint → render
  │
  v
Executor.call(input, pattern: :react)  # Auto-selects best pattern
  │
  v
LLM.ask(prompt, tier: :tier1) → Result.ok(response) | Result.err(reason)
```

### 2. Autonomous Agent Flow
```
$ master heartbeat start
  │
  v
Agent.spawn(policy: :refactor)
  │
  v
loop:
  Scheduler.poll → Triggers.evaluate → Executor.call → Memory.store
```

### 3. Chamber (Multi-Model) Flow
```
$ master chamber file.rb
  │
  v
Chamber.deliberate(modes: [:swarm, :creative])
  │
  v
Council personas debate → Weighted consensus → Best solution
```

## Key Subsystems

### Core Pipeline (lib/pipeline.rb)
Orchestrates 7 stages with Result monad (first error halts):
- **intake**: Parse input, validate structure
- **compress**: Reduce context size if needed
- **guard**: Check budget, rate limits, circuit breakers
- **route**: Select appropriate executor pattern
- **council**: Adversarial review (12 personas, 3 veto holders)
- **ask**: LLM invocation with tier fallback
- **lint**: Syntax validation, axiom checking
- **render**: Format output

### Executor Patterns (lib/executor/*.rb)
Auto-selected based on task complexity:
- **ReAct**: Reasoning + Acting (default for most tasks)
- **PreAct**: Planning before acting (complex multi-step)
- **ReWOO**: Retrieval-augmented (needs external knowledge)
- **Reflexion**: Self-reflection (when stuck or errors)
- **Momentum**: State tracking across iterations

### LLM Interface (lib/llm.rb)
Tier-based fallback with budget management:
- Tier 1: claude-opus-4, gpt-4o → highest quality
- Tier 2: claude-sonnet-4, gpt-4 → balanced
- Tier 3: claude-haiku-4, gpt-3.5 → fast/cheap
- Circuit breaker: Auto-disables failing providers
- Semantic cache: Avoid duplicate LLM calls
- Budget: $10 session cap with warnings

### Agent Autonomy (lib/agent/*.rb)
Safe autonomous operation with guardrails:
- **autonomy.rb**: Core autonomous behaviors
- **firewall.rb**: Safety policies, approval gates
- **policy.rb**: 4 modes (readonly/analyze/refactor/full)
- **pool.rb**: Agent lifecycle management

### Code Review (lib/review/*.rb, lib/code_review/*.rb)
Constitution-based quality enforcement:
- **scanner.rb**: Detect violations using AST + regex
- **enforcer.rb**: Apply remediation based on axioms
- **fixer.rb**: Auto-fix safe violations
- **analyzers**: Smell detection, bug hunting, security

### Data Persistence (lib/db_jsonl.rb)
JSONL-based append-only database:
- Loads data/*.yml files (axioms, council, personas, etc.)
- Memory-efficient streaming for large datasets
- Transaction log for audit trail

## Data Files (read in order)

1. **data/constitution.yml** — Golden rule, protection levels, quality gates, enforcement layers
2. **data/axioms.yml** — 68 axioms across 11 categories (every code change must satisfy relevant axioms)
3. **data/language_axioms.yml** — Detection rules for ruby, rails, zsh, html, css, js
4. **data/zsh_patterns.yml** — Banned commands, auto-remediation, token economics
5. **data/openbsd_patterns.yml** — Service management, forbidden commands, platform mappings
6. **data/council.yml** — 12 adversarial personas (3 have veto power)
7. **data/quality_thresholds.yml** — Minimum quality scores and enforcement levels
8. **data/personas.yml** — Persona definitions for LLM role-playing
9. **data/system_prompt.yml** — Base system prompts for different modes
10. **data/budget.yml** — Budget limits, tier costs, circuit breaker thresholds
11. **data/phases.yml** — 8-phase workflow definitions

## Golden Rule

**PRESERVE_THEN_IMPROVE_NEVER_BREAK**

Never delete working code. Never break existing behavior. Improve surgically.

## Banned Patterns

- `rescue nil` — always rescue specific exceptions
- File sprawl — never create summary.md, analysis.md, report.md, todo.md, notes.md, changelog.md
- ASCII decoration comments (`# ====`, `# ----`, `# ****`)
- Comments that restate the code
- Files over 300 lines (split along module boundaries)
- Trailing whitespace
- More than 2 consecutive blank lines

## Communication Style

OpenBSD dmesg-inspired. Terse, factual, evidence-based. No filler, no hedging, no unnecessary formatting. Show what changed and why.

Example:
```
llm0 at tier1: claude-opus-4 1234->567tok $0.0234 123ms
file0 at executor0: modified lib/logging.rb (fixed visibility)
boot: 45ms
```

## How to Apply MASTER2

Before modifying any file in this repository:
1. Check which axioms apply to the change (see data/axioms.yml)
2. Check language_axioms.yml for language-specific rules
3. Verify the change preserves existing behavior (golden rule)
4. Verify no banned patterns are introduced
5. Keep files small (< 300 lines), comments minimal, code self-documenting
6. Run `master scan` to validate changes

## Usage Examples

```sh
# Scan for issues
master scan [dir]

# Fix specific file
master fix file.rb

# Refactor with LLM
master refactor file.rb

# Multi-model deliberation
master chamber file.rb

# Evolve codebase
master evolve

# Autonomous mode
master heartbeat start

# REPL + web server
master
```

## Testing Your Changes

```sh
# Run MASTER2 validation
cd MASTER2 && ruby bin/master scan

# Run test suite (if available)
rake test

# Check syntax
ruby -c lib/your_file.rb
```

## Further Reading

- `README.md` — Quick start guide
- `data/constitution.yml` — Immutable governance rules
- `data/axioms.yml` — Complete axiom reference
- `lib/` — Implementation details
