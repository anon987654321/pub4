# OPENBSD — tree contract

This tree's contract lives in the OPENBSD section of the root
`TREE_CONTRACTS.md`. MASTER governs pub4: `MASTER/data/soul.yml` owns global
identity, source authority and protected paths; `MASTER/data/laws.yml` owns
individual Law records. The executable Law Ruby in `MASTER/law/`, `law_runtime.yml`
and `MASTER/checks/` implements and verifies those requirements.

`OPENBSD/RUNBOOK.md` holds the operator procedures and
`OPENBSD/data/operator.yml` the recipes.
