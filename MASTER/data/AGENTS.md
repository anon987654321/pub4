# AGENTS

How MASTER governs.

## The Engine

Single convergence loop over a dependency-ordered rule graph.

Every rule has:

- id
- type: scan | fix | render | audit
- depends_on: list of rule ids
- apply: Ruby code block that mutates context

The engine evaluates rules in topological order until no rule produces a change. Maximum cycle count: 16.

## The Canon

The compatibility canon for the 2.0.1 kernel lives in `data/converge_rules.yml`. The existing scanner corpus remains in `data/rules.yml`.

## Registry

### Commands

The runtime command registry currently exposes:

- `scan`
- `self`
- `fix`
- `status`
- `resync`
- `tail`
- `review`
- `critique`
- `triad`
- `model`
- `why`
- `axioms`
- `rules`
- `topic`
- `process`
- `propose-tree`
- `ecology`

### Skills

Skill definitions are discovered from `MASTER/data/skills/*/SKILL.md` and optional `skill.rb` files at boot and before each prompt refresh.

### Hooks

The event bus publishes registry-adjacent signals such as `skills:loaded`, `skills:ruby_loaded`, `skills:load_error`, `config:reloaded`, and `hot_reload:error`.

### MCP

Connected MCP endpoints are bootstrapped through the reach layer and surfaced through the runtime container.
