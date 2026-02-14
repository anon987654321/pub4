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

**ABSOLUTE** axioms halt on violation. **PROTECTED** axioms warn.

### Language Axioms

Language axioms are a comprehensive set of 41 timeless principles organized into 7 categories:

- **Engineering** (11) — Core software engineering principles (SRP, OCP, DRY, KISS, composability)
- **Structural** (8) — Refactoring operations (merge, flatten, decouple, hoist)
- **Process** (6) — Development workflow (test-first, one-change, measure-then-optimize)
- **Communication** (4) — Code as literature (concise, self-explaining)
- **Meta** (4) — Self-governance (show-cost-first, depth-on-demand)
- **Resilience** (3) — Systems that survive (degrade-gracefully, expect-failure)
- **Aesthetic** (5) — Beauty in craft (least-power, just-enough)

Each axiom includes:
- **ID** — Unique identifier
- **Title** — Short name
- **Statement** — Actionable, validatable principle
- **Source** — Authoritative reference (e.g., "The Pragmatic Programmer", "SOLID Principles")
- **Category** — Logical grouping
- **Protection Level** — ABSOLUTE (halt on violation) or PROTECTED (warn only)

#### View Language Axioms Stats

In the REPL, use the `axioms-stats` or `axioms` command:

```
master> axioms-stats
Language Axioms Summary
========================================

Total axioms: 41

By Category:
  engineering          11
  structural           8
  process              6
  aesthetic            5
  communication        4
  meta                 4
  resilience           3

By Protection Level:
  PROTECTED            40
  ABSOLUTE             1
```

#### Data Source

Language axioms are stored in `data/axioms.yml` as a data-driven YAML file. Each entry follows a consistent structure:

```yaml
- id: "ONE_SOURCE"
  category: "engineering"
  protection: "PROTECTED"
  title: "One Source of Truth"
  statement: "Every piece of knowledge has exactly one authoritative representation."
  source: "The Pragmatic Programmer"
```

To add new axioms, edit `data/axioms.yml` following the existing structure.

## Council

Twelve personas. Three hold veto:

- **Security Officer** — Guards CIA triad
- **The Attacker** — Finds exploits
- **The Maintainer** — 3 AM debuggability

Consensus requires 70% weighted agreement. Oscillation (25 rounds) halts system.

## Self-Application

> A system that asserts quality must achieve its own standards.

Run `selftest` to pass MASTER through itself:
- Static analysis
- Axiom validation
- Pipeline safety
- Council review (LLM)

If MASTER fails its own review, it has failed.

## Automatic Bug Hunting

Every refactor now runs a **6-phase analysis**:

1. **🔍 Bug Hunting** - 8-phase deep analysis (lexical, execution, data flow, patterns)
2. **🧠 Constitutional Validation** - Check all 32 principles
3. **📚 Learnings Check** - Apply patterns from past fixes
4. **👃 Smell Detection** - Find code smells
5. **🤖 Fix Generation** - LLM-powered refactoring
6. **📝 Learning Recording** - Save successful patterns

### Usage

```bash
# Automatic multi-phase analysis + fixes
master> refactor lib/session.rb

# Output:
# 🔍 PHASE 1: Bug Hunting...
# ⚠️  Found 2 potential bugs
# 🧠 PHASE 2: Constitutional Validation...
# 🚨 1 critical violations
# 📚 PHASE 3: Checking Learnings...
# 💡 Found 1 known patterns
# 👃 PHASE 4: Code Smell Detection...
# 📋 Found 3 code smells
#
# 📊 SUMMARY: 7 issues found
# 🤔 Proceed with automatic fixes? (y/n): y
# 🤖 PHASE 5: Generating Fixes...
# ✓ Applied 7 fixes
# 📝 PHASE 6: Recording Learnings...
# ✓ Learnings updated
```

### Manual Commands

For deep inspection without auto-fix:

```bash
master> hunt lib/session.rb        # 8-phase bug analysis only
master> critique lib/master.rb     # Constitutional validation only
master> learn lib/learnings.rb     # Show matching learned patterns
master> conflict                   # Detect principle conflicts
```

## Quickstart

```bash
# Start interactive REPL
$ cd MASTER2
$ ./bin/master

# Automatic refactor with bug hunting
master> refactor lib/session.rb

# Manual inspection
master> hunt lib/session.rb
master> critique lib/learnings.rb
master> learn lib/smells.rb
master> conflict

# Full codebase scan
master> scan .

# Weekly automation (cron: 0 9 * * 1)
$ ./bin/weekly
```

## Commands

MASTER2 supports both REPL mode and direct CLI commands:

### REPL Mode Commands

```
help          Show commands
refactor      Multi-model file review with 6-phase analysis
hunt          8-phase bug analysis (manual deep-dive)
critique      Constitutional validation (manual review)
learn         Show matching learned patterns for a file
conflict      Detect principle conflicts in constitution
chamber       Council deliberation
ideate        Creative brainstorming (Chamber)
evolve        Self-improvement cycle
fix           Auto-fix code violations
browse        Web browsing (Ferrum)
speak         Text-to-speech (Piper/Edge/Replicate)
model         Switch LLM model
models        List available models
pattern       Switch execution pattern (react/pre_act/rewoo/reflexion)
patterns      List execution patterns
opportunities Analyze codebase for improvements
selftest      Run MASTER through itself
axioms-stats  Show language axioms statistics
session       Session management
budget        Show remaining budget
health        System health check
```

### Direct CLI Commands

Execute commands directly from the shell without entering REPL mode:

```bash
# Refactor a file
./bin/master refactor path/to/file.rb

# Fix all violations in current directory
./bin/master fix --all

# Fix specific file
./bin/master fix path/to/file.rb

# Scan directory for code smells
./bin/master scan deploy/rails/

# Chamber review
./bin/master chamber lib/master.rb

# Generate ideas
./bin/master ideate "authentication system"

# Show version
./bin/master version

# Show help
./bin/master help

# Health check
./bin/master health

# Axiom statistics
./bin/master axioms-stats
```

### Zsh Completion

Tab completion is available for all commands and arguments:

**Installation:**

```bash
# Add to your ~/.zshrc
fpath=(~/path/to/pub4/MASTER2/completions $fpath)
autoload -Uz compinit && compinit
```

**Features:**
- Complete command names: `master <TAB>`
- File completion for `refactor`, `fix`, `opportunities`
- Directory completion for `scan`
- Language names for `chamber`
- Session subcommands for `session`
- `--all` flag completion for `fix`

## Modes

- **REPL**: `./bin/master`
- **Pipe**: `echo '{"text":"..."}' | ./bin/master --pipe`
- **Daemon**: `./sbin/agentd`

## Budget

$10.00 session limit. Four tiers:

- **Premium**: Claude-3.5-Sonnet, GPT-4o (high-quality, highest cost)
- **Strong**: Claude-3-Haiku, GPT-4o-mini (balanced quality/cost)
- **Fast**: Qwen/QwQ-32B-Preview, DeepSeek-R1 (quick iteration, lower cost)
- **Cheap**: Llama-3.1-8B, DeepSeek-Coder (bulk operations, minimal cost)

| Tier | Models |
|------|--------|
| strong | deepseek-r1, claude-sonnet-4 |
| fast | deepseek-v3, gpt-4.1-mini |
| cheap | gpt-4.1-nano |

Circuit breaker trips after 3 failures. 5-minute cooldown.

## Structure

```
bin/master       Entry point
lib/             60+ modules
data/            Axioms, council, patterns (YAML)
var/db/          JSONL storage
test/            Minitest suite
```

## License

MIT
