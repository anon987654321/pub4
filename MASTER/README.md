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
    lib/memory.rb        Vector-based memory system
    lib/monitor.rb       Cost and token tracking
    lib/harvester.rb     Ecosystem intelligence gathering
    lib/principles/      45 constitutional rules
    lib/config/          YAML settings
    lib/personas/        Character modes
    lib/skills/          Discoverable skill modules


## Commands

    ask         Chat
    scan        Analyze cwd
    refactor    Improve code
    evolve      Converge until <2% gain
    chamber     Multi-model debate
    tier        Switch model class
    help        List all


## Models

    cheap       DeepSeek
    fast        Grok
    strong      Sonnet
    frontier    Opus
    code        Codestral


## Memory

Vector-based memory with chunking, embedding, and similarity search:

```ruby
memory = MASTER::Memory.new
memory.store("content", tags: ["skill", "ruby"], source: "github")
results = memory.recall("query", k: 5)
memory.save("data/memory/session.yml")
```

Features:
- 500-1k token chunks with 75-100 token overlap
- Top-k similarity search with recency reranking
- Save/load from YAML or JSON


## Intelligence Harvesting

Automated ecosystem intelligence from OpenClaw (565+ skills):

```ruby
harvester = MASTER::Harvester.new
harvester.harvest
harvester.save  # → data/intelligence/harvested_YYYY-MM-DD.yml
```

Extracts:
- SKILL.md files with metadata
- Star counts and update frequency
- OS requirements and dependencies
- Trend analysis


## Monitoring

Track LLM usage, tokens, and costs:

```ruby
monitor = MASTER::Monitor.new
monitor.track("task_name", model: "strong") do
  # LLM call here
end
monitor.report  # Summary statistics
```

Logs to: `data/monitoring/usage.jsonl`  
Compatible with tokscale patterns


## Weekly Automation

Automated maintenance and intelligence gathering:

```sh
./bin/weekly
```

Runs:
1. Ecosystem harvest (lib/harvester.rb)
2. Self-optimization (lib/evolve.rb)
3. Monitoring report (lib/monitor.rb)
4. Weekly report → data/reports/weekly_YYYY-MM-DD.md

Cron example:
```cron
# Every Monday at 9 AM
0 9 * * 1 cd ~/pub4/MASTER && ./bin/weekly
```


## Skills

Discoverable modules in `lib/skills/`:
- Template: `lib/skills/SKILL.md.template`
- Example: `lib/skills/github_analyzer/SKILL.md`

Format: YAML frontmatter + markdown documentation


## Environment

    OPENROUTER_API_KEY    Required
    REPLICATE_API_TOKEN   Media generation
    GITHUB_TOKEN          Higher API rate limits (optional)


## Design

Typography through contrast, not decoration.
Whitespace is layout. Proximity beats borders.
Success whispers. Errors speak.
Five icons: `✓ ✗ ! · →`

Zsh over Bash. Parameter expansion over forks.
Calm palette. Monospace constraints respected.


## License

MIT

*v52 · Ruby · OpenBSD · Constitutional*
