# MASTER

Self-modifying AI framework. Pure Ruby. OpenBSD.

Entry · `bin/cli`
Loader · `lib/master.rb`


## What It Does

Give it a task. It writes code, runs it, sees the result, iterates.
Can modify its own source. No npm, no Python—just Ruby and LLMs.


## For LLMs

You are MASTER. Execute via `sh` or `ruby` fenced blocks.
Files in `lib/` are yours to improve.


## Structure

    bin/cli              Start here
    lib/master.rb        Autoloader
    lib/cli.rb           REPL and commands
    lib/llm.rb           Model routing (9 tiers)
    lib/executor.rb      Runs code blocks from responses
    lib/safety.rb        Guardrails
    lib/evolve.rb        Self-optimization loop
    lib/chamber.rb       Multi-model deliberation
    lib/principles/      45 constitutional rules
    lib/config/          YAML settings
    lib/personas/        Character modes


## Commands

    ask           Chat
    scan          Analyze cwd
    refactor      Improve code
    evolve        Converge until <2% gain
    chamber       Multi-model debate
    tier          Switch model class
    dashboard     Show live dashboard
    remember      Store in long-term memory
    recall        Search long-term memory
    memory-stats  Memory system status
    help          List all


## Dashboard

View live statistics and metrics:

```bash
bin/cli dashboard
```

Shows:
- Cost breakdown by model
- Recent tasks
- Memory statistics
- System health


## Memory

MASTER uses Weaviate for persistent vector memory.

### Store Information
```bash
bin/cli remember "Important fact" --tags important,fact --source documentation
```

### Recall Information
```bash
bin/cli recall "what did I learn about X"
```

### Memory Stats
```bash
bin/cli memory-stats
```

Memory persists across sessions and improves over time.

### Weaviate Setup

MASTER uses Weaviate for vector memory. Run via Docker:

```bash
docker run -d \
  -p 8080:8080 \
  -e QUERY_DEFAULTS_LIMIT=25 \
  -e AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true \
  -e PERSISTENCE_DATA_PATH='/var/lib/weaviate' \
  -e DEFAULT_VECTORIZER_MODULE='text2vec-openai' \
  -e ENABLE_MODULES='text2vec-openai' \
  -e OPENAI_APIKEY='your-key' \
  semitechnologies/weaviate:latest
```

Or use Weaviate Cloud: https://console.weaviate.cloud/


## Models

    cheap       DeepSeek
    fast        Grok
    strong      Sonnet
    frontier    Opus
    code        Codestral


## Environment

    OPENROUTER_API_KEY    Required
    REPLICATE_API_TOKEN   Media generation


## Design

Typography through contrast, not decoration.
Whitespace is layout. Proximity beats borders.
Success whispers. Errors speak.
Five icons: `✓ ✗ ! · →`

Zsh over Bash. Parameter expansion over forks.
Calm palette. Monospace constraints respected.


## License

MIT

*v51 · Ruby · OpenBSD · Constitutional*
