# pub4

A collection of autonomous systems and AI tools.

## MASTER2 - Constitutional AI Code Quality System

The main project in this repository. An AI that reviews its own code, argues with itself, and ships the result.

**[→ Full documentation in MASTER2/README.md](MASTER2/README.md)**

## Quick Start

```sh
cd MASTER2
bundle install
export OPENROUTER_API_KEY="your-key-here"
./bin/master refactor lib/session.rb
```

MASTER2 reads your code, runs it through twelve adversarial personas, enforces thirty-two axioms from Clean Code and The Pragmatic Programmer, and writes the fix.

## What It Does

- **Autonomous refactoring** - LLM-guided code improvements with consensus voting
- **Constitutional governance** - 32 timeless axioms from authoritative sources
- **Council deliberation** - 12 adversarial personas with veto power
- **Four reasoning patterns** - ReAct, PreAct, ReWOO, Reflexion
- **Self-improvement** - Runs itself through its own refactoring engine
- **OpenBSD-first** - Built for security and simplicity

## Key Features

- ✅ Zero violations tolerance - Enforces its own standards
- ✅ Budget limits - $10 session cap prevents runaway costs
- ✅ Circuit breaker - Auto-stops after failures
- ✅ Rollback safety - Validates before applying changes
- ✅ Result monad - No exceptions, explicit error handling
- ✅ Ruby-native - No system dependencies

## Version

**v1.0.0** - Stable release after architectural consolidation

All file sprawl eliminated. Regex removed from axioms. Ruby tree walker. Single README documentation.

## License

MIT License

---

**Everything you need is in [MASTER2/](MASTER2/)**
