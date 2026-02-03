# master.yml LLM OS v49.1

LLM-powered code quality analysis against 32 coding principles.

## Quick Start

```bash
export OPENROUTER_API_KEY="your-key"
ruby cli.rb .                    # analyze everything
ruby cli.rb --quick .            # fast scan (5 core principles)
ruby cli.rb --watch .            # watch mode
ruby cli.rb --garden-full        # self-improve constitution
```

## Features

| Feature | Description |
|---------|-------------|
| **Tiered Pipeline** | Fast (Qwen) → Medium (Sonnet) → Strong (Claude Opus 4) |
| **Progressive Disclosure** | Compact principle summaries for 60% token savings |
| **Prompt Caching** | System prompts cached 1h (75-90% savings) |
| **Parallel Detectors** | Concurrent smell scans |
| **Reflection Critic** | Validates fixes before applying |
| **Pattern Memory** | Remembers fix success rates |
| **Model Cooldowns** | Auto-skips rate-limited models (5min cooldown) |
| **Principle Profiles** | `--quick`, `--profile critical` for focused scans |
| **Cost Tracking** | Cross-session JSONL cost reports |
| **Hook System** | Event-driven extensibility |
| **Skill System** | Modular skills in `~/.constitutional/skills/` |
| **Gardener** | `--garden` / `--garden-full` self-improves |
| **Watch Mode** | `--watch` auto-reanalyze on save |
| **NO_COLOR Support** | Respects terminal preferences |

## Commands

```bash
# Basic usage
ruby cli.rb file.rb              # single file
ruby cli.rb src/                 # directory (recursive)
ruby cli.rb **/*.rb              # glob pattern
ruby cli.rb .                    # current directory

# Output modes
ruby cli.rb --json .             # JSON output for CI/CD
ruby cli.rb --quiet .            # minimal output (exit code only)

# Filtering
ruby cli.rb --git-changed        # only git-modified files
ruby cli.rb --quick .            # fast mode (5 principles)
ruby cli.rb --profile critical   # critical issues only

# Performance
ruby cli.rb --no-cache .         # skip cache, always query LLM
ruby cli.rb --no-parallel .      # disable parallel detection

# Watch & gardening
ruby cli.rb --watch .            # watch mode
ruby cli.rb --garden             # review learned smells
ruby cli.rb --garden-full        # full self-improvement

# Utilities
ruby cli.rb --cost               # show LLM spending (daily/weekly)
ruby cli.rb --rollback file.rb   # restore from backup
ruby cli.rb --help               # show help
ruby cli.rb --version            # show version
```

## Profiles

| Profile | Principles | Use Case |
|---------|------------|----------|
| `full` | All 32 | Complete analysis (default) |
| `quick` | 5 core | Fast CI checks |
| `axioms_only` | 10 | Foundational principles |
| `solid_focus` | 15 | SOLID + axioms |
| `critical` | 7 | Security/stability issues |

## Safety

- 🔒 **File locking** - concurrent-safe with stale lock detection
- ↩️ **Transactional rollback** - `.constitutional_backups/` (keeps 5)
- 💰 **Cost protection** - $1/file, $10/session limits with warnings
- 🔄 **Convergence detection** - stops loops and oscillations
- ⚖️ **Priority-aware** - won't introduce higher-priority violations
- 🧠 **Reflection critic** - rejects risky fixes
- ❄️ **Model cooldowns** - auto-skip rate-limited APIs (5min)
- 🛡️ **File validation** - binary detection, symlink protection, size limits

## Cross-Platform

✅ OpenBSD | ✅ Termux | ✅ macOS | ✅ Linux | ✅ Windows/Cygwin

Auto-installs dependencies via gem with `--user-install` fallback.

## Architecture

