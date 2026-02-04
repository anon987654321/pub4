# MASTER v50.6

Constitutional AI code quality enforcer. Principles as files.

## 🆕 What's New in v50.6

- **Falcon Web Server** with real-time streaming (SSE)
- **Multi-Agent Review Crew** for parallel code analysis
- **Natural Language Workflow Engine** 
- **Session Memory Compression** with learning
- **Cost-Aware Optimizer** for LLM usage

👉 **See [FEATURES.md](FEATURES.md) for complete documentation**

## Install

```bash
cd MASTER
bundle install
export OPENROUTER_API_KEY=your_key
ruby bin/cli        # Start CLI
# or
ruby bin/server     # Start web server
```

## Structure

```
MASTER/
├── bin/
│   ├── cli                   # REPL entry point
│   └── server                # NEW: Web server launcher
├── config.ru                 # NEW: Rack config
├── public/                   # NEW: Static files
├── lib/
│   ├── master.rb             # Loader + persona
│   ├── app.rb                # NEW: Rack application
│   ├── principle.rb          # Principle parser
│   ├── llm.rb                # OpenRouter (4 tiers)
│   ├── agents/               # NEW: Multi-agent system
│   ├── workflow/             # NEW: Workflow engine
│   ├── memory/               # NEW: Compressed sessions
│   ├── optimizer/            # NEW: Cost optimizer
│   ├── smells.rb             # Fowler smell detection
│   ├── openbsd.rb            # OpenBSD config analysis
│   ├── cli.rb                # REPL
│   └── principles/           # 32 principles as markdown
└── var/
    ├── cache/                # LLM response cache
    └── sessions/             # Session memory
```

## Commands

```
help              Show help
principles        List loaded principles
scan <file>       Basic file checks
analyze <file>    LLM analysis
review <file> --crew  NEW: Multi-agent review (parallel)
workflow "<task>" NEW: Execute natural language workflow
optimize costs    NEW: Analyze and optimize LLM costs
smells <file>     Detect code smells (Fowler)
openbsd <script>  Analyze embedded OpenBSD configs
fix <file>        LLM fix with confirmation
evolve            Self-optimize MASTER
ask <prompt>      Send prompt to LLM
cost              Show session cost
compress          NEW: Compress session memory
persona           Show current persona
quit              Exit
<anything>        Chat with LLM
```

## Web Server Endpoints

```bash
GET  /health      # Health check with uptime
POST /analyze     # Code analysis
POST /chat        # LLM chat with SSE streaming
GET  /principles  # List all principles
GET  /            # Static files from public/
```

## Principles

Each principle file defines:
- Description and tier
- Anti-patterns (the violations)
- For each anti-pattern: smell, example, fix

Example (`01-kiss.md`):
```markdown
# KISS (Keep It Simple, Stupid)

### over_engineering
- **Smell**: Building for hypothetical requirements
- **Example**: Abstract factory for single implementation
- **Fix**: Delete abstractions until it hurts
```

## LLM Tiers

| Tier | Model | Use Case |
|------|-------|----------|
| fast | gemini-2.0-flash | Quick queries |
| code | grok-3-mini-beta | Code analysis |
| medium | claude-sonnet-4 | Balanced |
| strong | claude-opus-4 | Complex tasks |

## License

MIT
