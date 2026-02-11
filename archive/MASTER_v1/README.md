# MASTER v3

Autonomous code refactoring engine. Pure Ruby. OpenBSD.

## Quick start

```bash
bundle install
bin/master                                              # REPL mode
echo '{"text":"Hello"}' | bin/master --pipe             # JSON in/out
echo '{"text":"...","file":"lib/foo.rb"}' | bin/master --pipe --evolve  # Self-modify
```

## Architecture

```
MASTER/
├── bin/
│   └── master              # Single entry. REPL or --pipe. Seeds DB on first run.
├── lib/
│   ├── master.rb           # Module root. VERSION = "3.0.0". Requires everything.
│   ├── result.rb           # Ok/Err monad.
│   ├── pipeline.rb         # Stage chain via Result.flat_map. Contains REPL loop.
│   ├── db.rb               # SQLite: 5 tables, connection, schema, seed, queries.
│   ├── llm.rb              # RubyLLM config + chat + circuit breaker + budget.
│   ├── pledge.rb           # Real pledge(2)/unveil(2) via Fiddle.
│   └── stages.rb           # All 5+ stage classes in one file.
├── data/
│   ├── principles.yml      # Seed data.
│   └── personas.yml        # Seed data.
└── test/
    ├── test_result.rb
    ├── test_pipeline.rb
    ├── test_db.rb
    ├── test_llm.rb
    └── test_stages.rb
```

**7 source files** (bin/master + 6 lib files). **5 tests.** **2 data files.**

**lib/master.rb** — Module root, requires all files.  
**lib/result.rb** — Functional Result monad (Ok/Err).  
**lib/pipeline.rb** — Chains stages via Result.flat_map, includes REPL.  
**lib/db.rb** — SQLite wrapper: 5 tables (principles, personas, config, costs, circuits).  
**lib/llm.rb** — LLM client + circuit breaker + budget tracking + model selection.  
**lib/pledge.rb** — OpenBSD pledge(2)/unveil(2) via Fiddle for sandboxing.  
**lib/stages.rb** — All pipeline stage classes: Intake, Guard, Route, Ask, Render, Evolve, Execute.

## Pipeline stages

| Stage    | Purpose                                                    |
|----------|------------------------------------------------------------|
| Intake   | Pass text through, load persona if specified               |
| Guard    | Block dangerous commands (rm -rf /, DROP TABLE, etc.)      |
| Route    | Select model via circuit breaker + budget awareness        |
| Ask      | Call LLM, stream to stderr, record cost                    |
| Render   | Format output: typeset prose, preserve code blocks         |

**Opt-in stages:**
- **Execute** — Run Ruby code blocks in sandboxed environment (pledge on OpenBSD)
- **Evolve** — Self-modify: git snapshot → write → test → rollback on failure

## Setup

```bash
cp .env.example .env
# Edit .env with your API keys
bin/master  # DB seeds automatically on first run
```

## Shell aliases

Add to `~/.zshrc`:

```bash
alias m="ruby ~/path/to/MASTER/bin/master"
alias m-ask='f() { echo "{\"text\":\"$*\"}" | ruby ~/path/to/MASTER/bin/master --pipe; }; f'
```

## Testing

```bash
rake test
```

## Security

- **Real pledge(2)** on OpenBSD via Fiddle for sandboxing Execute stage
- **Circuit breaker**: 3 failures → open, 5min cooldown
- **Guard stage**: blocks destructive patterns (rm -rf /, DROP TABLE, etc.)
- **Budget tracking**: $10 limit, model selection aware of remaining budget
