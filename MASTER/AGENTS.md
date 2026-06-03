# AGENTS.md

Guidance for AI coding agents working in this repository.

## Module layout

Seven modules under `lib/`:

| Module | Path | Responsibility |
|--------|------|----------------|
| now | lib/now/ | Pipeline (11 stages), CLI, command registry, routing |
| loop | lib/loop/ | Fix loop, rule loop, watch loop, convergence |
| judge | lib/judge/ | Scanner, AST fixer (Prism), council, swarm, security, embeddings |
| voice | lib/voice/ | Personality, renderer, TTS (Edge TTS), soul drift, expression |
| ground | lib/ground/ | Constitution, rules, memory, config, tool contracts, provider registry, axioms |
| reach | lib/reach/ | File I/O, git, shell, LLM, web, search, semantic cache |
| trace | lib/trace/ | Event bus, telemetry, audit log, session, undo, why-explainer |

## Pipeline

Eleven stages: Intake → Enhance → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render. Council and Lint run as `ParallelGroup` with a 30s timeout. The pipeline is a `Result` monad — each stage returns `Result.ok(ctx)` or `Result.err(...)` and short-circuits on error.

## Conventions

- `# frozen_string_literal: true` on every `.rb`
- Double-quoted strings
- No bare `rescue` — always `rescue StandardError => e`
- No god classes (>300 lines / >10 public methods)
- Guard clauses before main logic
- CQS — queries return, commands mutate, never both
- Endless methods for single expressions: `def foo = expr`
- Max 3 positional params; keyword args beyond that
- Max 2 nesting levels inside a method

## Authority order

`data/soul.yml` > `data/rules.yml` > `CLAUDE.md` > this file.

## Key entry points

- CLI: `bin/cli`
- Web face: `web/` (Falcon on port 53187)
- Constitution: `data/soul.yml`
- Rules: `data/rules.yml` (173 rules, single source of truth)
