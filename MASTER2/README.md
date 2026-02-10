# MASTER

LLM pipeline with adversarial council and axiom enforcement. Ruby. OpenBSD-native.

## Install

```sh
bundle install
cp .env.example .env
# Set OPENROUTER_API_KEY
./bin/master
```

## Architecture

MASTER is a hybrid agent system with multiple execution patterns:

### Execution Patterns (auto-selected)

| Pattern | Use Case | Behavior |
|---------|----------|----------|
| **ReAct** | Exploration, unknown tasks | Tight thought→action→observation loop |
| **Pre-Act** | Multi-step workflows | Plan all steps first, then execute (70% better recall) |
| **ReWOO** | Cost-sensitive reasoning | Single LLM call with #E{n} placeholders |
| **Reflexion** | Fix/debug/refactor | Execute → self-critique → retry if needed |

### Pipeline Stages

Seven stages, chained via Result monad:

1. **Intake** — Parse input
2. **Guard** — Block dangerous patterns
3. **Route** — Select model by budget/tier
4. **Debate** — Council deliberation (optional)
5. **Ask** — Query LLM
6. **Lint** — Axiom enforcement
7. **Render** — Typography refinement

First error short-circuits. No exceptions.

## Features

- **Auto-retry** with exponential backoff (3 attempts)
- **Rate limiting** (30 requests/minute, $0.50 per-query cap)
- **Circuit breaker** (3 failures → 5-minute cooldown)
- **Session persistence** with crash recovery (SIGINT/SIGTERM auto-save)
- **Pattern fallback** (if primary fails → react → direct)
- **Cinematic AI Pipeline** - Chain Replicate models for film-quality image transformations (see [docs/CINEMATIC_PIPELINE.md](docs/CINEMATIC_PIPELINE.md))

### Cinematic AI Pipeline

Transform images and videos using AI model chains with cinematic presets:

```ruby
# Apply a cinematic preset
MASTER::Cinematic.apply_preset("photo.jpg", "blade-runner")

# Build custom pipelines
pipeline = MASTER::Cinematic::Pipeline.new
  .chain('stability-ai/sdxl', { prompt: 'cinematic grade' })
  .chain('tencentarc/gfpgan', { scale: 2 })
  
result = pipeline.execute("input.jpg", save_intermediates: true)
```

Built-in presets: `blade-runner`, `wes-anderson`, `noir`, `golden-hour`, `teal-orange`

See [docs/CINEMATIC_PIPELINE.md](docs/CINEMATIC_PIPELINE.md) for full documentation.

## Axioms

Timeless rules from authoritative sources:

| Axiom | Source |
|-------|--------|
| DRY, KISS, POLA | Pragmatic Programmer |
| SRP, OCP | SOLID / Clean Code |
| Omit needless words | Strunk & White |
| Typography hierarchy | Bringhurst |
| Usability heuristics | Nielsen |

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

## Commands

MASTER2 supports both REPL mode and direct CLI commands:

### REPL Mode Commands

```
help          Show commands
refactor      Multi-model file review
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
