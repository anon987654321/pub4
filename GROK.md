# GROK.md

Bootstrap instructions for Grok-family agents working in this repository.

Start with `MASTER/QUICKSTART.md`. It is the designed entry point for all LLM agents and gives the practical workflow before the deeper constitution files.

Use these files as authority when precision matters:

- `MASTER/data/soul.yml`
- `MASTER/data/rules.yml`
- `MASTER/data/ruby_style.yml`
- `MASTER/data/workflow.yml`
- `MASTER/data/standing_orders.yml`
- `MASTER/data/patterns.yml`
- `AGENTS.md`
- `CLAUDE.md`

Do not duplicate rules here. If this file conflicts with `MASTER/data/*`, `MASTER/data/*` wins.

Grok-specific notes:

- Use long-context reasoning for architecture, review, and cleanup planning.
- Read affected files before editing.
- Keep patches scoped and reversible.
- Prefer evidence from local files, command output, and upstream references.
- Route major MASTER changes through `/scan deep`, `/sweep`, or council when the CLI is available.
- Treat deploy, auth, secrets, shell scripts, and public Rails surfaces as high-risk.
- Publish through a branch and draft PR unless the operator explicitly asks for direct main work.
