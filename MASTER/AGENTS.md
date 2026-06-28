# Agents

Bootstrap for coding agents (Cursor, Claude Code, Codex, Aider).

## Read first

1. `QUICKSTART.md` — mental model and ergonomics
2. `DEPLOY/OPERATOR.md` — VPS, SSH, deploy, domains
3. `data/soul.yml` and `data/rules.yml` — when editing production paths

Authority: `data/soul.yml` > `data/rules.yml` > `CONVENTIONS.md` > this file.

## Modules

| Module | Role |
|--------|------|
| `now/` | Pipeline, CLI, routing |
| `loop/` | Fix, rule, watch loops |
| `judge/` | Scanner, council, AST fixer |
| `voice/` | Renderer, TTS, expression |
| `ground/` | Constitution, memory, providers |
| `reach/` | Tools: file, git, shell, LLM, web |
| `trace/` | Events, telemetry, session |

Pipeline: Intake → Enhance → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render.

## Conventions

`# frozen_string_literal: true`. Double-quoted strings. No bare `rescue`. Guard clauses. CQS. Files ≤300 lines; methods ≤10. Read every file before editing.

## Commands

`/scan`, `/fix`, `/review`, `/video`, `/photograph` — full list via `/help`. Structural changes: `/scan deep <path>` inside MASTER first.

## VPS limits

One SSH session. `zsh DEPLOY/sh/vps_ci.sh <app>` for Rails CI. After `web/` edits: `doas rcctl restart master`.