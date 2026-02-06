# MASTER v3 — Autonomous Code Refactoring Engine

Pure Ruby. OpenBSD. One pipeline. Every path through the same stages.

## Overview

MASTER is an autonomous universal code refactoring and completion engine. It takes code, refactors/completes it via LLM, tests the result, and rolls back on failure. A Claude Code CLI replacement built entirely in Ruby with real security primitives.

**One version: 3.0.0**

## Quick Start

### REPL Mode (Default)
```bash
bin/master
```

Interactive mode. Type your requests, get responses. Exit with `quit` or `exit`.

### Pipeline Mode (JSON)
```bash
echo '{"text":"explain this code"}' | bin/master --pipe
```

Read JSON from stdin, write JSON to stdout. Perfect for automation.

### Evolution Mode (with tests)
```bash
echo '{"file":"lib/foo.rb","test_command":"rake test"}' | bin/master --pipe --evolve
```

Refactor a file, run tests, auto-rollback if tests fail.

## Architecture

```
MASTER/
├── bin/
│   ├── master                    # Single entry point: REPL or --pipe
│   └── seed                      # One-time YAML → SQLite seeder
├── lib/
│   ├── master.rb                 # Root require. VERSION = "3.0.0"
│   ├── pipeline.rb               # Pipeline engine: chains stages via Result monad
│   ├── result.rb                 # Result monad (Ok/Err)
│   ├── stages/
│   │   ├── intake.rb             # Parse input, load persona from DB
│   │   ├── guard.rb              # Regex blocklist for destructive commands
│   │   ├── route.rb              # Model selection using Circuit + Budget
│   │   ├── ask.rb                # RubyLLM.chat, stream to stderr, record cost
│   │   ├── execute.rb            # Extract Ruby code blocks, run under pledge(2)
│   │   ├── evolve.rb             # Git snapshot → modify file → test → rollback on fail
│   │   └── render.rb             # Code-aware typography, pipeline terminus
│   ├── db.rb                     # SQLite: 5 tables
│   ├── llm.rb                    # RubyLLM wrapper
│   ├── circuit.rb                # Circuit breaker with real state transitions
│   ├── budget.rb                 # Budget derived from SUM(cost)
│   ├── pledge.rb                 # Real pledge(2)/unveil(2) via Fiddle
│   └── typography.rb             # Code/prose splitter, typeset prose only
├── data/
│   ├── principles.yml            # Design principles
│   └── personas.yml              # Agent personas
└── test/                         # Tests mirror lib/
```

## Stages

Every request flows through the same pipeline:

1. **Intake** — Parse input, load persona from DB if specified
2. **Guard** — Block destructive patterns (rm -rf /, DROP TABLE, etc.)
3. **Route** — Select model based on complexity, budget, circuit availability
4. **Ask** — Call LLM with streaming, record cost to DB
5. **Render** — Apply typography to prose (code blocks pass through unchanged)

Optional stages:
- **Execute** — Extract and run Ruby code blocks (sandboxed with pledge on OpenBSD)
- **Evolve** — Modify file, run tests, rollback if tests fail

## Setup

### 1. Environment Variables
```bash
cp .env.example .env
# Edit .env with your API keys
```

### 2. Install Dependencies
```bash
bundle install
```

### 3. Seed Database
```bash
bin/seed
```

Imports `data/principles.yml` and `data/personas.yml` into SQLite.

### 4. Source Aliases (Optional)
```bash
source .zshrc
m                            # launches REPL
m-ask "what is 2+2?"        # quick pipeline query
```

## Testing

```bash
rake test
```

Runs all tests in `test/test_*.rb`. Each test file mirrors its corresponding source file.

## Security

### Real pledge(2) on OpenBSD
When executing Ruby code blocks, MASTER calls `pledge("stdio rpath")` via Fiddle. On non-OpenBSD systems, it gracefully degrades (no sandbox).

### Circuit Breaker
If a model fails 3 times, it's marked "open" for 5 minutes (cooldown). Prevents cascading failures.

### Guard Stage
Blocks patterns like:
- `rm -rf /`
- `> /dev/sda`
- `DROP TABLE`
- `FORMAT C:`
- `mkfs.`
- `dd if=`

### Budget Tracking
Every LLM call records `tokens_in`, `tokens_out`, `cost` to SQLite. Route stage selects models based on remaining budget.

## Database Schema

Five tables, no more:

- **principles** — Design principles (name, text, protection_level, category)
- **personas** — Agent personas (name, role, instructions, weight)
- **config** — Key-value config store
- **costs** — Token usage and cost per request (model, tokens_in, tokens_out, cost, timestamp)
- **circuits** — Circuit breaker state (model, failures, last_failure, state)

## Design Constraints

1. **One binary, not fifteen.** `bin/master` handles REPL and `--pipe`.
2. **No input compression.** User words pass through unchanged.
3. **Five DB tables.** No config inflation.
4. **Stages are Ruby classes with `call(input) → Result`.** In-process composition.
5. **Tests mirror lib.** One test file per source file.
6. **No eval(), no system() with user strings.** Use `IO.popen` with arrays.
7. **Real pledge(2) via Fiddle on OpenBSD.** Raise on failure, rescue in callers.
8. **Typography never touches code blocks.** Split into regions first.
9. **Budget derived from costs table.** No mutable config row.
10. **Circuit breaker has real state transitions.** closed → open → half-open.

## License

MIT