```
cli.rb ⟷ master.yml (symbiotic pair)

Core (pure functions):
  PrincipleRegistry   - principle lookup and filtering
  LLMDetector         - violation detection with progressive disclosure
  ScoreCalculator     - scoring and analysis
  SkillLoader         - modular skill system
  Hooks               - event-driven extensibility
  ModelCooldown       - rate limit tracking
  CostTracker         - cross-session cost persistence
  CostEstimator       - token/cost estimation
  ConvergenceDetector - loop and oscillation detection
  FixValidator        - priority-aware fix validation

Shell (IO/state):
  Constitution        - YAML loader with profile support
  LLMClient           - OpenRouter API with fallback
  TieredLLM           - fast/medium/strong pipeline
  ParallelDetector    - concurrent smell scanning
  Gardener            - self-improvement engine
  ReflectionCritic    - fix validation before apply
  PatternMemory       - fix success rate tracking
```

## 32 Principles

| Tier | Priority | Principles |
|------|----------|------------|
| **Axioms** | 10 | Clarity, Simplicity, Explicit, Scientific, Divide & Conquer |
| **SOLID** | 7-8 | SRP, OCP, LSP, ISP, DIP |
| **Coding** | 5-7 | DRY, WET, AHA (with conflict resolution) |
| **Clean Code** | 6-7 | Names, Small Functions, Few Args, CQS, No Side Effects |
| **UI** | 5-6 | Progressive Disclosure, Real-Time Feedback |
| **LLM** | 6-9 | Cost Transparency, Fail Gracefully, Cache Aggressively |
| **Operations** | 9-10 | Idempotent, Safe Refactoring |
| **Architecture** | 9 | Functional Core / Imperative Shell |

## Hooks

Event-driven extensibility via `master.yml`:

```yaml
hooks:
  on_violation_found:
    - action: "log"
      path: ".constitutional_violations.jsonl"
  on_cost_threshold:
    - action: "warn"
      message: "Cost limit approaching"
  on_convergence_stuck:
    - action: "pause"
      message: "Review and press Enter..."
```

**Events:** `before_scan`, `after_scan`, `before_fix`, `after_fix`, `violation_found`, `fix_applied`, `fix_rejected`, `iteration_start`, `iteration_end`, `cost_threshold`, `file_start`, `file_end`, `convergence_stuck`, `gardener_run`

**Actions:** `log` (JSONL), `warn` (console), `pause` (interactive)

## Skills

Modular skills in `~/.constitutional/skills/` or `./skills/`:

```yaml
# skills/my-skill/SKILL.yml
name: "My Custom Skill"
description: "Does something cool"
version: "1.0"
priority: 50
stages: [pre-scan, detection]
```

## Environment

```bash
OPENROUTER_API_KEY       # required for AI features
VERBOSE=1                # debug mode (detailed logs)
NO_COLOR=1               # disable colors
CONSTITUTIONAL_MINIMAL=1 # minimal boot output
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (100/100 score) |
| 1 | Violations found |
| 2 | Fatal error |

## Files Generated

| File | Purpose |
|------|---------|
| `.constitutional_backups/` | Rollback backups (keeps 5) |
| `.constitutional_locks/` | File locks for concurrency |
| `.constitutional_costs.jsonl` | Cross-session cost tracking |
| `.constitutional_history.json` | Analysis history |
| `.constitutional_memory.json` | Pattern memory (fix success rates) |
| `.constitutional_violations.jsonl` | Violation log (if hook enabled) |

## CI/CD Integration

```yaml
# GitHub Actions
- name: master.yml LLM OS Check
  run: |
    ruby cli.rb --json --quiet . > results.json
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
      echo "Violations found"
      cat results.json
      exit 1
    fi
```

## Starship Integration

Add to `~/.config/starship.toml`:

```toml
[custom.constitutional]
command = "ruby cli.rb --quiet --quick . && echo '✓' || echo '✗'"
when = "test -f cli.rb"
format = "[$output]($style) "
style = "green"
```

---

*May your code be clean and your merge conflicts few.*
