# MASTER v2 — Unix Pipeline Toolkit

Universal code refactoring and completion engine. Pure Ruby. Composable pipelines. OpenBSD.

**Version 2.0** transforms the monolithic 94KB `cli.rb` into surgical Unix executables powered by the ruby_llm ecosystem.

---

## Quick Start

```bash
# Interactive REPL
bin/start

# Pipeline execution
echo '{"text":"Refactor this code"}' | \
  bin/intake | bin/guard | bin/route | bin/ask | bin/render

# Shell alias (after sourcing .zshrc)
m-ask What is the KISS principle?
```

---

## Architecture

### Core Philosophy
- **Do one thing well** - Each executable has a single responsibility
- **Compose via pipes** - JSON in, JSON out (except `render` terminus)
- **No side effects** - Pure functions (except database/git operations)
- **Under 200 lines** - Every `bin/` file
- **Under 300 lines** - Every `lib/` file

### Structure

```
MASTER/
├── bin/              Pipeline executables (15 stages)
│   ├── start         Interactive Ruby REPL
│   ├── intake        Input filter + compression
│   ├── guard         Safety firewall
│   ├── route         Model selector + circuit breaker
│   ├── ask           LLM interface (RubyLLM.chat)
│   ├── critique      Review (ruby_llm-tribunal)
│   ├── chamber       Multi-model deliberation
│   ├── execute       Sandboxed execution
│   ├── evolve        Self-modification + rollback
│   ├── quality       Quality gate
│   ├── converge      Convergence detection
│   ├── remember      Memory store/recall
│   ├── plan          8-phase workflow
│   ├── render        Output formatter
│   └── seed          YAML → SQLite import
├── lib/              Core libraries (8 modules)
│   ├── db.rb         SQLite (10 tables)
│   ├── json_protocol.rb  stdin/stdout protocol
│   ├── llm_client.rb     RubyLLM wrapper (28 lines)
│   ├── strunk.rb         Text compression
│   ├── metz.rb           Quality rules
│   ├── typography.rb     Formatting
│   ├── pledge.rb         OpenBSD sandboxing
│   └── hooks.rb          Event system
├── data/
│   ├── principles.yml    Design principles
│   └── personas.yml      Character modes
├── test/             Minitest suite
├── .zshrc            Shell environment
└── master.db         SQLite state (gitignored)
```

---

## Pipeline Stages

### 1. intake
Applies Strunk & White compression, loads persona, measures information density.

**Input:** `{ text: "..." }`  
**Output:** `{ text: "compressed", persona: "...", density: 0.7 }`

### 2. guard
Safety firewall. Checks dangerous operations and principle violations.

**Input:** `{ text: "..." }`  
**Output:** `{ allowed: true/false, reason: "..." }`

### 3. route
Selects model based on complexity, budget, circuit breaker state.

**Tiers:**
- **strong** - deepseek-r1, claude-sonnet-4
- **fast** - deepseek-v3, gpt-4.1-mini
- **cheap** - gpt-4.1-nano

**Input:** `{ text: "..." }`  
**Output:** `{ model: "deepseek-r1", tier: "strong", budget_remaining: 8.5 }`

### 4. ask
Sends to LLM using `RubyLLM.chat`. Streams response. Tracks costs.

**Input:** `{ text: "...", model: "...", persona: "..." }`  
**Output:** `{ response: "...", tokens_in: 100, tokens_out: 200 }`

### 5. critique
Post-LLM review using `ruby_llm-tribunal`. Detects hallucination, checks relevance.

**Input:** `{ text: "...", response: "..." }`  
**Output:** `{ critique_passed: true, confidence: 0.9 }`

### 6. chamber
Multi-model deliberation. Parallel execution. Synthesis.

**Input:** `{ text: "...", models: ["model1", "model2"] }`  
**Output:** `{ response: "synthesized", consensus: true }`

### 7. execute
Extracts code blocks, runs in sandbox with pledge/unveil.

**Input:** `{ response: "```ruby\ncode\n```" }`  
**Output:** `{ success: true, output: "...", executed: true }`

### 8. evolve
Self-modification. Git stash snapshot → modify → test → rollback on failure.

**Input:** `{ file: "path", modification: "..." }`  
**Output:** `{ modified: true, tests_passed: true, rolled_back: false }`

### 9. quality
Sandi Metz quality rules: 100 lines/class, 5 lines/method, 4 params.

**Input:** `{ response: "...", file: "..." }`  
**Output:** `{ quality_passed: true, quality_score: 1.0 }`

### 10. converge
Detects convergence (δ < 2% threshold).

**Input:** `{ response: "...", previous: "..." }`  
**Output:** `{ converged: true, delta: 0.01 }`

### 11. remember
Store/recall memories from SQLite.

**Input:** `{ action: "store", content: "..." }`  
**Output:** `{ stored: true }`

### 12. plan
8-phase workflow: discover → analyze → ideate → design → implement → validate → deliver → learn

**Input:** `{ phase: "discover", completed_criteria: [...] }`  
**Output:** `{ phase: "discover", next_phase: "analyze", criteria_met: true }`

### 13. render
Typography formatter. Pipeline terminus (outputs text, not JSON).

**Input:** `{ response: "..." }`  
**Output:** Plain text with proper quotes, em dashes, 72-char wrapping

---

## Dependencies

Using ruby_llm ecosystem (no custom HTTP client):

