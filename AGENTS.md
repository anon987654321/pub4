# AGENTS.md

Bootstrap for autonomous coding agents (Claude Code, Cursor, Aider, Codex, Continue).

Read `MASTER/data/soul.yml`, `rules.yml`, `ruby_style.yml`, `workflow.yml`, `standing_orders.yml` before any work. Operator environment, SSH, DNS, and deploy details are in `CLAUDE.md`.

Read every file in full before editing. Match surrounding style. Run `/scan deep <path>` inside MASTER before structural changes.

After editing `web/` files: `doas rcctl restart master` — Falcon does not hot-reload.

Key commands: `/scan`, `/fix`, `/review`, `/critique`, `/why`, `/snapshot`. Type `/help` inside MASTER for the full list.
