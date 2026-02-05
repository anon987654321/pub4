# MASTER v50.9

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
chamber <file>  Multi-model deliberation on code
queue <dir>     Add directory to refactor queue
introspect      Hostile question all principles
sanity <plan>   Pre-action sanity check
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

## Chamber RAG

Multi-model deliberation system. After refactoring a file, send it to an "echo chamber" of top models. Each model proposes changes and defends them. The arbiter cherry-picks the best.

### Code Chamber

```ruby
chamber = MASTER::Chamber.new(llm)
result = chamber.deliberate("lib/cli.rb")
# => Models propose diffs + write letters defending changes
# => Arbiter (sonnet) picks winner
```

Models: sonnet (arbiter), gpt-4o, gemini-2.0-flash, deepseek-chat, qwen-coder

### Creative Chamber

```ruby
chamber = MASTER::CreativeChamber.new(llm, replicate)

# Brainstorm ideas
result = chamber.brainstorm("App for connecting elderly with volunteers")

# Image variations from multiple models
result = chamber.image_variations("Norwegian fjord at sunset, cinematic")

# Video storyboard
result = chamber.video_storyboard("30-second ad for volleyball team", scenes: 4)

# Simulated conversation
result = chamber.simulate_conversation(
  "Debate about AI regulation",
  roles: [
    { name: "Tech CEO", model: :gpt4, perspective: "Innovation-first" },
    { name: "Policy Maker", model: :sonnet, perspective: "Public safety" }
  ],
  turns: 5
)
```

## Introspection

LLM self-examination at end of each phase. Hostile questioning for all principles.

```ruby
intro = MASTER::Introspection.new(llm)

# End-of-phase reflection
intro.reflect_on_phase(:implement, "Refactored 5 files, added tests")

# Hostile question a principle
intro.hostile_question("DRY: Don't Repeat Yourself")
# => "What assumption here could be completely wrong?"

# Audit all principles
intro.audit_principles(Paths.principles)

# Pre-action sanity check
intro.sanity_check("Delete all .bak files recursively")
# => Is this reversible? What's the worst case?

# Self-review generated code
intro.review_own_code(code, "API rate limiter")
```

## Environment

```bash
OPENROUTER_API_KEY    # Required
REPLICATE_API_TOKEN   # For image generation
```
