# MASTER v50.8

Constitutional AI for code quality. 33 principles, modular Ruby architecture.

## Quick Start

```bash
export OPENROUTER_API_KEY="your-key"
ruby bin/cli
```

## Boot

```
master 50.8 (GENERIC) #1: Wed Feb  5 02:50:00 UTC 2026
const0 at master0: 33 principles, 74 smells
llm0 at openrouter0: deepseek-chat
root0: /home/dev/pub
openbsd0 at mainbus0
boot time: 140ms
```

## Architecture

```
bin/cli                    # Entry point
lib/
  master.rb                # Module loader (autoload)
  paths.rb                 # Centralized path management
  result.rb                # Ok/Err monad
  llm.rb                   # 5-tier OpenRouter client
  principle.rb             # YAML principle parser
  persona.rb               # YAML persona parser
  boot.rb                  # dmesg-style startup
  cli.rb                   # REPL with 30+ commands
  server.rb                # Falcon web server
  engine.rb                # Code scanner
  converge.rb              # Convergence detection
  smells.rb                # Code smell patterns
  safety.rb                # Dangerous command blocklist
  memory.rb                # Session compression
  replicate.rb             # Image/audio generation
  web.rb                   # Headless browser (Ferrum or curl)
  openbsd.rb               # Config validation + pledge/unveil
  principles/              # 33 principle .yml files
  personas/                # Persona .yml files
test/
  test_master.rb           # Test suite
DEMOS/
  orb01-20.html            # Audio-reactive orb visualizations
```

## Commands

```
ask <msg>       Chat with LLM
cat <file>      View file (alias: read)
cd <dir>        Change directory
clean <file>    Fix CRLF, trim whitespace
clear           Clear chat history
commit [msg]    Git commit
cost            Show LLM cost
diff            Git diff
edit <file>     Edit file
git <cmd>       Run git command
help            Show help
image <prompt>  Generate image (Replicate)
log             Git log
ls              List files
persona <name>  Switch persona
personas        List personas
principles      List principles
pull            Git pull
push            Git push
refactor <path> Auto-refactor with research
refine [path]   Suggest micro-refinements, cherry-pick
review <path>   Multi-agent code review
scan <path>     Scan for issues
smells <path>   Detect code smells
status          Show status
version         Show version
web <url>       Browse URL
exit            Quit
```

## LLM Tiers

| Tier | Model | Cost/1K |
|------|-------|---------|
| fast | deepseek-chat | $0.00014 |
| code | deepseek-chat | $0.00014 |
| medium | deepseek-chat | $0.00014 |
| strong | claude-sonnet-4 | $0.015 |
| premium | claude-opus-4 | $0.075 |

## Test

```bash
ruby test/test_master.rb
```

## Cross-Platform

openbsd0 | termux0 | darwin0 | linux0 | win0

## Environment

```bash
OPENROUTER_API_KEY    # Required
REPLICATE_API_TOKEN   # For image generation
```
