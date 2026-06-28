# Governance

Governance describes how MASTER discovers commands, applies rules, and converges toward a fixpoint without ad-hoc orchestration.

Bootstrap docs are `AGENTS.md` and `QUICKSTART.md`. Operator procedures are in `DEPLOY/OPERATOR.md`. The engine is a convergence loop over a dependency-ordered rule graph. Each rule has an id, a type (`scan`, `fix`, `render`, or `audit`), `depends_on`, and `apply`. The loop runs until fixpoint or sixteen cycles. Canon lives in `data/converge_rules.yml`; the scanner registry is in `data/rules.yml`.

Commands such as `scan`, `fix`, `review`, `critique`, `why`, `model`, `workflow`, and `ecology` are discovered at boot. Skills are `data/skills/*.md` plus optional `skill.rb`. Hooks include `skills:loaded`, `config:reloaded`, and similar lifecycle events. MCP integration goes through `reach/`.