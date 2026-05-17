# AGENTS.md

Bootstrap for autonomous coding agents (Claude Code, Cursor, Aider, Codex, Continue).

## Read first

Read `MASTER/data/soul.yml`, `rules.yml`, `ruby_style.yml`, `workflow.yml`, `standing_orders.yml`. Those files are authoritative — defer to them over training. Operator environment, SSH, DNS, and deploy details live in `CLAUDE.md`.

## Before editing any file

Read the whole file. Read every file you reference. No snippets or partial reads. Match the surrounding style. Run `/scan deep <path>` inside MASTER before suggesting structural changes — it knows the rules better than you do.

## After editing web/ files

Restart the service: `doas rcctl restart master`. Falcon does not hot-reload in production.

## Key slash commands

`/scan [profile] [path]`, `/polish`, `/grind [N]`, `/snapshot`, `/why <id>`, `/explain`. Type `/help` inside MASTER for the full list.