```ruby
gem "ruby_llm"            # Chat, streaming, 800+ models
gem "ruby_llm-schema"     # Structured output
gem "ruby_llm-tribunal"   # LLM evaluation
gem "sqlite3"             # State persistence
gem "tty-prompt"          # Interactive UI
gem "tty-table"           # Data tables
gem "tty-box"             # Framed boxes
gem "tty-spinner"         # Loading spinners
gem "tty-screen"          # Terminal size
gem "minitest"            # Testing
```

**Critical:** No `net/http`, `faraday`, `httparty`. RubyLLM handles all provider communication.

---

## Environment Setup

### 1. API Keys
Create `MASTER/.env`:
```bash
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
DEEPSEEK_API_KEY=sk-...
OPENROUTER_API_KEY=sk-or-...
```

### 2. Source .zshrc
Add to `~/.zshrc`:
```zsh
source /home/dev/pub/MASTER/.zshrc
```

This adds aliases:
- `m-start` - Interactive REPL
- `m-ask <query>` - Quick pipeline query
- `m-evolve` - Self-modification
- `m-quality` - Quality check

### 3. Seed Database
```bash
bin/seed  # Imports principles.yml and personas.yml
```

---

## Usage Examples

### Interactive REPL
```bash
bin/start
› What is SOLID?
```

### Single Query
```bash
m-ask Explain the KISS principle
```

### Full Pipeline
```bash
echo '{"text":"Refactor this for clarity", "persona":"architect"}' | \
  bin/intake | \
  bin/guard | \
  bin/route | \
  bin/ask | \
  bin/critique | \
  bin/quality | \
  bin/render
```

### Multi-Model Chamber
```bash
echo '{"text":"Design a REST API", "models":["deepseek-r1","claude-sonnet-4"]}' | \
  bin/intake | \
  bin/chamber | \
  bin/render
```

### Self-Evolution
```bash
echo '{"file":"lib/strunk.rb", "test_command":"ruby test/test_protocol.rb"}' | \
  bin/evolve
```

---

## Testing

```bash
# All tests
ruby -Ilib:test test/test_*.rb

# Specific test
ruby test/test_protocol.rb
ruby test/test_db.rb
ruby test/test_pipeline.rb
```

---

## Database Schema

SQLite with 10 tables:

- **principles** - Design principles (KISS, DRY, SOLID, etc.)
- **personas** - Character modes (architect, generic, etc.)
- **config** - Key-value configuration
- **memories** - Long-term memory with embeddings
- **costs** - LLM usage tracking
- **circuits** - Circuit breaker state (3 failures → open)
- **hooks** - Event handlers (before_edit, after_fix, etc.)
- **sessions** - Chat sessions with total cost
- **evolutions** - Self-modification history
- **messages** - Session message log

---

## Security

### API Keys
- **Never** commit `.env` to git (in `.gitignore`)
- **Never** hardcode keys in `.zshrc` or source files
- Source `.env` from `.zshrc` at runtime

### Circuit Breaker
- 3 consecutive failures → model marked 'open'
- Auto-downgrade to next tier
- Reset with `MASTER::DB.reset_circuit(model)`

### Sandboxing
- `pledge.rb` wraps OpenBSD pledge/unveil syscalls
- Restricts filesystem and syscall access during execution
- Graceful degradation on non-OpenBSD platforms

### Safety Firewall
- `bin/guard` blocks dangerous operations
- Checks against ABSOLUTE principles
- Detects `rm -rf`, `drop table`, etc.

---

## Philosophy

### Unix Pipeline Principles
1. **Small, focused tools** - Each stage does one thing
2. **Text (JSON) streams** - Universal interface
3. **Composable** - Chain any combination
4. **Testable** - Each stage tested independently
5. **Observable** - stderr for streaming, stdout for data

### Code Quality
- **Strunk & White** - Omit needless words, active voice
- **Sandi Metz** - 100 lines/class, 5 lines/method, 4 params
- **Bringhurst** - Typography matters

### LLM Strategy
- **Circuit breaker** - Fail fast, auto-recover
- **Multi-model** - Deliberate, synthesize
- **Cost tracking** - Budget awareness
- **Critique** - Detect hallucination

---

## Migration from v1

**Old (monolithic):**
```ruby
# lib/cli.rb - 94KB god object
class CLI
  def run
    # 2000+ lines of REPL logic, commands, LLM calls...
  end
end
```

**New (composable):**
```bash
# 15 focused executables, 8 libraries
bin/intake | bin/guard | bin/route | bin/ask | bin/render
```

**Benefits:**
- ✅ Testable - Each stage tested independently
- ✅ Debuggable - Inspect JSON between stages
- ✅ Composable - Mix and match stages
- ✅ Maintainable - No file over 200 lines
- ✅ Extensible - Add stages without touching core

---

## Troubleshooting

### RubyLLM not found
```bash
bundle install
```

### API key errors
Check `.env` exists and is sourced:
```bash
echo $OPENAI_API_KEY
```

### Database locked
```bash
rm master.db
bin/seed
```

### Tests failing
```bash
bundle exec ruby test/test_protocol.rb -v
```

---

## License

See repository root.

---

## Credits

- **RubyLLM** - https://github.com/alexrudall/ruby-llm
- **TTY toolkit** - https://ttytoolkit.org
- **Strunk & White** - The Elements of Style
- **Sandi Metz** - Practical Object-Oriented Design in Ruby
- **Robert Bringhurst** - The Elements of Typographic Style
