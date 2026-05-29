# GPT.md

Bootstrap instructions for GPT-family agents working in this repository.

Start with `MASTER/QUICKSTART.md`. It is the designed entry point for all LLM agents and gives the practical workflow before the deeper constitution files.

Use these files as authority when precision matters:

- `MASTER/data/soul.yml`
- `MASTER/data/rules.yml`
- `MASTER/data/ruby_style.yml`
- `MASTER/data/workflow.yml`
- `MASTER/data/standing_orders.yml`
- `AGENTS.md`
- `CLAUDE.md`

Do not duplicate rules here. If this file conflicts with `MASTER/data/*`, `MASTER/data/*` wins.

GPT/Codex-specific notes:

- Read affected files before editing.
- Keep patches scoped and reversible.
- Prefer local checks with concrete output over claims.
- Treat deploy, auth, secrets, shell scripts, and public Rails surfaces as high-risk.
- For frontend files, verify syntax and basic structure before changing style.
- Publish through a branch and draft PR unless the operator explicitly asks for direct main work.
