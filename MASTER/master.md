# MASTER — Reference

## Pipeline stages

| Stage | Role |
|---|---|
| Intake | Normalize input, detect channel (CLI/web/IRC/Matrix) |
| Infer | NLP → command routing via infer_patterns.yml |
| Route | Select model tier, tool, or pipeline branch |
| Guard | Axiom enforcement; abort on violation |
| Execute | LLM call, tool dispatch, or command handler |
| Council | Adversarial multi-persona review (parallel) |
| Lint | Scan output for rule violations (parallel) |
| Prune | Strunk & White prose pass; trim verbosity |
| Memo | Write to memory, learnings, audit log |
| Render | Format and emit to source channel |

## Scan rules

| Rule | Checks |
|---|---|
| FROZEN_STRING | Missing `# frozen_string_literal: true` |
| EXPLICIT | Bare rescue, implicit returns, shadow variables |
| IMMUTABLE | Mutable constants, shared mutable state |
| CQS | Methods that command and query simultaneously |
| SRP | Classes with multiple responsibilities |
| SELF_EXPLAINING | Unclear names, missing intent |
| LONG_METHOD | Methods over ~20 lines |
| GOD_CLASS | Files over ~300 lines with too many concerns |
| DUPLICATE | Copy-paste code blocks |
| BARE_RESCUE | `rescue` without error variable |

## Models

Default: `nvidia/nemotron-3-super-120b-a12b:free`

Fallback chain: qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash

Circuit breaker: FAILURE_THRESHOLD=8, RATE_MAX=60/min.

## Constitution

Golden rule: **PRESERVE_THEN_IMPROVE_NEVER_BREAK**

Kernel axioms (violation aborts pipeline):
- PRESERVE_FIRST
- SIMPLEST_WORKS
- FAIL_VISIBLY
- ONE_SOURCE
- DECOUPLE
- GUARD_EXPENSIVE
- DEGRADE_GRACEFULLY
- BE_CONCISE

## Evolution Protocol

1. `soul propose <rationale>` — LLM drafts amendment
2. `soul diff` — review changes
3. `soul approve` — bump version, commit, tag
4. `soul reject` — discard

ABSOLUTE sections (anti-simulation rule, golden rule) block without `/override`.
