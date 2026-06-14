# AGENTS.md

Bootstrap for autonomous coding agents (Claude Code, Cursor, Aider, Codex, Continue).

**Primary entry point:** Read `MASTER/QUICKSTART.md` first. It provides a practical mental model and LLM ergonomics guidance (see `data/workflow.yml` → `llm_ergonomics` for constitutional details) without forcing you to swallow the entire constitution upfront.

Only after you have a working model should you dive into the deep sources:
- `MASTER/data/soul.yml`
- `data/rules.yml`, `ruby_style.yml`, `workflow.yml`, `standing_orders.yml`
- `CLAUDE.md` (operator environment, SSH, deploy details)

Current MASTER module layout under `MASTER/lib/`:
- `now/` — pipeline, CLI, command registry, routing
- `loop/` — fix loop, rule loop, watch loop, convergence
- `judge/` — scanner, AST fixer, council, swarm, security, embeddings
- `voice/` — personality, renderer, TTS, soul drift, expression
- `ground/` — constitution, rules, memory, config, contracts, provider registry, axioms
- `reach/` — file I/O, git, shell, LLM, web, search, semantic cache
- `trace/` — event bus, telemetry, audit log, session, undo, why-explainer

Read every file in full before editing. Match surrounding style. Run `/scan deep <path>` inside MASTER before structural changes.

After editing `web/` files: `doas rcctl restart master` — Falcon does not hot-reload.

Key commands: `/scan`, `/fix`, `/review`, `/critique`, `/why`, `/snapshot`. Type `/help` inside MASTER for the full list.
