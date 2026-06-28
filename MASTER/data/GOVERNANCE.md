# Governance

How MASTER governs. Agent bootstrap: `AGENTS.md`, `QUICKSTART.md`. Operator: `DEPLOY/OPERATOR.md`.

## Engine

Convergence loop over a dependency-ordered rule graph. Each rule: id, type (scan | fix | render | audit), `depends_on`, `apply` block. Runs until fixpoint or 16 cycles.

Canon: `data/converge_rules.yml`. Scanner corpus: `data/rules.yml`.

## Registry

Commands include `scan`, `fix`, `review`, `critique`, `why`, `model`, `workflow`, `ecology`, and others — discovered at boot.

Skills: `data/skills/*/SKILL.md` plus optional `skill.rb`.

Hooks via event bus: `skills:loaded`, `config:reloaded`, etc. MCP endpoints through `reach/`.