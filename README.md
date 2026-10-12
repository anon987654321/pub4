# pub4

pub4 is one repository with four governed trees: **MASTER** controls the repair and reasoning runtime, **RAILS** holds the products, **OPENBSD** owns deployment and machine security, and **STUDIO** owns sound and media generation. `RECOVERY/` contains recovery material rather than a fifth application tree.

Start with [the architecture](ARCHITECTURE.md) and the repository's [agent contract](AGENTS.md). For changes, follow the authority chain: `MASTER/data/soul.yml`, `MASTER/data/laws.yml`, executable laws in `MASTER/law/`, then the relevant gates and tree contracts. Do not call work complete without the command output that proves it.

## The four trees

- [MASTER](MASTER/README.md) — constitutional Ruby runtime, `/fix`, laws, operator commands and verification.
- [RAILS](RAILS/README.md) — Brgen, Amber, shared product code and Rails contracts.
- [OPENBSD](OPENBSD/README.md) — production host, network, deployment, security and recovery.
- [STUDIO](STUDIO/README.md) — Dilla, visual tools, post-processing and media-provider workflows.

## Operator commands

Run the pinned MASTER operator from its own tree:

```zsh
cd MASTER
bin/operator status
bin/operator measure
bin/operator gate --scan-only
```

The gate's default mode can repair files; `--scan-only` is the read-only option. Use the tree's canonical test runner and record its real exit status. The main proof surfaces are `cd MASTER && rake test`, `ruby RAILS/test/run_all.rb`, `ruby OPENBSD/bin/check --profile=full`, and `cd STUDIO/test && rake`. Browser, device, paid-provider, DNS, backup, and production checks require their respective real environments.

The repo-wide work queue is [TODO.md](TODO.md); each tree owns its deeper queue. Delete entries when the work and its required evidence are complete rather than using the backlog as a changelog.

[MIT License](LICENSE).
