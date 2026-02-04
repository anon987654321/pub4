# MASTER v50.5

Constitutional AI code quality enforcer. Principles as files.

## Install

```bash
cd MASTER
bundle install
export OPENROUTER_API_KEY=your_key
ruby bin/cli
```

## Structure

```
MASTER/
├── bin/cli                   # REPL entry point
├── lib/
│   ├── master.rb             # Loader + persona
│   ├── principle.rb          # Principle parser
│   ├── llm.rb                # OpenRouter (4 tiers)
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
smells <file>     Detect code smells (Fowler)
openbsd <script>  Analyze embedded OpenBSD configs
fix <file>        LLM fix with confirmation
evolve            Self-optimize MASTER
ask <prompt>      Send prompt to LLM
cost              Show session cost
persona           Show current persona
quit              Exit
<anything>        Chat with LLM
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
