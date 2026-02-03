# Constitutional AI v48.2

LLM-powered code quality analysis against 32 coding principles.

## Quick Start

```bash
export OPENROUTER_API_KEY="your-key"
ruby cli.rb .                    # analyze everything
ruby cli.rb --watch .            # watch mode
ruby cli.rb --garden-full        # self-improve constitution
```

## Features

| Feature | Description |
|---------|-------------|
| **Tiered Pipeline** | Fast (Qwen) → Medium (Sonnet) → Strong (Claude Opus 4) |
| **Prompt Caching** | System prompts cached 1h |
| **Parallel Detectors** | Concurrent smell scans |
| **Reflection Critic** | Validates fixes before applying |
| **Pattern Memory** | Remembers fix success rates |
| **Gardener** | `--garden` / `--garden-full` self-improves |
| **Watch Mode** | `--watch` auto-reanalyze on save |
| **NO_COLOR Support** | Respects terminal preferences |

## Commands

```bash
ruby cli.rb file.rb              # single file
ruby cli.rb src/                 # directory
ruby cli.rb --json **/*.rb       # CI mode
ruby cli.rb --watch .            # watch mode
ruby cli.rb --garden             # review learned smells
ruby cli.rb --garden-full        # full self-improvement
ruby cli.rb --cost               # show LLM spending
ruby cli.rb --rollback file.rb   # restore backup
```

## Safety

- 🔒 File locking (concurrent-safe)
- ↩️ Transactional rollback (`.constitutional_backups/`)
- 💰 Cost protection ($1/file, $10/session)
- 🔄 Convergence detection (stops loops)
- ⚖️ Priority-aware (won't make things worse)
- 🧠 Reflection critic (rejects risky fixes)

## Cross-Platform

✅ OpenBSD | ✅ Termux | ✅ macOS | ✅ Linux | ✅ Windows/Cygwin

## Architecture

```
cli.rb ⟷ master.yml (symbiotic pair)

Core (pure functions):
  PrincipleRegistry, LLMDetector, ScoreCalculator, SkillLoader

Shell (IO/state):
  Constitution, LLMClient, TieredLLM, ParallelDetector, Gardener
  ReflectionCritic, PatternMemory
```

## 32 Principles

1. **Axioms** (P10): Clarity, Simplicity, Explicit > Implicit
2. **SOLID** (P7-8): SRP, OCP, LSP, ISP, DIP
3. **Clean Code** (P6-7): Names, Small Functions, CQS
4. **Operations** (P9): Idempotent, Safe Refactoring

## Environment

```bash
OPENROUTER_API_KEY       # required for AI
VERBOSE=1                # debug mode
NO_COLOR=1               # disable colors
CONSTITUTIONAL_MINIMAL=1 # minimal boot output
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (100/100 score) |
| 1 | Violations found |
| 2 | Fatal error |

## Starship Integration

Add to `~/.config/starship.toml`:

```toml
[custom.constitutional]
command = "ruby cli.rb --quiet . && echo ok || echo fail"
when = "test -f cli.rb"
```

---

*May your code be clean and your merge conflicts few.*
