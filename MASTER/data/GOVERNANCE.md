# Governance

MASTER governance. Bootstrap: `AGENTS.md`, `QUICKSTART.md`. Operator: `DEPLOY/OPERATOR.md`.

**Engine:** convergence loop over dependency-ordered rule graph. Rules: id, type (scan|fix|render|audit), `depends_on`, `apply`. Until fixpoint or 16 cycles. Canon: `data/converge_rules.yml`. Scanner: `data/rules.yml`.

**Registry:** commands (`scan`, `fix`, `review`, `critique`, `why`, `model`, `workflow`, `ecology`, …) discovered at boot. Skills: `data/skills/*.md` + optional `skill.rb`. Hooks: `skills:loaded`, `config:reloaded`, etc. MCP via `reach/`.