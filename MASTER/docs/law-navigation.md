# Law navigation

This page is a route to the live Law sources, not a second Law catalogue.

## Authority

`MASTER/data/soul.yml` owns global identity, preservation, source precedence and protected paths.
`MASTER/data/laws.yml` owns individual Law identities, statements, parentage and invariant-node order.
Its reserved `law_catalogue` block owns per-Law severity, mode, lifecycle, autofix, language, surface and path reach.
`MASTER/data/law_runtime.yml` retains scanner, veto, plugin and /fix runtime configuration; it does not hold the per-Law catalogue.

## Agent entry

At the start of a task, run:

```zsh
ruby MASTER/tools/agent_context.rb --json
```

For broad or cross-tree work, add `--tree`.
Use `MASTER/bin/operator laws <ID>` to retrieve the exact Law row.
For an executable-policy change, inspect the matching `laws.yml#law_catalogue` entry, its `Law.define` source, bad/good fixtures and focused tests.
Use `cd MASTER && bundle exec rake dogfood` to prove the Law implementations against their fixtures. Run the relevant focused tests and check ladder for the affected tree.

A declaration or digest is not execution evidence. Missing or unrun measurements remain INCONCLUSIVE.
