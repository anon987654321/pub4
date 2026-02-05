# MASTER v50.8

Constitutional AI for code quality. 33 principles, modular Ruby architecture.

## Quick Start

```bash
export OPENROUTER_API_KEY="your-key"
cd pub4
ruby bin/cli
```

## Architecture

```
bin/cli                    # Entry point
lib/
├── master.rb              # Module loader (autoload)
├── paths.rb               # Centralized path management
├── result.rb              # Ok/Err monad
├── llm.rb                 # 5-tier OpenRouter client
├── principle.rb           # YAML principle parser
├── persona.rb             # YAML persona parser
├── boot.rb                # dmesg-style startup
├── cli.rb                 # REPL with 20+ commands
├── server.rb              # Falcon web server
├── engine.rb              # Code scanner
├── converge.rb            # Convergence detection
├── smells.rb              # Code smell patterns
├── safety.rb              # Dangerous command blocklist
├── memory.rb              # Session compression
├── replicate.rb           # Image/audio generation
├── web.rb                 # Ferrum headless browser
├── openbsd.rb             # pledge/unveil support
├── sandbox.rb             # Sandboxing (disabled)
├── principles/            # 33 principle .yml files
└── personas/              # Persona .yml files
DEMOS/                     # 60+ audio-reactive css-doodle orbs
```

## LLM Tiers

| Tier | Model | Cost/1K |
|------|-------|---------|
| fast | DeepSeek | $0.00014 |
| code | DeepSeek | $0.00014 |
| medium | DeepSeek | $0.00014 |
| strong | Claude Sonnet 4 | $0.015 |
| premium | Claude Opus 4 | $0.075 |

## Commands

```
ask <msg>      Chat with LLM
audit [ref]    Compare features vs git history
cat <file>     View file
cd <dir>       Change directory
clean <file>   Fix CRLF, trim whitespace
clear          Clear chat history
converge       Iterate until no changes
cost           Show LLM cost
describe <img> Describe image (Replicate)
edit <file>    Edit file
help           Show help
image <prompt> Generate image (Replicate)
ls             List files
persona <name> Switch persona
personas       List personas
principles     List principles
refactor <path> Auto-refactor with research
review <path>  Multi-agent code review
scan <path>    Scan for issues
status         Show status
tree           Show file tree
version        Show version
web <url>      Browse URL
exit           Quit
```

## Web Interface

```bash
ruby bin/cli
# Server starts automatically
# Open cli.html for orb interface
# DEMOS/ contains 60+ audio-reactive visualizations
```

## Cross-Platform

openbsd0 at mainbus0 | termux0 at mainbus0 | darwin0 at mainbus0 | linux0 at mainbus0

## Environment

```bash
OPENROUTER_API_KEY    # Required
REPLICATE_API_TOKEN   # For image generation
```

---

*Delete until it hurts, then delete some more.*
