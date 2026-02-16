# MASTER2 — Constitutional AI Code Quality System

Any LLM working in this repository must read, internalize, and follow MASTER2.

## System Architecture at a Glance

MASTER2 is a self-enforcing constitutional AI system that validates and improves code against 68 axioms. The data flow is:

```
User Input → Pipeline → Executor → LLM → Output
             ↓          ↓         ↓
          Stages     Patterns  CircuitBreaker
             ↓          ↓         ↓
          Guard      Tools    RateLimit
             ↓          ↓         ↓
          Council    Context  Logging
```

**Boot Flow:** `boot.rb` → loads `master.rb` → initializes `DB`, `LLM`, `Pipeline`, `Executor`

**Request Flow:** `Pipeline.call(input)` → `Stages` (intake, guard, route, council, ask, lint, render) → `Executor` (React/PreAct/ReWOO/Reflexion patterns) → `LLM.ask` → `CircuitBreaker.run` → `ruby_llm` API call

**Data Sources:** `data/*.yml` (constitution, axioms, council, language rules, patterns) are the single source of truth. No hardcoded fallbacks.

## File Responsibilities & Axiom Categories

| File | Responsibility | Primary Axioms | Lines |
|------|---------------|----------------|-------|
| `lib/master.rb` | Module loader, namespace | PRESERVE_THEN_IMPROVE_NEVER_BREAK | 100 |
| `lib/boot.rb` | System initialization, banner | FAIL_VISIBLY | 98 |
| `lib/pipeline.rb` | Request orchestration | ONE_JOB, REFLOW | 213 |
| `lib/executor.rb` | Multi-pattern execution | PATTERNS_OVER_PROCEDURES | 290 |
| `lib/llm.rb` | OpenRouter API client | CIRCUIT_BREAKER, GUARD_EXPENSIVE | 206 |
| `lib/db_jsonl.rb` | JSONL database (axioms, council) | ONE_SOURCE | 209 |
| `lib/session.rb` | Conversation state | AUTOSAVE | 222 |
| `lib/result.rb` | Railway monad | EXPLICIT | 124 |
| `lib/circuit_breaker.rb` | Failure handling, rate limits | DEADLINES | 145 |
| `lib/logging.rb` | Unified logging (dmesg-style) | FAIL_VISIBLY | 257 |
| `lib/stages.rb` | Pipeline stages (guard, lint) | GUARD, LINT_BEFORE_SHIP | 315 |
| `lib/ui.rb` | Terminal UI, colors, spinners | UI_CONSISTENCY | 280 |
| `lib/council.rb` | Adversarial review (12 personas) | COUNCIL_REVIEW | 198 |
| `lib/shell.rb` | Safe command execution | GUARD | 135 |
| `data/constitution.yml` | Golden rule, constraints | SELF_APPLY | 297 |
| `data/axioms.yml` | 68 axioms across 11 categories | ALL | 2100 |
| `data/council.yml` | 12 personas, 3 veto holders | COUNCIL_REVIEW | 234 |

## Three Most Critical Axioms for Any Change

1. **PRESERVE_THEN_IMPROVE_NEVER_BREAK** — Never delete working code. Never break existing behavior. Improve surgically.
2. **SELF_APPLY** — MASTER2 must obey its own rules. All changes to `MASTER2/` itself must pass its own validators.
3. **FAIL_VISIBLY** — Never swallow exceptions silently. Always log errors. No `rescue nil`, no bare `rescue`.

## Core files (read in order)

1. `data/constitution.yml` — golden rule, convergence, anti-sprawl, constraints, detectors
2. `data/axioms.yml` — 68 axioms across 11 categories (every code change must satisfy relevant axioms)
3. `data/language_axioms.yml` — detection rules and philosophy for ruby, rails, zsh, html, css, js
4. `data/zsh_patterns.yml` — banned commands, auto-remediation, token economics
5. `data/openbsd_patterns.yml` — service management, forbidden commands, platform mappings
6. `data/council.yml` — 12 adversarial personas (3 have veto power)
7. `data/quality_thresholds.yml` — minimum quality scores and enforcement levels

## Golden rule

PRESERVE_THEN_IMPROVE_NEVER_BREAK

Never delete working code. Never break existing behavior. Improve surgically.

## Platform

OpenBSD 7.8, Ruby 3.4, zsh. No python, no bash, no awk, no sed, no sudo, no find, no wc, no head, no tail. Use doas, rcctl, pkg_add. Pure zsh parameter expansion for all string and array operations.

## Architecture

Deploy scripts in `deploy/` contain Ruby/Rails apps embedded in zsh heredocs. This is the single source of truth. Edit in-place with atomic precision. Never extract heredoc content to separate files.

Rails apps use Hotwire, Turbo, Stimulus, Solid Queue. Monolith first. Convention over configuration.

## Banned patterns

- `rescue nil` — always rescue specific exceptions
- File sprawl — never create summary.md, analysis.md, report.md, todo.md, notes.md, changelog.md
- ASCII decoration comments (`# ====`, `# ----`, `# ****`)
- Comments that restate the code
- Files over 300 lines (split along module boundaries)
- Trailing whitespace
- More than 2 consecutive blank lines

## Communication style

OpenBSD dmesg-inspired. Terse, factual, evidence-based. No filler, no hedging, no unnecessary formatting. Show what changed and why.

## How to apply

Before modifying any file in this repository:
1. Check which axioms apply to the change
2. Check language_axioms.yml for language-specific rules
3. Verify the change preserves existing behavior
4. Verify no banned patterns are introduced
5. Keep files small, comments minimal, code self-documenting
