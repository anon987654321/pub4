# Judge

Constitution scanner, council deliberation, swarm workers, and review crews.

- `scan/` — rules, scanner, constitution triage (`rake constitution`, `rake selftest`)
- `council/` — multi-agent deliberation and quality framework
- `swarm/` — coordinator, vote engine, worker roles
- `review_crew/` — specialized review agents

Entrypoints: `MASTER/bin/audit`, `MASTER/bin/gate`, `rake selftest`.
