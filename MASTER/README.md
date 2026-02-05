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


## License

MIT

*v51 · Ruby · OpenBSD · Constitutional*
