# MASTER v50.8

Constitutional AI code quality enforcer with advanced memory, automation, and self-improvement.

## ✨ New in v50.8

**8 Advanced Features:**
1. 🧠 **Git-Backed Memory** - Long-term decision tracking with pattern learning
2. ⚡ **Smart Pre-Commit Hooks** - Fast cached analysis (<100ms for commits)
3. 🎤 **Voice-to-Code Interface** - Hands-free analysis via voice commands
4. 🧪 **Automatic Test Generation** - Generate RSpec tests from violations
5. 📊 **Knowledge Graph** - Visualize violations and relationships
6. ⚖️ **Conflict Resolution** - Smart handling when principles contradict
7. 🤖 **Principle Agents** - Specialized refactoring agents (DRY, SRP, KISS, Perf)
8. 🔄 **Meta-Evolution** - MASTER improves its own code

**See [FEATURES_v50.8.md](FEATURES_v50.8.md) for complete documentation.**

---

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
│   ├── principles/           # 32 principles as markdown
│   ├── memory/               # NEW: Git-backed memory
│   ├── git/                  # NEW: Smart hooks
│   ├── voice/                # NEW: Voice interface
│   ├── test_gen/             # NEW: Test generation
│   ├── graph/                # NEW: Knowledge graph
│   ├── conflicts/            # NEW: Conflict resolution
│   ├── agents/               # NEW: Principle agents
│   └── evolution/            # NEW: Meta-evolution
└── var/
    ├── cache/                # LLM response cache
    ├── sessions/             # Session memory
    └── evolution.yml         # Self-improvement tracking
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

# New in v50.8
memory <cmd>      Git-backed memory (search, patterns, sync)
hooks <cmd>       Smart pre-commit hooks (install, test, uninstall)
voice             Voice-to-code interface
graph [--output]  Generate knowledge graph
agent <type>      Run principle agents (dry, solid_srp, kiss, perf)
meta-evolve       Self-improvement for MASTER
test-coverage     Show test coverage by principle

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
