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
