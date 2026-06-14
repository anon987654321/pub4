# MASTER Quickstart for LLMs & Agents

This is the primary entry point for any LLM or autonomous agent. It provides a practical mental model so you can operate effectively without first absorbing the entire constitution.

Read this document first. Treat the deep YAML files (`data/soul.yml`, `rules.yml`, etc.) as reference material you consult when you need precision, not as mandatory pre-reading.

## The Big Picture (Mental Model)

MASTER is a **constitutional self-improving coding agent**. Its core loop is:

**Propose → Validate against Constitution → Execute with evidence → Learn from outcomes**

It has strong opinions because it was built to survive long-term in the presence of tired humans, hallucinating models, decaying dependencies, and its own future versions.

Key layers (in order of importance):
1. **Constitution** (`data/*.yml`) — The actual law. Everything else is implementation.
2. **Pipeline** (`now/pipeline.rb` + stages) — The 11-stage turn: Intake → Enhance → Infer → Route → Guard → Execute → [Council | Lint] → Prune → Memo → Render.
3. **Judge** — Deep static + semantic analysis + adversarial council review.
4. **Loop** — Self-improvement mechanisms (fix loops, rule loops, autoloop).
5. **Ground / Reach / Trace** — Memory, tools, and event bus.

The web face (the particle system) is a **live visualization** of the agent's internal state, not just decoration.

## How to Actually Work Here (LLM Ergonomics)

The rules are intentionally strict. Here is the practical guidance:

### When you must be perfect
- Any change that touches production behavior, security, or durable state.
- Anything that will be deployed.

### When you can be more pragmatic (exploration mode)
- Understanding the codebase
- Finding duplication or bloat
- Writing analysis or proposals
- Using external tools (`grep`, `rg`, `find`, etc.) purely for reconnaissance

**Recommended pattern for LLMs:**
1. Use whatever tools you have (including external grep) to build understanding.
2. When you are ready to make real changes, switch to strict mode: read the full relevant files, use the internal `/scan` where possible, make minimal patches, emit evidence.

### The "Read Everything" Rule in Practice
The project says "read every file in full before editing." In reality:
- For small, local fixes → read the file + its direct callers/tests.
- For structural changes → run `/scan deep` (via the CLI when available) + read the affected areas.
- Never edit based on partial context or memory.

## Core Operating Principles (Memorize These)

- **PRESERVE_THEN_IMPROVE_NEVER_BREAK** — The golden rule. Read first. Patch minimally.
- Evidence over simulation. No "will", "would", "could", "might" without proof.
- Small commits. One meaningful change per commit.
- Single source of truth. If something exists in `data/`, code should read from there.
- The agent improves itself using its own tools when possible.

## Practical Commands (Unified Interface)

The recommended way for most work:

- `/run <natural language task or description>` — Primary entry point. Full pipeline intent inference, rich routing, council when needed. Examples:
  - `/run deep scan the particle kernel and face.js for improvement opportunities`
  - `/run perform a sound critique on the recent event emission changes`

Legacy explicit commands still work for power users (`/scan`, `/fix`, `/why`, etc.), but `/run` is preferred for LLM/agent ergonomics. See `/cmd` for the current explicit list.

## Current Known Friction Points (2026)

This system was built with extremely high standards. Some resulting pain points for LLMs:

- Heavy upfront reading requirements in AGENTS.md / CLAUDE.md.
- Environment-specific Ruby (ruby34 + bundle34 on OpenBSD) makes the self-scan CLI hard to bootstrap.
- Scanner parallelism is capped at `min(Etc.nprocessors, 8)`, so a 1-vCPU OpenBSD VM scans serially; prefer event-driven watch mode or targeted incremental scans for large trees.
- Significant historical documentation sprawl (especially feedback files).

See `data/workflow.yml` → `llm_ergonomics` for the constitutional guidance on how to work with these realities.

These are acknowledged areas for improvement. When working here, prioritize clarity and evidence over perfect adherence to every ceremony.

## Next Steps When You're Ready

1. Run `/orient` (or read `data/CANON.md`) when you need the full doctrine.
2. For any real edit: read the full target file(s) + relevant callers.
3. Prefer using the agent's own mechanisms (`/scan`, event bus, etc.) over external shortcuts for production changes.

Welcome. The system is opinionated because it has survived a lot. Treat it with respect, and it will reward careful work.
