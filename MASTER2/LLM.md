# MASTER2 — Constitutional AI Code Quality System

Any LLM working in this repository must read, internalize, and follow MASTER2.

## What is MASTER2?

MASTER2 is a Constitutional AI code quality system that enforces software quality through:
- **68 axioms** across 11 categories (DRY, SOLID, security, performance, etc.)
- **12 adversarial personas** in a council with veto power
- **Multi-model deliberation** (chamber/swarm modes) for complex decisions
- **Autonomous execution** with ReAct, PreAct, ReWOO, Reflexion patterns
- **Convergence detection** to avoid infinite loops and oscillation
- **Budget management** with circuit breakers and graceful degradation

Target platform: OpenBSD 7.8, Ruby 3.4, zsh. No python, bash, awk, sed, sudo.

## Problem MASTER2 solves

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

## Platform Requirements

- **OS**: OpenBSD 7.8 (Linux/macOS with zsh also supported)
- **Ruby**: 3.4+
- **Shell**: zsh (no bash, no python, no awk, no sed)
- **Tools**: doas (not sudo), rcctl (service management), pkg_add (packages)

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
