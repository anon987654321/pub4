# Agents

This file bootstraps coding agents—Cursor, Claude Code, Codex, Aider, and similar tools—into the MASTER workspace.

Read `QUICKSTART.md` first for the mental model and ergonomics. For VPS, SSH, deploy, and domains, use `DEPLOY/OPERATOR.md`. When editing production paths, consult `data/soul.yml` and `data/rules.yml`. Authority order is `data/soul.yml`, then `data/rules.yml`, then `CONVENTIONS.md`, then this file.

The `now/` module owns the pipeline and CLI routing. `loop/` runs fix, rule, and watch loops. `judge/` provides the scanner, council, and AST fixer. `voice/` handles rendering, TTS, and expression. `ground/` aggregates the constitution, memory, and providers. `reach/` exposes tools for file, git, shell, LLM, and web work. `trace/` records events, telemetry, and session state. The pipeline flows Intake → Enhance → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render.

Conventions mirror the constitution: `# frozen_string_literal: true`, double-quoted strings, no bare `rescue`, guard clauses, command-query separation. Files stay at or below three hundred lines; methods at or below ten. Read every file before editing.

Slash commands include `/scan`, `/fix`, `/review`, `/video`, and `/photograph`; the full list is via `/help`. For structural changes, run `/scan deep <path>` inside MASTER first. You do not need to memorize scan and fix choreography. After any mutating tool lands, standing orders run constitution drift and autocommit; the Review stage lints paths recorded in that turn. Plain language works: say "check my edits", "fix `path`", "clean this up", or "run through master".

The VPS allows one SSH session. Run Rails CI with `zsh DEPLOY/sh/vps_ci.sh <app>`. After `web/` edits, run `doas rcctl restart master`.