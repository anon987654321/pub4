# pub4

pub4 is one repository with four governed trees: **MASTER** controls the repair and reasoning runtime, **RAILS** holds the products, **OPENBSD** owns deployment and machine security, and **STUDIO** owns sound and media generation. `RECOVERY/` contains recovery material rather than a fifth application tree.

Start with the repository's [agent contract](AGENTS.md) and the relevant tree or project `README.md`. Design constraints are specified in `MASTER/data/laws.yml` under the constitutional authority of `MASTER/data/soul.yml`; executable laws in `MASTER/law/` and scanner adapters enforce them. Each README is the human entry point for its boundary, while configuration and code remain authoritative for behavior. Do not call work complete without the command output that proves it.

## Visual identity

pub4's visual direction is **signal and stillness**: flat neutral structure,
decisive type, deliberate negative space, and a restrained mineral-lime signal
(`#C8F55F`) used only where it carries meaning. The contract is
`MASTER/data/laws.yml#visual_identity_contract`; values live in
`MASTER/data/tokens.yml#tokens.visual_identity`. Brgen keeps its deep-blue local
identity remains product-specific, bsdports remains terminal-green,
OpenBSD output stays plain and explicit, and STUDIO never overrides operator-owned
grades. The reference is inspiration only: pub4 must retain original branding.

## The four trees

- [MASTER](MASTER/README.md) — constitutional Ruby runtime, `/fix`, laws, operator commands and verification.
- [RAILS](RAILS/README.md) — Brgen, bsdports, shared product code and Rails contracts.
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

The single authoritative work queue is [TODO.md](TODO.md) at the repository root. All four trees and cross-tree tasks belong there; do not create child TODO.md files. Delete entries when the work and its required evidence are complete rather than using the backlog as a changelog.

[MIT License](LICENSE).
