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
    lib/cli_v226.rb      Unified CLI (interactive + batch)
    lib/llm.rb           Model routing (9 tiers)
    lib/executor.rb      Runs code blocks from responses
    lib/safety.rb        Guardrails
    lib/evolve.rb        Self-optimization loop
    lib/chamber.rb       Multi-model deliberation
    lib/postpro.rb       Cinematic film emulation (12 stocks, 12 presets)
    lib/principles/      45 constitutional rules
    lib/config/          YAML settings
    lib/personas/        Character modes
    lib/unified/         v226 unified framework components


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


## Unified Framework v226

MASTER v226 "Unified Deep Debug" merges powerful debugging frameworks:

### Interactive Mode
```bash
ruby lib/cli_v226.rb
```
Conversational REPL with visual mood indicators and persona switching.

### Batch Analysis
```bash
ruby lib/cli_v226.rb file.rb            # Basic analysis
ruby lib/cli_v226.rb file.rb --debug    # 8-phase bug hunting
ruby lib/cli_v226.rb file.rb --json     # JSON output
```

### Features
- **Enhanced Postpro**: 12 film stocks, 12 presets, caching
- **Bug Hunting**: 8-phase systematic debugging protocol
- **Resilience**: Act-react loop, never give up approach
- **Constitutional AI**: 7 personas, 12 biases, 7 depth techniques
- **Systematic**: Required workflows (tree, clean, diff, logs)
- **Mood Indicators**: Visual feedback (idle, thinking, working, success, error)
- **Persona Modes**: Character-based output (ronin, verbose, hacker, poet, detective)

### Documentation
See `docs/UNIFIED_v226.md` for complete documentation.

### Configuration
Edit `config/master_v226.yml` to customize behavior.


## License

MIT

*v52 · Ruby · OpenBSD · Constitutional · Unified v226*
